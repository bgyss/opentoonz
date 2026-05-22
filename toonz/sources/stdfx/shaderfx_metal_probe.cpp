#include "stdfx/shaderfx.h"

#include "tgraphics.h"
#include "trasterfx.h"
#include "ttile.h"

#include <QGuiApplication>
#include <QObject>

#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <string>

namespace {

bool fail(const char* message) {
  std::cerr << "shaderfx_metal_probe: " << message << std::endl;
  return false;
}

struct Options {
  TFilePath shaderFolder = TFilePath("stuff/library/shaders");
  std::string shaderName = "SHADER_sunflare";
  std::string writePamPath;
  std::string comparePamPath;
  std::string writeDiffPamPath;
  int tolerance = 0;
};

void printUsage() {
  std::cerr << "usage: shaderfx_metal_probe [--shader SHADER_name]\n"
               "                            [--shader-folder DIR] [--write-pam "
               "FILE]\n"
               "                            [--compare-pam FILE] "
               "[--write-diff-pam FILE]\n"
               "                            [--tolerance N]\n";
}

bool parseOptions(int argc, char* argv[], Options& options) {
  for (int i = 1; i < argc; ++i) {
    std::string arg(argv[i]);
    if (arg == "--shader" && i + 1 < argc) {
      options.shaderName = argv[++i];
    } else if (arg == "--shader-folder" && i + 1 < argc) {
      options.shaderFolder = TFilePath(argv[++i]);
    } else if (arg == "--write-pam" && i + 1 < argc) {
      options.writePamPath = argv[++i];
    } else if (arg == "--compare-pam" && i + 1 < argc) {
      options.comparePamPath = argv[++i];
    } else if (arg == "--write-diff-pam" && i + 1 < argc) {
      options.writeDiffPamPath = argv[++i];
    } else if (arg == "--tolerance" && i + 1 < argc) {
      options.tolerance = std::atoi(argv[++i]);
    } else if (arg == "--help" || arg == "-h") {
      printUsage();
      return false;
    } else {
      printUsage();
      return false;
    }
  }
  return true;
}

bool pixelsNear(const TPixel32& actual, const TPixel32& expected,
                int tolerance) {
  return std::abs(actual.r - expected.r) <= tolerance &&
         std::abs(actual.g - expected.g) <= tolerance &&
         std::abs(actual.b - expected.b) <= tolerance &&
         std::abs(actual.m - expected.m) <= tolerance;
}

bool compareRasters(const TRaster32P& actual, const TRaster32P& expected,
                    int tolerance) {
  if (!actual || !expected) return fail("missing comparison raster");
  if (actual->getLx() != expected->getLx() ||
      actual->getLy() != expected->getLy())
    return fail("comparison raster dimensions differ");

  actual->lock();
  expected->lock();

  int mismatches = 0;
  for (int y = 0; y < actual->getLy(); ++y) {
    TPixel32* actualRow         = actual->pixels(y);
    const TPixel32* expectedRow = expected->pixels(y);
    for (int x = 0; x < actual->getLx(); ++x) {
      if (!pixelsNear(actualRow[x], expectedRow[x], tolerance)) {
        if (++mismatches <= 8) {
          std::cerr << "shaderfx_metal_probe: pixel mismatch at " << x << ","
                    << y << " actual=(" << int(actualRow[x].r) << ","
                    << int(actualRow[x].g) << "," << int(actualRow[x].b) << ","
                    << int(actualRow[x].m) << ") expected=("
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

bool writePam(const TRaster32P& raster, const std::string& path) {
  if (!raster) return fail("missing raster for PAM write");

  std::ofstream os(path, std::ios::binary);
  if (!os) return fail("could not open PAM output");

  os << "P7\nWIDTH " << raster->getLx() << "\nHEIGHT " << raster->getLy()
     << "\nDEPTH 4\nMAXVAL 255\nTUPLTYPE RGB_ALPHA\nENDHDR\n";

  raster->lock();
  for (int y = 0; y < raster->getLy(); ++y) {
    const TPixel32* row = raster->pixels(y);
    for (int x = 0; x < raster->getLx(); ++x) {
      const unsigned char rgba[4] = {row[x].r, row[x].g, row[x].b, row[x].m};
      os.write(reinterpret_cast<const char*>(rgba), sizeof(rgba));
    }
  }
  raster->unlock();

  return bool(os);
}

TRaster32P readPam(const std::string& path) {
  std::ifstream is(path, std::ios::binary);
  if (!is) {
    fail("could not open PAM input");
    return TRaster32P();
  }

  std::string token;
  int width = 0, height = 0, depth = 0, maxval = 0;
  is >> token;
  if (token != "P7") {
    fail("PAM input is not P7");
    return TRaster32P();
  }

  while (is >> token) {
    if (token == "ENDHDR") break;
    if (token == "WIDTH")
      is >> width;
    else if (token == "HEIGHT")
      is >> height;
    else if (token == "DEPTH")
      is >> depth;
    else if (token == "MAXVAL")
      is >> maxval;
    else {
      std::string ignored;
      std::getline(is, ignored);
    }
  }
  is.get();

  if (width <= 0 || height <= 0 || depth != 4 || maxval != 255) {
    fail("unsupported PAM header");
    return TRaster32P();
  }

  TRaster32P raster(width, height);
  raster->lock();
  for (int y = 0; y < height; ++y) {
    TPixel32* row = raster->pixels(y);
    for (int x = 0; x < width; ++x) {
      unsigned char rgba[4] = {};
      is.read(reinterpret_cast<char*>(rgba), sizeof(rgba));
      row[x] = TPixel32(rgba[0], rgba[1], rgba[2], rgba[3]);
    }
  }
  raster->unlock();

  if (!is) {
    fail("could not read PAM pixel data");
    return TRaster32P();
  }
  return raster;
}

TRaster32P makeDiffRaster(const TRaster32P& actual,
                          const TRaster32P& expected) {
  if (!actual || !expected || actual->getSize() != expected->getSize())
    return TRaster32P();

  TRaster32P diff(actual->getLx(), actual->getLy());
  actual->lock();
  expected->lock();
  diff->lock();

  for (int y = 0; y < actual->getLy(); ++y) {
    const TPixel32* actualRow   = actual->pixels(y);
    const TPixel32* expectedRow = expected->pixels(y);
    TPixel32* diffRow           = diff->pixels(y);
    for (int x = 0; x < actual->getLx(); ++x) {
      diffRow[x] =
          TPixel32(std::abs(actualRow[x].r - expectedRow[x].r),
                   std::abs(actualRow[x].g - expectedRow[x].g),
                   std::abs(actualRow[x].b - expectedRow[x].b),
                   std::max({std::abs(actualRow[x].r - expectedRow[x].r),
                             std::abs(actualRow[x].g - expectedRow[x].g),
                             std::abs(actualRow[x].b - expectedRow[x].b),
                             std::abs(actualRow[x].m - expectedRow[x].m)}));
    }
  }

  diff->unlock();
  expected->unlock();
  actual->unlock();
  return diff;
}

const char* activeBackendName() {
  return TGraphics::activeBackendType() == TGraphics::BackendType::Metal
             ? "metal"
             : "opengl";
}

TRaster32P renderExpectedMetalHelper(const Options& options, int width,
                                     int height, const TTile& tile,
                                     const TRenderSettings& settings) {
  const TAffine outputToWorld =
      (TTranslation(-tile.m_pos) * settings.m_affine).inv();
  if (options.shaderName == "SHADER_sunflare") {
    return TGraphics::renderSunflareWithMetalBackend(
        width, height, outputToWorld, TPixel32(255, 170, 75, 255), 6, 1.0, 0.0,
        0.0, 3.0);
  }
  if (options.shaderName == "SHADER_caustics") {
    return TGraphics::renderCausticsWithMetalBackend(
        width, height, outputToWorld, TPixel32(0, 120, 255, 255), 0.0);
  }
  if (options.shaderName == "SHADER_starsky") {
    return TGraphics::renderStarskyWithMetalBackend(
        width, height, outputToWorld, TPixel32(128, 0, 255, 255), 0.0, 1.0);
  }
  if (options.shaderName == "SHADER_wavy") {
    return TGraphics::renderWavyWithMetalBackend(width, height, outputToWorld,
                                                 TPixel32(0, 0, 255, 255),
                                                 TPixel32(255, 0, 0, 255), 0.0);
  }
  return TRaster32P();
}

}  // namespace

int main(int argc, char* argv[]) {
  if (!TGraphics::isMetalBuildEnabled())
    return fail("Metal support was not compiled into this build") ? 0 : 1;
  if (TGraphics::activeBackendType() == TGraphics::BackendType::Metal &&
      !TGraphics::isMetalDeviceAvailable())
    return fail("no Metal device is available") ? 0 : 1;

  Options options;
  if (!parseOptions(argc, argv, options)) return 1;

  QGuiApplication app(argc, argv);
  QObject mainScope;
  mainScope.setObjectName("mainScope");
  mainScope.setParent(&app);

  loadShaderInterfaces(options.shaderFolder);

  const int width  = 96;
  const int height = 64;
  TTile tile(TRaster32P(width, height), TPointD(-32.0, -24.0));

  TRenderSettings settings;
  settings.m_bpp = 32;
  settings.m_affine =
      TAffine::translation(4.0, -3.0) * TAffine::scale(1.25, 0.75);

  if (!renderShaderFxForProbe(options.shaderName.c_str(), tile, 1.0, settings))
    return fail("could not render shader through ShaderFx") ? 0 : 1;

  TRaster32P actual = tile.getRaster();
  if (!options.writePamPath.empty() && !writePam(actual, options.writePamPath))
    return 1;

  if (!options.comparePamPath.empty()) {
    TRaster32P expected = readPam(options.comparePamPath);
    if (!compareRasters(actual, expected, options.tolerance)) {
      if (!options.writeDiffPamPath.empty())
        writePam(makeDiffRaster(actual, expected), options.writeDiffPamPath);
      return 1;
    }
    if (!options.writeDiffPamPath.empty())
      writePam(makeDiffRaster(actual, expected), options.writeDiffPamPath);
  } else if (TGraphics::activeBackendType() == TGraphics::BackendType::Metal) {
    TRaster32P expected =
        renderExpectedMetalHelper(options, width, height, tile, settings);
    if (!compareRasters(actual, expected, 0)) return 1;
  }

  std::cout << "shaderfx_metal_probe: ok shader=" << options.shaderName
            << " backend=" << activeBackendName();
  if (TGraphics::activeBackendType() == TGraphics::BackendType::Metal)
    std::cout << " device=" << TGraphics::metalDeviceName();
  std::cout << std::endl;
  return 0;
}
