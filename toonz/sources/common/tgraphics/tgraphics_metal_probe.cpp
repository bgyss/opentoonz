#include "tgraphics.h"

#include <cstdlib>
#include <iostream>
#include <memory>

namespace {

bool samePixel(const TPixel32 &a, const TPixel32 &b) {
  return a.r == b.r && a.g == b.g && a.b == b.b && a.m == b.m;
}

TRaster32P makeSolidRaster(int width, int height, const TPixel32 &color) {
  TRaster32P raster(width, height);
  raster->lock();
  for (int y = 0; y < height; ++y) {
    TPixel32 *line = raster->pixels(y);
    for (int x = 0; x < width; ++x) line[x] = color;
  }
  raster->unlock();
  return raster;
}

int fail(const char *message) {
  std::cerr << "tgraphics_metal_probe: " << message << std::endl;
  return EXIT_FAILURE;
}

}  // namespace

int main() {
  if (!TGraphics::isMetalBuildEnabled()) {
    return fail("Metal support was not compiled into this build");
  }
  if (!TGraphics::isMetalDeviceAvailable()) {
    return fail("no Metal device is available");
  }

  const int width  = 8;
  const int height = 8;
  const TPixel32 color(37, 93, 211, 255);

  std::unique_ptr<TGraphics::RenderTarget> target =
      TGraphics::createMetalImageRenderTarget(width, height);
  if (!target) return fail("could not create offscreen Metal render target");

  TGraphics::DrawList2D drawList;
  drawList.addTexture(TRectD(0, 0, width, height),
                      makeSolidRaster(width, height, color), false);

  std::unique_ptr<TGraphics::CommandEncoder> encoder =
      TGraphics::metalDevice().createCommandEncoder(target.get());
  encoder->draw(drawList);

  TRaster32P readback = TGraphics::readMetalRenderTarget(target.get());
  if (!readback) return fail("could not read back offscreen Metal target");
  if (readback->getLx() != width || readback->getLy() != height) {
    return fail("readback dimensions do not match render target dimensions");
  }

  readback->lock();
  for (int y = 0; y < height; ++y) {
    const TPixel32 *line = readback->pixels(y);
    for (int x = 0; x < width; ++x) {
      if (!samePixel(line[x], color)) {
        readback->unlock();
        std::cerr << "tgraphics_metal_probe: pixel mismatch at " << x << ","
                  << y << " expected rgba=(" << static_cast<int>(color.r)
                  << "," << static_cast<int>(color.g) << ","
                  << static_cast<int>(color.b) << ","
                  << static_cast<int>(color.m) << ") actual rgba=("
                  << static_cast<int>(line[x].r) << ","
                  << static_cast<int>(line[x].g) << ","
                  << static_cast<int>(line[x].b) << ","
                  << static_cast<int>(line[x].m) << ")" << std::endl;
        return EXIT_FAILURE;
      }
    }
  }
  readback->unlock();

  std::cout << "tgraphics_metal_probe: ok on "
            << TGraphics::metalDeviceName() << std::endl;
  return EXIT_SUCCESS;
}
