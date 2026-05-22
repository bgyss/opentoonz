#include "tgraphics.h"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <optional>
#include <string>

namespace TGraphics {
namespace {

struct MetalState {
  id<MTLDevice> m_device             = nil;
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
          "}\n"
          "fragment float4 tgraphicsColorFragment(VertexOut in [[stage_in]], "
          "constant float4 &color [[buffer(0)]]) {\n"
          "  return color;\n"
          "}\n";
}

class MetalLayerRenderTarget final : public RenderTarget {
  CAMetalLayer *m_layer = nil;
  int m_width           = 0;
  int m_height          = 0;
  double m_scale        = 1.0;

public:
  MetalLayerRenderTarget(CAMetalLayer *layer, int width, int height, double devicePixelRatio)
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

class MetalTextureRenderTarget final : public RenderTarget {
  id<MTLTexture> m_texture = nil;
  int m_width              = 0;
  int m_height             = 0;

public:
  MetalTextureRenderTarget(int width, int height)
      : m_width(std::max(1, width)), m_height(std::max(1, height)) {
    MetalState &state = metalState();
    MTLTextureDescriptor *descriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                           width:m_width
                                                          height:m_height
                                                       mipmapped:NO];
    descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    m_texture        = [state.m_device newTextureWithDescriptor:descriptor];
  }

  ~MetalTextureRenderTarget() override {
#if !__has_feature(objc_arc)
    [m_texture release];
#endif
  }

  id<MTLTexture> texture() const { return m_texture; }
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
  RenderTarget *m_target = nullptr;

public:
  explicit MetalCommandEncoder(RenderTarget *target) : m_target(target) {}

  BackendType backendType() const override { return BackendType::Metal; }

  void draw(const DrawList2D &drawList) override {
    if (!m_target || drawList.empty()) return;

    MetalState &state = metalState();
    if (!state.m_device || !state.m_commandQueue) return;

    MetalLayerRenderTarget *layerTarget     = dynamic_cast<MetalLayerRenderTarget *>(m_target);
    MetalTextureRenderTarget *textureTarget = dynamic_cast<MetalTextureRenderTarget *>(m_target);

    id<CAMetalDrawable> drawable = nil;
    id<MTLTexture> renderTexture = nil;

    if (layerTarget) {
      drawable      = [layerTarget->layer() nextDrawable];
      renderTexture = drawable.texture;
    } else if (textureTarget) {
      renderTexture = textureTarget->texture();
    }
    if (!renderTexture) return;

    MTLRenderPassDescriptor *pass        = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture     = renderTexture;
    pass.colorAttachments[0].loadAction  = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    const TPixel32 clearColor =
        drawList.hasClearColor() ? drawList.clearColor() : TPixel32(0, 0, 0, 0);
    pass.colorAttachments[0].clearColor = MTLClearColorMake(
        clearColor.r / 255.0, clearColor.g / 255.0, clearColor.b / 255.0, clearColor.m / 255.0);

    id<MTLCommandBuffer> commandBuffer = [state.m_commandQueue commandBuffer];
    commandBuffer.label                = @"OpenToonz TGraphics";

    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
    encoder.label                       = @"DrawList2D";

    for (const ColorRect &rect : drawList.colorRects()) {
      id<MTLRenderPipelineState> pipeline = colorPipelineState(rect.m_blending);
      if (!pipeline) continue;

      std::array<MetalVertex, 6> vertices = makeVertices(rect.m_rect);
      const float color[4]                = {rect.m_color.r / 255.0f, rect.m_color.g / 255.0f,
                                             rect.m_color.b / 255.0f, rect.m_color.m / 255.0f};
      [encoder setRenderPipelineState:pipeline];
      [encoder setVertexBytes:vertices.data()
                       length:vertices.size() * sizeof(MetalVertex)
                      atIndex:0];
      [encoder setFragmentBytes:color length:sizeof(color) atIndex:0];
      [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
    }

    for (const ColorLine &line : drawList.colorLines()) {
      id<MTLRenderPipelineState> pipeline = colorPipelineState(line.m_blending);
      if (!pipeline) continue;

      const float color[4] = {line.m_color.r / 255.0f, line.m_color.g / 255.0f,
                              line.m_color.b / 255.0f, line.m_color.m / 255.0f};
      [encoder setRenderPipelineState:pipeline];
      [encoder setFragmentBytes:color length:sizeof(color) atIndex:0];

      if (std::optional<TRectD> lineRect = axisAlignedLineRect(line)) {
        std::array<MetalVertex, 6> vertices = makeVertices(*lineRect);
        [encoder setVertexBytes:vertices.data()
                         length:vertices.size() * sizeof(MetalVertex)
                        atIndex:0];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
      } else {
        std::array<MetalVertex, 2> vertices = makeLineVertices(line);
        [encoder setVertexBytes:vertices.data()
                         length:vertices.size() * sizeof(MetalVertex)
                        atIndex:0];
        [encoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:2];
      }
    }

    id<MTLSamplerState> sampler = samplerState();
    if (sampler) [encoder setFragmentSamplerState:sampler atIndex:0];

    for (const TextureQuad &quad : drawList.textureQuads()) {
      if (!sampler) break;
      const RasterTexture *texture = dynamic_cast<const RasterTexture *>(quad.m_texture.get());
      if (!texture || !texture->raster()) continue;

      id<MTLTexture> metalTexture = upload(texture->raster());
      if (!metalTexture) continue;

      id<MTLRenderPipelineState> pipeline = pipelineState(quad.m_blending);
      if (!pipeline) continue;

      std::array<MetalVertex, 6> vertices = makeVertices(quad.m_rect);
      [encoder setRenderPipelineState:pipeline];
      [encoder setVertexBytes:vertices.data()
                       length:vertices.size() * sizeof(MetalVertex)
                      atIndex:0];
      [encoder setFragmentTexture:metalTexture atIndex:0];
      [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
    }

    [encoder endEncoding];
    if (drawable) [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
    if (textureTarget) [commandBuffer waitUntilCompleted];
  }

private:
  id<MTLRenderPipelineState> pipelineState(bool blending) {
    static id<MTLRenderPipelineState> replacePipeline = nil;
    static id<MTLRenderPipelineState> blendPipeline   = nil;
    static bool attemptedReplace                      = false;
    static bool attemptedBlend                        = false;

    id<MTLRenderPipelineState> &pipeline = blending ? blendPipeline : replacePipeline;
    bool &attempted                      = blending ? attemptedBlend : attemptedReplace;
    if (attempted) return pipeline;
    attempted = true;

    MetalState &state      = metalState();
    NSError *error         = nil;
    id<MTLLibrary> library = [state.m_device newLibraryWithSource:shaderSource()
                                                          options:nil
                                                            error:&error];
    if (!library) return nil;

    id<MTLFunction> vertexFunction   = [library newFunctionWithName:@"tgraphicsVertex"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"tgraphicsFragment"];

    MTLRenderPipelineDescriptor *descriptor        = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.label                               = @"OpenToonz TGraphics Texture";
    descriptor.vertexFunction                      = vertexFunction;
    descriptor.fragmentFunction                    = fragmentFunction;
    descriptor.colorAttachments[0].pixelFormat     = MTLPixelFormatBGRA8Unorm;
    descriptor.colorAttachments[0].blendingEnabled = blending ? YES : NO;
    if (blending) {
      descriptor.colorAttachments[0].sourceRGBBlendFactor      = MTLBlendFactorSourceAlpha;
      descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
      descriptor.colorAttachments[0].sourceAlphaBlendFactor    = MTLBlendFactorSourceAlpha;
      descriptor.colorAttachments[0].destinationAlphaBlendFactor =
          MTLBlendFactorOneMinusSourceAlpha;
    }

    pipeline = [state.m_device newRenderPipelineStateWithDescriptor:descriptor error:&error];

#if !__has_feature(objc_arc)
    [descriptor release];
    [fragmentFunction release];
    [vertexFunction release];
    [library release];
#endif

    return pipeline;
  }

  id<MTLRenderPipelineState> colorPipelineState(bool blending) {
    static id<MTLRenderPipelineState> replacePipeline = nil;
    static id<MTLRenderPipelineState> blendPipeline   = nil;
    static bool attemptedReplace                      = false;
    static bool attemptedBlend                        = false;

    id<MTLRenderPipelineState> &pipeline = blending ? blendPipeline : replacePipeline;
    bool &attempted                      = blending ? attemptedBlend : attemptedReplace;
    if (attempted) return pipeline;
    attempted = true;

    MetalState &state      = metalState();
    NSError *error         = nil;
    id<MTLLibrary> library = [state.m_device newLibraryWithSource:shaderSource()
                                                          options:nil
                                                            error:&error];
    if (!library) return nil;

    id<MTLFunction> vertexFunction   = [library newFunctionWithName:@"tgraphicsVertex"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"tgraphicsColorFragment"];

    MTLRenderPipelineDescriptor *descriptor        = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.label                               = @"OpenToonz TGraphics Color";
    descriptor.vertexFunction                      = vertexFunction;
    descriptor.fragmentFunction                    = fragmentFunction;
    descriptor.colorAttachments[0].pixelFormat     = MTLPixelFormatBGRA8Unorm;
    descriptor.colorAttachments[0].blendingEnabled = blending ? YES : NO;
    if (blending) {
      descriptor.colorAttachments[0].sourceRGBBlendFactor      = MTLBlendFactorSourceAlpha;
      descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
      descriptor.colorAttachments[0].sourceAlphaBlendFactor    = MTLBlendFactorSourceAlpha;
      descriptor.colorAttachments[0].destinationAlphaBlendFactor =
          MTLBlendFactorOneMinusSourceAlpha;
    }

    pipeline = [state.m_device newRenderPipelineStateWithDescriptor:descriptor error:&error];

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

    MetalState &state                = metalState();
    MTLSamplerDescriptor *descriptor = [[MTLSamplerDescriptor alloc] init];
    descriptor.minFilter             = MTLSamplerMinMagFilterLinear;
    descriptor.magFilter             = MTLSamplerMinMagFilterLinear;
    descriptor.sAddressMode          = MTLSamplerAddressModeClampToEdge;
    descriptor.tAddressMode          = MTLSamplerAddressModeClampToEdge;
    sampler                          = [state.m_device newSamplerStateWithDescriptor:descriptor];

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
    descriptor.usage       = MTLTextureUsageShaderRead;
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

  std::array<MetalVertex, 2> makeLineVertices(const ColorLine &line) const {
    return {{{pixelToClipX(line.m_p0.x), pixelToClipY(line.m_p0.y), 0.0f, 0.0f},
             {pixelToClipX(line.m_p1.x), pixelToClipY(line.m_p1.y), 0.0f, 0.0f}}};
  }

  std::optional<TRectD> axisAlignedLineRect(const ColorLine &line) const {
    const double epsilon = 1e-6;
    if (std::abs(line.m_p0.y - line.m_p1.y) <= epsilon) {
      const double x0 = std::min(line.m_p0.x, line.m_p1.x);
      const double x1 = std::max(line.m_p0.x, line.m_p1.x);
      return TRectD(x0, line.m_p0.y, x1 + 1.0, line.m_p0.y + 1.0);
    }
    if (std::abs(line.m_p0.x - line.m_p1.x) <= epsilon) {
      const double y0 = std::min(line.m_p0.y, line.m_p1.y);
      const double y1 = std::max(line.m_p0.y, line.m_p1.y);
      return TRectD(line.m_p0.x, y0, line.m_p0.x + 1.0, y1 + 1.0);
    }
    return std::nullopt;
  }

  float pixelToClipX(double x) const { return static_cast<float>((2.0 * x / targetWidth()) - 1.0); }

  float pixelToClipY(double y) const {
    return static_cast<float>(1.0 - (2.0 * y / targetHeight()));
  }

  int targetWidth() const {
    if (MetalLayerRenderTarget *layerTarget = dynamic_cast<MetalLayerRenderTarget *>(m_target)) {
      return layerTarget->width();
    }
    if (MetalTextureRenderTarget *textureTarget =
            dynamic_cast<MetalTextureRenderTarget *>(m_target)) {
      return textureTarget->width();
    }
    return 1;
  }

  int targetHeight() const {
    if (MetalLayerRenderTarget *layerTarget = dynamic_cast<MetalLayerRenderTarget *>(m_target)) {
      return layerTarget->height();
    }
    if (MetalTextureRenderTarget *textureTarget =
            dynamic_cast<MetalTextureRenderTarget *>(m_target)) {
      return textureTarget->height();
    }
    return 1;
  }
};

class MetalDevice final : public Device {
public:
  BackendType backendType() const override { return BackendType::Metal; }

  std::unique_ptr<CommandEncoder> createCommandEncoder(RenderTarget *target = 0) override {
    return std::unique_ptr<CommandEncoder>(new MetalCommandEncoder(target));
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

void *createNativeMetalLayerForView(void *nativeView) {
  if (!probeMetalDevice() || !nativeView) return nullptr;

  NSView *view = static_cast<NSView *>(nativeView);
  if (![view isKindOfClass:[NSView class]]) return nullptr;

  CAMetalLayer *layer   = [CAMetalLayer layer];
  layer.device          = metalState().m_device;
  layer.pixelFormat     = MTLPixelFormatBGRA8Unorm;
  layer.framebufferOnly = YES;
  layer.contentsScale =
      view.window ? view.window.backingScaleFactor : NSScreen.mainScreen.backingScaleFactor;
  layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;

  view.wantsLayer = YES;
  view.layer      = layer;
  return layer;
}

std::unique_ptr<RenderTarget> createNativeMetalLayerRenderTarget(void *metalLayer, int width,
                                                                 int height,
                                                                 double devicePixelRatio) {
  if (!probeMetalDevice() || !metalLayer) return std::unique_ptr<RenderTarget>();

  CAMetalLayer *layer = static_cast<CAMetalLayer *>(metalLayer);
  if (![layer isKindOfClass:[CAMetalLayer class]]) {
    return std::unique_ptr<RenderTarget>();
  }

  return std::unique_ptr<RenderTarget>(
      new MetalLayerRenderTarget(layer, width, height, devicePixelRatio));
}

std::unique_ptr<RenderTarget> createNativeMetalImageRenderTarget(int width, int height) {
  if (!probeMetalDevice()) return std::unique_ptr<RenderTarget>();

  std::unique_ptr<RenderTarget> target(new MetalTextureRenderTarget(width, height));
  MetalTextureRenderTarget *textureTarget = dynamic_cast<MetalTextureRenderTarget *>(target.get());
  if (!textureTarget->texture()) return std::unique_ptr<RenderTarget>();
  return target;
}

bool isNativeMetalLayerRenderTarget(const RenderTarget *target) {
  return dynamic_cast<const MetalLayerRenderTarget *>(target) != nullptr;
}

TRaster32P readNativeMetalRenderTarget(RenderTarget *target) {
  MetalTextureRenderTarget *textureTarget = dynamic_cast<MetalTextureRenderTarget *>(target);
  if (!textureTarget || !textureTarget->texture()) return TRaster32P();

  TRaster32P raster(textureTarget->width(), textureTarget->height());
  raster->lock();
  const MTLRegion region = MTLRegionMake2D(0, 0, textureTarget->width(), textureTarget->height());
  [textureTarget->texture() getBytes:raster->pixels(0)
                         bytesPerRow:raster->getWrap() * sizeof(TPixel32)
                          fromRegion:region
                         mipmapLevel:0];
  raster->unlock();
  return raster;
}

}  // namespace TGraphics
