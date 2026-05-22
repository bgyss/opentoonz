#include "stdfx/shaderfx.h"

#include "tgraphics.h"
#include "trasterfx.h"
#include "ttile.h"

#include <cstdlib>
#include <iostream>

namespace {

bool fail(const char *message) {
  std::cerr << "shaderfx_metal_probe: " << message << std::endl;
  return false;
}

bool pixelsNear(const TPixel32 &actual, const TPixel32 &expected,
                int tolerance) {
  return std::abs(actual.r - expected.r) <= tolerance &&
         std::abs(actual.g - expected.g) <= tolerance &&
         std::abs(actual.b - expected.b) <= tolerance &&
         std::abs(actual.m - expected.m) <= tolerance;
}

bool compareRasters(const TRaster32P &actual, const TRaster32P &expected,
                    int tolerance) {
  if (!actual || !expected) return fail("missing comparison raster");
  if (actual->getLx() != expected->getLx() ||
      actual->getLy() != expected->getLy())
    return fail("comparison raster dimensions differ");

  actual->lock();
  expected->lock();

  int mismatches = 0;
  for (int y = 0; y < actual->getLy(); ++y) {
    TPixel32 *actualRow         = actual->pixels(y);
    const TPixel32 *expectedRow = expected->pixels(y);
    for (int x = 0; x < actual->getLx(); ++x) {
      if (!pixelsNear(actualRow[x], expectedRow[x], tolerance)) {
        if (++mismatches <= 8) {
          std::cerr << "shaderfx_metal_probe: pixel mismatch at " << x << ","
                    << y << " actual=(" << int(actualRow[x].r) << ","
                    << int(actualRow[x].g) << "," << int(actualRow[x].b)
                    << "," << int(actualRow[x].m) << ") expected=("
                    << int(expectedRow[x].r) << "," << int(expectedRow[x].g)
                    << "," << int(expectedRow[x].b) << ","
                    << int(expectedRow[x].m) << ")" << std::endl;
        }
      }
    }
  }

  actual->unlock();
  expected->unlock();

  if (mismatches != 0) {
    std::cerr << "shaderfx_metal_probe: mismatched pixels=" << mismatches
              << std::endl;
    return false;
  }
  return true;
}

}  // namespace

int main(int argc, char *argv[]) {
  if (!TGraphics::isMetalBuildEnabled())
    return fail("Metal support was not compiled into this build") ? 0 : 1;
  if (!TGraphics::isMetalDeviceAvailable())
    return fail("no Metal device is available") ? 0 : 1;
  if (TGraphics::activeBackendType() != TGraphics::BackendType::Metal)
    return fail("run with OPENTOONZ_GRAPHICS_BACKEND=metal") ? 0 : 1;

  TFilePath shaderFolder(argc > 1 ? argv[1] : "stuff/library/shaders");
  loadShaderInterfaces(shaderFolder);

  const int width = 96;
  const int height = 64;
  TTile tile(TRaster32P(width, height), TPointD(-32.0, -24.0));

  TRenderSettings settings;
  settings.m_bpp = 32;
  settings.m_affine =
      TAffine::translation(4.0, -3.0) * TAffine::scale(1.25, 0.75);

  if (!renderSunflareShaderFxWithMetalForProbe(tile, 1.0, settings))
    return fail("could not render SHADER_sunflare through ShaderFx") ? 0 : 1;

  TRaster32P actual = tile.getRaster();
  TRaster32P expected = TGraphics::renderSunflareWithMetalBackend(
      width, height, (TTranslation(-tile.m_pos) * settings.m_affine).inv(),
      TPixel32(255, 170, 75, 255), 6, 1.0, 0.0, 0.0, 3.0);
  if (!compareRasters(actual, expected, 0)) return 1;

  std::cout << "shaderfx_metal_probe: ok on "
            << TGraphics::metalDeviceName() << std::endl;
  return 0;
}
