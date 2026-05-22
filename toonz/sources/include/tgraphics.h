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
  std::shared_ptr<Texture> m_texture;
  bool m_blending = false;
};

class DVAPI DrawList2D final {
  std::vector<TextureQuad> m_textureQuads;

public:
  void addTexture(const TRectD& rect, const TRaster32P& raster, bool blending);

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

}  // namespace TGraphics

#endif
