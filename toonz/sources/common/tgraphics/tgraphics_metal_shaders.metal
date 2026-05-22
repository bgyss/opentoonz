#include <metal_stdlib>

using namespace metal;

struct VertexIn {
  float2 position;
  float2 texCoord;
};

struct VertexOut {
  float4 position [[position]];
  float2 texCoord;
};

vertex VertexOut tgraphicsVertex(uint vertexId [[vertex_id]],
                                 constant VertexIn *vertices [[buffer(0)]]) {
  VertexIn in = vertices[vertexId];
  VertexOut out;
  out.position = float4(in.position, 0.0, 1.0);
  out.texCoord = in.texCoord;
  return out;
}

fragment float4 tgraphicsFragment(VertexOut in [[stage_in]],
                                  texture2d<float> colorTexture [[texture(0)]],
                                  sampler colorSampler [[sampler(0)]],
                                  constant float4 &colorScale [[buffer(0)]]) {
  return colorTexture.sample(colorSampler, in.texCoord) * colorScale;
}

fragment float4 tgraphicsColorFragment(VertexOut in [[stage_in]],
                                       constant float4 &color [[buffer(0)]]) {
  return color;
}

struct SunflareUniforms {
  float a11;
  float a12;
  float a13;
  float a21;
  float a22;
  float a23;
  float4 color;
  float blades;
  float intensity;
  float angle;
  float bias;
  float sharpness;
};

fragment float4 tgraphicsSunflareFragment(
    VertexOut in [[stage_in]],
    constant SunflareUniforms &u [[buffer(0)]]) {
  float2 world =
      float2(in.position.x * u.a11 + in.position.y * u.a12 + u.a13,
             in.position.x * u.a21 + in.position.y * u.a22 + u.a23);
  float2 p = 0.03 * world;
  float shiftedAngle = atan2(p.y, p.x) - u.angle * 0.017453292519943295;
  float bladeBase = sin(shiftedAngle * u.blades) + 0.01 * u.bias;
  float blade = u.intensity * clamp(pow(bladeBase, u.sharpness), 0.0, 1.0);
  float4 premultiplied = float4(u.color.rgb * u.color.a, u.color.a);
  return premultiplied * (1.0 + blade) / max(length(p), 1.0e-6);
}
