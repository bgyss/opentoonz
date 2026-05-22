#include "tgraphics.h"

#include <QGuiApplication>

#include <cstdlib>
#include <iostream>
#include <memory>

namespace {

bool samePixel(const TPixel32& a, const TPixel32& b) {
  return a.r == b.r && a.g == b.g && a.b == b.b && a.m == b.m;
}

bool closeChannel(int a, int b) { return std::abs(a - b) <= 1; }

bool closePixel(const TPixel32& a, const TPixel32& b) {
  return closeChannel(a.r, b.r) && closeChannel(a.g, b.g) &&
         closeChannel(a.b, b.b) && closeChannel(a.m, b.m);
}

void printPixel(const TPixel32& pixel) {
  std::cerr << "rgba=(" << static_cast<int>(pixel.r) << ","
            << static_cast<int>(pixel.g) << "," << static_cast<int>(pixel.b)
            << "," << static_cast<int>(pixel.m) << ")";
}

TPixel32 gradientPixel(int x, int y) {
  return TPixel32(31 + x * 37, 47 + y * 43, 83 + x * 11 + y * 7, 255);
}

TRaster32P makeSolidRaster(int width, int height, const TPixel32& color) {
  TRaster32P raster(width, height);
  raster->lock();
  for (int y = 0; y < height; ++y) {
    TPixel32* line = raster->pixels(y);
    for (int x = 0; x < width; ++x) line[x] = color;
  }
  raster->unlock();
  return raster;
}

TRaster32P makeGradientRaster(int width, int height) {
  TRaster32P raster(width, height);
  raster->lock();
  for (int y = 0; y < height; ++y) {
    TPixel32* line = raster->pixels(y);
    for (int x = 0; x < width; ++x) line[x] = gradientPixel(x, y);
  }
  raster->unlock();
  return raster;
}

int fail(const char* message) {
  std::cerr << "tgraphics_metal_probe: " << message << std::endl;
  return EXIT_FAILURE;
}

TPixel32 openGLBlend(const TPixel32& src, const TPixel32& dst) {
  const int invAlpha = 255 - src.m;
  return TPixel32((src.r * src.m + dst.r * invAlpha + 127) / 255,
                  (src.g * src.m + dst.g * invAlpha + 127) / 255,
                  (src.b * src.m + dst.b * invAlpha + 127) / 255,
                  (src.m * src.m + dst.m * invAlpha + 127) / 255);
}

bool requireDimensions(const TRaster32P& readback, int width, int height) {
  if (!readback) return false;
  return readback->getLx() == width && readback->getLy() == height;
}

bool validateGradientClear(const TRaster32P& readback, int width, int height,
                           const TPixel32& outsideColor, int rectX0, int rectY0,
                           int rectX1, int rectY1) {
  readback->lock();
  for (int y = 0; y < height; ++y) {
    const TPixel32* line = readback->pixels(y);
    for (int x = 0; x < width; ++x) {
      const bool inside =
          x >= rectX0 && x < rectX1 && y >= rectY0 && y < rectY1;
      const TPixel32 expected =
          inside ? gradientPixel(x - rectX0, y - rectY0) : outsideColor;
      if (!samePixel(line[x], expected)) {
        readback->unlock();
        std::cerr << "tgraphics_metal_probe: pixel mismatch at " << x << ","
                  << y << " expected ";
        printPixel(expected);
        std::cerr << " actual ";
        printPixel(line[x]);
        std::cerr << std::endl;
        return false;
      }
    }
  }
  readback->unlock();
  return true;
}

bool validateAlphaBlend(const TRaster32P& readback, int width, int height,
                        const TPixel32& baseColor, int gradientX0,
                        int gradientY0, int gradientX1, int gradientY1,
                        int overlayX0, int overlayY0, int overlayX1,
                        int overlayY1, const TPixel32& overlayColor) {
  readback->lock();
  for (int y = 0; y < height; ++y) {
    const TPixel32* line = readback->pixels(y);
    for (int x = 0; x < width; ++x) {
      const bool inGradient = x >= gradientX0 && x < gradientX1 &&
                              y >= gradientY0 && y < gradientY1;
      const bool inOverlay =
          x >= overlayX0 && x < overlayX1 && y >= overlayY0 && y < overlayY1;

      TPixel32 expected = inGradient
                              ? gradientPixel(x - gradientX0, y - gradientY0)
                              : baseColor;
      if (inOverlay) expected = openGLBlend(overlayColor, expected);

      if (!closePixel(line[x], expected)) {
        readback->unlock();
        std::cerr << "tgraphics_metal_probe: alpha pixel mismatch at " << x
                  << "," << y << " expected ";
        printPixel(expected);
        std::cerr << " actual ";
        printPixel(line[x]);
        std::cerr << std::endl;
        return false;
      }
    }
  }
  readback->unlock();
  return true;
}

bool compareRasters(const TRaster32P& metal, const TRaster32P& opengl,
                    const char* caseName) {
  if (!metal || !opengl) return false;
  if (metal->getLx() != opengl->getLx() || metal->getLy() != opengl->getLy()) {
    std::cerr << "tgraphics_metal_probe: " << caseName
              << " readback dimensions differ" << std::endl;
    return false;
  }

  metal->lock();
  opengl->lock();
  for (int y = 0; y < metal->getLy(); ++y) {
    const TPixel32* metalLine  = metal->pixels(y);
    const TPixel32* openglLine = opengl->pixels(y);
    for (int x = 0; x < metal->getLx(); ++x) {
      if (!closePixel(metalLine[x], openglLine[x])) {
        const TPixel32 metalPixel  = metalLine[x];
        const TPixel32 openglPixel = openglLine[x];
        metal->unlock();
        opengl->unlock();
        std::cerr << "tgraphics_metal_probe: " << caseName
                  << " Metal/OpenGL mismatch at " << x << "," << y << " metal ";
        printPixel(metalPixel);
        std::cerr << " opengl ";
        printPixel(openglPixel);
        std::cerr << std::endl;
        return false;
      }
    }
  }
  metal->unlock();
  opengl->unlock();
  return true;
}

TRaster32P renderMetal(const TGraphics::DrawList2D& drawList, int width,
                       int height) {
  std::unique_ptr<TGraphics::RenderTarget> target =
      TGraphics::createMetalImageRenderTarget(width, height);
  if (!target) return TRaster32P();

  std::unique_ptr<TGraphics::CommandEncoder> encoder =
      TGraphics::metalDevice().createCommandEncoder(target.get());
  encoder->draw(drawList);
  return TGraphics::readMetalRenderTarget(target.get());
}

TRaster32P renderOpenGL(const TGraphics::DrawList2D& drawList, int width,
                        int height) {
  std::unique_ptr<TGraphics::RenderTarget> target =
      TGraphics::createOpenGLImageRenderTarget(width, height);
  if (!target) return TRaster32P();

  std::unique_ptr<TGraphics::CommandEncoder> encoder =
      TGraphics::openGLDevice().createCommandEncoder(target.get());
  encoder->draw(drawList);
  return TGraphics::readOpenGLRenderTarget(target.get());
}

}  // namespace

int main(int argc, char* argv[]) {
  QGuiApplication app(argc, argv);

  if (!TGraphics::isMetalBuildEnabled()) {
    return fail("Metal support was not compiled into this build");
  }
  if (!TGraphics::isMetalDeviceAvailable()) {
    return fail("no Metal device is available");
  }

  const int width      = 8;
  const int height     = 8;
  const int gradientX0 = 2;
  const int gradientY0 = 1;
  const int gradientX1 = 6;
  const int gradientY1 = 5;
  const TPixel32 clearColor(0, 0, 0, 0);

  {
    TGraphics::DrawList2D drawList;
    drawList.addTexture(
        TRectD(gradientX0, gradientY0, gradientX1, gradientY1),
        makeGradientRaster(gradientX1 - gradientX0, gradientY1 - gradientY0),
        false);

    TRaster32P readback = renderMetal(drawList, width, height);
    if (!readback) return fail("could not read back offscreen Metal target");
    if (!requireDimensions(readback, width, height)) {
      return fail("readback dimensions do not match render target dimensions");
    }
    if (!validateGradientClear(readback, width, height, clearColor, gradientX0,
                               gradientY0, gradientX1, gradientY1)) {
      return EXIT_FAILURE;
    }

    TRaster32P openGLReadback = renderOpenGL(drawList, width, height);
    if (!openGLReadback) return fail("could not read back OpenGL baseline");
    if (!compareRasters(readback, openGLReadback, "gradient")) {
      return EXIT_FAILURE;
    }
  }

  {
    const TPixel32 baseColor(17, 59, 101, 255);
    const TPixel32 overlayColor(209, 37, 129, 128);
    const int overlayX0 = 3;
    const int overlayY0 = 2;
    const int overlayX1 = 7;
    const int overlayY1 = 6;

    TGraphics::DrawList2D drawList;
    drawList.addTexture(TRectD(0, 0, width, height),
                        makeSolidRaster(width, height, baseColor), false);
    drawList.addTexture(
        TRectD(gradientX0, gradientY0, gradientX1, gradientY1),
        makeGradientRaster(gradientX1 - gradientX0, gradientY1 - gradientY0),
        false);
    drawList.addTexture(TRectD(overlayX0, overlayY0, overlayX1, overlayY1),
                        makeSolidRaster(overlayX1 - overlayX0,
                                        overlayY1 - overlayY0, overlayColor),
                        true);

    TRaster32P readback = renderMetal(drawList, width, height);
    if (!readback) return fail("could not read back alpha Metal target");
    if (!requireDimensions(readback, width, height)) {
      return fail("alpha readback dimensions do not match render target");
    }
    if (!validateAlphaBlend(readback, width, height, baseColor, gradientX0,
                            gradientY0, gradientX1, gradientY1, overlayX0,
                            overlayY0, overlayX1, overlayY1, overlayColor)) {
      return EXIT_FAILURE;
    }

    TRaster32P openGLReadback = renderOpenGL(drawList, width, height);
    if (!openGLReadback)
      return fail("could not read back alpha OpenGL baseline");
    if (!compareRasters(readback, openGLReadback, "alpha")) {
      return EXIT_FAILURE;
    }
  }

  std::cout << "tgraphics_metal_probe: ok on " << TGraphics::metalDeviceName()
            << std::endl;
  return EXIT_SUCCESS;
}
