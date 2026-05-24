

// Tnz6 includes
#include "crashhandler.h"
#include "mainwindow.h"
#include "flipbook.h"
#include "sceneviewer.h"
#include "tapp.h"
#include "iocommand.h"
#include "previewer.h"
#include "previewfxmanager.h"
#include "cleanupsettingspopup.h"
#include "filebrowsermodel.h"
#include "expressionreferencemanager.h"
#include "thirdparty.h"

// TnzTools includes
#include "tools/tool.h"
#include "tools/toolcommandids.h"

// TnzQt includes
#include "toonzqt/dvdialog.h"
#include "toonzqt/menubarcommand.h"
#include "toonzqt/tmessageviewer.h"
#include "toonzqt/icongenerator.h"
#include "toonzqt/gutil.h"
#include "toonzqt/pluginloader.h"

// TnzStdfx includes
#include "stdfx/shaderfx.h"

// TnzLib includes
#include "toonz/preferences.h"
#include "toonz/toonzfolders.h"
#include "toonz/tproject.h"
#include "toonz/studiopalette.h"
#include "toonz/stylemanager.h"
#include "toonz/tscenehandle.h"
#include "toonz/tframehandle.h"
#include "toonz/txshsimplelevel.h"
#include "toonz/tproject.h"
#include "toonz/scriptengine.h"
#include "toonz/scenefx.h"
#include "toonz/toonzscene.h"
#include "toonz/sceneproperties.h"
#include "toonz/tcamera.h"
#include "toonz/txshcolumn.h"
#include "toonz/tpalettehandle.h"

// TnzSound includes
#include "tnzsound.h"

// TnzImage includes
#include "tnzimage.h"

// TnzBase includes
#include "permissionsmanager.h"
#include "tenv.h"
#include "tcli.h"

// TnzCore includes
#include "tsystem.h"
#include "tthread.h"
#include "tthreadmessage.h"
#include "tundo.h"
#include "tconvert.h"
#include "tiio_std.h"
#include "timagecache.h"
#include "toutputproperties.h"
#include "tofflinegl.h"
#include "tpluginmanager.h"
#include "tsimplecolorstyles.h"
#include "toonz/imagestyles.h"
#include "tvectorbrushstyle.h"
#include "tvectorimage.h"
#include "tpixelcm.h"
#include "tfont.h"

#include "kis_tablet_support_win8.h"

#ifdef MACOSX
#include "tipc.h"
#endif

// Qt includes
#include <QApplication>
#include <QAbstractEventDispatcher>
#include <QAbstractNativeEventFilter>
#include <QSplashScreen>
#include <QSurfaceFormat>
#include <QTranslator>
#include <QFileInfo>
#include <QSettings>
#include <QLibraryInfo>
#include <QHash>
#include <QImage>
#include <QFile>
#include <QPixmap>
#include <QThread>
#include <QTimer>
#include <QMouseEvent>

#include <cstdlib>
#include <cerrno>
#include <climits>
#include <atomic>
#include <fstream>
#include <iostream>

#ifdef _WIN32
#ifndef x64
#include <float.h>
#endif
#include <QtPlatformHeaders/QWindowsWindowFunctions>
#endif

using namespace DVGui;

TEnv::IntVar EnvSoftwareCurrentFontSize("SoftwareCurrentFontSize", 12);

// These are the same as the default values. See tenv.cpp and tversion.h
const char* rootVarName     = "TOONZROOT";
const char* systemVarPrefix = "TOONZ";

#ifdef MACOSX
#include "tthread.h"
void postThreadMsg(TThread::Message*) {}
void qt_mac_set_menubar_merge(bool enable);
#endif

// Modifica per toonz (non servono questo tipo di licenze)
#define NO_LICENSE
//-----------------------------------------------------------------------------

static void logGraphicsSmokeMainEvent(const std::string& event) {
  if (!std::getenv("OPENTOONZ_GRAPHICS_METAL_FRAME_DIAGNOSTICS")) return;

  const std::string message =
      std::string("OpenToonz graphics smoke: main_") + event;
  std::cerr << message << std::endl;

  const char* tracePath = std::getenv("OPENTOONZ_GRAPHICS_SMOKE_TRACE_FILE");
  if (tracePath && *tracePath) {
    std::ofstream trace(tracePath, std::ios::app);
    trace << message << '\n';
  }
}

//-----------------------------------------------------------------------------

static int getGraphicsSmokeFrame() {
  const char* frameText = std::getenv("OPENTOONZ_GRAPHICS_SMOKE_FRAME");
  if (!frameText || !*frameText) return -1;

  errno      = 0;
  char* end  = nullptr;
  long frame = std::strtol(frameText, &end, 10);
  if (errno != 0 || end == frameText || *end != '\0' || frame <= 0 ||
      frame > INT_MAX) {
    logGraphicsSmokeMainEvent(std::string("smoke_frame_invalid value=") +
                              frameText);
    return -1;
  }
  return static_cast<int>(frame);
}

static void setGraphicsSmokeFrame(QApplication& app, int oneBasedFrame) {
  if (oneBasedFrame <= 0) return;

  TApp* toonzApp = TApp::instance();
  if (!toonzApp || !toonzApp->getCurrentFrame()) {
    logGraphicsSmokeMainEvent("smoke_frame_no_handle");
    return;
  }

  const int zeroBasedFrame = oneBasedFrame - 1;
  toonzApp->getCurrentFrame()->setFrame(zeroBasedFrame);
  app.processEvents();
  logGraphicsSmokeMainEvent(
      "smoke_frame_set frame=" + std::to_string(oneBasedFrame) +
      " index=" + std::to_string(zeroBasedFrame));
}

//-----------------------------------------------------------------------------

static std::string getGraphicsSmokeRasterSummary(const TRasterP& raster) {
  if (!raster) return "raster=null";

  TRaster32P raster32 = raster;
  if (!raster32)
    return "raster_type=unsupported width=" + std::to_string(raster->getLx()) +
           " height=" + std::to_string(raster->getLy());

  const int width  = raster32->getLx();
  const int height = raster32->getLy();
  if (width <= 0 || height <= 0)
    return "raster_type=rgba width=" + std::to_string(width) +
           " height=" + std::to_string(height) + " samples=0";

  const TPixel32 first = raster32->pixels(0)[0];
  bool colorVaries     = false;
  bool alphaVaries     = false;
  bool hasAlpha        = first.m > 0;
  int sampleCount      = 0;
  for (int y = 0; y < height; ++y) {
    const TPixel32* line = raster32->pixels(y);
    for (int x = 0; x < width; ++x) {
      const TPixel32 pixel = line[x];
      ++sampleCount;
      if (pixel.r != first.r || pixel.g != first.g || pixel.b != first.b)
        colorVaries = true;
      if (pixel.m != first.m) alphaVaries = true;
      if (pixel.m > 0) hasAlpha = true;
    }
  }

  return "raster_type=rgba width=" + std::to_string(width) +
         " height=" + std::to_string(height) +
         " samples=" + std::to_string(sampleCount) +
         " first_rgba=" + std::to_string(first.r) + "," +
         std::to_string(first.g) + "," + std::to_string(first.b) + "," +
         std::to_string(first.m) +
         " color_varies=" + std::to_string(colorVaries ? 1 : 0) +
         " alpha_varies=" + std::to_string(alphaVaries ? 1 : 0) +
         " has_alpha=" + std::to_string(hasAlpha ? 1 : 0);
}

//-----------------------------------------------------------------------------

static bool isGraphicsSmokeNonBlankImage(const QImage& image) {
  if (image.isNull() || image.width() <= 0 || image.height() <= 0) return false;

  const QRgb first = image.pixel(0, 0);
  for (int y = 0; y < image.height(); ++y) {
    for (int x = 0; x < image.width(); ++x) {
      if (image.pixel(x, y) != first) return true;
    }
  }
  return false;
}

//-----------------------------------------------------------------------------

static std::string getGraphicsSmokeRasterCmSummary(const TRasterCM32P& raster) {
  if (!raster) return "cm_raster=null";

  const int width  = raster->getLx();
  const int height = raster->getLy();
  if (width <= 0 || height <= 0)
    return "cm_raster width=" + std::to_string(width) +
           " height=" + std::to_string(height) + " samples=0";

  const TPixelCM32 first = raster->pixels(0)[0];
  bool varies           = false;
  int nonEmpty          = 0;
  int sampleCount       = 0;
  for (int y = 0; y < height; ++y) {
    const TPixelCM32* line = raster->pixels(y);
    for (int x = 0; x < width; ++x) {
      const TPixelCM32 pixel = line[x];
      ++sampleCount;
      if (!(pixel == first)) varies = true;
      if (pixel.getInk() != 0 || pixel.getPaint() != 0 ||
          pixel.getTone() != TPixelCM32::getMaxTone()) {
        ++nonEmpty;
      }
    }
  }

  return "cm_raster width=" + std::to_string(width) +
         " height=" + std::to_string(height) +
         " samples=" + std::to_string(sampleCount) +
         " first_cmp=" + std::to_string(first.getInk()) + "," +
         std::to_string(first.getPaint()) + "," +
         std::to_string(first.getTone()) +
         " varies=" + std::to_string(varies ? 1 : 0) +
         " non_empty=" + std::to_string(nonEmpty);
}

//-----------------------------------------------------------------------------

static std::string getGraphicsSmokeToolImageSummary() {
  TImageP image(TTool::getImage(false));
  if (!image) return "type=null";

  if (TVectorImageP vi = image) {
    return "type=vector strokes=" + std::to_string(vi->getStrokeCount());
  }

  if (TToonzImageP ti = image) {
    return "type=toonz " + getGraphicsSmokeRasterCmSummary(ti->getRaster());
  }

  if (TRasterImageP ri = image) {
    return "type=raster " + getGraphicsSmokeRasterSummary(ri->getRaster());
  }

  return "type=unknown";
}

//-----------------------------------------------------------------------------

class GraphicsSmokeRenderPort final : public TRenderPort {
  std::atomic<bool> m_done{false};
  std::atomic<bool> m_failed{false};
  TRasterP m_raster;

public:
  void onRenderRasterCompleted(const RenderData& renderData) override {
    if (renderData.m_rasA) m_raster = renderData.m_rasA->clone();
    m_done = true;
  }

  void onRenderFailure(const RenderData&, TException&) override {
    m_failed = true;
    m_done   = true;
  }

  bool isDone() const { return m_done; }
  bool isFailed() const { return m_failed; }
  TRasterP raster() const { return m_raster; }
};

static QImage renderGraphicsSmokeSceneFrame(QApplication& app, int frame) {
  TApp* toonzApp    = TApp::instance();
  ToonzScene* scene = toonzApp && toonzApp->getCurrentScene()
                          ? toonzApp->getCurrentScene()->getScene()
                          : nullptr;
  if (!scene) {
    logGraphicsSmokeMainEvent("internal_scene_render_no_scene");
    return QImage();
  }

  TRenderSettings renderSettings =
      scene->getProperties()->getOutputProperties()->getRenderSettings();
  TFxPair fxPair;
  fxPair.m_frameA = buildSceneFx(scene, scene->getXsheet(), frame,
                                 TOutputProperties::AllLevels,
                                 renderSettings.m_shrinkX, false);
  if (!fxPair.m_frameA) {
    logGraphicsSmokeMainEvent("internal_scene_render_no_fx");
    return QImage();
  }

  GraphicsSmokeRenderPort port;
  TCamera* camera = scene->getCurrentCamera();
  if (camera) {
    TDimension cameraRes = camera->getRes();
    port.setRenderArea(TRectD(TPointD(-0.5 * cameraRes.lx, -0.5 * cameraRes.ly),
                              TDimensionD(cameraRes.lx, cameraRes.ly)));
  }
  TRenderer renderer(1);
  renderer.enablePrecomputing(false);
  renderer.addPort(&port);
  renderer.startRendering(frame, renderSettings, fxPair);

  for (int attempt = 0; attempt < 200 && !port.isDone(); ++attempt) {
    app.processEvents();
    QThread::msleep(50);
  }
  renderer.stopRendering(true);
  renderer.removePort(&port);

  if (!port.isDone()) {
    logGraphicsSmokeMainEvent("internal_scene_render_timeout frame=" +
                              std::to_string(frame + 1));
    return QImage();
  }
  if (port.isFailed()) {
    logGraphicsSmokeMainEvent("internal_scene_render_failed frame=" +
                              std::to_string(frame + 1));
    return QImage();
  }

  TRasterP raster = port.raster();
  logGraphicsSmokeMainEvent("internal_scene_render_raster " +
                            getGraphicsSmokeRasterSummary(raster));
  if (!raster) return QImage();

  QImage image = rasterToQImage(raster, true, true).copy();
  if (!isGraphicsSmokeNonBlankImage(image)) {
    logGraphicsSmokeMainEvent("internal_scene_render_blank frame=" +
                              std::to_string(frame + 1));
  }
  return image;
}

//-----------------------------------------------------------------------------

static std::vector<bool> enableGraphicsSmokePreviewColumns(ToonzScene* scene) {
  std::vector<bool> oldStatus;
  TXsheet* xsh = scene ? scene->getXsheet() : nullptr;
  if (!xsh) return oldStatus;

  const int columnCount = xsh->getColumnCount();
  oldStatus.reserve(columnCount);
  int changedCount  = 0;
  int nonEmptyCount = 0;
  for (int i = 0; i < columnCount; ++i) {
    TXshColumn* column    = xsh->getColumn(i);
    const bool wasVisible = column && column->isPreviewVisible();
    oldStatus.push_back(wasVisible);
    if (column && !column->isEmpty()) {
      ++nonEmptyCount;
      if (!wasVisible) {
        column->setPreviewVisible(true);
        ++changedCount;
      }
    }
  }

  logGraphicsSmokeMainEvent(
      "internal_preview_columns column_count=" + std::to_string(columnCount) +
      " non_empty=" + std::to_string(nonEmptyCount) +
      " changed=" + std::to_string(changedCount));
  return oldStatus;
}

static void restoreGraphicsSmokePreviewColumns(
    ToonzScene* scene, const std::vector<bool>& oldStatus) {
  TXsheet* xsh = scene ? scene->getXsheet() : nullptr;
  if (!xsh) return;

  const int columnCount =
      std::min(static_cast<int>(oldStatus.size()), xsh->getColumnCount());
  for (int i = 0; i < columnCount; ++i) {
    TXshColumn* column = xsh->getColumn(i);
    if (column) column->setPreviewVisible(oldStatus[i]);
  }
}

//-----------------------------------------------------------------------------

static void runGraphicsSmokeInternalActions(QApplication& app) {
  const char* actions =
      std::getenv("OPENTOONZ_GRAPHICS_SMOKE_INTERNAL_ACTIONS");
  if (!actions) return;
  const std::string actionName(actions);
  if (actionName != "basic-viewer" && actionName != "internal-basic-viewer" &&
      actionName != "internal-editing-context" &&
      actionName != "internal-viewer-input" &&
      actionName != "internal-style-editor" &&
      actionName != "internal-drawing-gesture" &&
      actionName != "internal-preview-export")
    return;

  logGraphicsSmokeMainEvent("internal_actions_start");
  const int targetFrame = getGraphicsSmokeFrame();

  TApp* toonzApp      = TApp::instance();
  SceneViewer* viewer = toonzApp ? toonzApp->getActiveViewer() : nullptr;
  if (!viewer) {
    logGraphicsSmokeMainEvent("internal_actions_no_viewer");
    return;
  }

  viewer->resetSceneViewer();
  app.processEvents();

  viewer->zoomIn();
  app.processEvents();

  viewer->zoomOut();
  app.processEvents();

  if (toonzApp->getCurrentFrame()) {
    toonzApp->getCurrentFrame()->setFrame(1);
    app.processEvents();
    toonzApp->getCurrentFrame()->setFrame(0);
    app.processEvents();
  }

  viewer->resetZoom();
  viewer->GLInvalidateAll();
  app.processEvents();

  if (actionName == "internal-editing-context") {
    const char* toolIds[] = {T_Edit,      T_Selection, T_Brush,
                             T_Geometric, T_Skeleton,  T_Hand};
    for (const char* toolId : toolIds) {
      CommandManager::instance()->execute(toolId);
      logGraphicsSmokeMainEvent(std::string("internal_tool_") + toolId);
      viewer->GLInvalidateAll();
      app.processEvents();
    }
  }

  if (actionName == "internal-viewer-input") {
    const struct {
      const char* toolId;
      const char* label;
    } toolGestures[] = {
        {T_Hand, "hand"},
        {T_Selection, "selection"},
    };

    for (const auto& toolGesture : toolGestures) {
      CommandManager::instance()->execute(toolGesture.toolId);
      app.processEvents();
      logGraphicsSmokeMainEvent(std::string("internal_input_tool_") +
                                toolGesture.toolId);

      const QPointF center(viewer->width() * 0.5, viewer->height() * 0.5);
      const QPointF dragTarget =
          center + QPointF(std::max(12, viewer->width() / 12),
                           std::max(8, viewer->height() / 12));

      QMouseEvent press(QEvent::MouseButtonPress, center, Qt::LeftButton,
                        Qt::LeftButton, Qt::NoModifier);
      QApplication::sendEvent(viewer, &press);
      app.processEvents();
      logGraphicsSmokeMainEvent(std::string("internal_input_press_") +
                                toolGesture.label);

      QMouseEvent move(QEvent::MouseMove, dragTarget, Qt::NoButton,
                       Qt::LeftButton, Qt::NoModifier);
      QApplication::sendEvent(viewer, &move);
      app.processEvents();
      logGraphicsSmokeMainEvent(std::string("internal_input_move_") +
                                toolGesture.label);

      QMouseEvent release(QEvent::MouseButtonRelease, dragTarget,
                          Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
      QApplication::sendEvent(viewer, &release);
      app.processEvents();
      logGraphicsSmokeMainEvent(std::string("internal_input_release_") +
                                toolGesture.label);

      viewer->GLInvalidateAll();
      app.processEvents();
    }
  }

  if (actionName == "internal-drawing-gesture") {
    CommandManager::instance()->execute(T_Brush);
    app.processEvents();
    logGraphicsSmokeMainEvent("internal_drawing_tool_T_Brush");

    const std::string beforeSummary = getGraphicsSmokeToolImageSummary();
    logGraphicsSmokeMainEvent("internal_drawing_before " + beforeSummary);

    const QPointF center(viewer->width() * 0.5, viewer->height() * 0.5);
    const QPointF point1 =
        center + QPointF(std::max(16, viewer->width() / 16),
                         std::max(10, viewer->height() / 18));
    const QPointF point2 =
        center + QPointF(std::max(32, viewer->width() / 10),
                         std::max(18, viewer->height() / 12));

    QMouseEvent press(QEvent::MouseButtonPress, center, Qt::LeftButton,
                      Qt::LeftButton, Qt::NoModifier);
    QApplication::sendEvent(viewer, &press);
    app.processEvents();
    logGraphicsSmokeMainEvent("internal_drawing_press");

    QMouseEvent move1(QEvent::MouseMove, point1, Qt::NoButton, Qt::LeftButton,
                      Qt::NoModifier);
    QApplication::sendEvent(viewer, &move1);
    app.processEvents();
    logGraphicsSmokeMainEvent("internal_drawing_move_1");

    QMouseEvent move2(QEvent::MouseMove, point2, Qt::NoButton, Qt::LeftButton,
                      Qt::NoModifier);
    QApplication::sendEvent(viewer, &move2);
    app.processEvents();
    logGraphicsSmokeMainEvent("internal_drawing_move_2");

    QMouseEvent release(QEvent::MouseButtonRelease, point2, Qt::LeftButton,
                        Qt::NoButton, Qt::NoModifier);
    QApplication::sendEvent(viewer, &release);
    app.processEvents();
    logGraphicsSmokeMainEvent("internal_drawing_release");

    viewer->GLInvalidateAll();
    app.processEvents();

    const std::string afterSummary = getGraphicsSmokeToolImageSummary();
    logGraphicsSmokeMainEvent("internal_drawing_after " + afterSummary);
    logGraphicsSmokeMainEvent(std::string("internal_drawing_changed changed=") +
                              (afterSummary != beforeSummary ? "1" : "0"));
  }

  if (actionName == "internal-style-editor") {
    CommandManager::instance()->execute("MI_OpenStyleControl");
    app.processEvents();

    TPaletteHandle* paletteHandle = toonzApp->getCurrentPalette();
    TPalette* palette = paletteHandle ? paletteHandle->getPalette() : nullptr;
    const int styleIndex =
        paletteHandle ? std::max(1, paletteHandle->getStyleIndex()) : -1;
    TColorStyle* originalStyle =
        palette && 0 <= styleIndex && styleIndex < palette->getStyleCount()
            ? palette->getStyle(styleIndex)
            : nullptr;

    if (paletteHandle && palette && originalStyle) {
      TColorStyle* restoredStyle = originalStyle->clone();
      TColorStyle* smokeStyle    = originalStyle->clone();
      smokeStyle->setMainColor(TPixel32(64, 176, 255, 255));

      paletteHandle->setStyleIndex(styleIndex, true);
      palette->setStyle(styleIndex, smokeStyle);
      paletteHandle->notifyColorStyleChanged(false, false);
      logGraphicsSmokeMainEvent("internal_style_editor_changed style=" +
                                std::to_string(styleIndex));
      viewer->GLInvalidateAll();
      app.processEvents();

      palette->setStyle(styleIndex, restoredStyle);
      paletteHandle->notifyColorStyleChanged(false, false);
      logGraphicsSmokeMainEvent("internal_style_editor_restored style=" +
                                std::to_string(styleIndex));
      viewer->GLInvalidateAll();
      app.processEvents();
    } else {
      logGraphicsSmokeMainEvent("internal_style_editor_no_palette");
    }
  }

  if (actionName == "internal-preview-export") {
    const char* previewExportPath =
        std::getenv("OPENTOONZ_GRAPHICS_SMOKE_PREVIEW_EXPORT");
    const int frame   = targetFrame > 0 ? targetFrame - 1
                                        : toonzApp->getCurrentFrame()->getFrame();
    ToonzScene* scene = toonzApp->getCurrentScene()
                            ? toonzApp->getCurrentScene()->getScene()
                            : nullptr;
    const std::vector<bool> oldPreviewColumns =
        enableGraphicsSmokePreviewColumns(scene);

    setGraphicsSmokeFrame(app, targetFrame);
    viewer->enablePreview(SceneViewer::FULL_PREVIEW);
    viewer->regeneratePreviewFrame();
    Previewer* previewer = Previewer::instance(false);
    TRasterP previewRaster;
    for (int attempt = 0; attempt < 100; ++attempt) {
      app.processEvents();
      previewRaster = previewer->getRaster(frame, true);
      if (previewRaster && previewer->isFrameReady(frame)) break;
      QThread::msleep(50);
    }

    if (previewRaster && previewer->isFrameReady(frame)) {
      logGraphicsSmokeMainEvent("internal_preview_frame_ready frame=" +
                                std::to_string(frame + 1));
      logGraphicsSmokeMainEvent("internal_preview_raster " +
                                getGraphicsSmokeRasterSummary(previewRaster));
      if (previewExportPath && *previewExportPath) {
        QImage image = rasterToQImage(previewRaster, true, true).copy();
        std::string exportSource("preview_raster");
        if (!isGraphicsSmokeNonBlankImage(image)) {
          logGraphicsSmokeMainEvent("internal_preview_raster_blank");
          image        = renderGraphicsSmokeSceneFrame(app, frame);
          exportSource = "scene_renderer";
        }
        if (!isGraphicsSmokeNonBlankImage(image)) {
          viewer->GLInvalidateAll();
          app.processEvents();
          app.processEvents();
          image        = viewer->grabFramebuffer();
          exportSource = "viewer_framebuffer";
          if (!isGraphicsSmokeNonBlankImage(image)) {
            const QPixmap widgetGrab = viewer->grab();
            if (!widgetGrab.isNull()) image = widgetGrab.toImage();
            exportSource = "viewer_widget";
          }
        }
        if (!image.isNull() && image.save(previewExportPath, "PNG")) {
          logGraphicsSmokeMainEvent("internal_preview_export_source source=" +
                                    exportSource);
          logGraphicsSmokeMainEvent("internal_preview_export_saved path=" +
                                    std::string(previewExportPath) + " width=" +
                                    std::to_string(image.width()) + " height=" +
                                    std::to_string(image.height()));
        } else {
          logGraphicsSmokeMainEvent("internal_preview_export_failed path=" +
                                    std::string(previewExportPath));
        }
      }
    } else {
      logGraphicsSmokeMainEvent("internal_preview_frame_not_ready frame=" +
                                std::to_string(frame + 1));
    }
    viewer->enablePreview(SceneViewer::NO_PREVIEW);
    restoreGraphicsSmokePreviewColumns(scene, oldPreviewColumns);
  }

  setGraphicsSmokeFrame(app, targetFrame);
  logGraphicsSmokeMainEvent("internal_actions_done");
}

//-----------------------------------------------------------------------------

static void saveGraphicsSmokeInternalScreenshot(QApplication& app) {
  const char* screenshotPath =
      std::getenv("OPENTOONZ_GRAPHICS_SMOKE_INTERNAL_SCREENSHOT");
  if (!screenshotPath || !*screenshotPath) return;

  TApp* toonzApp      = TApp::instance();
  SceneViewer* viewer = toonzApp ? toonzApp->getActiveViewer() : nullptr;
  if (!viewer) {
    logGraphicsSmokeMainEvent("internal_screenshot_no_viewer");
    return;
  }

  QImage image;
  for (int attempt = 0; attempt < 50; ++attempt) {
    viewer->GLInvalidateAll();
    app.processEvents();
    app.processEvents();
    image = viewer->grabFramebuffer();

    if (isGraphicsSmokeNonBlankImage(image)) break;

    const QPixmap widgetGrab = viewer->grab();
    if (!widgetGrab.isNull()) image = widgetGrab.toImage();
    if (isGraphicsSmokeNonBlankImage(image)) break;

    QThread::msleep(200);
  }

  const QString finalPath = QString::fromUtf8(screenshotPath);
  const QString tempPath  = finalPath + ".tmp";
  QFile::remove(tempPath);
  if (image.isNull()) {
    logGraphicsSmokeMainEvent("internal_screenshot_failed reason=null_image");
    return;
  }
  if (!image.save(tempPath, "PNG")) {
    logGraphicsSmokeMainEvent("internal_screenshot_failed reason=save_failed");
    logGraphicsSmokeMainEvent("internal_screenshot_failed");
    return;
  }
  QFile::remove(finalPath);
  if (!QFile::rename(tempPath, finalPath)) {
    QFile::remove(tempPath);
    logGraphicsSmokeMainEvent("internal_screenshot_failed");
    return;
  }

  logGraphicsSmokeMainEvent(
      "internal_screenshot_saved width=" + std::to_string(image.width()) +
      " height=" + std::to_string(image.height()));
}

//-----------------------------------------------------------------------------

static void fatalError(QString msg) {
  DVGui::MsgBoxInPopup(
      CRITICAL,
      msg + "\n" +
          QObject::tr("Installing %1 again could fix the problem.")
              .arg(QString::fromStdString(TEnv::getApplicationFullName())));
  exit(0);
}
//-----------------------------------------------------------------------------

static void lastWarningError(QString msg) {
  DVGui::error(msg);
  // exit(0);
}
//-----------------------------------------------------------------------------

static void toonzRunOutOfContMemHandler(unsigned long size) {
#ifdef _WIN32
  static bool firstTime = true;
  if (firstTime) {
    MessageBox(NULL, (LPCWSTR)L"Run out of contiguous physical memory: please save all and restart Toonz!",
				   (LPCWSTR)L"Warning", MB_OK | MB_SYSTEMMODAL);
    firstTime = false;
  }
#endif
}

//-----------------------------------------------------------------------------

// todo.. da mettere in qualche .h
DV_IMPORT_API void initStdFx();
DV_IMPORT_API void initColorFx();

//-----------------------------------------------------------------------------

//! Inizializzaza l'Environment di Toonz
/*! In particolare imposta la projectRoot e
    la stuffDir, controlla se la directory di outputs esiste (e provvede a
    crearla in caso contrario) verifica inoltre che stuffDir esista.
*/
static void initToonzEnv(QHash<QString, QString>& argPathValues) {
  StudioPalette::enable(true);
  TEnv::setRootVarName(rootVarName);
  TEnv::setSystemVarPrefix(systemVarPrefix);

  QHash<QString, QString>::const_iterator i = argPathValues.constBegin();
  while (i != argPathValues.constEnd()) {
    if (!TEnv::setArgPathValue(i.key().toStdString(), i.value().toStdString()))
      DVGui::error(
          QObject::tr("The qualifier %1 is not a valid key name. Skipping.")
              .arg(i.key()));
    ++i;
  }

  QCoreApplication::setOrganizationName("OpenToonz");
  QCoreApplication::setOrganizationDomain("");
  QCoreApplication::setApplicationName(
      QString::fromStdString(TEnv::getApplicationName()));

  /*-- TOONZROOTのPathの確認 --*/
  // controllo se la xxxroot e' definita e corrisponde ad un folder esistente

  /*-- ENGLISH: Confirm TOONZROOT Path
        Check if the xxxroot is defined and corresponds to an existing folder
  --*/

  TFilePath stuffDir = TEnv::getStuffDir();
  if (stuffDir == TFilePath())
    fatalError("Undefined or empty: \"" + toQString(TEnv::getRootVarPath()) +
               "\"");
  else if (!TFileStatus(stuffDir).isDirectory())
    fatalError("Folder \"" + toQString(stuffDir) +
               "\" not found or not readable");

  Tiio::defineStd();
  initImageIo();
  initSoundIo();
  initStdFx();
  initColorFx();

  // TPluginManager::instance()->loadStandardPlugins();

  TFilePath library = ToonzFolder::getLibraryFolder();

  TRasterImagePatternStrokeStyle::setRootDir(library);
  TVectorImagePatternStrokeStyle::setRootDir(library);
  TVectorBrushStyle::setRootDir(library);

  CustomStyleManager::setRootPath(library);

  // sembra indispensabile nella lettura dei .tab 2.2:
  TPalette::setRootDir(library);
  TImageStyle::setLibraryDir(library);

  // TProjectManager::instance()->enableTabMode(true);

  TProjectManager* projectManager = TProjectManager::instance();

  /*--
   * TOONZPROJECTSのパスセットを取得する。（TOONZPROJECTSはセミコロンで区切って複数設定可能）
   * --*/
  TFilePathSet projectsRoots = ToonzFolder::getProjectsFolders();
  TFilePathSet::iterator it;
  for (it = projectsRoots.begin(); it != projectsRoots.end(); ++it)
    projectManager->addProjectsRoot(*it);

  /*-- もしまだ無ければ、TOONZROOT/sandboxにsandboxプロジェクトを作る --*/
  projectManager->createSandboxIfNeeded();

  /*
TProjectP project = projectManager->getCurrentProject();
Non dovrebbe servire per Tab:
project->setFolder(TProject::Drawings, TFilePath("$scenepath"));
project->setFolder(TProject::Extras, TFilePath("$scenepath"));
project->setUseScenePath(TProject::Drawings, false);
project->setUseScenePath(TProject::Extras, false);
*/
  // Imposto la rootDir per ImageCache

  /*-- TOONZCACHEROOTの設定  --*/
  TFilePath cacheDir = ToonzFolder::getCacheRootFolder();
  if (cacheDir.isEmpty()) cacheDir = TEnv::getStuffDir() + "cache";
  TImageCache::instance()->setRootDir(cacheDir);
}

//-----------------------------------------------------------------------------

static void script_output(int type, const QString& value) {
  if (type == ScriptEngine::ExecutionError ||
      type == ScriptEngine::SyntaxError ||
      type == ScriptEngine::UndefinedEvaluationResult ||
      type == ScriptEngine::Warning)
    std::cerr << value.toStdString() << std::endl;
  else
    std::cout << value.toStdString() << std::endl;
}

//-----------------------------------------------------------------------------

int main(int argc, char* argv[]) {
  logGraphicsSmokeMainEvent("entry");
#ifdef Q_OS_WIN
  // Enable standard input/output on Windows Platform for debug
  if (::AttachConsole(ATTACH_PARENT_PROCESS)) {
    freopen("CON", "r", stdin);
    freopen("CON", "w", stdout);
    freopen("CON", "w", stderr);
    atexit([]() { ::FreeConsole(); });
  }
#endif

  // Install signal handlers to catch crashes
  CrashHandler::install();
  logGraphicsSmokeMainEvent("after_crash_handler");

  // parsing arguments and qualifiers
  TFilePath loadFilePath;
  QString argumentLayoutFileName = "";
  QHash<QString, QString> argumentPathValues;
  if (argc > 1) {
    TCli::Usage usage(argv[0]);
    TCli::UsageLine usageLine;
    TCli::FilePathArgument loadFileArg(
        "filePath", "Source scene file to open or script file to run");
    TCli::StringQualifier layoutFileQual(
        "-layout filename",
        "Custom layout file to be used, it should be saved in "
        "$TOONZPROFILES\\layouts\\personal\\[CurrentLayoutName].[UserName]\\. "
        "layouts.txt is used by default.");
    usageLine = usageLine + layoutFileQual;

    // system path qualifiers
    std::map<QString, std::unique_ptr<TCli::QualifierT<TFilePath>>>
        systemPathQualMap;
    QString qualKey  = QString("%1ROOT").arg(systemVarPrefix);
    QString qualName = QString("-%1 folderpath").arg(qualKey);
    QString qualHelp =
        QString(
            "%1 path. It will automatically set other system paths to %1 "
            "unless individually specified with other qualifiers.")
            .arg(qualKey);
    systemPathQualMap[qualKey].reset(new TCli::QualifierT<TFilePath>(
        qualName.toStdString(), qualHelp.toStdString()));
    usageLine = usageLine + *systemPathQualMap[qualKey];

    const std::map<std::string, std::string>& spm = TEnv::getSystemPathMap();
    for (auto itr = spm.begin(); itr != spm.end(); ++itr) {
      qualKey = QString("%1%2")
                    .arg(systemVarPrefix)
                    .arg(QString::fromStdString((*itr).first));
      qualName = QString("-%1 folderpath").arg(qualKey);
      qualHelp = QString("%1 path.").arg(qualKey);
      systemPathQualMap[qualKey].reset(new TCli::QualifierT<TFilePath>(
          qualName.toStdString(), qualHelp.toStdString()));
      usageLine = usageLine + *systemPathQualMap[qualKey];
    }
    usage.add(usageLine);
    usage.add(usageLine + loadFileArg);

    if (!usage.parse(argc, argv)) exit(1);

    loadFilePath = loadFileArg.getValue();
    if (layoutFileQual.isSelected())
      argumentLayoutFileName =
          QString::fromStdString(layoutFileQual.getValue());
    for (auto q_itr = systemPathQualMap.begin();
         q_itr != systemPathQualMap.end(); ++q_itr) {
      if (q_itr->second->isSelected())
        argumentPathValues.insert(q_itr->first,
                                  q_itr->second->getValue().getQString());
    }

    argc = 1;
  }
  logGraphicsSmokeMainEvent("after_arguments");

  // Enables high-DPI scaling. This attribute must be set before QApplication is
  // constructed. Available from Qt 5.6.
  QApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
  logGraphicsSmokeMainEvent("before_qapplication");

  QApplication a(argc, argv);
  logGraphicsSmokeMainEvent("after_qapplication");

#ifdef MACOSX
  // This workaround is to avoid missing left button problem on Qt5.6.0.
  // To invalidate m_rightButtonClicked in Qt/qnsview.mm, sending
  // NSLeftButtonDown event before NSLeftMouseDragged event propagated to
  // QApplication. See more details in ../mousedragfilter/mousedragfilter.mm.

#include "mousedragfilter.h"

  class OSXMouseDragFilter final : public QAbstractNativeEventFilter {
    bool leftButtonPressed = false;

  public:
    bool nativeEventFilter(const QByteArray& eventType, void* message,
                           long*) Q_DECL_OVERRIDE {
      if (IsLeftMouseDown(message)) {
        leftButtonPressed = true;
      }
      if (IsLeftMouseUp(message)) {
        leftButtonPressed = false;
      }

      if (eventType == "mac_generic_NSEvent") {
        if (IsLeftMouseDragged(message) && !leftButtonPressed) {
          std::cout << "force mouse press event" << std::endl;
          SendLeftMousePressEvent();
          return true;
        }
      }
      return false;
    }
  };

  a.installNativeEventFilter(new OSXMouseDragFilter);
  logGraphicsSmokeMainEvent("after_native_event_filter");
#endif

#ifdef Q_OS_WIN
  //	Since currently OpenToonz does not work with OpenGL of software or
  // angle,	force Qt to use desktop OpenGL
  // FIXME: This options should be called before constructing the application.
  // Thus, ANGLE seems to be enabled as of now.
  a.setAttribute(Qt::AA_UseDesktopOpenGL, true);
#endif

  // Some Qt objects are destroyed badly without a living qApp. So, we must
  // enforce a way to either
  // postpone the application destruction until the very end, OR ensure that
  // sensible objects are
  // destroyed before.

  // Using a static QApplication only worked on Windows, and in any case C++
  // respects the statics destruction
  // order ONLY within the same library. On MAC, it made the app crash on exit
  // o_o. So, nope.

  std::unique_ptr<QObject> mainScope(new QObject(
      &a));  // A QObject destroyed before the qApp is therefore explicitly
  mainScope->setObjectName("mainScope");  // provided. It can be accessed by
                                          // looking in the qApp's children.
  logGraphicsSmokeMainEvent("after_main_scope");

#ifdef _WIN32
#ifndef x64
  // Store the floating point control word. It will be re-set before Toonz
  // initialization
  // has ended.
  unsigned int fpWord = 0;
  _controlfp_s(&fpWord, 0, 0);
#endif
#endif

#ifdef _WIN32
  // At least on windows, Qt's 4.5.2 native windows feature tend to create
  // weird flickering effects when dragging panel separators.
  a.setAttribute(Qt::AA_DontCreateNativeWidgetSiblings);
#endif

  // Enable to render smooth icons on high dpi monitors
  a.setAttribute(Qt::AA_UseHighDpiPixmaps);
#if defined(_WIN32)
  // Compress tablet events with application attributes instead of implementing
  // the delay-timer by ourselves
  a.setAttribute(Qt::AA_CompressHighFrequencyEvents);
  a.setAttribute(Qt::AA_CompressTabletEvents);
#endif

#ifdef _WIN32
  // BUG_WORKAROUND: #20230627
  // This attribute is set to make menubar icon to be always (16 x devPixRatio).
  // Without this attribute the menu bar icon size becomes the same as tool bar
  // when Windows scale is in 125%. Currently hiding the menu bar icon is done
  // by setting transparent pixmap only in menu bar icon size. So the size must
  // be different between for menu bar and for tool bar.
  a.setAttribute(Qt::AA_Use96Dpi);
#endif

  // Set the app's locale for numeric stuff to standard C. This is important for
  // atof() and similar
  // calls that are locale-dependent.
  setlocale(LC_NUMERIC, "C");

// Set current directory to the bundle/application path - this is needed to have
// correct relative paths
#ifdef MACOSX
  {
    logGraphicsSmokeMainEvent("before_set_current");
    QDir appDir(QApplication::applicationDirPath());
    appDir.cdUp(), appDir.cdUp(), appDir.cdUp();

    bool ret = QDir::setCurrent(appDir.absolutePath());
    assert(ret);
    logGraphicsSmokeMainEvent("after_set_current");
  }
#endif

  // Set show icons in menus flag (use iconVisibleInMenu to disable selectively)
  QApplication::instance()->setAttribute(Qt::AA_DontShowIconsInMenus, false);

  TEnv::setApplicationFileName(argv[0]);
  logGraphicsSmokeMainEvent("after_set_application_file_name");

  // splash screen (override with local file if present)
  QString exeDir          = QCoreApplication::applicationDirPath();
  QString localSplashPath = QDir(exeDir).filePath("splash.svg");

  QPixmap splashPixmap;

  if (QFileInfo(localSplashPath).exists() &&
      QFileInfo(localSplashPath).isFile()) {
    splashPixmap = QIcon(localSplashPath).pixmap(QSize(610, 344));
    if (splashPixmap.isNull()) {
      // fallback if loading fails
      splashPixmap = QIcon(":Resources/splash.svg").pixmap(QSize(610, 344));
    }
  } else {
    splashPixmap = QIcon(":Resources/splash.svg").pixmap(QSize(610, 344));
  }
  logGraphicsSmokeMainEvent("after_splash_pixmap");
#ifdef _WIN32
  QFont font("Segoe UI", -1);
#else
  QFont font("Helvetica", -1);
#endif
  font.setPixelSize(13);
  font.setWeight(50);
  a.setFont(font);

  QString offsetStr("\n\n\n\n\n\n\n\n");

  TSystem::hasMainLoop(true);

  TMessageRepository::instance();
  logGraphicsSmokeMainEvent("after_message_repository");

  bool isRunScript = (loadFilePath.getType() == "toonzscript");

  logGraphicsSmokeMainEvent("before_splash_show");
  QSplashScreen splash(splashPixmap);
  if (!isRunScript) splash.show();
  a.processEvents();
  logGraphicsSmokeMainEvent("after_splash_show");

  splash.showMessage(offsetStr + "Initializing OpenGL surface...",
                     Qt::AlignCenter, Qt::white);
  a.processEvents();

  // OpenGL
  QSurfaceFormat fmt = QSurfaceFormat::defaultFormat();
  fmt.setAlphaBufferSize(8);
  fmt.setStencilBufferSize(8);
  QSurfaceFormat::setDefaultFormat(fmt);

#ifndef __HAIKU__
  logGraphicsSmokeMainEvent("before_glut_init");
  glutInit(&argc, argv);
  logGraphicsSmokeMainEvent("after_glut_init");
#endif

  splash.showMessage(offsetStr + "Initializing Toonz environment ...",
                     Qt::AlignCenter, Qt::white);
  a.processEvents();

  // Install run out of contiguous memory callback
  TBigMemoryManager::instance()->setRunOutOfContiguousMemoryHandler(
      &toonzRunOutOfContMemHandler);
  logGraphicsSmokeMainEvent("after_big_memory_handler");

  // Setup third party
  logGraphicsSmokeMainEvent("before_third_party_initialize");
  ThirdParty::initialize();
  logGraphicsSmokeMainEvent("after_third_party_initialize");

  // Toonz environment
  logGraphicsSmokeMainEvent("before_init_toonz_env");
  initToonzEnv(argumentPathValues);
  logGraphicsSmokeMainEvent("after_init_toonz_env");

  // prepare for 30bit display
  logGraphicsSmokeMainEvent("before_preferences_30bit");
  if (Preferences::instance()->is30bitDisplayEnabled()) {
    QSurfaceFormat sFmt = QSurfaceFormat::defaultFormat();
    sFmt.setRedBufferSize(10);
    sFmt.setGreenBufferSize(10);
    sFmt.setBlueBufferSize(10);
    sFmt.setAlphaBufferSize(2);
    QSurfaceFormat::setDefaultFormat(sFmt);
  }
  logGraphicsSmokeMainEvent("after_preferences_30bit");

  // Initialize thread components
  logGraphicsSmokeMainEvent("before_thread_init");
  TThread::init();
  logGraphicsSmokeMainEvent("after_thread_init");

  logGraphicsSmokeMainEvent("before_project_manager");
  TProjectManager* projectManager = TProjectManager::instance();
  logGraphicsSmokeMainEvent("after_project_manager");
  if (Preferences::instance()->isSVNEnabled()) {
    // Read Version Control repositories and add it to project manager as
    // "special" svn project root
    VersionControl::instance()->init();
    QList<SVNRepository> repositories =
        VersionControl::instance()->getRepositories();
    int count = repositories.size();
    for (int i = 0; i < count; i++) {
      SVNRepository r = repositories.at(i);

      TFilePath localPath(r.m_localPath.toStdWString());
      if (!TFileStatus(localPath).doesExist()) {
        try {
          TSystem::mkDir(localPath);
        } catch (TException& e) {
          fatalError(QString::fromStdWString(e.getMessage()));
        }
      }
      projectManager->addSVNProjectsRoot(localPath);
    }
  }

#if defined(MACOSX) && defined(__LP64__)

  // Load the shared memory settings
  int shmmax = Preferences::instance()->getShmMax();
  int shmseg = Preferences::instance()->getShmSeg();
  int shmall = Preferences::instance()->getShmAll();
  int shmmni = Preferences::instance()->getShmMni();

  if (shmall <
      0)  // Make sure that at least 100 MB of shared memory are available
    shmall = (tipc::shm_maxSharedPages() < (100 << 8)) ? (100 << 8) : -1;

  tipc::shm_set(shmmax, shmseg, shmall, shmmni);

#endif

  // DVDirModel must be instantiated after Version Control initialization...
  logGraphicsSmokeMainEvent("before_folder_listener");
  FolderListenerManager::instance()->addListener(DvDirModel::instance());
  logGraphicsSmokeMainEvent("after_folder_listener");

  splash.showMessage(offsetStr + "Loading Translator ...", Qt::AlignCenter,
                     Qt::white);
  a.processEvents();

  // Carico la traduzione contenuta in toonz.qm (se ï¿½ presente)
  QString languagePathString =
      QString::fromStdString(::to_string(TEnv::getConfigDir() + "loc"));
#ifndef WIN32
  // the merge of menu on osx can cause problems with different languages with
  // the Preferences menu
  // qt_mac_set_menubar_merge(false);
  languagePathString += "/" + Preferences::instance()->getCurrentLanguage();
#else
  languagePathString += "\\" + Preferences::instance()->getCurrentLanguage();
#endif
  QTranslator translator;
  translator.load("toonz", languagePathString);

  // La installo
  a.installTranslator(&translator);

  // Carico la traduzione contenuta in toonzqt.qm (se e' presente)
  QTranslator translator2;
  translator2.load("toonzqt", languagePathString);
  a.installTranslator(&translator2);

  // Carico la traduzione contenuta in tnzcore.qm (se e' presente)
  QTranslator tnzcoreTranslator;
  tnzcoreTranslator.load("tnzcore", languagePathString);
  qApp->installTranslator(&tnzcoreTranslator);

  // Carico la traduzione contenuta in toonzlib.qm (se e' presente)
  QTranslator toonzlibTranslator;
  toonzlibTranslator.load("toonzlib", languagePathString);
  qApp->installTranslator(&toonzlibTranslator);

  // Carico la traduzione contenuta in colorfx.qm (se e' presente)
  QTranslator colorfxTranslator;
  colorfxTranslator.load("colorfx", languagePathString);
  qApp->installTranslator(&colorfxTranslator);

  // Carico la traduzione contenuta in tools.qm
  QTranslator toolTranslator;
  toolTranslator.load("tnztools", languagePathString);
  qApp->installTranslator(&toolTranslator);

  // load translation for file writers properties
  QTranslator imageTranslator;
  imageTranslator.load("image", languagePathString);
  qApp->installTranslator(&imageTranslator);

  QTranslator qtTranslator;
  qtTranslator.load("qt_" + QLocale::system().name(),
                    QLibraryInfo::location(QLibraryInfo::TranslationsPath));
  a.installTranslator(&qtTranslator);
  logGraphicsSmokeMainEvent("after_translators");

  // Aggiorno la traduzione delle properties di tutti i tools
  TTool::updateToolsPropertiesTranslation();
  // Apply translation to file writers properties
  Tiio::updateFileWritersPropertiesTranslation();
  logGraphicsSmokeMainEvent("after_tool_translations");

  // Force to have left-to-right layout direction in any language environment.
  // This function has to be called after installTranslator().
  a.setLayoutDirection(Qt::LeftToRight);

  splash.showMessage(offsetStr + "Loading styles ...", Qt::AlignCenter,
                     Qt::white);
  a.processEvents();

  // stile
  QApplication::setStyle("windows");
  logGraphicsSmokeMainEvent("after_set_style");

  IconGenerator::setFilmstripIconSize(Preferences::instance()->getIconSize());
  logGraphicsSmokeMainEvent("after_icon_size");

  splash.showMessage(offsetStr + "Loading shaders ...", Qt::AlignCenter,
                     Qt::white);
  a.processEvents();

  logGraphicsSmokeMainEvent("before_load_shader_interfaces");
  loadShaderInterfaces(ToonzFolder::getLibraryFolder() + TFilePath("shaders"));
  logGraphicsSmokeMainEvent("after_load_shader_interfaces");

  splash.showMessage(offsetStr + "Initializing OpenToonz ...", Qt::AlignCenter,
                     Qt::white);
  a.processEvents();

  // Initialize ThemeManager before TApp
  auto& themeManager = ThemeManager::getInstance();
  logGraphicsSmokeMainEvent("before_theme_initialize");
  themeManager.initialize();
  logGraphicsSmokeMainEvent("after_theme_initialize");

  TTool::setApplication(TApp::instance());
  logGraphicsSmokeMainEvent("before_tapp_init");
  TApp::instance()->init();
  logGraphicsSmokeMainEvent("after_tapp_init");

  splash.showMessage(offsetStr + "Loading Plugins...", Qt::AlignCenter,
                     Qt::white);
  a.processEvents();
  /* poll the thread ends:
   絶対に必要なわけではないが PluginLoader は中で setup
   ハンドラが常に固有のスレッドで呼ばれるよう main thread queue の blocking
   をしているので
   processEvents を行う必要がある
*/
  logGraphicsSmokeMainEvent("before_plugin_loader");
  while (!PluginLoader::load_entries("")) {
    a.processEvents();
  }
  logGraphicsSmokeMainEvent("after_plugin_loader");

  splash.showMessage(offsetStr + "Creating main window ...", Qt::AlignCenter,
                     Qt::white);
  a.processEvents();
  logGraphicsSmokeMainEvent("before_main_window");

  /*-- Layoutファイル名をMainWindowのctorに渡す --*/
  MainWindow w(argumentLayoutFileName);
  logGraphicsSmokeMainEvent("after_main_window");
  CrashHandler::attachParentWindow(&w);
  CrashHandler::reportProjectInfo(true);

  if (isRunScript) {
    // load script
    if (TFileStatus(loadFilePath).doesExist()) {
      // find project for this script file
      TProjectManager* pm = TProjectManager::instance();
      auto sceneProject   = pm->loadSceneProject(loadFilePath);
      TFilePath oldProjectPath;
      if (!sceneProject) {
        std::cerr << QObject::tr(
                         "It is not possible to load the scene %1 because it "
                         "does not "
                         "belong to any project.")
                         .arg(loadFilePath.getQString())
                         .toStdString()
                  << std::endl;
        return 1;
      }
      if (sceneProject && !sceneProject->isCurrent()) {
        oldProjectPath = pm->getCurrentProjectPath();
        pm->setCurrentProjectPath(sceneProject->getProjectPath());
      }
      ScriptEngine engine;
      QObject::connect(&engine, &ScriptEngine::output, script_output);
      QString s = QString::fromStdWString(loadFilePath.getWideString())
                      .replace("\\", "\\\\")
                      .replace("\"", "\\\"");
      QString cmd = QString("run(\"%1\")").arg(s);
      engine.evaluate(cmd);
      engine.wait();
      if (!oldProjectPath.isEmpty()) pm->setCurrentProjectPath(oldProjectPath);
      return 1;
    } else {
      std::cerr << QObject::tr("Script file %1 does not exists.")
                       .arg(loadFilePath.getQString())
                       .toStdString()
                << std::endl;
      return 1;
    }
  }

#ifdef _WIN32
  // http://doc.qt.io/qt-5/windows-issues.html#fullscreen-opengl-based-windows
  if (w.windowHandle())
    QWindowsWindowFunctions::setHasBorderInFullScreen(w.windowHandle(), true);
#endif

  // Qt have started to support Windows Ink from 5.12.
  // Unlike WinTab API used in Qt 5.9 the tablet behaviors are different and
  // are (at least, for OT) problematic. The customized Qt5.15.2 are made with
  // cherry-picking the WinTab feature to be officially introduced from 6.0.
  // See https://github.com/shun-iwasawa/qt5/releases/tag/v5.15.2_wintab for
  // details. The following feature can only be used with the customized Qt,
  // with WITH_WINTAB build option, and in Windows-x64 build.

#ifdef WITH_WINTAB
  bool useQtNativeWinInk = Preferences::instance()->isQtNativeWinInkEnabled();
  QWindowsWindowFunctions::setWinTabEnabled(!useQtNativeWinInk);
#endif

  splash.showMessage(offsetStr + "Loading style sheet ...", Qt::AlignCenter,
                     Qt::white);
  a.processEvents();

  // Carico lo styleSheet
  QString currentStyle = Preferences::instance()->getCurrentStyleSheet();
  a.setStyleSheet(currentStyle);

  // Parse inital stylesheet in ThemeManager
  themeManager.parseCustomPropertiesFromStylesheet(currentStyle);

  // w.setWindowTitle(QString::fromStdString(TEnv::getApplicationFullName()));
  w.changeWindowTitle();
  if (TEnv::getIsPortable()) {
    splash.showMessage(offsetStr + "Starting OpenToonz Portable ...",
                       Qt::AlignCenter, Qt::white);
  } else {
    splash.showMessage(offsetStr + "Starting main window ...", Qt::AlignCenter,
                       Qt::white);
  }
  a.processEvents();

  TFilePath fp = ToonzFolder::getModuleFile("mainwindow.ini");
  QSettings settings(toQString(fp), QSettings::IniFormat);
  if (settings.contains("MainWindowGeometry"))
    w.restoreGeometry(settings.value("MainWindowGeometry").toByteArray());
  else  // maximize window on the first launch
    w.setWindowState(w.windowState() | Qt::WindowMaximized);

  ExpressionReferenceManager::instance()->init();

#ifndef MACOSX
  // Workaround for the maximized window case: Qt delivers two resize events,
  // one in the normal geometry, before
  // maximizing (why!?), the second afterwards - all inside the following show()
  // call. This makes troublesome for
  // the docking system to correctly restore the saved geometry. Fortunately,
  // MainWindow::showEvent(..) gets called
  // just between the two, so we can disable the currentRoom layout right before
  // showing and re-enable it after
  // the normal resize has happened.
  if (w.isMaximized()) w.getCurrentRoom()->layout()->setEnabled(false);
#endif

  QRect splashGeometry = splash.geometry();
  splash.finish(&w);

  a.setQuitOnLastWindowClosed(false);
  // a.connect(&a, SIGNAL(lastWindowClosed()), &a, SLOT(quit()));
  if (Preferences::instance()->isLatestVersionCheckEnabled())
    w.checkForUpdates();

  w.show();
  logGraphicsSmokeMainEvent("after_show");

  // Show floating panels only after the main window has been shown
  w.startupFloatingPanels();
  logGraphicsSmokeMainEvent("after_startup_floating_panels");

  CommandManager::instance()->execute(T_Hand);
  logGraphicsSmokeMainEvent("after_hand_tool");
  if (!loadFilePath.isEmpty()) {
    splash.showMessage(
        QString("Loading file '") + loadFilePath.getQString() + "'...",
        Qt::AlignCenter, Qt::white);
    if (TFileStatus(loadFilePath).doesExist()) {
      IoCmd::loadScene(loadFilePath);
      logGraphicsSmokeMainEvent("after_load_scene");
      setGraphicsSmokeFrame(a, getGraphicsSmokeFrame());
      runGraphicsSmokeInternalActions(a);
      QTimer::singleShot(1000,
                         [&a]() { saveGraphicsSmokeInternalScreenshot(a); });
    }
  }

  QFont* myFont;
  QString fontName  = Preferences::instance()->getInterfaceFont();
  QString fontStyle = Preferences::instance()->getInterfaceFontStyle();

  TFontManager* fontMgr = TFontManager::instance();
  std::vector<std::wstring> typefaces;
  bool isBold = false, isItalic = false, hasKerning = false;
  try {
    fontMgr->loadFontNames();
    fontMgr->setFamily(fontName.toStdWString());
    fontMgr->getAllTypefaces(typefaces);
    isBold     = fontMgr->isBold(fontName, fontStyle);
    isItalic   = fontMgr->isItalic(fontName, fontStyle);
    hasKerning = fontMgr->hasKerning();
  } catch (TFontCreationError&) {
    // Do nothing. A default font should load
  }

  myFont = new QFont(fontName);
  myFont->setPixelSize(EnvSoftwareCurrentFontSize);
  myFont->setBold(isBold);
  myFont->setItalic(isItalic);
  myFont->setKerning(hasKerning);

  a.setFont(*myFont);

  QAction* action = CommandManager::instance()->getAction("MI_OpenTMessage");
  if (action)
    QObject::connect(TMessageRepository::instance(),
                     SIGNAL(openMessageCenter()), action, SLOT(trigger()));

  QObject::connect(TUndoManager::manager(), SIGNAL(somethingChanged()),
                   TApp::instance()->getCurrentScene(), SLOT(setDirtyFlag()));

#ifdef _WIN32
#ifndef x64
  // On 32-bit architecture, there could be cases in which initialization could
  // alter the
  // FPU floating point control word. I've seen this happen when loading some
  // AVI coded (VFAPI),
  // where 80-bit internal precision was used instead of the standard 64-bit
  // (much faster and
  // sufficient - especially considering that x86 truncates to 64-bit
  // representation anyway).
  // IN ANY CASE, revert to the original control word.
  // In the x64 case these precision changes simply should not take place up to
  // _controlfp_s
  // documentation.
  _controlfp_s(0, fpWord, -1);
#endif
#endif

#ifdef _WIN32
  if (Preferences::instance()->isWinInkEnabled()) {
    KisTabletSupportWin8* penFilter = new KisTabletSupportWin8();
    if (penFilter->init()) {
      a.installNativeEventFilter(penFilter);
    } else {
      delete penFilter;
    }
  }
#endif

  a.installEventFilter(TApp::instance());

  int ret = a.exec();

  TUndoManager::manager()->reset();
  PreviewFxManager::instance()->reset();

  return ret;
}
