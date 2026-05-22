#include "tgraphics.h"

#include <cstdlib>
#include <iostream>
#include <memory>

namespace {

bool samePixel(const TPixel32 &a, const TPixel32 &b) {
  return a.r == b.r && a.g == b.g && a.b == b.b && a.m == b.m;
}

void printPixel(const TPixel32 &pixel) {
  std::cerr << "rgba=(" << static_cast<int>(pixel.r) << ","
            << static_cast<int>(pixel.g) << "," << static_cast<int>(pixel.b)
            << "," << static_cast<int>(pixel.m) << ")";
}

TPixel32 gradientPixel(int x, int y) {
  return TPixel32(31 + x * 37, 47 + y * 43, 83 + x * 11 + y * 7, 255);
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

int fail(const char *message) {
  std::cerr << "tgraphics_metal_probe: " << message << std::endl;
  return EXIT_FAILURE;
}

bool validateRaster(const TRaster32P &readback, int width, int height,
                    const TPixel32 &outsideColor, int rectX0, int rectY0,
                    int rectX1, int rectY1) {
  readback->lock();
  for (int y = 0; y < height; ++y) {
    const TPixel32 *line = readback->pixels(y);
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
  const int rectX0 = 2;
  const int rectY0 = 1;
  const int rectX1 = 6;
  const int rectY1 = 5;
  const TPixel32 clearColor(0, 0, 0, 0);

  std::unique_ptr<TGraphics::RenderTarget> target =
      TGraphics::createMetalImageRenderTarget(width, height);
  if (!target) return fail("could not create offscreen Metal render target");

  TGraphics::DrawList2D drawList;
  drawList.addTexture(TRectD(rectX0, rectY0, rectX1, rectY1),
                      makeGradientRaster(rectX1 - rectX0, rectY1 - rectY0),
                      false);

  std::unique_ptr<TGraphics::CommandEncoder> encoder =
      TGraphics::metalDevice().createCommandEncoder(target.get());
  encoder->draw(drawList);

  TRaster32P readback = TGraphics::readMetalRenderTarget(target.get());
  if (!readback) return fail("could not read back offscreen Metal target");
  if (readback->getLx() != width || readback->getLy() != height) {
    return fail("readback dimensions do not match render target dimensions");
  }
  if (!validateRaster(readback, width, height, clearColor, rectX0, rectY0,
                      rectX1, rectY1)) {
    return EXIT_FAILURE;
  }

  std::cout << "tgraphics_metal_probe: ok on "
            << TGraphics::metalDeviceName() << std::endl;
  return EXIT_SUCCESS;
}
