#include "tgraphics.h"

#include "tgl.h"

#include <algorithm>
#include <cassert>
#include <cctype>
#include <cstdlib>
#include <iostream>
#include <string>

namespace TGraphics {
namespace {

std::string normalizedBackendName() {
  const char *value = std::getenv("OPENTOONZ_GRAPHICS_BACKEND");
  if (!value) return std::string();

  std::string name(value);
  std::transform(name.begin(), name.end(), name.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  return name;
}

void warnMetalUnavailableOnce() {
  static bool alreadyWarned = false;
  if (alreadyWarned) return;

  std::cerr << "OPENTOONZ_GRAPHICS_BACKEND=metal was requested, but the "
               "Metal backend is not available in this build. Falling back "
               "to OpenGL."
            << std::endl;
  alreadyWarned = true;
}

}  // namespace

RenderTarget::~RenderTarget() {}
Texture::~Texture() {}
Buffer::~Buffer() {}
Pipeline::~Pipeline() {}
ShaderLibrary::~ShaderLibrary() {}
HitTest::~HitTest() {}
CommandEncoder::~CommandEncoder() {}
Device::~Device() {}

RasterTexture::RasterTexture(const TRaster32P &raster) : m_raster(raster) {}

const TRaster32P &RasterTexture::raster() const { return m_raster; }

void DrawList2D::addTexture(const TRectD &rect, const TRaster32P &raster,
                            bool blending) {
  TextureQuad quad;
  quad.m_rect     = rect;
  quad.m_texture  = std::make_shared<RasterTexture>(raster);
  quad.m_blending = blending;
  m_textureQuads.push_back(quad);
}

const std::vector<TextureQuad> &DrawList2D::textureQuads() const {
  return m_textureQuads;
}

bool DrawList2D::empty() const { return m_textureQuads.empty(); }

class OpenGLCommandEncoder final : public CommandEncoder {
public:
  BackendType backendType() const override { return BackendType::OpenGL; }

  void draw(const DrawList2D &drawList) override {
    for (const TextureQuad &quad : drawList.textureQuads()) {
      const RasterTexture *texture =
          dynamic_cast<const RasterTexture *>(quad.m_texture.get());
      assert(texture);
      if (!texture) continue;

      tglDraw(quad.m_rect, texture->raster(), quad.m_blending);
    }
  }
};

class OpenGLDevice final : public Device {
public:
  BackendType backendType() const override { return BackendType::OpenGL; }

  std::unique_ptr<CommandEncoder> createCommandEncoder(
      RenderTarget *target = 0) override {
    (void)target;
    return std::unique_ptr<CommandEncoder>(new OpenGLCommandEncoder());
  }
};

Device &openGLDevice() {
  static OpenGLDevice device;
  return device;
}

bool isMetalBuildEnabled() {
#ifdef OPENTOONZ_WITH_GRAPHICS_METAL
  return true;
#else
  return false;
#endif
}

bool isMetalBackendAvailable() {
  return false;
}

BackendType requestedBackendType() {
  const std::string backendName = normalizedBackendName();
  if (backendName == "metal") return BackendType::Metal;
  return BackendType::OpenGL;
}

BackendType activeBackendType() {
  if (requestedBackendType() == BackendType::Metal &&
      isMetalBackendAvailable()) {
    return BackendType::Metal;
  }
  return BackendType::OpenGL;
}

Device &activeDevice() {
  if (requestedBackendType() == BackendType::Metal &&
      !isMetalBackendAvailable()) {
    warnMetalUnavailableOnce();
  }

  return openGLDevice();
}

void drawWithOpenGLBackend(const DrawList2D &drawList) {
  std::unique_ptr<CommandEncoder> encoder =
      openGLDevice().createCommandEncoder();
  encoder->draw(drawList);
}

void drawWithActiveBackend(const DrawList2D &drawList) {
  std::unique_ptr<CommandEncoder> encoder =
      activeDevice().createCommandEncoder();
  encoder->draw(drawList);
}

}  // namespace TGraphics
