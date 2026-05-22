#include "tofflinegl.h"
#include "tgraphics.h"
#include "trasterimage.h"

#include <QGuiApplication>

#include <cstdlib>
#include <iostream>

namespace {

int fail(const char *message) {
  std::cerr << "tofflinegl_probe: " << message << std::endl;
  return EXIT_FAILURE;
}

const char *backendName(TGraphics::BackendType backend) {
  return backend == TGraphics::BackendType::Metal ? "metal" : "opengl";
}

void printPixel(const TPixel32 &pixel) {
  std::cerr << "rgba=(" << static_cast<int>(pixel.r) << ","
            << static_cast<int>(pixel.g) << "," << static_cast<int>(pixel.b)
            << "," << static_cast<int>(pixel.m) << ")";
}

bool matchesColor(const TRaster32P &raster, const TPixel32 &expected) {
  raster->lock();
  for (int y = 0; y < raster->getLy(); ++y) {
    const TPixel32 *line = raster->pixels(y);
    for (int x = 0; x < raster->getLx(); ++x) {
      if (line[x] != expected) {
        const TPixel32 actual = line[x];
        raster->unlock();
        std::cerr << "tofflinegl_probe: pixel mismatch at " << x << "," << y
                  << " expected ";
        printPixel(expected);
        std::cerr << " actual ";
        printPixel(actual);
        std::cerr << std::endl;
        return false;
      }
    }
  }
  raster->unlock();
  return true;
}

bool matchesRaster(const TRaster32P &actual, const TRaster32P &expected) {
  if (!actual || !expected) return false;
  if (actual->getSize() != expected->getSize()) return false;

  actual->lock();
  expected->lock();
  for (int y = 0; y < actual->getLy(); ++y) {
    const TPixel32 *actualLine   = actual->pixels(y);
    const TPixel32 *expectedLine = expected->pixels(y);
    for (int x = 0; x < actual->getLx(); ++x) {
      if (actualLine[x] != expectedLine[x]) {
        const TPixel32 actualPixel   = actualLine[x];
        const TPixel32 expectedPixel = expectedLine[x];
        expected->unlock();
        actual->unlock();
        std::cerr << "tofflinegl_probe: tgraphics mismatch at " << x << ","
                  << y << " expected ";
        printPixel(expectedPixel);
        std::cerr << " actual ";
        printPixel(actualPixel);
        std::cerr << std::endl;
        return false;
      }
    }
  }
  expected->unlock();
  actual->unlock();
  return true;
}

TPixel32 gradientPixel(int x, int y) {
  return TPixel32(23 + x * 21, 41 + y * 17, 79 + x * 9 + y * 13, 255);
}

TRaster32P makeGradientRaster(int width, int height) {
  TRaster32P raster(width, height);
  raster->lock();
  for (int y = 0; y < height; ++y) {
    TPixel32 *line = raster->pixels(y);
    for (int x = 0; x < width; ++x) line[x] = gradientPixel(x, y);
  }
  raster->unlock();
  return raster;
}

TRaster32P renderLegacyRasterDraw(const TDimension &size,
                                  const TPixel32 &clearColor,
                                  const TRaster32P &source,
                                  const TAffine &placement) {
  TOfflineGL offline(size);
  offline.clear(clearColor);
  offline.draw(TRasterImageP(source), placement, false);
  offline.flush();
  return offline.getRaster();
}

TRaster32P renderTGraphicsRasterDraw(const TDimension &size,
                                     const TPixel32 &clearColor,
                                     const TRectD &placement) {
  TGraphics::DrawList2D drawList;
  drawList.setClearColor(clearColor);
  drawList.addColorRect(placement, TPixel32::White, false);
  return TGraphics::renderDrawListWithActiveBackend(drawList, size.lx, size.ly);
}

}  // namespace

int main(int argc, char *argv[]) {
  QGuiApplication app(argc, argv);

  const TDimension size(16, 12);
  const TPixel32 clearColor(37, 79, 131, 255);

  TOfflineGL offline(size);
  offline.clear(clearColor);
  offline.flush();

  TRaster32P readback = offline.getRaster();
  if (!readback) return fail("readback raster is null");
  if (readback->getSize() != size) {
    return fail("readback dimensions do not match offline target");
  }
  if (!matchesColor(readback, clearColor)) return EXIT_FAILURE;

  TGraphics::DrawList2D drawList;
  drawList.setClearColor(clearColor);
  TRaster32P tgraphicsReadback =
      TGraphics::renderDrawListWithActiveBackend(drawList, size.lx, size.ly);
  if (!tgraphicsReadback) return fail("tgraphics readback raster is null");
  if (!matchesRaster(tgraphicsReadback, readback)) return EXIT_FAILURE;

  const TRaster32P source = makeGradientRaster(8, 8);
  const TAffine rasterPlacement =
      TTranslation(size.lx * 0.5, size.ly * 0.5);
  const TRectD textureRect(4, 2, 12, 10);

  TRaster32P legacyRaster =
      renderLegacyRasterDraw(size, clearColor, source, rasterPlacement);
  if (!legacyRaster) return fail("legacy raster draw readback is null");

  TRaster32P tgraphicsRaster =
      renderTGraphicsRasterDraw(size, clearColor, textureRect);
  if (!tgraphicsRaster) return fail("tgraphics raster draw readback is null");
  if (!matchesRaster(tgraphicsRaster, legacyRaster)) return EXIT_FAILURE;

  std::cout << "tofflinegl_probe: ok backend="
            << backendName(TGraphics::activeBackendType()) << std::endl;
  return EXIT_SUCCESS;
}
