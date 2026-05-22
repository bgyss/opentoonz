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

int toByte(double value) {
  return std::max(0,
                  std::min(255, static_cast<int>(std::lround(value * 255.0))));
}

struct RgbD {
  double r = 0.0;
  double g = 0.0;
  double b = 0.0;
};

double min3(const RgbD& c) { return std::min({c.r, c.g, c.b}); }
double max3(const RgbD& c) { return std::max({c.r, c.g, c.b}); }
double lum3(const RgbD& c) { return c.r * 0.30 + c.g * 0.59 + c.b * 0.11; }
double sat3(const RgbD& c) { return max3(c) - min3(c); }

RgbD clipColor(RgbD color) {
  const double lum    = lum3(color);
  const double mincol = min3(color);
  const double maxcol = max3(color);
  if (mincol < 0.0) {
    color.r = lum + ((color.r - lum) * lum) / (lum - mincol);
    color.g = lum + ((color.g - lum) * lum) / (lum - mincol);
    color.b = lum + ((color.b - lum) * lum) / (lum - mincol);
  }
  if (maxcol > 1.0) {
    color.r = lum + ((color.r - lum) * (1.0 - lum)) / (maxcol - lum);
    color.g = lum + ((color.g - lum) * (1.0 - lum)) / (maxcol - lum);
    color.b = lum + ((color.b - lum) * (1.0 - lum)) / (maxcol - lum);
  }
  return color;
}

RgbD setLum(const RgbD& cbase, const RgbD& clum) {
  const double diff = lum3(clum) - lum3(cbase);
  return clipColor({cbase.r + diff, cbase.g + diff, cbase.b + diff});
}

RgbD setLumSat(const RgbD& cbase, const RgbD& csat, const RgbD& clum) {
  const double minbase = min3(cbase);
  const double sbase   = sat3(cbase);
  const double ssat    = sat3(csat);
  RgbD color;
  if (sbase > 0.0) {
    color.r = (cbase.r - minbase) * ssat / sbase;
    color.g = (cbase.g - minbase) * ssat / sbase;
    color.b = (cbase.b - minbase) * ssat / sbase;
  }
  return setLum(color, clum);
}

RgbD unpremultiply(const TPixel32& pixel) {
  const double alpha = pixel.m / 255.0;
  if (alpha <= 0.0) return RgbD();
  return {pixel.r / 255.0 / alpha, pixel.g / 255.0 / alpha,
          pixel.b / 255.0 / alpha};
}

TPixel32 hslBlendReferencePixel(const TPixel32& foreground,
                                const TPixel32& background, bool blendHue,
                                bool blendSaturation, bool blendLuminosity,
                                double blendAlpha, bool baseMask) {
  const RgbD fgPix     = unpremultiply(foreground);
  const RgbD bgPix     = unpremultiply(background);
  const double fgAlpha = foreground.m / 255.0 * blendAlpha;
  const double bgAlpha = background.m / 255.0;
  const double outAlpha =
      baseMask ? bgAlpha : bgAlpha + fgAlpha * (1.0 - bgAlpha);
  if (outAlpha <= 0.0) return TPixel32(0, 0, 0, 0);

  const RgbD oPix =
      setLumSat(blendHue ? fgPix : bgPix, blendSaturation ? fgPix : bgPix,
                blendLuminosity ? fgPix : bgPix);
  const RgbD bPix = baseMask ? RgbD() : fgPix;
  RgbD outRgb;
  outRgb.r = bgPix.r * bgAlpha * (1.0 - fgAlpha) +
             (bPix.r * (1.0 - bgAlpha) + oPix.r * bgAlpha) * fgAlpha;
  outRgb.g = bgPix.g * bgAlpha * (1.0 - fgAlpha) +
             (bPix.g * (1.0 - bgAlpha) + oPix.g * bgAlpha) * fgAlpha;
  outRgb.b = bgPix.b * bgAlpha * (1.0 - fgAlpha) +
             (bPix.b * (1.0 - bgAlpha) + oPix.b * bgAlpha) * fgAlpha;
  return TPixel32(toByte(outRgb.r), toByte(outRgb.g), toByte(outRgb.b),
                  toByte(outAlpha));
}

bool validateHSLBlend(const TRaster32P& readback, const TRaster32P& foreground,
                      const TRaster32P& background, bool blendHue,
                      bool blendSaturation, bool blendLuminosity,
                      double blendAlpha, bool baseMask) {
  if (!readback || !foreground || !background) return false;
  if (readback->getSize() != foreground->getSize() ||
      readback->getSize() != background->getSize())
    return false;

  readback->lock();
  foreground->lock();
  background->lock();
  for (int y = 0; y < readback->getLy(); ++y) {
    const TPixel32* actualRow = readback->pixels(y);
    const TPixel32* fgRow     = foreground->pixels(y);
    const TPixel32* bgRow     = background->pixels(y);
    for (int x = 0; x < readback->getLx(); ++x) {
      const TPixel32 expected =
          hslBlendReferencePixel(fgRow[x], bgRow[x], blendHue, blendSaturation,
                                 blendLuminosity, blendAlpha, baseMask);
      if (std::abs(actualRow[x].r - expected.r) > 2 ||
          std::abs(actualRow[x].g - expected.g) > 2 ||
          std::abs(actualRow[x].b - expected.b) > 2 ||
          std::abs(actualRow[x].m - expected.m) > 2) {
        background->unlock();
        foreground->unlock();
        readback->unlock();
        std::cerr << "tgraphics_metal_probe: HSL blend pixel mismatch at " << x
                  << "," << y << " expected ";
        printPixel(expected);
        std::cerr << " actual ";
        printPixel(actualRow[x]);
        std::cerr << std::endl;
        return false;
      }
    }
  }
  background->unlock();
  foreground->unlock();
  readback->unlock();
  return true;
}

TPixel32 sunflareReferencePixel(double fragmentX, double fragmentY,
                                const TAffine& outputToWorld,
                                const TPixel32& color, int blades,
                                double intensity, double angle, double bias,
                                double sharpness) {
  constexpr double pi       = 3.14159265358979323846;
  const TPointD world       = outputToWorld * TPointD(fragmentX, fragmentY);
  const double px           = 0.03 * world.x;
  const double py           = 0.03 * world.y;
  const double shiftedAngle = std::atan2(py, px) - angle * pi / 180.0;
  const double bladeBase =
      std::sin(shiftedAngle * std::max(1, blades)) + 0.01 * bias;
  const double blade =
      intensity * std::max(0.0, std::min(1.0, std::pow(bladeBase, sharpness)));
  const double length = std::max(std::sqrt(px * px + py * py), 1.0e-6);
  const double alpha  = color.m / 255.0;
  const double scale  = (1.0 + blade) / length;

  return TPixel32(toByte(color.r / 255.0 * alpha * scale),
                  toByte(color.g / 255.0 * alpha * scale),
                  toByte(color.b / 255.0 * alpha * scale),
                  toByte(alpha * scale));
}

bool closeSunflarePixel(const TPixel32& a, const TPixel32& b) {
  return std::abs(a.r - b.r) <= 2 && std::abs(a.g - b.g) <= 2 &&
         std::abs(a.b - b.b) <= 2 && std::abs(a.m - b.m) <= 2;
}

bool validateSunflare(const TRaster32P& readback, int width, int height,
                      const TAffine& outputToWorld, const TPixel32& color,
                      int blades, double intensity, double angle, double bias,
                      double sharpness) {
  readback->lock();
  for (int y = 0; y < height; ++y) {
    const TPixel32* line = readback->pixels(y);
    for (int x = 0; x < width; ++x) {
      const TPixel32 expected =
          sunflareReferencePixel(x + 0.5, y + 0.5, outputToWorld, color, blades,
                                 intensity, angle, bias, sharpness);
      if (!closeSunflarePixel(line[x], expected)) {
        readback->unlock();
        std::cerr << "tgraphics_metal_probe: sunflare pixel mismatch at " << x
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

TRaster32P renderMetal(const TGraphics::DrawList2D& drawList, int width,
                       int height) {
  return TGraphics::renderDrawListWithMetalBackend(drawList, width, height);
}

TRaster32P renderOpenGL(const TGraphics::DrawList2D& drawList, int width,
                        int height) {
  return TGraphics::renderDrawListWithOpenGLBackend(drawList, width, height);
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
    const TPixel32 backgroundColor0(43, 47, 53, 255);
    const TPixel32 backgroundColor1(87, 93, 101, 255);
    TGraphics::DrawList2D drawList =
        TGraphics::makeCheckerboardBackgroundDrawList(
            TRectD(0, 0, width, height), TDimensionD(3, 2), TPointD(1, -1),
            backgroundColor0, backgroundColor1);

    TRaster32P readback = renderMetal(drawList, width, height);
    if (!readback)
      return fail("could not read back checker background Metal target");
    if (!requireDimensions(readback, width, height)) {
      return fail(
          "checker background readback dimensions do not match render target");
    }

    TRaster32P openGLReadback = renderOpenGL(drawList, width, height);
    if (!openGLReadback)
      return fail("could not read back checker background OpenGL baseline");
    if (!compareRasters(readback, openGLReadback, "checker background",
                        artifactDir)) {
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
    const TPixel32 diagonalClearColor(13, 19, 29, 255);
    const TPixel32 diagonalLineColor(36, 221, 144, 255);
    TGraphics::DrawList2D drawList;
    drawList.setClearColor(diagonalClearColor);
    drawList.addColorLine(TPointD(1, 6), TPointD(7, 2), diagonalLineColor,
                          false);

    TRaster32P readback = renderMetal(drawList, width, height);
    if (!readback)
      return fail("could not read back diagonal color line Metal target");
    if (!requireDimensions(readback, width, height)) {
      return fail(
          "diagonal color line readback dimensions do not match render target");
    }

    TRaster32P openGLReadback = renderOpenGL(drawList, width, height);
    if (!openGLReadback)
      return fail("could not read back diagonal color line OpenGL baseline");
    if (!compareRasters(readback, openGLReadback, "diagonal color line",
                        artifactDir)) {
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
    TRaster32P presentation = makeGradientRaster(width, height);
    TGraphics::DrawList2D drawList =
        TGraphics::makeRasterPresentationDrawList(presentation, width, height);

    TRaster32P readback = renderMetal(drawList, width, height);
    if (!readback)
      return fail("could not read back raster presentation Metal target");
    if (!requireDimensions(readback, width, height)) {
      return fail(
          "raster presentation readback dimensions do not match render target");
    }

    TRaster32P openGLReadback = renderOpenGL(drawList, width, height);
    if (!openGLReadback)
      return fail("could not read back raster presentation OpenGL baseline");
    if (!compareRasters(readback, openGLReadback, "raster presentation",
                        artifactDir)) {
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

  {
    const TPixel32 overlayColor(231, 123, 29, 192);
    const int overlayX0 = 2;
    const int overlayY0 = 1;
    const int overlayX1 = 6;
    const int overlayY1 = 5;
    TGraphics::DrawList2D drawList = TGraphics::makeRasterRectDrawList(
        makeSolidRaster(overlayX1 - overlayX0, overlayY1 - overlayY0,
                        overlayColor),
        TRectD(overlayX0, overlayY0, overlayX1, overlayY1), true);

    TRaster32P readback = renderMetal(drawList, width, height);
    if (!readback)
      return fail("could not read back raster rect Metal target");
    if (!requireDimensions(readback, width, height)) {
      return fail("raster rect readback dimensions do not match render target");
    }

    TRaster32P openGLReadback = renderOpenGL(drawList, width, height);
    if (!openGLReadback)
      return fail("could not read back raster rect OpenGL baseline");
    if (!compareRasters(readback, openGLReadback, "raster rect", artifactDir)) {
      return EXIT_FAILURE;
    }
  }

  {
    const int shaderWidth      = 16;
    const int shaderHeight     = 12;
    const bool blendHue        = true;
    const bool blendSaturation = true;
    const bool blendLuminosity = false;
    const double blendAlpha    = 0.65;
    const bool baseMask        = false;
    TRaster32P foreground      = makeGradientRaster(shaderWidth, shaderHeight);
    TRaster32P background =
        makeSolidRaster(shaderWidth, shaderHeight, TPixel32(36, 120, 210, 255));
    const TAffine outputToTexture =
        TScale(1.0 / shaderWidth, 1.0 / shaderHeight);

    TRaster32P readback = TGraphics::renderHSLBlendWithMetalBackend(
        shaderWidth, shaderHeight, foreground, background, outputToTexture,
        outputToTexture, blendHue, blendSaturation, blendLuminosity, blendAlpha,
        baseMask);
    if (!readback) return fail("could not read back HSL blend Metal shader");
    if (!requireDimensions(readback, shaderWidth, shaderHeight)) {
      return fail("HSL blend readback dimensions do not match render target");
    }
    if (!validateHSLBlend(readback, foreground, background, blendHue,
                          blendSaturation, blendLuminosity, blendAlpha,
                          baseMask)) {
      return EXIT_FAILURE;
    }
  }

  {
    const int shaderWidth      = 1;
    const int shaderHeight     = 1;
    const bool blendHue        = true;
    const bool blendSaturation = true;
    const bool blendLuminosity = false;
    const double blendAlpha    = 1.0;
    const bool baseMask        = false;
    TRaster32P foreground =
        makeSolidRaster(shaderWidth, shaderHeight, TPixel32(75, 120, 180, 255));
    TRaster32P background =
        makeSolidRaster(shaderWidth, shaderHeight, TPixel32(180, 80, 60, 255));
    const TAffine outputToTexture = TScale(1.0, 1.0);

    TRaster32P readback = TGraphics::renderHSLBlendWithMetalBackend(
        shaderWidth, shaderHeight, foreground, background, outputToTexture,
        outputToTexture, blendHue, blendSaturation, blendLuminosity, blendAlpha,
        baseMask);
    if (!readback) return fail("could not read back 1x1 HSL blend shader");
    if (!requireDimensions(readback, shaderWidth, shaderHeight)) {
      return fail("1x1 HSL blend dimensions do not match render target");
    }
    if (!validateHSLBlend(readback, foreground, background, blendHue,
                          blendSaturation, blendLuminosity, blendAlpha,
                          baseMask)) {
      return EXIT_FAILURE;
    }
  }

  {
    const int shaderWidth       = 16;
    const int shaderHeight      = 12;
    const TAffine outputToWorld = TTranslation(24.0, 31.0);
    const TPixel32 color(96, 68, 28, 128);
    const int blades       = 6;
    const double intensity = 0.35;
    const double angle     = 12.0;
    const double bias      = 20.0;
    const double sharpness = 3.0;

    TRaster32P readback = TGraphics::renderSunflareWithMetalBackend(
        shaderWidth, shaderHeight, outputToWorld, color, blades, intensity,
        angle, bias, sharpness);
    if (!readback) return fail("could not read back sunflare Metal shader");
    if (!requireDimensions(readback, shaderWidth, shaderHeight)) {
      return fail("sunflare readback dimensions do not match render target");
    }
    if (!validateSunflare(readback, shaderWidth, shaderHeight, outputToWorld,
                          color, blades, intensity, angle, bias, sharpness)) {
      return EXIT_FAILURE;
    }
  }

  std::cout << "tgraphics_metal_probe: ok on " << TGraphics::metalDeviceName()
            << std::endl;
  return EXIT_SUCCESS;
}
