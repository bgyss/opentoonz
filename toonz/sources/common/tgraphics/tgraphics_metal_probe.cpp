#include "tgraphics.h"

#include <QDir>
#include <QGuiApplication>
#include <QImage>
#include <QString>

#include <algorithm>
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

QString caseFileStem(const char* caseName) {
  QString stem = QString::fromLatin1(caseName);
  stem.replace(' ', '_');
  return stem;
}

QImage rasterToImage(const TRaster32P& raster) {
  if (!raster) return QImage();

  QImage image(raster->getLx(), raster->getLy(), QImage::Format_ARGB32);
  raster->lock();
  for (int y = 0; y < raster->getLy(); ++y) {
    const TPixel32* src = raster->pixels(y);
    QRgb* dst           = reinterpret_cast<QRgb*>(image.scanLine(y));
    for (int x = 0; x < raster->getLx(); ++x) {
      dst[x] = qRgba(src[x].r, src[x].g, src[x].b, src[x].m);
    }
  }
  raster->unlock();
  return image;
}

TRaster32P makeDiffRaster(const TRaster32P& a, const TRaster32P& b) {
  if (!a || !b || a->getLx() != b->getLx() || a->getLy() != b->getLy())
    return TRaster32P();

  TRaster32P diff(a->getLx(), a->getLy());
  a->lock();
  b->lock();
  diff->lock();
  for (int y = 0; y < a->getLy(); ++y) {
    const TPixel32* aLine = a->pixels(y);
    const TPixel32* bLine = b->pixels(y);
    TPixel32* dLine       = diff->pixels(y);
    for (int x = 0; x < a->getLx(); ++x) {
      const int dr = std::min(std::abs(aLine[x].r - bLine[x].r) * 32, 255);
      const int dg = std::min(std::abs(aLine[x].g - bLine[x].g) * 32, 255);
      const int db = std::min(std::abs(aLine[x].b - bLine[x].b) * 32, 255);
      const int da = std::min(std::abs(aLine[x].m - bLine[x].m) * 32, 255);
      dLine[x]     = TPixel32(dr, dg, db, da == 0 ? 255 : da);
    }
  }
  diff->unlock();
  b->unlock();
  a->unlock();
  return diff;
}

bool writeComparisonArtifacts(const char* caseName, const TRaster32P& metal,
                              const TRaster32P& opengl,
                              const QString& outputDir) {
  if (outputDir.isEmpty()) return true;
  QDir dir(outputDir);
  if (!dir.exists() && !dir.mkpath(QStringLiteral("."))) {
    std::cerr << "tgraphics_metal_probe: could not create artifact directory "
              << outputDir.toStdString() << std::endl;
    return false;
  }

  const QString stem       = caseFileStem(caseName);
  const QImage metalImage  = rasterToImage(metal);
  const QImage openglImage = rasterToImage(opengl);
  const QImage diffImage   = rasterToImage(makeDiffRaster(metal, opengl));
  if (!metalImage.save(dir.filePath(stem + QStringLiteral("_metal.png"))) ||
      !openglImage.save(dir.filePath(stem + QStringLiteral("_opengl.png"))) ||
      !diffImage.save(dir.filePath(stem + QStringLiteral("_diff.png")))) {
    std::cerr << "tgraphics_metal_probe: could not write artifacts for "
              << caseName << std::endl;
    return false;
  }
  return true;
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

bool validateColorRects(const TRaster32P& readback, int width, int height,
                        const TPixel32& clearColor, int rectX0, int rectY0,
                        int rectX1, int rectY1, const TPixel32& rectColor,
                        int overlayX0, int overlayY0, int overlayX1,
                        int overlayY1, const TPixel32& overlayColor) {
  readback->lock();
  for (int y = 0; y < height; ++y) {
    const TPixel32* line = readback->pixels(y);
    for (int x = 0; x < width; ++x) {
      const bool inRect =
          x >= rectX0 && x < rectX1 && y >= rectY0 && y < rectY1;
      const bool inOverlay =
          x >= overlayX0 && x < overlayX1 && y >= overlayY0 && y < overlayY1;

      TPixel32 expected = inRect ? rectColor : clearColor;
      if (inOverlay) expected = openGLBlend(overlayColor, expected);

      if (!closePixel(line[x], expected)) {
        readback->unlock();
        std::cerr << "tgraphics_metal_probe: color rect pixel mismatch at " << x
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

bool validateCheckerboard(const TRaster32P& readback, int width, int height,
                          int cellWidth, int cellHeight, const TPixel32& color0,
                          const TPixel32& color1) {
  readback->lock();
  for (int y = 0; y < height; ++y) {
    const TPixel32* line = readback->pixels(y);
    for (int x = 0; x < width; ++x) {
      const TPixel32 expected =
          (((x / cellWidth) + (y / cellHeight)) & 1) ? color1 : color0;
      if (!samePixel(line[x], expected)) {
        readback->unlock();
        std::cerr << "tgraphics_metal_probe: checker pixel mismatch at " << x
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
                    const char* caseName, const QString& artifactDir) {
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
  return writeComparisonArtifacts(caseName, metal, opengl, artifactDir);
}

bool validateSolidClear(const TRaster32P& readback, int width, int height,
                        const TPixel32& clearColor) {
  readback->lock();
  for (int y = 0; y < height; ++y) {
    const TPixel32* line = readback->pixels(y);
    for (int x = 0; x < width; ++x) {
      if (!samePixel(line[x], clearColor)) {
        readback->unlock();
        std::cerr << "tgraphics_metal_probe: clear pixel mismatch at " << x
                  << "," << y << " expected ";
        printPixel(clearColor);
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

  QString artifactDir;
  for (int i = 1; i < argc; ++i) {
    const QString arg = QString::fromLocal8Bit(argv[i]);
    if (arg == QStringLiteral("--write-images")) {
      if (i + 1 >= argc) return fail("--write-images requires a directory");
      artifactDir = QString::fromLocal8Bit(argv[++i]);
    } else {
      std::cerr << "usage: tgraphics_metal_probe [--write-images DIR]"
                << std::endl;
      return EXIT_FAILURE;
    }
  }

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
    const TPixel32 viewerBgColor(19, 23, 29, 255);
    TGraphics::DrawList2D drawList;
    drawList.setClearColor(viewerBgColor);

    TRaster32P readback = renderMetal(drawList, width, height);
    if (!readback) return fail("could not read back clear Metal target");
    if (!requireDimensions(readback, width, height)) {
      return fail("clear readback dimensions do not match render target");
    }
    if (!validateSolidClear(readback, width, height, viewerBgColor)) {
      return EXIT_FAILURE;
    }

    TRaster32P openGLReadback = renderOpenGL(drawList, width, height);
    if (!openGLReadback) return fail("could not read back clear OpenGL target");
    if (!compareRasters(readback, openGLReadback, "clear", artifactDir)) {
      return EXIT_FAILURE;
    }
  }

  {
    const TPixel32 rectClearColor(11, 13, 17, 255);
    const TPixel32 rectColor(120, 40, 200, 255);
    const TPixel32 rectOverlayColor(40, 220, 70, 128);
    const int rectX0    = 1;
    const int rectY0    = 2;
    const int rectX1    = 6;
    const int rectY1    = 7;
    const int overlayX0 = 3;
    const int overlayY0 = 0;
    const int overlayX1 = 8;
    const int overlayY1 = 4;

    TGraphics::DrawList2D drawList;
    drawList.setClearColor(rectClearColor);
    drawList.addColorRect(TRectD(rectX0, rectY0, rectX1, rectY1), rectColor,
                          false);
    drawList.addColorRect(TRectD(overlayX0, overlayY0, overlayX1, overlayY1),
                          rectOverlayColor, true);

    TRaster32P readback = renderMetal(drawList, width, height);
    if (!readback) return fail("could not read back color rect Metal target");
    if (!requireDimensions(readback, width, height)) {
      return fail("color rect readback dimensions do not match render target");
    }
    if (!validateColorRects(readback, width, height, rectClearColor, rectX0,
                            rectY0, rectX1, rectY1, rectColor, overlayX0,
                            overlayY0, overlayX1, overlayY1,
                            rectOverlayColor)) {
      return EXIT_FAILURE;
    }

    TRaster32P openGLReadback = renderOpenGL(drawList, width, height);
    if (!openGLReadback)
      return fail("could not read back color rect OpenGL baseline");
    if (!compareRasters(readback, openGLReadback, "color rect", artifactDir)) {
      return EXIT_FAILURE;
    }
  }

  {
    const TPixel32 checkerColor0(180, 180, 180, 255);
    const TPixel32 checkerColor1(230, 230, 230, 255);
    const int cellWidth  = 2;
    const int cellHeight = 2;
    TGraphics::DrawList2D drawList;
    drawList.setClearColor(TPixel32(0, 0, 0, 255));
    drawList.addCheckerboard(TRectD(0, 0, width, height),
                             TDimensionD(cellWidth, cellHeight), TPointD(),
                             checkerColor0, checkerColor1);

    TRaster32P readback = renderMetal(drawList, width, height);
    if (!readback) return fail("could not read back checker Metal target");
    if (!requireDimensions(readback, width, height)) {
      return fail("checker readback dimensions do not match render target");
    }
    if (!validateCheckerboard(readback, width, height, cellWidth, cellHeight,
                              checkerColor0, checkerColor1)) {
      return EXIT_FAILURE;
    }

    TRaster32P openGLReadback = renderOpenGL(drawList, width, height);
    if (!openGLReadback)
      return fail("could not read back checker OpenGL baseline");
    if (!compareRasters(readback, openGLReadback, "checker", artifactDir)) {
      return EXIT_FAILURE;
    }
  }

  {
    const TPixel32 lineClearColor(7, 9, 11, 255);
    const TPixel32 lineColor(240, 30, 50, 255);
    TGraphics::DrawList2D drawList;
    drawList.setClearColor(lineClearColor);
    drawList.addColorLine(TPointD(1, 1), TPointD(6, 1), lineColor, false);
    drawList.addColorLine(TPointD(6, 1), TPointD(6, 6), lineColor, false);
    drawList.addColorLine(TPointD(6, 6), TPointD(1, 6), lineColor, false);
    drawList.addColorLine(TPointD(1, 6), TPointD(1, 1), lineColor, false);

    TRaster32P readback = renderMetal(drawList, width, height);
    if (!readback) return fail("could not read back color line Metal target");
    if (!requireDimensions(readback, width, height)) {
      return fail("color line readback dimensions do not match render target");
    }

    TRaster32P openGLReadback = renderOpenGL(drawList, width, height);
    if (!openGLReadback)
      return fail("could not read back color line OpenGL baseline");
    if (!compareRasters(readback, openGLReadback, "color line", artifactDir)) {
      return EXIT_FAILURE;
    }
  }

  {
    const TPixel32 quadClearColor(11, 17, 23, 255);
    const TPixel32 baseColor(31, 67, 103, 255);
    const TPixel32 quadColor(219, 181, 47, 192);
    TGraphics::DrawList2D drawList;
    drawList.setClearColor(quadClearColor);
    drawList.addColorRect(TRectD(0, 0, width, height), baseColor, false);
    drawList.addColorQuad(TPointD(1, 2), TPointD(7, 2), TPointD(7, 6),
                          TPointD(1, 6), quadColor, true);

    TRaster32P readback = renderMetal(drawList, width, height);
    if (!readback) return fail("could not read back color quad Metal target");
    if (!requireDimensions(readback, width, height)) {
      return fail("color quad readback dimensions do not match render target");
    }

    TRaster32P openGLReadback = renderOpenGL(drawList, width, height);
    if (!openGLReadback)
      return fail("could not read back color quad OpenGL baseline");
    if (!compareRasters(readback, openGLReadback, "color quad", artifactDir)) {
      return EXIT_FAILURE;
    }
  }

  {
    TGraphics::DrawList2D drawList;
    drawList.setClearColor(clearColor);
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
    if (!compareRasters(readback, openGLReadback, "gradient", artifactDir)) {
      return EXIT_FAILURE;
    }
  }

  {
    const int quadX0 = 1;
    const int quadY0 = 2;
    const int quadX1 = 7;
    const int quadY1 = 6;

    TGraphics::DrawList2D drawList;
    drawList.setClearColor(clearColor);
    drawList.addTextureQuad(
        TPointD(quadX0, quadY0), TPointD(quadX1, quadY0),
        TPointD(quadX1, quadY1), TPointD(quadX0, quadY1),
        makeGradientRaster(quadX1 - quadX0, quadY1 - quadY0), false);

    TRaster32P readback = renderMetal(drawList, width, height);
    if (!readback)
      return fail("could not read back transformed texture Metal target");
    if (!requireDimensions(readback, width, height)) {
      return fail(
          "transformed texture readback dimensions do not match render target");
    }
    if (!validateGradientClear(readback, width, height, clearColor, quadX0,
                               quadY0, quadX1, quadY1)) {
      return EXIT_FAILURE;
    }

    TRaster32P openGLReadback = renderOpenGL(drawList, width, height);
    if (!openGLReadback)
      return fail("could not read back transformed texture OpenGL baseline");
    if (!compareRasters(readback, openGLReadback, "transformed texture",
                        artifactDir)) {
      return EXIT_FAILURE;
    }
  }

  {
    const TPixel32 baseColor(17, 59, 101, 255);
    const TPixel32 colorScale(255, 255, 255, 128);
    const int quadX0 = 1;
    const int quadY0 = 2;
    const int quadX1 = 7;
    const int quadY1 = 6;

    TGraphics::DrawList2D drawList;
    drawList.setClearColor(TPixel32(0, 0, 0, 0));
    drawList.addTexture(TRectD(0, 0, width, height),
                        makeSolidRaster(width, height, baseColor), false);
    drawList.addTextureQuad(
        TPointD(quadX0, quadY0), TPointD(quadX1, quadY0),
        TPointD(quadX1, quadY1), TPointD(quadX0, quadY1),
        makeGradientRaster(quadX1 - quadX0, quadY1 - quadY0), colorScale, true);

    TRaster32P readback = renderMetal(drawList, width, height);
    if (!readback)
      return fail("could not read back modulated texture Metal target");
    if (!requireDimensions(readback, width, height)) {
      return fail(
          "modulated texture readback dimensions do not match render target");
    }

    TRaster32P openGLReadback = renderOpenGL(drawList, width, height);
    if (!openGLReadback)
      return fail("could not read back modulated texture OpenGL baseline");
    if (!compareRasters(readback, openGLReadback, "modulated texture",
                        artifactDir)) {
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
    drawList.setClearColor(TPixel32(0, 0, 0, 0));
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
    if (!compareRasters(readback, openGLReadback, "alpha", artifactDir)) {
      return EXIT_FAILURE;
    }
  }

  std::cout << "tgraphics_metal_probe: ok on " << TGraphics::metalDeviceName()
            << std::endl;
  return EXIT_SUCCESS;
}
