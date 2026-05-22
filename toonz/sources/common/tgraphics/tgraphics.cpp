#include "tgraphics.h"

#include "tgl.h"

#include <QGuiApplication>
#include <QOffscreenSurface>
#include <QOpenGLContext>
#include <QOpenGLFramebufferObject>
#include <QOpenGLFramebufferObjectFormat>
#include <QSurfaceFormat>

#include <algorithm>
#include <array>
#include <cassert>
#include <cctype>
#include <cmath>
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
TRaster32P renderNativeMetalSunflare(int width, int height,
                                     const TAffine& outputToWorld,
                                     const TPixel32& color, int blades,
                                     double intensity, double angle,
                                     double bias, double sharpness);
#endif

namespace {

bool makeStrokedLineQuad(const ColorLine& line,
                         std::array<TPointD, 4>& points) {
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

void DrawList2D::setClearColor(const TPixel32& color) {
  m_clearColor    = color;
  m_hasClearColor = true;
}

void DrawList2D::addColorRect(const TRectD& rect, const TPixel32& color,
                              bool blending) {
  ColorRect colorRect;
  colorRect.m_rect     = rect;
  colorRect.m_color    = color;
  colorRect.m_blending = blending;
  m_colorRects.push_back(colorRect);
}

void DrawList2D::addColorQuad(const TPointD& p00, const TPointD& p10,
                              const TPointD& p11, const TPointD& p01,
                              const TPixel32& color, bool blending) {
  ColorQuad colorQuad;
  colorQuad.m_points[0] = p00;
  colorQuad.m_points[1] = p10;
  colorQuad.m_points[2] = p11;
  colorQuad.m_points[3] = p01;
  colorQuad.m_color     = color;
  colorQuad.m_blending  = blending;
  m_colorQuads.push_back(colorQuad);
}

void DrawList2D::addCheckerboard(const TRectD& rect,
                                 const TDimensionD& cellSize,
                                 const TPointD& origin, const TPixel32& color0,
                                 const TPixel32& color1) {
  if (rect.isEmpty() || cellSize.lx <= 0.0 || cellSize.ly <= 0.0) return;

  const int ix0 =
      static_cast<int>(std::floor((rect.x0 - origin.x) / cellSize.lx));
  const int ix1 =
      static_cast<int>(std::ceil((rect.x1 - origin.x) / cellSize.lx));
  const int iy0 =
      static_cast<int>(std::floor((rect.y0 - origin.y) / cellSize.ly));
  const int iy1 =
      static_cast<int>(std::ceil((rect.y1 - origin.y) / cellSize.ly));

  for (int iy = iy0; iy < iy1; ++iy) {
    for (int ix = ix0; ix < ix1; ++ix) {
      const double x0 = std::max(rect.x0, origin.x + ix * cellSize.lx);
      const double x1 = std::min(rect.x1, origin.x + (ix + 1) * cellSize.lx);
      const double y0 = std::max(rect.y0, origin.y + iy * cellSize.ly);
      const double y1 = std::min(rect.y1, origin.y + (iy + 1) * cellSize.ly);
      if (x1 <= x0 || y1 <= y0) continue;

      const TPixel32 color = ((ix + iy) & 1) ? color1 : color0;
      addColorRect(TRectD(x0, y0, x1, y1), color, false);
    }
  }
}

void DrawList2D::addColorLine(const TPointD& p0, const TPointD& p1,
                              const TPixel32& color, bool blending) {
  ColorLine colorLine;
  colorLine.m_p0       = p0;
  colorLine.m_p1       = p1;
  colorLine.m_color    = color;
  colorLine.m_blending = blending;
  m_colorLines.push_back(colorLine);
}

void DrawList2D::addTexture(const TRectD& rect, const TRaster32P& raster,
                            bool blending) {
  TextureQuad quad;
  quad.m_rect              = rect;
  quad.m_points[0]         = TPointD(rect.x0, rect.y0);
  quad.m_points[1]         = TPointD(rect.x1, rect.y0);
  quad.m_points[2]         = TPointD(rect.x1, rect.y1);
  quad.m_points[3]         = TPointD(rect.x0, rect.y1);
  quad.m_texture           = std::make_shared<RasterTexture>(raster);
  quad.m_blending          = blending;
  quad.m_hasExplicitPoints = false;
  m_textureQuads.push_back(quad);
}

void DrawList2D::addTextureQuad(const TPointD& p00, const TPointD& p10,
                                const TPointD& p11, const TPointD& p01,
                                const TRaster32P& raster, bool blending) {
  addTextureQuad(p00, p10, p11, p01, raster, TPixel32::White, blending);
}

void DrawList2D::addTextureQuad(const TPointD& p00, const TPointD& p10,
                                const TPointD& p11, const TPointD& p01,
                                const TRaster32P& raster,
                                const TPixel32& colorScale, bool blending) {
  TextureQuad quad;
  quad.m_points[0] = p00;
  quad.m_points[1] = p10;
  quad.m_points[2] = p11;
  quad.m_points[3] = p01;
  quad.m_rect =
      TRectD(std::min(std::min(p00.x, p10.x), std::min(p11.x, p01.x)),
             std::min(std::min(p00.y, p10.y), std::min(p11.y, p01.y)),
             std::max(std::max(p00.x, p10.x), std::max(p11.x, p01.x)),
             std::max(std::max(p00.y, p10.y), std::max(p11.y, p01.y)));
  quad.m_texture           = std::make_shared<RasterTexture>(raster);
  quad.m_colorScale        = colorScale;
  quad.m_blending          = blending;
  quad.m_hasExplicitPoints = true;
  m_textureQuads.push_back(quad);
}

bool DrawList2D::hasClearColor() const { return m_hasClearColor; }

const TPixel32& DrawList2D::clearColor() const { return m_clearColor; }

const std::vector<ColorRect>& DrawList2D::colorRects() const {
  return m_colorRects;
}

const std::vector<ColorQuad>& DrawList2D::colorQuads() const {
  return m_colorQuads;
}

const std::vector<ColorLine>& DrawList2D::colorLines() const {
  return m_colorLines;
}

const std::vector<TextureQuad>& DrawList2D::textureQuads() const {
  return m_textureQuads;
}

bool DrawList2D::empty() const {
  return !m_hasClearColor && m_colorRects.empty() && m_colorQuads.empty() &&
         m_colorLines.empty() && m_textureQuads.empty();
}

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
    if (drawList.hasClearColor()) clear(drawList.clearColor());

    for (const ColorRect& rect : drawList.colorRects()) {
      drawColorRect(rect);
    }

    for (const ColorQuad& quad : drawList.colorQuads()) {
      drawColorQuad(quad);
    }

    for (const ColorLine& line : drawList.colorLines()) {
      drawColorLine(line);
    }

    for (const TextureQuad& quad : drawList.textureQuads()) {
      const RasterTexture* texture =
          dynamic_cast<const RasterTexture*>(quad.m_texture.get());
      assert(texture);
      if (!texture) continue;

      drawTextureQuad(quad, texture->raster());
    }

    if (imageTarget) endImageTargetDraw(*imageTarget);
  }

private:
  void clear(const TPixel32& color) {
    glClearColor(color.r / 255.0f, color.g / 255.0f, color.b / 255.0f,
                 color.m / 255.0f);
    glClear(GL_COLOR_BUFFER_BIT);
  }

  void drawColorRect(const ColorRect& rect) {
    if (rect.m_blending) {
      glEnable(GL_BLEND);
      glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    } else {
      glDisable(GL_BLEND);
    }

    tglColor(rect.m_color);
    tglFillRect(rect.m_rect);
    glDisable(GL_BLEND);
  }

  void drawColorQuad(const ColorQuad& quad) {
    if (quad.m_blending) {
      glEnable(GL_BLEND);
      glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    } else {
      glDisable(GL_BLEND);
    }

    tglColor(quad.m_color);
    glBegin(GL_POLYGON);
    tglVertex(quad.m_points[0]);
    tglVertex(quad.m_points[1]);
    tglVertex(quad.m_points[2]);
    tglVertex(quad.m_points[3]);
    glEnd();
    glDisable(GL_BLEND);
  }

  void drawColorLine(const ColorLine& line) {
    if (line.m_blending) {
      glEnable(GL_BLEND);
      glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    } else {
      glDisable(GL_BLEND);
    }

    tglColor(line.m_color);
    const double epsilon = 1e-6;
    if (std::abs(line.m_p0.y - line.m_p1.y) <= epsilon) {
      const double x0 = std::min(line.m_p0.x, line.m_p1.x);
      const double x1 = std::max(line.m_p0.x, line.m_p1.x);
      tglFillRect(TRectD(x0, line.m_p0.y, x1 + 1.0, line.m_p0.y + 1.0));
    } else if (std::abs(line.m_p0.x - line.m_p1.x) <= epsilon) {
      const double y0 = std::min(line.m_p0.y, line.m_p1.y);
      const double y1 = std::max(line.m_p0.y, line.m_p1.y);
      tglFillRect(TRectD(line.m_p0.x, y0, line.m_p0.x + 1.0, y1 + 1.0));
    } else {
      std::array<TPointD, 4> points;
      if (makeStrokedLineQuad(line, points)) {
        glBegin(GL_POLYGON);
        for (const TPointD& point : points) tglVertex(point);
        glEnd();
      }
    }
    glDisable(GL_BLEND);
  }

  void drawTextureQuad(const TextureQuad& quad, const TRaster32P& tex) {
    if (!tex) return;
    if (!quad.m_hasExplicitPoints) {
      tglDraw(quad.m_rect, tex, quad.m_blending);
      return;
    }

    glPushAttrib(GL_ALL_ATTRIB_BITS);
    if (quad.m_blending) {
      glEnable(GL_BLEND);
      glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    } else {
      glDisable(GL_BLEND);
    }

    unsigned int texWidth  = 1;
    unsigned int texHeight = 1;
    while (texWidth < static_cast<unsigned int>(tex->getLx()))
      texWidth = texWidth << 1;
    while (texHeight < static_cast<unsigned int>(tex->getLy()))
      texHeight = texHeight << 1;

    double lwTex             = 1.0;
    double lhTex             = 1.0;
    const unsigned int texLx = static_cast<unsigned int>(tex->getLx());
    const unsigned int texLy = static_cast<unsigned int>(tex->getLy());

    TRaster32P texture;
    if (texWidth != texLx || texHeight != texLy) {
      texture = TRaster32P(texWidth, texHeight);
      texture->fill(TPixel32(0, 0, 0, 0));
      texture->copy(tex);
      lwTex = std::min(1.0, texLx / static_cast<double>(texWidth));
      lhTex = std::min(1.0, texLy / static_cast<double>(texHeight));
    } else {
      texture = tex;
    }

    GLenum fmt =
#if defined(TNZ_MACHINE_CHANNEL_ORDER_BGRM)
        GL_BGRA_EXT;
#elif defined(TNZ_MACHINE_CHANNEL_ORDER_MBGR)
        GL_ABGR_EXT;
#elif defined(TNZ_MACHINE_CHANNEL_ORDER_RGBM)
        GL_RGBA;
#elif defined(TNZ_MACHINE_CHANNEL_ORDER_MRGB)
        GL_BGRA;
#else
#error "unknown channel order!"
#endif

    GLuint texId;
    glGenTextures(1, &texId);
    glBindTexture(GL_TEXTURE_2D, texId);
    glPixelStorei(GL_UNPACK_ROW_LENGTH, texture->getWrap());

    texture->lock();
    glTexImage2D(GL_TEXTURE_2D, 0, 4, texWidth, texHeight, 0, fmt,
#ifdef TNZ_MACHINE_CHANNEL_ORDER_MRGB
                 GL_UNSIGNED_INT_8_8_8_8_REV,
#else
                 GL_UNSIGNED_BYTE,
#endif
                 texture->getRawData());

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
    glEnable(GL_TEXTURE_2D);
    glHint(GL_PERSPECTIVE_CORRECTION_HINT, GL_NICEST);
    tglColor(quad.m_colorScale);

    glBegin(GL_POLYGON);
    glTexCoord2d(0.0, 0.0);
    tglVertex(quad.m_points[0]);
    glTexCoord2d(lwTex, 0.0);
    tglVertex(quad.m_points[1]);
    glTexCoord2d(lwTex, lhTex);
    tglVertex(quad.m_points[2]);
    glTexCoord2d(0.0, lhTex);
    tglVertex(quad.m_points[3]);
    glEnd();

    glDisable(GL_TEXTURE_2D);
    glDeleteTextures(1, &texId);
    texture->unlock();
    glPopAttrib();
  }

  void beginImageTargetDraw(OpenGLImageRenderTarget& target) {
    target.makeCurrent();
    target.fbo()->bind();

    glViewport(0, 0, target.width(), target.height());
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_SCISSOR_TEST);
    clear(TPixel32(0, 0, 0, 0));

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

TRaster32P renderDrawListWithOpenGLBackend(const DrawList2D& drawList,
                                           int width, int height) {
  std::unique_ptr<RenderTarget> target =
      createOpenGLImageRenderTarget(width, height);
  if (!target) return TRaster32P();

  std::unique_ptr<CommandEncoder> encoder =
      openGLDevice().createCommandEncoder(target.get());
  encoder->draw(drawList);
  return readOpenGLRenderTarget(target.get());
}

TRaster32P renderDrawListWithMetalBackend(const DrawList2D& drawList, int width,
                                          int height) {
  std::unique_ptr<RenderTarget> target =
      createMetalImageRenderTarget(width, height);
  if (!target) return TRaster32P();

  std::unique_ptr<CommandEncoder> encoder =
      metalDevice().createCommandEncoder(target.get());
  encoder->draw(drawList);
  return readMetalRenderTarget(target.get());
}

TRaster32P renderDrawListWithActiveBackend(const DrawList2D& drawList,
                                           int width, int height) {
  if (activeBackendType() == BackendType::Metal)
    return renderDrawListWithMetalBackend(drawList, width, height);
  return renderDrawListWithOpenGLBackend(drawList, width, height);
}

TRaster32P renderSunflareWithMetalBackend(int width, int height,
                                          const TAffine& outputToWorld,
                                          const TPixel32& color, int blades,
                                          double intensity, double angle,
                                          double bias, double sharpness) {
#ifdef OPENTOONZ_WITH_GRAPHICS_METAL
  return renderNativeMetalSunflare(width, height, outputToWorld, color, blades,
                                   intensity, angle, bias, sharpness);
#else
  (void)width;
  (void)height;
  (void)outputToWorld;
  (void)color;
  (void)blades;
  (void)intensity;
  (void)angle;
  (void)bias;
  (void)sharpness;
  return TRaster32P();
#endif
}

}  // namespace TGraphics
