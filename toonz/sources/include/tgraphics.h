#pragma once

#ifndef TGRAPHICS_INCLUDED
#define TGRAPHICS_INCLUDED

#include "tgeometry.h"
#include "tmachine.h"
#include "traster.h"

#include <memory>
#include <vector>

#undef DVAPI
#undef DVVAR

#ifdef DV_LOCAL_DEFINED
#define DVAPI
#define DVVAR
#else
#ifdef TGRAPHICS_EXPORTS
#define DVAPI DV_EXPORT_API
#define DVVAR DV_EXPORT_VAR
#else
#define DVAPI DV_IMPORT_API
#define DVVAR DV_IMPORT_VAR
#endif
#endif

namespace TGraphics {

enum class BackendType { OpenGL, Metal };

class DVAPI RenderTarget {
public:
  virtual ~RenderTarget();
};

class DVAPI Texture {
public:
  virtual ~Texture();
};

class DVAPI Buffer {
public:
  virtual ~Buffer();
};

class DVAPI Pipeline {
public:
  virtual ~Pipeline();
};

class DVAPI ShaderLibrary {
public:
  virtual ~ShaderLibrary();
};

class DVAPI HitTest {
public:
  virtual ~HitTest();
};

class DVAPI RasterTexture final : public Texture {
  TRaster32P m_raster;

public:
  explicit RasterTexture(const TRaster32P& raster);

  const TRaster32P& raster() const;
};

struct DVAPI TextureQuad final {
  TRectD m_rect;
  TPointD m_points[4];
  std::shared_ptr<Texture> m_texture;
  TPixel32 m_colorScale    = TPixel32::White;
  bool m_blending          = false;
  bool m_hasExplicitPoints = false;
};

struct DVAPI ColorRect final {
  TRectD m_rect;
  TPixel32 m_color;
  bool m_blending = false;
};

struct DVAPI ColorQuad final {
  TPointD m_points[4];
  TPixel32 m_color;
  bool m_blending = false;
};

struct DVAPI ColorLine final {
  TPointD m_p0;
  TPointD m_p1;
  TPixel32 m_color;
  bool m_blending = false;
};

class DVAPI DrawList2D final {
  std::vector<ColorRect> m_colorRects;
  std::vector<ColorQuad> m_colorQuads;
  std::vector<ColorLine> m_colorLines;
  std::vector<TextureQuad> m_textureQuads;
  TPixel32 m_clearColor;
  bool m_hasClearColor = false;

public:
  void setClearColor(const TPixel32& color);
  void addColorRect(const TRectD& rect, const TPixel32& color, bool blending);
  void addColorQuad(const TPointD& p00, const TPointD& p10, const TPointD& p11,
                    const TPointD& p01, const TPixel32& color, bool blending);
  void addCheckerboard(const TRectD& rect, const TDimensionD& cellSize,
                       const TPointD& origin, const TPixel32& color0,
                       const TPixel32& color1);
  void addColorLine(const TPointD& p0, const TPointD& p1, const TPixel32& color,
                    bool blending);
  void addTexture(const TRectD& rect, const TRaster32P& raster, bool blending);
  void addTextureQuad(const TPointD& p00, const TPointD& p10,
                      const TPointD& p11, const TPointD& p01,
                      const TRaster32P& raster, bool blending);
  void addTextureQuad(const TPointD& p00, const TPointD& p10,
                      const TPointD& p11, const TPointD& p01,
                      const TRaster32P& raster, const TPixel32& colorScale,
                      bool blending);

  bool hasClearColor() const;
  const TPixel32& clearColor() const;
  const std::vector<ColorRect>& colorRects() const;
  const std::vector<ColorQuad>& colorQuads() const;
  const std::vector<ColorLine>& colorLines() const;
  const std::vector<TextureQuad>& textureQuads() const;
  bool empty() const;
};

class DVAPI CommandEncoder {
public:
  virtual ~CommandEncoder();

  virtual BackendType backendType() const       = 0;
  virtual void draw(const DrawList2D& drawList) = 0;
};

class DVAPI Device {
public:
  virtual ~Device();

  virtual BackendType backendType() const = 0;
  virtual std::unique_ptr<CommandEncoder> createCommandEncoder(
      RenderTarget* target = 0) = 0;
};

DVAPI Device& openGLDevice();
DVAPI Device& metalDevice();
DVAPI std::unique_ptr<RenderTarget> createOpenGLImageRenderTarget(int width,
                                                                  int height);
DVAPI TRaster32P readOpenGLRenderTarget(RenderTarget* target);
DVAPI bool isMetalBuildEnabled();
DVAPI bool isMetalDeviceAvailable();
DVAPI const char* metalDeviceName();
DVAPI void* createMetalLayerForNativeView(void* nativeView);
DVAPI std::unique_ptr<RenderTarget> createMetalLayerRenderTarget(
    void* metalLayer, int width, int height, double devicePixelRatio);
DVAPI std::unique_ptr<RenderTarget> createMetalImageRenderTarget(int width,
                                                                 int height);
DVAPI bool isMetalLayerRenderTarget(const RenderTarget* target);
DVAPI TRaster32P readMetalRenderTarget(RenderTarget* target);
DVAPI bool isMetalBackendAvailable();
DVAPI BackendType requestedBackendType();
DVAPI BackendType activeBackendType();
DVAPI Device& activeDevice();
DVAPI void drawWithOpenGLBackend(const DrawList2D& drawList);
DVAPI void drawWithActiveBackend(const DrawList2D& drawList);
DVAPI TRaster32P renderDrawListWithOpenGLBackend(const DrawList2D& drawList,
                                                 int width, int height);
DVAPI TRaster32P renderDrawListWithMetalBackend(const DrawList2D& drawList,
                                                int width, int height);
DVAPI TRaster32P renderDrawListWithActiveBackend(const DrawList2D& drawList,
                                                 int width, int height);
DVAPI TRaster32P renderSunflareWithMetalBackend(
    int width, int height, const TAffine& outputToWorld, const TPixel32& color,
    int blades, double intensity, double angle, double bias, double sharpness);
DVAPI TRaster32P renderCausticsWithMetalBackend(int width, int height,
                                                const TAffine& outputToWorld,
                                                const TPixel32& color,
                                                double time);
DVAPI TRaster32P renderStarskyWithMetalBackend(int width, int height,
                                               const TAffine& outputToWorld,
                                               const TPixel32& color,
                                               double time, double brightness);
DVAPI TRaster32P renderWavyWithMetalBackend(int width, int height,
                                            const TAffine& outputToWorld,
                                            const TPixel32& color1,
                                            const TPixel32& color2,
                                            double time);
DVAPI TRaster32P renderFireballWithMetalBackend(int width, int height,
                                                const TAffine& outputToWorld,
                                                const TPixel32& color1,
                                                const TPixel32& color2,
                                                double detail, double time);
DVAPI TRaster32P renderHSLBlendWithMetalBackend(
    int width, int height, const TRaster32P& foreground,
    const TRaster32P& background, const TAffine& outputToForeground,
    const TAffine& outputToBackground, bool blendHue, bool blendSaturation,
    bool blendLuminosity, double blendAlpha, bool baseMask);
DVAPI TRaster32P renderRadialBlurWithMetalBackend(
    int width, int height, const TRaster32P& source,
    const TAffine& outputToInput, const TAffine& worldToOutput,
    const TPointD& center, double radius, double blur);

}  // namespace TGraphics

#endif
