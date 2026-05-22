#include "tgraphics.h"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <iostream>
#include <optional>
#include <string>

namespace TGraphics {
namespace {

bool makeStrokedLineQuad(const ColorLine &line, std::array<TPointD, 4> &points) {
  const double dx     = line.m_p1.x - line.m_p0.x;
  const double dy     = line.m_p1.y - line.m_p0.y;
  const double length = std::sqrt(dx * dx + dy * dy);
  if (length <= 1e-6) return false;

  const double halfWidth = 0.5;
  const TPointD tangent(dx / length * halfWidth, dy / length * halfWidth);
  const TPointD normal(-dy / length * halfWidth, dx / length * halfWidth);
  const TPointD p0 = line.m_p0 - tangent;
  const TPointD p1 = line.m_p1 + tangent;

  points[0] = p0 + normal;
  points[1] = p1 + normal;
  points[2] = p1 - normal;
  points[3] = p0 - normal;
  return true;
}

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

void logMetalError(NSString *context, NSError *error) {
  if (!error) return;
  const char *message = [[error localizedDescription] UTF8String];
  std::cerr << "OpenToonz Metal: " << [context UTF8String] << " failed";
  if (message) std::cerr << ": " << message;
  std::cerr << std::endl;
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
          "colorSampler [[sampler(0)]], constant float4 &colorScale "
          "[[buffer(0)]]) {\n"
          "  return colorTexture.sample(colorSampler, in.texCoord) * "
          "colorScale;\n"
          "}\n"
          "fragment float4 tgraphicsColorFragment(VertexOut in [[stage_in]], "
          "constant float4 &color [[buffer(0)]]) {\n"
          "  return color;\n"
          "}\n"
          "struct SunflareUniforms { float a11; float a12; float a13; float "
          "a21; float a22; float a23; float4 color; float blades; float "
          "intensity; float angle; float bias; float sharpness; };\n"
          "struct CausticsUniforms { float a11; float a12; float a13; float "
          "a21; float a22; float a23; float4 color; float time; };\n"
          "struct StarskyUniforms { float a11; float a12; float a13; float "
          "a21; float a22; float a23; float4 color; float time; float "
          "brightness; };\n"
          "struct WavyUniforms { float a11; float a12; float a13; float "
          "a21; float a22; float a23; float4 color1; float4 color2; float "
          "time; };\n"
          "struct FireballUniforms { float a11; float a12; float a13; float "
          "a21; float a22; float a23; float4 color1; float4 color2; float "
          "detail; float time; };\n"
          "fragment float4 tgraphicsSunflareFragment(VertexOut in "
          "[[stage_in]], constant SunflareUniforms &u [[buffer(0)]]) {\n"
          "  float2 world = float2(in.position.x * u.a11 + in.position.y * "
          "u.a12 + u.a13, in.position.x * u.a21 + in.position.y * u.a22 + "
          "u.a23);\n"
          "  float2 p = 0.03 * world;\n"
          "  float angle = atan2(p.y, p.x) - u.angle * "
          "0.017453292519943295;\n"
          "  float bladeBase = sin(angle * u.blades) + 0.01 * u.bias;\n"
          "  float blade = u.intensity * clamp(pow(bladeBase, u.sharpness), "
          "0.0, 1.0);\n"
          "  float4 premultiplied = float4(u.color.rgb * u.color.a, "
          "u.color.a);\n"
          "  return premultiplied * (1.0 + blade) / max(length(p), 1.0e-6);\n"
          "}\n"
          "float4 causticsTextureRND2D(float2 uv, float time) {\n"
          "  uv = floor(uv);\n"
          "  float v = uv.x + uv.y * 1.0e3;\n"
          "  float4 res = fract(1.0e5 * sin(float4(v * 1.0e-2, "
          "(v + 1.0) * 1.0e-2, (v + 1.0e3) * 1.0e-2, "
          "(v + 1.0e3 + 1.0) * 1.0e-2)));\n"
          "  return 2.0 * abs(fract(res + float4(time * 0.03)) - 0.5);\n"
          "}\n"
          "float causticsNoise(float2 p, float time) {\n"
          "  float4 r = causticsTextureRND2D(p, time);\n"
          "  float2 f = fract(p);\n"
          "  f = f * f * (3.0 - 2.0 * f);\n"
          "  return mix(mix(r.x, r.y, f.x), mix(r.z, r.w, f.x), f.y);\n"
          "}\n"
          "float causticsBuildColor(float2 p, float time) {\n"
          "  p += causticsNoise(p, time);\n"
          "  return 1.0 - abs(pow(abs(causticsNoise(p, time) - 0.5), "
          "0.75)) * 1.7;\n"
          "}\n"
          "fragment float4 tgraphicsCausticsFragment(VertexOut in "
          "[[stage_in]], constant CausticsUniforms &u [[buffer(0)]]) {\n"
          "  float2 p = float2(in.position.x * u.a11 + in.position.y * "
          "u.a12 + u.a13, in.position.x * u.a21 + in.position.y * u.a22 + "
          "u.a23);\n"
          "  float speed = 0.15;\n"
          "  float c1 = causticsBuildColor(p * 0.03 + u.time * speed, "
          "u.time);\n"
          "  float c2 = causticsBuildColor(p * 0.03 - u.time * speed, "
          "u.time);\n"
          "  float c3 = causticsBuildColor(p * 0.02 - u.time * speed, "
          "u.time);\n"
          "  float c4 = causticsBuildColor(p * 0.02 + u.time * speed, "
          "u.time);\n"
          "  float cf = pow(c1 * c2 * c3 * c4 + 0.5, 6.0);\n"
          "  float4 outColor = float4(float3(cf), 0.0) + u.color;\n"
          "  outColor.rgb *= outColor.a;\n"
          "  return outColor;\n"
          "}\n"
          "float starskyHash(float n) { return fract(sin(n) * 43758.5453); }\n"
          "float starskyRand(float2 co) {\n"
          "  return fract(sin(dot(co.xy, float2(12.9898, 78.233))) * "
          "43758.5453);\n"
          "}\n"
          "float starskyNoise(float2 x) {\n"
          "  float2 p = floor(x);\n"
          "  float2 f = fract(x);\n"
          "  f = f * f * (3.0 - 2.0 * f);\n"
          "  float n = p.x + p.y * 57.0;\n"
          "  return mix(mix(starskyHash(n + 0.0), starskyHash(n + 1.0), "
          "f.x), mix(starskyHash(n + 57.0), starskyHash(n + 58.0), f.x), "
          "f.y);\n"
          "}\n"
          "float3 starskyCloud(float2 p, float4 color) {\n"
          "  float f = 0.0;\n"
          "  f += 0.50000 * starskyNoise(p * 1.0 * 10.0);\n"
          "  f += 0.25000 * starskyNoise(p * 2.0 * 10.0);\n"
          "  f += 0.12500 * starskyNoise(p * 4.0 * 10.0);\n"
          "  f += 0.06250 * starskyNoise(p * 8.0 * 10.0);\n"
          "  f *= f;\n"
          "  return color.rgb * color.a * f * 0.6;\n"
          "}\n"
          "fragment float4 tgraphicsStarskyFragment(VertexOut in "
          "[[stage_in]], constant StarskyUniforms &u [[buffer(0)]]) {\n"
          "  float2 pos = 0.01 * float2(in.position.x * u.a11 + "
          "in.position.y * u.a12 + u.a13, in.position.x * u.a21 + "
          "in.position.y * u.a22 + u.a23);\n"
          "  float3 outRgb = starskyCloud(pos, u.color);\n"
          "  float dist = length(pos);\n"
          "  float2 coord = float2(dist, atan2(pos.y, pos.x));\n"
          "  float2 p = 40.0 * float2(coord.x, floor(coord.x + 1.0) * "
          "coord.y + starskyHash(floor(40.0 * coord.x)));\n"
          "  float2 uv = 2.0 * fract(p) - 1.0;\n"
          "  float cellValue = abs(2.0 * fract(starskyRand(floor(p)) + "
          "0.01 * u.time) - 1.0);\n"
          "  float cellBrightness = clamp((cellValue - 0.9) * u.brightness * "
          "10.0, 0.0, 1.0);\n"
          "  outRgb += clamp((1.0 - 2.0 * length(uv)) * cellBrightness, "
          "0.0, 1.0);\n"
          "  return float4(outRgb, 1.0);\n"
          "}\n"
          "float2 wavyDistort(float2 p) {\n"
          "  float theta = atan2(p.y, p.x);\n"
          "  float radius = pow(length(p), 1.3);\n"
          "  p.x = radius * cos(theta);\n"
          "  p.y = radius * sin(theta);\n"
          "  return 0.5 * (p + 1.0);\n"
          "}\n"
          "float4 wavyPattern(float2 p) {\n"
          "  float2 v = p + p.x + p.y;\n"
          "  float2 m = v - 2.0 * floor(v / 2.0) - 1.0;\n"
          "  return float4(length(m));\n"
          "}\n"
          "float wavyHash(float n) { return fract(sin(n) * 43758.5453); }\n"
          "float wavyNoise(float3 x) {\n"
          "  float3 p = floor(x);\n"
          "  float3 f = fract(x);\n"
          "  f = f * f * (3.0 - 2.0 * f);\n"
          "  float n = p.x + p.y * 57.0 + p.z * 43.0;\n"
          "  float r1 = mix(mix(wavyHash(n + 0.0), wavyHash(n + 1.0), "
          "f.x), mix(wavyHash(n + 57.0), wavyHash(n + 57.0 + 1.0), f.x), "
          "f.y);\n"
          "  float r2 = mix(mix(wavyHash(n + 43.0), wavyHash(n + 43.0 + "
          "1.0), f.x), mix(wavyHash(n + 43.0 + 57.0), wavyHash(n + 43.0 "
          "+ 57.0 + 1.0), f.x), f.y);\n"
          "  return mix(r1, r2, f.z);\n"
          "}\n"
          "fragment float4 tgraphicsWavyFragment(VertexOut in [[stage_in]], "
          "constant WavyUniforms &u [[buffer(0)]]) {\n"
          "  float2 position = 0.01 * float2(in.position.x * u.a11 + "
          "in.position.y * u.a12 + u.a13, in.position.x * u.a21 + "
          "in.position.y * u.a22 + u.a23);\n"
          "  float off = wavyNoise(float3(position.x, position.y, position.x) "
          "+ float3(u.time));\n"
          "  float4 c = wavyPattern(wavyDistort(position + off));\n"
          "  c.xy = wavyDistort(c.xy);\n"
          "  float4 col1 = float4(u.color1.rgb * u.color1.a, u.color1.a);\n"
          "  float4 col2 = float4(u.color2.rgb * u.color2.a, u.color2.a);\n"
          "  float coeff1 = c.x - off;\n"
          "  float coeff2 = cos(c.z);\n"
          "  return (coeff1 * col1 + coeff2 * col2) / (coeff1 + coeff2);\n"
          "}\n"
          "float3 fireballMod(float3 x, float y) {\n"
          "  return x - y * floor(x / y);\n"
          "}\n"
          "float fireballSnoise(float3 uv, float res) {\n"
          "  const float3 s = float3(1.0e0, 1.0e2, 1.0e4);\n"
          "  uv *= res;\n"
          "  float3 uv0 = floor(fireballMod(uv, res)) * s;\n"
          "  float3 uv1 = floor(fireballMod(uv + float3(1.0), res)) * s;\n"
          "  float3 f = fract(uv);\n"
          "  f = f * f * (3.0 - 2.0 * f);\n"
          "  float4 v = float4(uv0.x + uv0.y + uv0.z, uv1.x + uv0.y + "
          "uv0.z, uv0.x + uv1.y + uv0.z, uv1.x + uv1.y + uv0.z);\n"
          "  float4 r = fract(sin(v * 1.0e-3) * 1.0e5);\n"
          "  float r0 = mix(mix(r.x, r.y, f.x), mix(r.z, r.w, f.x), f.y);\n"
          "  r = fract(sin((v + uv1.z - uv0.z) * 1.0e-3) * 1.0e5);\n"
          "  float r1 = mix(mix(r.x, r.y, f.x), mix(r.z, r.w, f.x), f.y);\n"
          "  return 2.0 * mix(r0, r1, f.z) - 1.0;\n"
          "}\n"
          "fragment float4 tgraphicsFireballFragment(VertexOut in "
          "[[stage_in]], constant FireballUniforms &u [[buffer(0)]]) {\n"
          "  constexpr float piTwice = 6.283185307;\n"
          "  float2 p = 0.002 * float2(in.position.x * u.a11 + "
          "in.position.y * u.a12 + u.a13, in.position.x * u.a21 + "
          "in.position.y * u.a22 + u.a23);\n"
          "  float color = 3.0 * (1.0 - 2.0 * length(p));\n"
          "  float3 coord = float3(atan2(p.y, p.x) / piTwice, length(p) * "
          "0.4, 0.0);\n"
          "  for (int i = 1; i <= 7; ++i) {\n"
          "    float power = pow(2.0, float(i));\n"
          "    float3 timed = float3(0.0, -u.time * 0.02, u.time * 0.01);\n"
          "    color += 1.5 * fireballSnoise(coord + timed, power * "
          "u.detail) / power;\n"
          "  }\n"
          "  color = max(color, 0.0);\n"
          "  float4 col1 = u.color1 * u.color1.a;\n"
          "  float4 col2 = u.color2 * u.color2.a;\n"
          "  float4 outColor = mix(col1, col2, color / 3.0);\n"
          "  outColor.a *= smoothstep(0.0, 1.0, color);\n"
          "  outColor.rgb *= outColor.a;\n"
          "  return outColor;\n"
          "}\n";
}

NSURL *packagedShaderLibraryURL() {
  return [[NSBundle mainBundle] URLForResource:@"tgraphics_metal_shaders"
                                 withExtension:@"metallib"];
}

id<MTLLibrary> newShaderLibrary(MetalState &state, NSError **error) {
  if (NSURL *url = packagedShaderLibraryURL()) {
    NSError *loadError      = nil;
    id<MTLLibrary> library = [state.m_device newLibraryWithURL:url error:&loadError];
    if (library) return library;

    logMetalError(@"load packaged shader library", loadError);
  }

  if (error) *error = nil;
  return [state.m_device newLibraryWithSource:shaderSource() options:nil error:error];
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

struct SunflareUniforms {
  float m_a11         = 1.0f;
  float m_a12         = 0.0f;
  float m_a13         = 0.0f;
  float m_a21         = 0.0f;
  float m_a22         = 1.0f;
  float m_a23         = 0.0f;
  float m_padding0[2] = {0.0f, 0.0f};
  float m_color[4]    = {1.0f, 1.0f, 1.0f, 1.0f};
  float m_blades      = 6.0f;
  float m_intensity   = 1.0f;
  float m_angle       = 0.0f;
  float m_bias        = 0.0f;
  float m_sharpness   = 3.0f;
};

struct CausticsUniforms {
  float m_a11         = 1.0f;
  float m_a12         = 0.0f;
  float m_a13         = 0.0f;
  float m_a21         = 0.0f;
  float m_a22         = 1.0f;
  float m_a23         = 0.0f;
  float m_padding0[2] = {0.0f, 0.0f};
  float m_color[4]    = {0.0f, 120.0f / 255.0f, 1.0f, 1.0f};
  float m_time        = 0.0f;
};

struct StarskyUniforms {
  float m_a11          = 1.0f;
  float m_a12          = 0.0f;
  float m_a13          = 0.0f;
  float m_a21          = 0.0f;
  float m_a22          = 1.0f;
  float m_a23          = 0.0f;
  float m_padding0[2]  = {0.0f, 0.0f};
  float m_color[4]     = {128.0f / 255.0f, 0.0f, 1.0f, 1.0f};
  float m_time         = 0.0f;
  float m_brightness   = 1.0f;
  float m_padding1[2]  = {0.0f, 0.0f};
};

struct WavyUniforms {
  float m_a11         = 1.0f;
  float m_a12         = 0.0f;
  float m_a13         = 0.0f;
  float m_a21         = 0.0f;
  float m_a22         = 1.0f;
  float m_a23         = 0.0f;
  float m_padding0[2] = {0.0f, 0.0f};
  float m_color1[4]   = {0.0f, 0.0f, 1.0f, 1.0f};
  float m_color2[4]   = {1.0f, 0.0f, 0.0f, 1.0f};
  float m_time        = 0.0f;
};

struct FireballUniforms {
  float m_a11         = 1.0f;
  float m_a12         = 0.0f;
  float m_a13         = 0.0f;
  float m_a21         = 0.0f;
  float m_a22         = 1.0f;
  float m_a23         = 0.0f;
  float m_padding0[2] = {0.0f, 0.0f};
  float m_color1[4]   = {1.0f, 0.0f, 0.0f, 1.0f};
  float m_color2[4]   = {225.0f / 255.0f, 200.0f / 255.0f, 0.0f, 1.0f};
  float m_detail      = 12.0f;
  float m_time        = 0.0f;
};

id<MTLRenderPipelineState> proceduralShaderPipelineState(id<MTLRenderPipelineState> &pipeline,
                                                         bool &attempted, NSString *label,
                                                         NSString *fragmentFunctionName) {
  if (attempted) return pipeline;
  attempted = true;

  MetalState &state      = metalState();
  NSError *error         = nil;
  id<MTLLibrary> library = newShaderLibrary(state, &error);
  if (!library) {
    logMetalError(@"compile shader library", error);
    return nil;
  }

  id<MTLFunction> vertexFunction   = [library newFunctionWithName:@"tgraphicsVertex"];
  id<MTLFunction> fragmentFunction = [library newFunctionWithName:fragmentFunctionName];

  MTLRenderPipelineDescriptor *descriptor        = [[MTLRenderPipelineDescriptor alloc] init];
  descriptor.label                               = label;
  descriptor.vertexFunction                      = vertexFunction;
  descriptor.fragmentFunction                    = fragmentFunction;
  descriptor.colorAttachments[0].pixelFormat     = MTLPixelFormatBGRA8Unorm;
  descriptor.colorAttachments[0].blendingEnabled = NO;

  pipeline = [state.m_device newRenderPipelineStateWithDescriptor:descriptor error:&error];
  if (!pipeline) logMetalError(label, error);

#if !__has_feature(objc_arc)
  [descriptor release];
  [fragmentFunction release];
  [vertexFunction release];
  [library release];
#endif

  return pipeline;
}

id<MTLRenderPipelineState> sunflarePipelineState() {
  static id<MTLRenderPipelineState> pipeline = nil;
  static bool attempted                      = false;
  return proceduralShaderPipelineState(pipeline, attempted, @"create sunflare pipeline",
                                       @"tgraphicsSunflareFragment");
}

id<MTLRenderPipelineState> causticsPipelineState() {
  static id<MTLRenderPipelineState> pipeline = nil;
  static bool attempted                      = false;
  return proceduralShaderPipelineState(pipeline, attempted, @"create caustics pipeline",
                                       @"tgraphicsCausticsFragment");
}

id<MTLRenderPipelineState> starskyPipelineState() {
  static id<MTLRenderPipelineState> pipeline = nil;
  static bool attempted                      = false;
  return proceduralShaderPipelineState(pipeline, attempted, @"create starsky pipeline",
                                       @"tgraphicsStarskyFragment");
}

id<MTLRenderPipelineState> wavyPipelineState() {
  static id<MTLRenderPipelineState> pipeline = nil;
  static bool attempted                      = false;
  return proceduralShaderPipelineState(pipeline, attempted, @"create wavy pipeline",
                                       @"tgraphicsWavyFragment");
}

id<MTLRenderPipelineState> fireballPipelineState() {
  static id<MTLRenderPipelineState> pipeline = nil;
  static bool attempted                      = false;
  return proceduralShaderPipelineState(pipeline, attempted, @"create fireball pipeline",
                                       @"tgraphicsFireballFragment");
}

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

    MTLRenderPassDescriptor *pass    = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = renderTexture;
    pass.colorAttachments[0].loadAction =
        (layerTarget && !drawList.hasClearColor()) ? MTLLoadActionLoad : MTLLoadActionClear;
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

    for (const ColorQuad &quad : drawList.colorQuads()) {
      id<MTLRenderPipelineState> pipeline = colorPipelineState(quad.m_blending);
      if (!pipeline) continue;

      std::array<MetalVertex, 6> vertices = makeVertices(quad);
      const float color[4]                = {quad.m_color.r / 255.0f, quad.m_color.g / 255.0f,
                                             quad.m_color.b / 255.0f, quad.m_color.m / 255.0f};
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
        std::array<TPointD, 4> points;
        if (!makeStrokedLineQuad(line, points)) continue;
        std::array<MetalVertex, 6> vertices = makeVertices(points);
        [encoder setVertexBytes:vertices.data()
                         length:vertices.size() * sizeof(MetalVertex)
                        atIndex:0];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
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

      std::array<MetalVertex, 6> vertices = makeVertices(quad);
      const float colorScale[4] = {quad.m_colorScale.r / 255.0f, quad.m_colorScale.g / 255.0f,
                                   quad.m_colorScale.b / 255.0f, quad.m_colorScale.m / 255.0f};
      [encoder setRenderPipelineState:pipeline];
      [encoder setVertexBytes:vertices.data()
                       length:vertices.size() * sizeof(MetalVertex)
                      atIndex:0];
      [encoder setFragmentBytes:colorScale length:sizeof(colorScale) atIndex:0];
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
    id<MTLLibrary> library = newShaderLibrary(state, &error);
    if (!library) {
      logMetalError(@"compile shader library", error);
      return nil;
    }

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
    if (!pipeline) logMetalError(@"create texture pipeline", error);

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
    id<MTLLibrary> library = newShaderLibrary(state, &error);
    if (!library) {
      logMetalError(@"compile shader library", error);
      return nil;
    }

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
    if (!pipeline) logMetalError(@"create color pipeline", error);

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

  std::array<MetalVertex, 6> makeVertices(const TextureQuad &quad) const {
    const TPointD &p00 = quad.m_points[0];
    const TPointD &p10 = quad.m_points[1];
    const TPointD &p11 = quad.m_points[2];
    const TPointD &p01 = quad.m_points[3];

    return {{{pixelToClipX(p00.x), pixelToClipY(p00.y), 0.0f, 0.0f},
             {pixelToClipX(p10.x), pixelToClipY(p10.y), 1.0f, 0.0f},
             {pixelToClipX(p01.x), pixelToClipY(p01.y), 0.0f, 1.0f},
             {pixelToClipX(p10.x), pixelToClipY(p10.y), 1.0f, 0.0f},
             {pixelToClipX(p11.x), pixelToClipY(p11.y), 1.0f, 1.0f},
             {pixelToClipX(p01.x), pixelToClipY(p01.y), 0.0f, 1.0f}}};
  }

  std::array<MetalVertex, 6> makeVertices(const ColorQuad &quad) const {
    const TPointD &p00 = quad.m_points[0];
    const TPointD &p10 = quad.m_points[1];
    const TPointD &p11 = quad.m_points[2];
    const TPointD &p01 = quad.m_points[3];

    return {{{pixelToClipX(p00.x), pixelToClipY(p00.y), 0.0f, 0.0f},
             {pixelToClipX(p10.x), pixelToClipY(p10.y), 1.0f, 0.0f},
             {pixelToClipX(p01.x), pixelToClipY(p01.y), 0.0f, 1.0f},
             {pixelToClipX(p10.x), pixelToClipY(p10.y), 1.0f, 0.0f},
             {pixelToClipX(p11.x), pixelToClipY(p11.y), 1.0f, 1.0f},
             {pixelToClipX(p01.x), pixelToClipY(p01.y), 0.0f, 1.0f}}};
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

  std::array<MetalVertex, 6> makeVertices(const std::array<TPointD, 4> &points) const {
    const TPointD &p00 = points[0];
    const TPointD &p10 = points[1];
    const TPointD &p11 = points[2];
    const TPointD &p01 = points[3];

    return {{{pixelToClipX(p00.x), pixelToClipY(p00.y), 0.0f, 0.0f},
             {pixelToClipX(p10.x), pixelToClipY(p10.y), 1.0f, 0.0f},
             {pixelToClipX(p01.x), pixelToClipY(p01.y), 0.0f, 1.0f},
             {pixelToClipX(p10.x), pixelToClipY(p10.y), 1.0f, 0.0f},
             {pixelToClipX(p11.x), pixelToClipY(p11.y), 1.0f, 1.0f},
             {pixelToClipX(p01.x), pixelToClipY(p01.y), 0.0f, 1.0f}}};
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

TRaster32P readNativeMetalRenderTarget(RenderTarget *target);

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

TRaster32P renderNativeMetalSunflare(int width, int height, const TAffine &outputToWorld,
                                     const TPixel32 &color, int blades, double intensity,
                                     double angle, double bias, double sharpness) {
  if (!probeMetalDevice() || width <= 0 || height <= 0) return TRaster32P();

  MetalTextureRenderTarget target(width, height);
  if (!target.texture()) return TRaster32P();

  id<MTLRenderPipelineState> pipeline = sunflarePipelineState();
  if (!pipeline) return TRaster32P();

  MetalState &state = metalState();

  MTLRenderPassDescriptor *pass        = [MTLRenderPassDescriptor renderPassDescriptor];
  pass.colorAttachments[0].texture     = target.texture();
  pass.colorAttachments[0].loadAction  = MTLLoadActionClear;
  pass.colorAttachments[0].storeAction = MTLStoreActionStore;
  pass.colorAttachments[0].clearColor  = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);

  id<MTLCommandBuffer> commandBuffer  = [state.m_commandQueue commandBuffer];
  commandBuffer.label                 = @"OpenToonz TGraphics Sunflare";
  id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
  encoder.label                       = @"Sunflare";

  const float left              = -1.0f;
  const float right             = 1.0f;
  const float top               = 1.0f;
  const float bottom            = -1.0f;
  const MetalVertex vertices[6] = {{left, top, 0.0f, 0.0f},     {right, top, 1.0f, 0.0f},
                                   {left, bottom, 0.0f, 1.0f},  {right, top, 1.0f, 0.0f},
                                   {right, bottom, 1.0f, 1.0f}, {left, bottom, 0.0f, 1.0f}};

  SunflareUniforms uniforms;
  uniforms.m_a11       = static_cast<float>(outputToWorld.a11);
  uniforms.m_a12       = static_cast<float>(outputToWorld.a12);
  uniforms.m_a13       = static_cast<float>(outputToWorld.a13);
  uniforms.m_a21       = static_cast<float>(outputToWorld.a21);
  uniforms.m_a22       = static_cast<float>(outputToWorld.a22);
  uniforms.m_a23       = static_cast<float>(outputToWorld.a23);
  uniforms.m_color[0]  = color.r / 255.0f;
  uniforms.m_color[1]  = color.g / 255.0f;
  uniforms.m_color[2]  = color.b / 255.0f;
  uniforms.m_color[3]  = color.m / 255.0f;
  uniforms.m_blades    = static_cast<float>(std::max(1, blades));
  uniforms.m_intensity = static_cast<float>(intensity);
  uniforms.m_angle     = static_cast<float>(angle);
  uniforms.m_bias      = static_cast<float>(bias);
  uniforms.m_sharpness = static_cast<float>(sharpness);

  [encoder setRenderPipelineState:pipeline];
  [encoder setVertexBytes:vertices length:sizeof(vertices) atIndex:0];
  [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
  [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
  [encoder endEncoding];
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];

  return readNativeMetalRenderTarget(&target);
}

TRaster32P renderNativeMetalCaustics(int width, int height, const TAffine &outputToWorld,
                                     const TPixel32 &color, double time) {
  if (!probeMetalDevice() || width <= 0 || height <= 0) return TRaster32P();

  MetalTextureRenderTarget target(width, height);
  if (!target.texture()) return TRaster32P();

  id<MTLRenderPipelineState> pipeline = causticsPipelineState();
  if (!pipeline) return TRaster32P();

  MetalState &state = metalState();

  MTLRenderPassDescriptor *pass        = [MTLRenderPassDescriptor renderPassDescriptor];
  pass.colorAttachments[0].texture     = target.texture();
  pass.colorAttachments[0].loadAction  = MTLLoadActionClear;
  pass.colorAttachments[0].storeAction = MTLStoreActionStore;
  pass.colorAttachments[0].clearColor  = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);

  id<MTLCommandBuffer> commandBuffer  = [state.m_commandQueue commandBuffer];
  commandBuffer.label                 = @"OpenToonz TGraphics Caustics";
  id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
  encoder.label                       = @"Caustics";

  const float left              = -1.0f;
  const float right             = 1.0f;
  const float top               = 1.0f;
  const float bottom            = -1.0f;
  const MetalVertex vertices[6] = {{left, top, 0.0f, 0.0f},     {right, top, 1.0f, 0.0f},
                                   {left, bottom, 0.0f, 1.0f},  {right, top, 1.0f, 0.0f},
                                   {right, bottom, 1.0f, 1.0f}, {left, bottom, 0.0f, 1.0f}};

  CausticsUniforms uniforms;
  uniforms.m_a11      = static_cast<float>(outputToWorld.a11);
  uniforms.m_a12      = static_cast<float>(outputToWorld.a12);
  uniforms.m_a13      = static_cast<float>(outputToWorld.a13);
  uniforms.m_a21      = static_cast<float>(outputToWorld.a21);
  uniforms.m_a22      = static_cast<float>(outputToWorld.a22);
  uniforms.m_a23      = static_cast<float>(outputToWorld.a23);
  uniforms.m_color[0] = color.r / 255.0f;
  uniforms.m_color[1] = color.g / 255.0f;
  uniforms.m_color[2] = color.b / 255.0f;
  uniforms.m_color[3] = color.m / 255.0f;
  uniforms.m_time     = static_cast<float>(time);

  [encoder setRenderPipelineState:pipeline];
  [encoder setVertexBytes:vertices length:sizeof(vertices) atIndex:0];
  [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
  [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
  [encoder endEncoding];
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];

  return readNativeMetalRenderTarget(&target);
}

TRaster32P renderNativeMetalStarsky(int width, int height, const TAffine &outputToWorld,
                                    const TPixel32 &color, double time,
                                    double brightness) {
  if (!probeMetalDevice() || width <= 0 || height <= 0) return TRaster32P();

  MetalTextureRenderTarget target(width, height);
  if (!target.texture()) return TRaster32P();

  id<MTLRenderPipelineState> pipeline = starskyPipelineState();
  if (!pipeline) return TRaster32P();

  MetalState &state = metalState();

  MTLRenderPassDescriptor *pass        = [MTLRenderPassDescriptor renderPassDescriptor];
  pass.colorAttachments[0].texture     = target.texture();
  pass.colorAttachments[0].loadAction  = MTLLoadActionClear;
  pass.colorAttachments[0].storeAction = MTLStoreActionStore;
  pass.colorAttachments[0].clearColor  = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);

  id<MTLCommandBuffer> commandBuffer  = [state.m_commandQueue commandBuffer];
  commandBuffer.label                 = @"OpenToonz TGraphics Starsky";
  id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
  encoder.label                       = @"Starsky";

  const float left              = -1.0f;
  const float right             = 1.0f;
  const float top               = 1.0f;
  const float bottom            = -1.0f;
  const MetalVertex vertices[6] = {{left, top, 0.0f, 0.0f},     {right, top, 1.0f, 0.0f},
                                   {left, bottom, 0.0f, 1.0f},  {right, top, 1.0f, 0.0f},
                                   {right, bottom, 1.0f, 1.0f}, {left, bottom, 0.0f, 1.0f}};

  StarskyUniforms uniforms;
  uniforms.m_a11        = static_cast<float>(outputToWorld.a11);
  uniforms.m_a12        = static_cast<float>(outputToWorld.a12);
  uniforms.m_a13        = static_cast<float>(outputToWorld.a13);
  uniforms.m_a21        = static_cast<float>(outputToWorld.a21);
  uniforms.m_a22        = static_cast<float>(outputToWorld.a22);
  uniforms.m_a23        = static_cast<float>(outputToWorld.a23);
  uniforms.m_color[0]   = color.r / 255.0f;
  uniforms.m_color[1]   = color.g / 255.0f;
  uniforms.m_color[2]   = color.b / 255.0f;
  uniforms.m_color[3]   = color.m / 255.0f;
  uniforms.m_time       = static_cast<float>(time);
  uniforms.m_brightness = static_cast<float>(brightness);

  [encoder setRenderPipelineState:pipeline];
  [encoder setVertexBytes:vertices length:sizeof(vertices) atIndex:0];
  [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
  [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
  [encoder endEncoding];
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];

  return readNativeMetalRenderTarget(&target);
}

TRaster32P renderNativeMetalWavy(int width, int height, const TAffine &outputToWorld,
                                 const TPixel32 &color1, const TPixel32 &color2,
                                 double time) {
  if (!probeMetalDevice() || width <= 0 || height <= 0) return TRaster32P();

  MetalTextureRenderTarget target(width, height);
  if (!target.texture()) return TRaster32P();

  id<MTLRenderPipelineState> pipeline = wavyPipelineState();
  if (!pipeline) return TRaster32P();

  MetalState &state = metalState();

  MTLRenderPassDescriptor *pass        = [MTLRenderPassDescriptor renderPassDescriptor];
  pass.colorAttachments[0].texture     = target.texture();
  pass.colorAttachments[0].loadAction  = MTLLoadActionClear;
  pass.colorAttachments[0].storeAction = MTLStoreActionStore;
  pass.colorAttachments[0].clearColor  = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);

  id<MTLCommandBuffer> commandBuffer  = [state.m_commandQueue commandBuffer];
  commandBuffer.label                 = @"OpenToonz TGraphics Wavy";
  id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
  encoder.label                       = @"Wavy";

  const float left              = -1.0f;
  const float right             = 1.0f;
  const float top               = 1.0f;
  const float bottom            = -1.0f;
  const MetalVertex vertices[6] = {{left, top, 0.0f, 0.0f},     {right, top, 1.0f, 0.0f},
                                   {left, bottom, 0.0f, 1.0f},  {right, top, 1.0f, 0.0f},
                                   {right, bottom, 1.0f, 1.0f}, {left, bottom, 0.0f, 1.0f}};

  WavyUniforms uniforms;
  uniforms.m_a11       = static_cast<float>(outputToWorld.a11);
  uniforms.m_a12       = static_cast<float>(outputToWorld.a12);
  uniforms.m_a13       = static_cast<float>(outputToWorld.a13);
  uniforms.m_a21       = static_cast<float>(outputToWorld.a21);
  uniforms.m_a22       = static_cast<float>(outputToWorld.a22);
  uniforms.m_a23       = static_cast<float>(outputToWorld.a23);
  uniforms.m_color1[0] = color1.r / 255.0f;
  uniforms.m_color1[1] = color1.g / 255.0f;
  uniforms.m_color1[2] = color1.b / 255.0f;
  uniforms.m_color1[3] = color1.m / 255.0f;
  uniforms.m_color2[0] = color2.r / 255.0f;
  uniforms.m_color2[1] = color2.g / 255.0f;
  uniforms.m_color2[2] = color2.b / 255.0f;
  uniforms.m_color2[3] = color2.m / 255.0f;
  uniforms.m_time      = static_cast<float>(time);

  [encoder setRenderPipelineState:pipeline];
  [encoder setVertexBytes:vertices length:sizeof(vertices) atIndex:0];
  [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
  [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
  [encoder endEncoding];
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];

  return readNativeMetalRenderTarget(&target);
}

TRaster32P renderNativeMetalFireball(int width, int height, const TAffine &outputToWorld,
                                     const TPixel32 &color1, const TPixel32 &color2,
                                     double detail, double time) {
  if (!probeMetalDevice() || width <= 0 || height <= 0) return TRaster32P();

  MetalTextureRenderTarget target(width, height);
  if (!target.texture()) return TRaster32P();

  id<MTLRenderPipelineState> pipeline = fireballPipelineState();
  if (!pipeline) return TRaster32P();

  MetalState &state = metalState();

  MTLRenderPassDescriptor *pass        = [MTLRenderPassDescriptor renderPassDescriptor];
  pass.colorAttachments[0].texture     = target.texture();
  pass.colorAttachments[0].loadAction  = MTLLoadActionClear;
  pass.colorAttachments[0].storeAction = MTLStoreActionStore;
  pass.colorAttachments[0].clearColor  = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);

  id<MTLCommandBuffer> commandBuffer  = [state.m_commandQueue commandBuffer];
  commandBuffer.label                 = @"OpenToonz TGraphics Fireball";
  id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
  encoder.label                       = @"Fireball";

  const float left              = -1.0f;
  const float right             = 1.0f;
  const float top               = 1.0f;
  const float bottom            = -1.0f;
  const MetalVertex vertices[6] = {{left, top, 0.0f, 0.0f},     {right, top, 1.0f, 0.0f},
                                   {left, bottom, 0.0f, 1.0f},  {right, top, 1.0f, 0.0f},
                                   {right, bottom, 1.0f, 1.0f}, {left, bottom, 0.0f, 1.0f}};

  FireballUniforms uniforms;
  uniforms.m_a11       = static_cast<float>(outputToWorld.a11);
  uniforms.m_a12       = static_cast<float>(outputToWorld.a12);
  uniforms.m_a13       = static_cast<float>(outputToWorld.a13);
  uniforms.m_a21       = static_cast<float>(outputToWorld.a21);
  uniforms.m_a22       = static_cast<float>(outputToWorld.a22);
  uniforms.m_a23       = static_cast<float>(outputToWorld.a23);
  uniforms.m_color1[0] = color1.r / 255.0f;
  uniforms.m_color1[1] = color1.g / 255.0f;
  uniforms.m_color1[2] = color1.b / 255.0f;
  uniforms.m_color1[3] = color1.m / 255.0f;
  uniforms.m_color2[0] = color2.r / 255.0f;
  uniforms.m_color2[1] = color2.g / 255.0f;
  uniforms.m_color2[2] = color2.b / 255.0f;
  uniforms.m_color2[3] = color2.m / 255.0f;
  uniforms.m_detail    = static_cast<float>(detail);
  uniforms.m_time      = static_cast<float>(time);

  [encoder setRenderPipelineState:pipeline];
  [encoder setVertexBytes:vertices length:sizeof(vertices) atIndex:0];
  [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
  [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
  [encoder endEncoding];
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];

  return readNativeMetalRenderTarget(&target);
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
