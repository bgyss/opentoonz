#include "tofflinegl.h"

#include <QGuiApplication>

#include <cstdlib>
#include <iostream>

namespace {

int fail(const char *message) {
  std::cerr << "tofflinegl_probe: " << message << std::endl;
  return EXIT_FAILURE;
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
                  << " expected rgba=(" << static_cast<int>(expected.r) << ","
                  << static_cast<int>(expected.g) << ","
                  << static_cast<int>(expected.b) << ","
                  << static_cast<int>(expected.m) << ") actual rgba=("
                  << static_cast<int>(actual.r) << ","
                  << static_cast<int>(actual.g) << ","
                  << static_cast<int>(actual.b) << ","
                  << static_cast<int>(actual.m) << ")" << std::endl;
        return false;
      }
    }
  }
  raster->unlock();
  return true;
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

  std::cout << "tofflinegl_probe: ok" << std::endl;
  return EXIT_SUCCESS;
}
