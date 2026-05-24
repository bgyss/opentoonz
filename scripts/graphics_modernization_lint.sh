#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-toonz/sources}"
SCENEVIEWER="$ROOT/toonz/sceneviewer.cpp"
VIEWERDRAW="$ROOT/toonz/viewerdraw.cpp"
PLANEVIEWER="$ROOT/toonzqt/planeviewer.cpp"
STYLEEDITOR="$ROOT/toonzqt/styleeditor.cpp"
STYLEEDITOR_H="$ROOT/include/toonzqt/styleeditor.h"
EDITTOOL="$ROOT/tnztools/edittool.cpp"
EDITTOOLGADGETS="$ROOT/tnztools/edittoolgadgets.cpp"
SKELETONTOOL="$ROOT/tnztools/skeletontool.cpp"
WORKFLOW=".github/workflows/workflow_macos.yml"

if ! command -v rg >/dev/null 2>&1; then
  echo "graphics-modernization-lint: rg is required" >&2
  exit 1
fi

if [[ ! -d "$ROOT" ]]; then
  echo "graphics-modernization-lint: source root not found: $ROOT" >&2
  exit 1
fi

if [[ ! -f "$SCENEVIEWER" ]]; then
  echo "graphics-modernization-lint: SceneViewer source not found: $SCENEVIEWER" >&2
  exit 1
fi

for source in "$VIEWERDRAW" "$PLANEVIEWER" "$STYLEEDITOR" "$STYLEEDITOR_H" \
  "$EDITTOOL" "$EDITTOOLGADGETS" "$SKELETONTOOL"; do
  if [[ ! -f "$source" ]]; then
    echo "graphics-modernization-lint: source not found: $source" >&2
    exit 1
  fi
done

fail=0

require_absent() {
  local label="$1"
  local pattern="$2"
  shift 2

  if rg -n "$@" -e "$pattern" "$ROOT" >/tmp/opentoonz-graphics-lint-rg.$$ 2>/dev/null; then
    echo "graphics-modernization-lint: unexpected $label markers:" >&2
    cat /tmp/opentoonz-graphics-lint-rg.$$ >&2
    fail=1
  fi
  rm -f /tmp/opentoonz-graphics-lint-rg.$$
}

require_absent_file() {
  local label="$1"
  local pattern="$2"
  local file="$3"

  if rg -n -e "$pattern" "$file" >/tmp/opentoonz-graphics-lint-rg.$$ 2>/dev/null; then
    echo "graphics-modernization-lint: unexpected $label markers in $file:" >&2
    cat /tmp/opentoonz-graphics-lint-rg.$$ >&2
    fail=1
  fi
  rm -f /tmp/opentoonz-graphics-lint-rg.$$
}

require_present() {
  local label="$1"
  local pattern="$2"
  local file="$3"

  if ! rg -n -e "$pattern" "$file" >/dev/null 2>&1; then
    echo "graphics-modernization-lint: missing $label in $file" >&2
    fail=1
  fi
}

CODE_GLOBS=(
  --glob '*.c'
  --glob '*.cc'
  --glob '*.cpp'
  --glob '*.cxx'
  --glob '*.h'
  --glob '*.hh'
  --glob '*.hpp'
  --glob '*.m'
  --glob '*.mm'
)

require_absent "Qt QGL" 'QGL[A-Za-z0-9_]*|QGLWidget::convertToGLFormat' "${CODE_GLOBS[@]}"
require_absent "glDrawPixels" 'glDrawPixels' "${CODE_GLOBS[@]}"

require_present "SceneViewer scoped picking guard" \
  'ScopedBoolSetter pickingGuard\(m_isPicking, true\)' "$SCENEVIEWER"
require_present "SceneViewer Metal pick guard" \
  'TGraphics::requestedBackendType\(\) == TGraphics::BackendType::Metal' \
  "$SCENEVIEWER"
require_present "SceneViewer Metal frame smoke diagnostics" \
  'OPENTOONZ_GRAPHICS_METAL_FRAME_DIAGNOSTICS' "$SCENEVIEWER"
require_present "PlaneViewer checkerboard draw-list presentation" \
  'TGraphics::makeCheckerboardBackgroundDrawList' "$PLANEVIEWER"
require_present "PlaneViewer raster draw-list presentation" \
  'TGraphics::makeRasterPresentationDrawList' "$PLANEVIEWER"
require_present "Style Editor color wheel QWidget surface" \
  'class DVAPI HexagonalColorWheel final : public QWidget' "$STYLEEDITOR_H"
require_absent_file "Style Editor direct OpenGL drawing" \
  'QOpenGL|glBegin|glEnd|glMatrixMode|glOrtho|glClear|glDraw' \
  "$STYLEEDITOR"
require_present "ViewerDraw camera mask draw-list overlay" \
  'void ViewerDraw::drawCameraMask\(SceneViewer \*viewer\)' "$VIEWERDRAW"
require_present "ViewerDraw camera mask draw-list storage" \
  'TGraphics::DrawList2D drawList' "$VIEWERDRAW"
require_present "ViewerDraw color card draw-list overlay" \
  'void ViewerDraw::drawColorcard\(UCHAR channel\)' "$VIEWERDRAW"
require_present "ViewerDraw color card draw-list fill" \
  'drawList\.addColorRect' "$VIEWERDRAW"
require_present "Edit Tool main handle CPU picking" \
  'int EditTool::pickMainHandleCpu\(const TPointD &pos\)' "$EDITTOOL"
require_present "Edit Tool FX gadget CPU hover picking" \
  'm_fxGadgetController->pickCpu\(e\.m_pos\)' "$EDITTOOL"
require_present "FX gadget controller CPU picking" \
  'int FxGadgetController::pickCpu\(const TPointD &viewerPos\)' \
  "$EDITTOOLGADGETS"
require_present "Skeleton Tool CPU picking" \
  'int SkeletonTool::pickCpu\(const TPointD& viewerPos\)' "$SKELETONTOOL"
require_present "Skeleton Tool OpenGL selection compatibility gate" \
  'bool canUseOpenGLSelectionPicking\(TToolViewer\* viewer\)' "$SKELETONTOOL"
require_present "Skeleton Tool Metal-requested selection block" \
  'TGraphics::requestedBackendType\(\) != TGraphics::BackendType::Metal' \
  "$SKELETONTOOL"
require_present "Skeleton Tool guarded legacy pick fallback" \
  'if \(selectedDevice < 0 && useGlSelection\) selectedDevice = pick\(e\.m_pos\)' \
  "$SKELETONTOOL"

if [[ -f "$WORKFLOW" ]]; then
  require_present "Metal probe image verifier in macOS workflow" \
    'scripts/verify_metal_probe_images\.sh' "$WORKFLOW"
  require_present "offscreen/style probe verifier in macOS workflow" \
    'scripts/verify_macos_offscreen_style_probes\.sh' "$WORKFLOW"
  require_present "preview/export probe verifier in macOS workflow" \
    'scripts/verify_macos_preview_export_probe\.sh' "$WORKFLOW"
  require_present "OpenGL selection compatibility verifier in macOS workflow" \
    'scripts/verify_opengl_selection_compatibility\.sh' "$WORKFLOW"
  require_present "bundled Qt runtime verifier in macOS workflow" \
    'scripts/macos/verify-bundled-qt-runtime\.sh' "$WORKFLOW"
  require_present "direct Metal packaged app smoke in macOS workflow" \
    'OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=1' "$WORKFLOW"
  require_present "direct Metal smoke artifact verifier in macOS workflow" \
    '--require-direct-metal' "$WORKFLOW"
  require_present "shader effect scene verifier in macOS workflow" \
    'scripts/verify_shaderfx_scene_fixtures\.sh' "$WORKFLOW"
fi

if [[ -f scripts/macos/verify-bundled-qt-runtime.sh ]]; then
  require_present "bundled runtime GNU libiconv import check" \
    'GNU libiconv symbols resolve to Darwin libiconv' \
    scripts/macos/verify-bundled-qt-runtime.sh
  require_present "bundled runtime libidn2 GNU iconv link check" \
    'libidn2\.0\.dylib is not linked to bundled libgnuiconv\.2\.dylib' \
    scripts/macos/verify-bundled-qt-runtime.sh
fi

if [[ -f scripts/macos/graphics-app-smoke.sh ]]; then
  require_present "app smoke enables Metal frame diagnostics" \
    'OPENTOONZ_GRAPHICS_METAL_FRAME_DIAGNOSTICS=1' \
    scripts/macos/graphics-app-smoke.sh
fi

if [[ -f scripts/verify_graphics_app_smoke_artifacts.sh ]]; then
  require_present "direct Metal frame verifier option" \
    '--require-direct-metal-frame' scripts/verify_graphics_app_smoke_artifacts.sh
  require_present "direct Metal smoke requires direct frame diagnostics" \
    'metal_frame direct_content=1 compatibility_snapshot=0' \
    scripts/verify_graphics_app_smoke_artifacts.sh
fi

if [[ -f scripts/verify_metal_probe_images.sh ]]; then
  require_present "editing tool overlay Metal probe artifact gate" \
    'editing_tool_overlay' scripts/verify_metal_probe_images.sh
fi

if [[ -f scripts/graphics_app_smoke_manifest.sh ]]; then
  require_present "manifest smoke screenshot evidence gate" \
    '--require-screenshot' scripts/graphics_app_smoke_manifest.sh
fi

if [[ -x scripts/verify_sample_data.sh ]]; then
  bash scripts/verify_sample_data.sh
fi

if [[ -x scripts/verify_graphics_fixture_scenes.sh ]]; then
  bash scripts/verify_graphics_fixture_scenes.sh \
    "${OPENTOONZ_GRAPHICS_FIXTURE_DIR:-/tmp/opentoonz-graphics-fixtures}"
fi

if [[ -x scripts/verify_opengl_selection_compatibility.sh ]]; then
  bash scripts/verify_opengl_selection_compatibility.sh "$ROOT"
fi

if (( fail != 0 )); then
  exit 1
fi

echo "graphics-modernization-lint: ok"
