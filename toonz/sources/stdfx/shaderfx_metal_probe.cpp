#include "stdfx/shaderfx.h"

#include "tfxcachemanager.h"
#include "tgraphics.h"
#include "tstream.h"
#include "trenderer.h"
#include "trasterfx.h"
#include "trasterimage.h"
#include "tthread.h"
#include "ttile.h"
#include "toonz/fxdag.h"
#include "toonz/levelset.h"
#include "toonz/scenefx.h"
#include "toonz/sceneproperties.h"
#include "toonz/tcolumnfx.h"
#include "toonz/tcolumnfxset.h"
#include "toonz/toonzscene.h"
#include "toonz/txshcell.h"
#include "toonz/txshleveltypes.h"
#include "toonz/txshsimplelevel.h"
#include "toonz/txsheet.h"

#include <QCoreApplication>
#include <QEventLoop>
#include <QGuiApplication>
#include <QObject>
#include <QString>

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
  std::string saveLoadScenePath;
  int tolerance = 0;
  bool renderWithRenderer = false;
  bool renderWithScene    = false;
};

void printUsage() {
  std::cerr << "usage: shaderfx_metal_probe [--shader SHADER_name]\n"
               "                            [--shader-folder DIR] [--write-pam "
               "FILE]\n"
               "                            [--compare-pam FILE] "
               "[--write-diff-pam FILE]\n"
               "                            [--tolerance N] [--renderer]\n"
               "                            [--scene-render]\n"
               "                            [--save-load-scene FILE]\n";
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
    } else if (arg == "--save-load-scene" && i + 1 < argc) {
      options.saveLoadScenePath = argv[++i];
    } else if (arg == "--tolerance" && i + 1 < argc) {
      options.tolerance = std::atoi(argv[++i]);
    } else if (arg == "--renderer") {
      options.renderWithRenderer = true;
    } else if (arg == "--scene-render") {
      options.renderWithScene = true;
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

bool rasterHasVisiblePixel(const TRaster32P& raster) {
  if (!raster) return false;

  raster->lock();
  bool hasVisiblePixel = false;
  for (int y = 0; y < raster->getLy() && !hasVisiblePixel; ++y) {
    const TPixel32* row = raster->pixels(y);
    for (int x = 0; x < raster->getLx(); ++x) {
      if (row[x].m != 0) {
        hasVisiblePixel = true;
        break;
      }
    }
  }
  raster->unlock();
  return hasVisiblePixel;
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

TPixel32 hslProbeForegroundPixel(int x, int y) {
  return TPixel32(32 + (x * 7) % 180, 48 + (y * 5) % 160,
                  64 + (x * 3 + y * 2) % 150, 255);
}

TPixel32 hslProbeBackgroundPixel(int x, int y) {
  return TPixel32(180 - (x * 5) % 130, 58 + (x * 2 + y * 3) % 150,
                  80 + (y * 7) % 150, 255);
}

TRaster32P makeHSLProbeRaster(int width, int height, const TPointD& pos,
                              bool foreground) {
  TRaster32P raster(width, height);
  raster->lock();
  for (int y = 0; y < height; ++y) {
    TPixel32* row = raster->pixels(y);
    for (int x = 0; x < width; ++x) {
      const int worldX = tround(pos.x) + x;
      const int worldY = tround(pos.y) + y;
      row[x] = foreground ? hslProbeForegroundPixel(worldX, worldY)
                          : hslProbeBackgroundPixel(worldX, worldY);
    }
  }
  raster->unlock();
  return raster;
}

TRaster32P makeHSLProbeSceneRaster(int width, int height, bool foreground) {
  TRaster32P raster(width, height);
  const int xOffset = width / 2;
  const int yOffset = height / 2;
  raster->lock();
  for (int y = 0; y < height; ++y) {
    TPixel32* row = raster->pixels(y);
    for (int x = 0; x < width; ++x) {
      const int worldX = x - xOffset;
      const int worldY = y - yOffset;
      row[x] = foreground ? hslProbeForegroundPixel(worldX, worldY)
                          : hslProbeBackgroundPixel(worldX, worldY);
    }
  }
  raster->unlock();
  return raster;
}

class HSLProbeRasterFx final : public TRasterFx {
  FX_DECLARATION(HSLProbeRasterFx)

  bool m_foreground = false;

public:
  HSLProbeRasterFx() = default;
  explicit HSLProbeRasterFx(bool foreground) : m_foreground(foreground) {}

  TFx* clone(bool recursive = true) const override {
    HSLProbeRasterFx* fx =
        dynamic_cast<HSLProbeRasterFx*>(TRasterFx::clone(recursive));
    fx->m_foreground = m_foreground;
    return fx;
  }

  std::string getPluginId() const override { return std::string(); }

  bool doGetBBox(double, TRectD& bbox, const TRenderSettings&) override {
    bbox = TRectD(-100000.0, -100000.0, 100000.0, 100000.0);
    return true;
  }

  bool canHandle(const TRenderSettings&, double) override { return true; }

  int getMemoryRequirement(const TRectD&, double,
                           const TRenderSettings&) override {
    return -1;
  }

  std::string getAlias(double frame, const TRenderSettings& info) const override {
    return TRasterFx::getAlias(frame, info) + (m_foreground ? "[fg]" : "[bg]");
  }

protected:
  void doCompute(TTile& tile, double, const TRenderSettings&) override {
    TRaster32P raster = tile.getRaster();
    if (!raster) return;
    TRaster32P source =
        makeHSLProbeRaster(raster->getLx(), raster->getLy(), tile.m_pos,
                           m_foreground);
    raster->copy(source);
  }
};

FX_IDENTIFIER_IS_HIDDEN(HSLProbeRasterFx, "hslProbeRasterFx")

class ProbeRenderScope {
  TRenderer m_renderer;
  unsigned long m_renderId;
  double m_frame;

public:
  explicit ProbeRenderScope(double frame)
      : m_renderer(1), m_renderId(TRenderer::buildRenderId()), m_frame(frame) {
    m_renderer.install(m_renderId);
    m_renderer.declareRenderStart(m_renderId);
    m_renderer.declareFrameStart(m_frame);
    TFxCacheManager::instance()->onRenderStatusStart(TRenderer::COMPUTING);
  }

  ~ProbeRenderScope() {
    TFxCacheManager::instance()->onRenderStatusEnd(TRenderer::COMPUTING);
    m_renderer.declareFrameEnd(m_frame);
    m_renderer.declareRenderEnd(m_renderId);
    m_renderer.uninstall();
  }
};

class ProbeRenderPort final : public TRenderPort {
  TRasterP m_raster;
  bool m_finished = false;
  bool m_failed   = false;
  std::string m_error;

public:
  bool isFinished() const { return m_finished; }
  bool hasFailed() const { return m_failed; }
  const std::string& error() const { return m_error; }
  TRasterP raster() const { return m_raster; }

  void onRenderRasterCompleted(const RenderData& renderData) override {
    if (renderData.m_rasA) m_raster = renderData.m_rasA->clone();
  }

  void onRenderFailure(const RenderData&, TException& e) override {
    m_failed = true;
    m_error  = QString::fromStdWString(e.getMessage()).toStdString();
  }

  void onRenderFinished(bool isCanceled = false) override {
    m_finished = true;
    if (isCanceled) {
      m_failed = true;
      m_error  = "renderer canceled";
    }
  }
};

TRasterFxP makeProbeShaderFx(const Options& options, TFxP foregroundFx,
                             TFxP backgroundFx) {
  TFx* fx = TFx::create(options.shaderName.c_str());
  TRasterFx* rasterFx = dynamic_cast<TRasterFx*>(fx);
  if (!rasterFx) {
    delete fx;
    return TRasterFxP();
  }

  TRasterFxP root(rasterFx);
  if (options.shaderName == "SHADER_HSLBlendGPU") {
    if (root->getInputPortCount() != 2) return TRasterFxP();
    if (!root->getInputPort(0) || !root->getInputPort(1)) return TRasterFxP();
    root->getInputPort(0)->setFx(foregroundFx.getPointer());
    root->getInputPort(1)->setFx(backgroundFx.getPointer());
  }
  return root;
}

TRaster32P renderRasterFxWithRenderer(TRasterFxP root, const TTile& tile,
                                      double frame,
                                      const TRenderSettings& settings) {
  if (!root) return TRaster32P();

  TRenderer renderer(1);
  renderer.enablePrecomputing(true);

  ProbeRenderPort port;
  port.setRenderArea(TRectD(tile.m_pos,
                            TDimensionD(tile.getRaster()->getLx(),
                                        tile.getRaster()->getLy())));
  renderer.addPort(&port);

  TFxPair fxPair;
  fxPair.m_frameA = root;
  unsigned long renderId = renderer.startRendering(frame, settings, fxPair);
  if (renderId == (unsigned long)-1) {
    renderer.removePort(&port);
    return TRaster32P();
  }

  while (!port.isFinished()) {
    QCoreApplication::processEvents(QEventLoop::AllEvents |
                                    QEventLoop::WaitForMoreEvents);
  }
  renderer.removePort(&port);
  if (port.hasFailed()) {
    std::cerr << "shaderfx_metal_probe: renderer failed: " << port.error()
              << std::endl;
    return TRaster32P();
  }
  return TRaster32P(port.raster());
}

TRaster32P renderWithRendererForProbe(const Options& options, const TTile& tile,
                                      double frame,
                                      const TRenderSettings& settings,
                                      TFxP foregroundFx, TFxP backgroundFx) {
  return renderRasterFxWithRenderer(
      makeProbeShaderFx(options, foregroundFx, backgroundFx), tile, frame,
      settings);
}

TLevelColumnFx* addProbeRasterColumn(ToonzScene& scene, int columnIndex,
                                     int row,
                                     const std::wstring& levelName,
                                     TRaster32P raster) {
  TXshSimpleLevel* level = new TXshSimpleLevel(levelName);
  level->setScene(&scene);
  level->setType(OVL_XSHLEVEL);
  scene.getLevelSet()->insertLevel(level);
  level->setFrame(TFrameId(1), TImageP(new TRasterImage(raster)));

  TXsheet* xsheet = scene.getXsheet();
  if (!xsheet) return nullptr;

  if (!xsheet->setCell(row, columnIndex,
                       TXshCell(TXshLevelP(level), TFrameId(1))))
    return nullptr;

  TXshColumn* column = xsheet->getColumn(columnIndex);
  if (!column || !column->getCellColumn()) return nullptr;
  return dynamic_cast<TLevelColumnFx*>(column->getCellColumn()->getFx());
}

TRaster32P renderHSLSceneForProbe(const Options& options, const TTile& tile,
                                  double frame,
                                  const TRenderSettings& settings) {
  ToonzScene scene;
  const int width  = tile.getRaster()->getLx() * 3;
  const int height = tile.getRaster()->getLy() * 3;

  TLevelColumnFx* foregroundFx = addProbeRasterColumn(
      scene, 0, tfloor(frame), L"HSLProbeForeground",
      makeHSLProbeSceneRaster(width, height, true));
  TLevelColumnFx* backgroundFx = addProbeRasterColumn(
      scene, 1, tfloor(frame), L"HSLProbeBackground",
      makeHSLProbeSceneRaster(width, height, false));
  if (!foregroundFx || !backgroundFx) return TRaster32P();

  TFxP root = makeProbeShaderFx(options, TFxP(foregroundFx), TFxP(backgroundFx));
  if (!root) return TRaster32P();

  TFxP builtFx = buildSceneFx(&scene, frame, scene.getXsheet(), root,
                              BSFX_DEFAULT_TR, true);
  return renderRasterFxWithRenderer(builtFx, tile, frame, settings);
}

TRaster32P renderSceneForProbe(const Options& options, const TTile& tile,
                               double frame, const TRenderSettings& settings,
                               TFxP foregroundFx, TFxP backgroundFx) {
  if (options.shaderName == "SHADER_HSLBlendGPU")
    return renderHSLSceneForProbe(options, tile, frame, settings);

  TFxP root = makeProbeShaderFx(options, foregroundFx, backgroundFx);
  if (!root) return TRaster32P();

  ToonzScene scene;
  TFxP builtFx = buildSceneFx(&scene, frame, scene.getXsheet(), root,
                              BSFX_DEFAULT_TR, true);
  return renderRasterFxWithRenderer(builtFx, tile, frame, settings);
}

bool attachRootFxToScene(ToonzScene& scene, const TFxP& root) {
  if (!root) return false;

  TXsheet* xsheet = scene.getXsheet();
  if (!xsheet) return false;

  FxDag* fxDag = xsheet->getFxDag();
  if (!fxDag || fxDag->getOutputFxCount() < 1 || !fxDag->getOutputFx(0))
    return false;

  fxDag->getInternalFxs()->addFx(root.getPointer());
  fxDag->assignUniqueId(root.getPointer());
  fxDag->getOutputFx(0)->getInputPort(0)->setFx(root.getPointer());
  return true;
}

void writeProbeSceneFile(ToonzScene& scene, const TFilePath& scenePath) {
  TOStream os(scenePath, false);
  if (!os.checkStatus()) throw TException("Could not open probe scene file");

  std::map<std::string, std::string> attr;
  attr["version"]    = "71.1";
  attr["framecount"] = QString::number(scene.getFrameCount()).toStdString();
  os.openChild("tnz", attr);
  os.child("generator") << std::string("shaderfx_metal_probe");
  os.openChild("properties");
  scene.getProperties()->saveData(os);
  os.closeChild();
  os.openChild("levelSet");
  scene.getLevelSet()->saveData(os);
  os.closeChild();
  os.openChild("xsheet");
  os << *scene.getXsheet();
  os.closeChild();
  os.closeChild();

  if (!os.checkStatus()) throw TException("Could not write probe scene file");
}

TRaster32P renderSavedLoadedSceneForProbe(const Options& options,
                                          const TTile& tile, double frame,
                                          const TRenderSettings& settings,
                                          TFxP foregroundFx,
                                          TFxP backgroundFx) {
  TFxP root = makeProbeShaderFx(options, foregroundFx, backgroundFx);
  if (!root) return TRaster32P();

  ToonzScene sourceScene;
  if (!attachRootFxToScene(sourceScene, root)) return TRaster32P();

  const TFilePath scenePath(options.saveLoadScenePath);
  writeProbeSceneFile(sourceScene, scenePath);

  ToonzScene loadedScene;
  loadedScene.loadTnzFile(scenePath);
  TFxP builtFx = buildSceneFx(&loadedScene, loadedScene.getXsheet(), frame, 1,
                              true);
  return renderRasterFxWithRenderer(builtFx, tile, frame, settings);
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
  if (options.shaderName == "SHADER_fireball") {
    return TGraphics::renderFireballWithMetalBackend(
        width, height, outputToWorld, TPixel32(255, 0, 0, 255),
        TPixel32(225, 200, 0, 255), 12.0, 0.0);
  }
  if (options.shaderName == "SHADER_HSLBlendGPU") {
    const TAffine outputToTexture = TScale(1.0 / width, 1.0 / height);
    return TGraphics::renderHSLBlendWithMetalBackend(
        width, height, makeHSLProbeRaster(width, height, tile.m_pos, true),
        makeHSLProbeRaster(width, height, tile.m_pos, false), outputToTexture,
        outputToTexture, true, true, false, 1.0, false);
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
  TThread::init();
  TRenderer::initialize();

  loadShaderInterfaces(options.shaderFolder);

  TFxP foregroundFx;
  TFxP backgroundFx;
  if (options.shaderName == "SHADER_HSLBlendGPU") {
    foregroundFx = TFxP(new HSLProbeRasterFx(true));
    backgroundFx = TFxP(new HSLProbeRasterFx(false));
  }

  const int width  = 96;
  const int height = 64;
  TTile tile(TRaster32P(width, height), TPointD(-32.0, -24.0));

  TRenderSettings settings;
  settings.m_bpp = 32;
  settings.m_affine =
      TAffine::translation(4.0, -3.0) * TAffine::scale(1.25, 0.75);
  if (options.shaderName == "SHADER_HSLBlendGPU")
    settings.m_affine = TAffine();

  bool rendered = false;
  if (options.renderWithScene) {
    if (options.shaderName == "SHADER_HSLBlendGPU" &&
        TGraphics::activeBackendType() != TGraphics::BackendType::Metal)
      return fail("SHADER_HSLBlendGPU scene-render probe requires the Metal "
                  "backend")
                 ? 0
                 : 1;
    if (options.shaderName == "SHADER_HSLBlendGPU" &&
        !options.saveLoadScenePath.empty())
      return fail("SHADER_HSLBlendGPU saved-scene probe is not supported yet")
                 ? 0
                 : 1;
    TRaster32P renderedRaster;
    if (!options.saveLoadScenePath.empty())
      renderedRaster = renderSavedLoadedSceneForProbe(
          options, tile, 1.0, settings, foregroundFx, backgroundFx);
    else
      renderedRaster = renderSceneForProbe(options, tile, 1.0, settings,
                                           foregroundFx, backgroundFx);
    if (renderedRaster) {
      tile.getRaster()->copy(renderedRaster);
      rendered = true;
    }
  } else if (options.renderWithRenderer) {
    if (options.shaderName == "SHADER_HSLBlendGPU" &&
        TGraphics::activeBackendType() != TGraphics::BackendType::Metal)
      return fail("SHADER_HSLBlendGPU probe requires the Metal backend") ? 0
                                                                         : 1;
    TRaster32P renderedRaster = renderWithRendererForProbe(
        options, tile, 1.0, settings, foregroundFx, backgroundFx);
    if (renderedRaster) {
      tile.getRaster()->copy(renderedRaster);
      rendered = true;
    }
  } else if (options.shaderName == "SHADER_HSLBlendGPU") {
    if (TGraphics::activeBackendType() != TGraphics::BackendType::Metal)
      return fail("SHADER_HSLBlendGPU probe requires the Metal backend") ? 0
                                                                         : 1;
    ProbeRenderScope renderScope(1.0);
    rendered = renderConnectedShaderFxForProbe(
        options.shaderName.c_str(), foregroundFx.getPointer(),
        backgroundFx.getPointer(), tile, 1.0, settings);
  } else {
    rendered =
        renderShaderFxForProbe(options.shaderName.c_str(), tile, 1.0, settings);
  }
  if (!rendered)
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
  } else if (options.renderWithScene) {
    if (!rasterHasVisiblePixel(actual))
      return fail("scene-render output was fully transparent") ? 0 : 1;
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
