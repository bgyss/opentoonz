#include "tgraphics.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include <algorithm>
#include <array>
#include <string>

namespace TGraphics {
namespace {

struct MetalState {
  id<MTLDevice> m_device = nil;
  id<MTLCommandQueue> m_commandQueue = nil;
  std::string m_deviceName;

  MetalState() {
    m_device = MTLCreateSystemDefaultDevice();
    if (!m_device) return;

    m_commandQueue       = [m_device newCommandQueue];
    const char *nameUtf8 = [[m_device name] UTF8String];
    m_deviceName         = nameUtf8 ? nameUtf8 : "";
  }

  ~MetalState() {
#if !__has_feature(objc_arc)
    [m_commandQueue release];
    [m_device release];
#endif
  }
};

MetalState &metalState() {
  static MetalState state;
  return state;
}

NSString *shaderSource() {
  return @"#include <metal_stdlib>\n"
          "using namespace metal;\n"
          "struct VertexIn { float2 position; float2 texCoord; };\n"
          "struct VertexOut { float4 position [[position]]; float2 texCoord; "
          "};\n"
          "vertex VertexOut tgraphicsVertex(uint vertexId [[vertex_id]], "
          "constant VertexIn *vertices [[buffer(0)]]) {\n"
          "  VertexIn in = vertices[vertexId];\n"
          "  VertexOut out;\n"
          "  out.position = float4(in.position, 0.0, 1.0);\n"
          "  out.texCoord = in.texCoord;\n"
          "  return out;\n"
          "}\n"
          "fragment float4 tgraphicsFragment(VertexOut in [[stage_in]], "
          "texture2d<float> colorTexture [[texture(0)]], sampler "
          "colorSampler [[sampler(0)]]) {\n"
          "  return colorTexture.sample(colorSampler, in.texCoord);\n"
          "}\n";
}

class MetalLayerRenderTarget final : public RenderTarget {
  CAMetalLayer *m_layer = nil;
  int m_width           = 0;
  int m_height          = 0;
  double m_scale        = 1.0;

public:
  MetalLayerRenderTarget(CAMetalLayer *layer, int width, int height,
                         double devicePixelRatio)
      : m_layer(layer)
      , m_width(std::max(1, width))
      , m_height(std::max(1, height))
      , m_scale(devicePixelRatio > 0.0 ? devicePixelRatio : 1.0) {
#if !__has_feature(objc_arc)
    [m_layer retain];
#endif

    MetalState &state       = metalState();
    m_layer.device          = state.m_device;
    m_layer.pixelFormat     = MTLPixelFormatBGRA8Unorm;
    m_layer.framebufferOnly = YES;
    m_layer.drawableSize    = CGSizeMake(m_width * m_scale, m_height * m_scale);
  }

  ~MetalLayerRenderTarget() override {
#if !__has_feature(objc_arc)
    [m_layer release];
#endif
  }

  CAMetalLayer *layer() const { return m_layer; }
  int width() const { return m_width; }
  int height() const { return m_height; }
};

struct MetalVertex {
  float m_x = 0.0f;
  float m_y = 0.0f;
  float m_u = 0.0f;
  float m_v = 0.0f;
};

class MetalCommandEncoder final : public CommandEncoder {
  MetalLayerRenderTarget *m_target = nullptr;

public:
  explicit MetalCommandEncoder(MetalLayerRenderTarget *target)
      : m_target(target) {}

  BackendType backendType() const override { return BackendType::Metal; }

  void draw(const DrawList2D &drawList) override {
    if (!m_target || drawList.empty()) return;

    MetalState &state = metalState();
    if (!state.m_device || !state.m_commandQueue) return;

    id<CAMetalDrawable> drawable = [m_target->layer() nextDrawable];
    if (!drawable) return;

    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture     = drawable.texture;
    pass.colorAttachments[0].loadAction  = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor  = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);

    id<MTLCommandBuffer> commandBuffer = [state.m_commandQueue commandBuffer];
    commandBuffer.label = @"OpenToonz TGraphics";

    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer renderCommandEncoderWithDescriptor:pass];
    encoder.label = @"DrawList2D";

    id<MTLRenderPipelineState> pipeline = pipelineState();
    id<MTLSamplerState> sampler         = samplerState();
    if (!pipeline || !sampler) {
      [encoder endEncoding];
      [commandBuffer presentDrawable:drawable];
      [commandBuffer commit];
      return;
    }

    [encoder setRenderPipelineState:pipeline];
    [encoder setFragmentSamplerState:sampler atIndex:0];

    for (const TextureQuad &quad : drawList.textureQuads()) {
      const RasterTexture *texture =
          dynamic_cast<const RasterTexture *>(quad.m_texture.get());
      if (!texture || !texture->raster()) continue;

      id<MTLTexture> metalTexture = upload(texture->raster());
      if (!metalTexture) continue;

      std::array<MetalVertex, 6> vertices = makeVertices(quad.m_rect);
      [encoder setVertexBytes:vertices.data()
                       length:vertices.size() * sizeof(MetalVertex)
                      atIndex:0];
      [encoder setFragmentTexture:metalTexture atIndex:0];
      [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
    }

    [encoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
  }

private:
  id<MTLRenderPipelineState> pipelineState() {
    static id<MTLRenderPipelineState> pipeline = nil;
    static bool attempted                      = false;
    if (attempted) return pipeline;
    attempted = true;

    MetalState &state = metalState();
    NSError *error    = nil;
    id<MTLLibrary> library =
        [state.m_device newLibraryWithSource:shaderSource() options:nil error:&error];
    if (!library) return nil;

    id<MTLFunction> vertexFunction =
        [library newFunctionWithName:@"tgraphicsVertex"];
    id<MTLFunction> fragmentFunction =
        [library newFunctionWithName:@"tgraphicsFragment"];

    MTLRenderPipelineDescriptor *descriptor =
        [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.label                          = @"OpenToonz TGraphics Texture";
    descriptor.vertexFunction                 = vertexFunction;
    descriptor.fragmentFunction               = fragmentFunction;
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    descriptor.colorAttachments[0].blendingEnabled = YES;
    descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    descriptor.colorAttachments[0].destinationRGBBlendFactor =
        MTLBlendFactorOneMinusSourceAlpha;
    descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    descriptor.colorAttachments[0].destinationAlphaBlendFactor =
        MTLBlendFactorOneMinusSourceAlpha;

    pipeline = [state.m_device newRenderPipelineStateWithDescriptor:descriptor
                                                              error:&error];

#if !__has_feature(objc_arc)
    [descriptor release];
    [fragmentFunction release];
    [vertexFunction release];
    [library release];
#endif

    return pipeline;
  }

  id<MTLSamplerState> samplerState() {
    static id<MTLSamplerState> sampler = nil;
    if (sampler) return sampler;

    MetalState &state                 = metalState();
    MTLSamplerDescriptor *descriptor  = [[MTLSamplerDescriptor alloc] init];
    descriptor.minFilter              = MTLSamplerMinMagFilterLinear;
    descriptor.magFilter              = MTLSamplerMinMagFilterLinear;
    descriptor.sAddressMode           = MTLSamplerAddressModeClampToEdge;
    descriptor.tAddressMode           = MTLSamplerAddressModeClampToEdge;
    sampler                           = [state.m_device newSamplerStateWithDescriptor:descriptor];

#if !__has_feature(objc_arc)
    [descriptor release];
#endif

    return sampler;
  }

  id<MTLTexture> upload(const TRaster32P &raster) {
    MetalState &state = metalState();
    const int width   = raster->getLx();
    const int height  = raster->getLy();
    if (width <= 0 || height <= 0) return nil;

    MTLTextureDescriptor *descriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                           width:width
                                                          height:height
                                                       mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> texture = [state.m_device newTextureWithDescriptor:descriptor];
    if (!texture) return nil;

    raster->lock();
    const MTLRegion region = MTLRegionMake2D(0, 0, width, height);
    [texture replaceRegion:region
               mipmapLevel:0
                 withBytes:raster->pixels(0)
               bytesPerRow:raster->getWrap() * sizeof(TPixel32)];
    raster->unlock();

#if !__has_feature(objc_arc)
    return [texture autorelease];
#else
    return texture;
#endif
  }

  std::array<MetalVertex, 6> makeVertices(const TRectD &rect) const {
    const float left   = pixelToClipX(rect.x0);
    const float right  = pixelToClipX(rect.x1);
    const float top    = pixelToClipY(rect.y0);
    const float bottom = pixelToClipY(rect.y1);

    return {{{left, top, 0.0f, 0.0f},
             {right, top, 1.0f, 0.0f},
             {left, bottom, 0.0f, 1.0f},
             {right, top, 1.0f, 0.0f},
             {right, bottom, 1.0f, 1.0f},
             {left, bottom, 0.0f, 1.0f}}};
  }

  float pixelToClipX(double x) const {
    return static_cast<float>((2.0 * x / m_target->width()) - 1.0);
  }

  float pixelToClipY(double y) const {
    return static_cast<float>(1.0 - (2.0 * y / m_target->height()));
  }
};

class MetalDevice final : public Device {
public:
  BackendType backendType() const override { return BackendType::Metal; }

  std::unique_ptr<CommandEncoder> createCommandEncoder(
      RenderTarget *target = 0) override {
    return std::unique_ptr<CommandEncoder>(
        new MetalCommandEncoder(dynamic_cast<MetalLayerRenderTarget *>(target)));
  }
};

}  // namespace

Device &nativeMetalDevice() {
  static MetalDevice device;
  return device;
}

bool probeMetalDevice() {
  MetalState &state = metalState();
  return state.m_device && state.m_commandQueue;
}

const char *probeMetalDeviceName() {
  MetalState &state = metalState();
  return probeMetalDevice() ? state.m_deviceName.c_str() : "";
}

std::unique_ptr<RenderTarget> createNativeMetalLayerRenderTarget(
    void *metalLayer, int width, int height, double devicePixelRatio) {
  if (!probeMetalDevice() || !metalLayer) return std::unique_ptr<RenderTarget>();

  CAMetalLayer *layer = static_cast<CAMetalLayer *>(metalLayer);
  if (![layer isKindOfClass:[CAMetalLayer class]]) {
    return std::unique_ptr<RenderTarget>();
  }

  return std::unique_ptr<RenderTarget>(
      new MetalLayerRenderTarget(layer, width, height, devicePixelRatio));
}

bool isNativeMetalLayerRenderTarget(const RenderTarget *target) {
  return dynamic_cast<const MetalLayerRenderTarget *>(target) != nullptr;
}

}  // namespace TGraphics
