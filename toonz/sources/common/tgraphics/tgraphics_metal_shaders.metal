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
                                  sampler colorSampler [[sampler(0)]]) {
  return colorTexture.sample(colorSampler, in.texCoord);
}
