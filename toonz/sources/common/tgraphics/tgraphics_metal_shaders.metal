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

struct CausticsUniforms {
  float a11;
  float a12;
  float a13;
  float a21;
  float a22;
  float a23;
  float4 color;
  float time;
};

struct StarskyUniforms {
  float a11;
  float a12;
  float a13;
  float a21;
  float a22;
  float a23;
  float4 color;
  float time;
  float brightness;
};

struct WavyUniforms {
  float a11;
  float a12;
  float a13;
  float a21;
  float a22;
  float a23;
  float4 color1;
  float4 color2;
  float time;
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

float4 causticsTextureRND2D(float2 uv, float time) {
  uv = floor(uv);
  float v = uv.x + uv.y * 1.0e3;
  float4 res = fract(1.0e5 * sin(float4(v * 1.0e-2, (v + 1.0) * 1.0e-2,
                                          (v + 1.0e3) * 1.0e-2,
                                          (v + 1.0e3 + 1.0) * 1.0e-2)));
  return 2.0 * abs(fract(res + float4(time * 0.03)) - 0.5);
}

float causticsNoise(float2 p, float time) {
  float4 r = causticsTextureRND2D(p, time);
  float2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(r.x, r.y, f.x), mix(r.z, r.w, f.x), f.y);
}

float causticsBuildColor(float2 p, float time) {
  p += causticsNoise(p, time);
  return 1.0 - abs(pow(abs(causticsNoise(p, time) - 0.5), 0.75)) * 1.7;
}

fragment float4 tgraphicsCausticsFragment(
    VertexOut in [[stage_in]], constant CausticsUniforms &u [[buffer(0)]]) {
  float2 p = float2(in.position.x * u.a11 + in.position.y * u.a12 + u.a13,
                    in.position.x * u.a21 + in.position.y * u.a22 + u.a23);
  float speed = 0.15;
  float c1 = causticsBuildColor(p * 0.03 + u.time * speed, u.time);
  float c2 = causticsBuildColor(p * 0.03 - u.time * speed, u.time);
  float c3 = causticsBuildColor(p * 0.02 - u.time * speed, u.time);
  float c4 = causticsBuildColor(p * 0.02 + u.time * speed, u.time);
  float cf = pow(c1 * c2 * c3 * c4 + 0.5, 6.0);
  float4 outColor = float4(float3(cf), 0.0) + u.color;
  outColor.rgb *= outColor.a;
  return outColor;
}

float starskyHash(float n) { return fract(sin(n) * 43758.5453); }

float starskyRand(float2 co) {
  return fract(sin(dot(co.xy, float2(12.9898, 78.233))) * 43758.5453);
}

float starskyNoise(float2 x) {
  float2 p = floor(x);
  float2 f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  float n = p.x + p.y * 57.0;
  return mix(mix(starskyHash(n + 0.0), starskyHash(n + 1.0), f.x),
             mix(starskyHash(n + 57.0), starskyHash(n + 58.0), f.x), f.y);
}

float3 starskyCloud(float2 p, float4 color) {
  float f = 0.0;
  f += 0.50000 * starskyNoise(p * 1.0 * 10.0);
  f += 0.25000 * starskyNoise(p * 2.0 * 10.0);
  f += 0.12500 * starskyNoise(p * 4.0 * 10.0);
  f += 0.06250 * starskyNoise(p * 8.0 * 10.0);
  f *= f;

  return color.rgb * color.a * f * 0.6;
}

fragment float4 tgraphicsStarskyFragment(
    VertexOut in [[stage_in]], constant StarskyUniforms &u [[buffer(0)]]) {
  float2 pos =
      0.01 * float2(in.position.x * u.a11 + in.position.y * u.a12 + u.a13,
                    in.position.x * u.a21 + in.position.y * u.a22 + u.a23);

  float3 outRgb = starskyCloud(pos, u.color);

  float dist = length(pos);
  float2 coord = float2(dist, atan2(pos.y, pos.x));

  float2 p =
      40.0 * float2(coord.x, floor(coord.x + 1.0) * coord.y +
                                 starskyHash(floor(40.0 * coord.x)));

  float2 uv = 2.0 * fract(p) - 1.0;

  float cellValue =
      abs(2.0 * fract(starskyRand(floor(p)) + 0.01 * u.time) - 1.0);
  float cellBrightness =
      clamp((cellValue - 0.9) * u.brightness * 10.0, 0.0, 1.0);

  outRgb += clamp((1.0 - 2.0 * length(uv)) * cellBrightness, 0.0, 1.0);

  return float4(outRgb, 1.0);
}

float2 wavyDistort(float2 p) {
  float theta = atan2(p.y, p.x);
  float radius = pow(length(p), 1.3);
  p.x = radius * cos(theta);
  p.y = radius * sin(theta);
  return 0.5 * (p + 1.0);
}

float4 wavyPattern(float2 p) {
  float2 v = p + p.x + p.y;
  float2 m = v - 2.0 * floor(v / 2.0) - 1.0;
  return float4(length(m));
}

float wavyHash(float n) { return fract(sin(n) * 43758.5453); }

float wavyNoise(float3 x) {
  float3 p = floor(x);
  float3 f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  float n = p.x + p.y * 57.0 + p.z * 43.0;
  float r1 =
      mix(mix(wavyHash(n + 0.0), wavyHash(n + 1.0), f.x),
          mix(wavyHash(n + 57.0), wavyHash(n + 58.0), f.x), f.y);
  float r2 = mix(
      mix(wavyHash(n + 43.0), wavyHash(n + 44.0), f.x),
      mix(wavyHash(n + 100.0), wavyHash(n + 101.0), f.x), f.y);
  return mix(r1, r2, f.z);
}

fragment float4 tgraphicsWavyFragment(
    VertexOut in [[stage_in]], constant WavyUniforms &u [[buffer(0)]]) {
  float2 position =
      0.01 * float2(in.position.x * u.a11 + in.position.y * u.a12 + u.a13,
                    in.position.x * u.a21 + in.position.y * u.a22 + u.a23);
  float off = wavyNoise(float3(position.x, position.y, position.x) +
                        float3(u.time));
  float4 c = wavyPattern(wavyDistort(position + off));
  c.xy = wavyDistort(c.xy);
  float4 col1 = float4(u.color1.rgb * u.color1.a, u.color1.a);
  float4 col2 = float4(u.color2.rgb * u.color2.a, u.color2.a);
  float coeff1 = c.x - off;
  float coeff2 = cos(c.z);
  return (coeff1 * col1 + coeff2 * col2) / (coeff1 + coeff2);
}
