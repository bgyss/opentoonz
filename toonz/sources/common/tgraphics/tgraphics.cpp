#include "tgraphics.h"

#include "tgl.h"

#include <QGuiApplication>
#include <QOffscreenSurface>
#include <QOpenGLContext>
#include <QOpenGLFramebufferObject>
#include <QOpenGLFramebufferObjectFormat>
#include <QSurfaceFormat>

#include <algorithm>
#include <cassert>
#include <cctype>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

namespace TGraphics {

#ifdef OPENTOONZ_WITH_GRAPHICS_METAL
Device& nativeMetalDevice();
bool probeMetalDevice();
const char* probeMetalDeviceName();
void* createNativeMetalLayerForView(void* nativeView);
std::unique_ptr<RenderTarget> createNativeMetalLayerRenderTarget(
    void* metalLayer, int width, int height, double devicePixelRatio);
std::unique_ptr<RenderTarget> createNativeMetalImageRenderTarget(int width,
                                                                 int height);
bool isNativeMetalLayerRenderTarget(const RenderTarget* target);
TRaster32P readNativeMetalRenderTarget(RenderTarget* target);
#endif

namespace {

std::string normalizedBackendName() {
  const char* value = std::getenv("OPENTOONZ_GRAPHICS_BACKEND");
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

  if (isMetalBuildEnabled() && isMetalDeviceAvailable()) {
    std::cerr << "OPENTOONZ_GRAPHICS_BACKEND=metal was requested, and Metal "
                 "device \""
              << metalDeviceName()
              << "\" is available, but Metal rendering is not wired to a "
                 "viewer render target yet. Falling back to OpenGL."
              << std::endl;
  } else {
    std::cerr << "OPENTOONZ_GRAPHICS_BACKEND=metal was requested, but the "
                 "Metal backend is not available in this build. Falling back "
                 "to OpenGL."
              << std::endl;
  }
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

RasterTexture::RasterTexture(const TRaster32P& raster) : m_raster(raster) {}

const TRaster32P& RasterTexture::raster() const { return m_raster; }

void DrawList2D::addTexture(const TRectD& rect, const TRaster32P& raster,
                            bool blending) {
  TextureQuad quad;
  quad.m_rect     = rect;
  quad.m_texture  = std::make_shared<RasterTexture>(raster);
  quad.m_blending = blending;
  m_textureQuads.push_back(quad);
}

const std::vector<TextureQuad>& DrawList2D::textureQuads() const {
  return m_textureQuads;
}

bool DrawList2D::empty() const { return m_textureQuads.empty(); }

class OpenGLImageRenderTarget final : public RenderTarget {
  std::unique_ptr<QOffscreenSurface> m_surface;
  std::unique_ptr<QOpenGLContext> m_context;
  std::unique_ptr<QOpenGLFramebufferObject> m_fbo;
  int m_width  = 0;
  int m_height = 0;

public:
  OpenGLImageRenderTarget(int width, int height)
      : m_width(std::max(1, width)), m_height(std::max(1, height)) {
    if (!QGuiApplication::instance()) return;

    QSurfaceFormat format = QSurfaceFormat::defaultFormat();
    format.setProfile(QSurfaceFormat::CompatibilityProfile);

    m_surface.reset(new QOffscreenSurface());
    m_surface->setFormat(format);
    m_surface->create();
    if (!m_surface->isValid()) return;

    m_context.reset(new QOpenGLContext());
    m_context->setFormat(format);
    if (!m_context->create()) return;
    if (!m_context->makeCurrent(m_surface.get())) return;

    QOpenGLFramebufferObjectFormat fboFormat;
    fboFormat.setAttachment(QOpenGLFramebufferObject::CombinedDepthStencil);
    m_fbo.reset(new QOpenGLFramebufferObject(m_width, m_height, fboFormat));
    m_fbo->bind();
  }

  bool isValid() const { return m_context && m_surface && m_fbo; }
  int width() const { return m_width; }
  int height() const { return m_height; }

  void makeCurrent() {
    if (isValid()) m_context->makeCurrent(m_surface.get());
  }

  void doneCurrent() {
    if (m_context) m_context->doneCurrent();
  }

  QOpenGLFramebufferObject* fbo() const { return m_fbo.get(); }
};

class OpenGLCommandEncoder final : public CommandEncoder {
  RenderTarget* m_target = nullptr;

public:
  explicit OpenGLCommandEncoder(RenderTarget* target) : m_target(target) {}

  BackendType backendType() const override { return BackendType::OpenGL; }

  void draw(const DrawList2D& drawList) override {
    OpenGLImageRenderTarget* imageTarget =
        dynamic_cast<OpenGLImageRenderTarget*>(m_target);
    if (imageTarget) beginImageTargetDraw(*imageTarget);

    for (const TextureQuad& quad : drawList.textureQuads()) {
      const RasterTexture* texture =
          dynamic_cast<const RasterTexture*>(quad.m_texture.get());
      assert(texture);
      if (!texture) continue;

      tglDraw(quad.m_rect, texture->raster(), quad.m_blending);
    }

    if (imageTarget) endImageTargetDraw(*imageTarget);
  }

private:
  void beginImageTargetDraw(OpenGLImageRenderTarget& target) {
    target.makeCurrent();
    target.fbo()->bind();

    glViewport(0, 0, target.width(), target.height());
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_SCISSOR_TEST);
    glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    glMatrixMode(GL_PROJECTION);
    glPushMatrix();
    glLoadIdentity();
    glOrtho(0.0, target.width(), target.height(), 0.0, -1.0, 1.0);

    glMatrixMode(GL_MODELVIEW);
    glPushMatrix();
    glLoadIdentity();
  }

  void endImageTargetDraw(OpenGLImageRenderTarget& target) {
    glMatrixMode(GL_MODELVIEW);
    glPopMatrix();
    glMatrixMode(GL_PROJECTION);
    glPopMatrix();
    glFlush();

    target.fbo()->release();
    target.doneCurrent();
  }
};

class OpenGLDevice final : public Device {
public:
  BackendType backendType() const override { return BackendType::OpenGL; }

  std::unique_ptr<CommandEncoder> createCommandEncoder(
      RenderTarget* target = 0) override {
    return std::unique_ptr<CommandEncoder>(new OpenGLCommandEncoder(target));
  }
};

Device& openGLDevice() {
  static OpenGLDevice device;
  return device;
}

std::unique_ptr<RenderTarget> createOpenGLImageRenderTarget(int width,
                                                            int height) {
  std::unique_ptr<OpenGLImageRenderTarget> target(
      new OpenGLImageRenderTarget(width, height));
  if (!target->isValid()) return std::unique_ptr<RenderTarget>();
  return std::unique_ptr<RenderTarget>(target.release());
}

TRaster32P readOpenGLRenderTarget(RenderTarget* target) {
  OpenGLImageRenderTarget* imageTarget =
      dynamic_cast<OpenGLImageRenderTarget*>(target);
  if (!imageTarget || !imageTarget->isValid()) return TRaster32P();

  const int width  = imageTarget->width();
  const int height = imageTarget->height();
  std::vector<unsigned char> pixels(width * height * 4);

  imageTarget->makeCurrent();
  imageTarget->fbo()->bind();
  glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels.data());
  imageTarget->fbo()->release();
  imageTarget->doneCurrent();

  TRaster32P raster(width, height);
  raster->lock();
  for (int y = 0; y < height; ++y) {
    TPixel32* line           = raster->pixels(y);
    const unsigned char* src = pixels.data() + (height - 1 - y) * width * 4;
    for (int x = 0; x < width; ++x) {
      line[x] = TPixel32(src[x * 4 + 0], src[x * 4 + 1], src[x * 4 + 2],
                         src[x * 4 + 3]);
    }
  }
  raster->unlock();
  return raster;
}

Device& metalDevice() {
#ifdef OPENTOONZ_WITH_GRAPHICS_METAL
  return nativeMetalDevice();
#else
  return openGLDevice();
#endif
}

bool isMetalBuildEnabled() {
#ifdef OPENTOONZ_WITH_GRAPHICS_METAL
  return true;
#else
  return false;
#endif
}

bool isMetalDeviceAvailable() {
#ifdef OPENTOONZ_WITH_GRAPHICS_METAL
  return probeMetalDevice();
#else
  return false;
#endif
}

const char* metalDeviceName() {
#ifdef OPENTOONZ_WITH_GRAPHICS_METAL
  return probeMetalDeviceName();
#else
  return "";
#endif
}

std::unique_ptr<RenderTarget> createMetalLayerRenderTarget(
    void* metalLayer, int width, int height, double devicePixelRatio) {
#ifdef OPENTOONZ_WITH_GRAPHICS_METAL
  return createNativeMetalLayerRenderTarget(metalLayer, width, height,
                                            devicePixelRatio);
#else
  (void)metalLayer;
  (void)width;
  (void)height;
  (void)devicePixelRatio;
  return std::unique_ptr<RenderTarget>();
#endif
}

void* createMetalLayerForNativeView(void* nativeView) {
#ifdef OPENTOONZ_WITH_GRAPHICS_METAL
  return createNativeMetalLayerForView(nativeView);
#else
  (void)nativeView;
  return nullptr;
#endif
}

std::unique_ptr<RenderTarget> createMetalImageRenderTarget(int width,
                                                           int height) {
#ifdef OPENTOONZ_WITH_GRAPHICS_METAL
  return createNativeMetalImageRenderTarget(width, height);
#else
  (void)width;
  (void)height;
  return std::unique_ptr<RenderTarget>();
#endif
}

bool isMetalLayerRenderTarget(const RenderTarget* target) {
#ifdef OPENTOONZ_WITH_GRAPHICS_METAL
  return isNativeMetalLayerRenderTarget(target);
#else
  (void)target;
  return false;
#endif
}

TRaster32P readMetalRenderTarget(RenderTarget* target) {
#ifdef OPENTOONZ_WITH_GRAPHICS_METAL
  return readNativeMetalRenderTarget(target);
#else
  (void)target;
  return TRaster32P();
#endif
}

bool isMetalBackendAvailable() {
  return isMetalBuildEnabled() && isMetalDeviceAvailable();
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

Device& activeDevice() {
  if (requestedBackendType() == BackendType::Metal &&
      !isMetalBackendAvailable()) {
    warnMetalUnavailableOnce();
  }

  if (activeBackendType() == BackendType::Metal) return metalDevice();
  return openGLDevice();
}

void drawWithOpenGLBackend(const DrawList2D& drawList) {
  std::unique_ptr<CommandEncoder> encoder =
      openGLDevice().createCommandEncoder();
  encoder->draw(drawList);
}

void drawWithActiveBackend(const DrawList2D& drawList) {
  std::unique_ptr<CommandEncoder> encoder =
      activeDevice().createCommandEncoder();
  encoder->draw(drawList);
}

}  // namespace TGraphics
