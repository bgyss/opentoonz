#include "tgraphics.h"

#include "tgl.h"

#include <cassert>

namespace TGraphics {

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

void drawWithOpenGLBackend(const DrawList2D &drawList) {
  std::unique_ptr<CommandEncoder> encoder =
      openGLDevice().createCommandEncoder();
  encoder->draw(drawList);
}

}  // namespace TGraphics
