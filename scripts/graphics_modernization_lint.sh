#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-toonz/sources}"
SCENEVIEWER="$ROOT/toonz/sceneviewer.cpp"
MAINWINDOW="$ROOT/toonz/mainwindow.cpp"
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

for source in "$MAINWINDOW" "$VIEWERDRAW" "$PLANEVIEWER" "$STYLEEDITOR" \
  "$STYLEEDITOR_H" "$EDITTOOL" "$EDITTOOLGADGETS" "$SKELETONTOOL"; do
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

require_present "MainWindow skips FBO probe under Metal" \
  'fbo_probe_skip backend=metal' "$MAINWINDOW"
require_present "MainWindow skips FBO probe without current OpenGL context" \
  'QOpenGLContext::currentContext\(\)' "$MAINWINDOW"
require_present "SceneViewer scoped picking guard" \
  'ScopedBoolSetter pickingGuard\(m_isPicking, true\)' "$SCENEVIEWER"
require_absent_file "SceneViewer OpenGL selection mode" \
  'gl(RenderMode|SelectBuffer|InitNames)[[:space:]]*\(|GL_SELECT' \
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
require_present "Skeleton Tool CPU picking gate" \
  'bool canUseCpuSkeletonPicking\(TToolViewer\* viewer\)' "$SKELETONTOOL"
require_present "Skeleton Tool CPU picking condition" \
  'return viewer != nullptr;' \
  "$SKELETONTOOL"
require_absent_file "Skeleton Tool generic OpenGL selection pick fallback" \
  'pick\(e\.m_pos\)' "$SKELETONTOOL"
require_absent_file "Skeleton Tool old 2D-only CPU picking guard" \
  'viewer && !viewer->is3DView\(\)' "$SKELETONTOOL"
require_present "Skeleton Tool guarded IK joint pick name" \
  'if \(isPicking\(\)\) glPushName\(code\)' "$SKELETONTOOL"
require_present "Skeleton Tool guarded center pick name" \
  'if \(isPicking\(\)\) glPushName\(TD_Center\)' "$SKELETONTOOL"
require_present "Skeleton Tool guarded pick-name pop" \
  'if \(isPicking\(\)\) glPopName\(\)' "$SKELETONTOOL"

if [[ -f "$WORKFLOW" ]]; then
  require_present "Metal probe image verifier in macOS workflow" \
    'scripts/verify_metal_probe_images\.sh' "$WORKFLOW"
  require_present "offscreen/style probe verifier in macOS workflow" \
    'scripts/verify_macos_offscreen_style_probes\.sh' "$WORKFLOW"
  require_present "preview/export probe verifier in macOS workflow" \
    'scripts/verify_macos_preview_export_probe\.sh' "$WORKFLOW"
  require_present "packaged tcomposer scene export verifier in macOS workflow" \
    'scripts/verify_macos_tcomposer_scene_export\.sh' "$WORKFLOW"
  require_present "OpenGL selection compatibility verifier in macOS workflow" \
    'scripts/verify_opengl_selection_compatibility\.sh' "$WORKFLOW"
  require_present "bundled Qt runtime verifier in macOS workflow" \
    'scripts/macos/verify-bundled-qt-runtime\.sh' "$WORKFLOW"
  require_present "direct Metal packaged app smoke in macOS workflow" \
    'OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=1' "$WORKFLOW"
  require_present "direct Metal packaged app smoke uses direct-frame sample" \
    'OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/tga_paint\.tnz' \
    "$WORKFLOW"
  require_present "direct Metal packaged app smoke internal viewer actions" \
    'OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=internal-editing-context' "$WORKFLOW"
  require_present "drawing gesture packaged app smoke in macOS workflow" \
    'scripts/verify_macos_drawing_gesture_app_smoke\.sh' "$WORKFLOW"
  require_present "direct Metal packaged app smoke startup trace gate in macOS workflow" \
    'OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_STARTUP_TRACE=1' "$WORKFLOW"
  require_present "direct Metal packaged app smoke frame trace gate in macOS workflow" \
    'OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_METAL_FRAME_TRACE=1' "$WORKFLOW"
  require_present "direct Metal smoke frame artifact verifier in macOS workflow" \
    '--require-direct-metal-frame' "$WORKFLOW"
  require_present "shader effect scene verifier in macOS workflow" \
    'scripts/verify_shaderfx_scene_fixtures\.sh' "$WORKFLOW"
fi

require_present "Shader FX compare documents wavy tolerance" \
  'SHADERFX_WAVY_COMPARE_TOLERANCE' "scripts/graphics_shaderfx_compare.sh"
require_present "Shader FX compare gates wavy parity separately" \
  'SHADERFX_WAVY_COMPARE' "scripts/graphics_shaderfx_compare.sh"
require_present "Shader FX compare gates fireball parity separately" \
  'SHADERFX_FIREBALL_COMPARE' "scripts/graphics_shaderfx_compare.sh"

if [[ -f scripts/macos/verify-bundled-qt-runtime.sh ]]; then
  require_present "bundled runtime GNU libiconv import check" \
    'GNU libiconv symbols resolve to Darwin libiconv' \
    scripts/macos/verify-bundled-qt-runtime.sh
  require_present "bundled runtime libidn2 GNU iconv link check" \
    'libidn2\.0\.dylib is not linked to bundled libgnuiconv\.2\.dylib' \
    scripts/macos/verify-bundled-qt-runtime.sh
fi

if [[ -f scripts/macos/verify-metal-resources.sh ]]; then
  require_present "Metal resource verifier checks repository shader source" \
    'toonz/sources/common/tgraphics/tgraphics_metal_shaders\.metal' \
    scripts/macos/verify-metal-resources.sh
  require_present "Metal resource verifier compares bundled shader source" \
    'cmp -s "\$repo_source" "\$source_resource"' \
    scripts/macos/verify-metal-resources.sh
  require_present "Metal resource verifier records shader hashes" \
    'source_sha256' scripts/macos/verify-metal-resources.sh
  require_present "Metal resource verifier supports strict metallib mode" \
    'OPENTOONZ_REQUIRE_METALLIB' scripts/macos/verify-metal-resources.sh
  require_present "Metal resource verifier records strict metallib mode" \
    'require_metallib=' scripts/macos/verify-metal-resources.sh
fi

if [[ -f scripts/macos/package-nix-app.sh ]]; then
  require_present "macOS packager compiles Metal shader library when host tools are available" \
    'compile_metal_resources' scripts/macos/package-nix-app.sh
  require_present "macOS packager invokes metallib" \
    'xcrun metallib' scripts/macos/package-nix-app.sh
fi

if [[ -f .github/workflows/workflow_macos.yml ]]; then
  require_present "macOS Metal CI enables Metal build" \
    'cmake_extra_args: -DWITH_GRAPHICS_METAL=ON' .github/workflows/workflow_macos.yml
  require_present "macOS Metal CI writes Metal resource summary" \
    'OPENTOONZ_METAL_RESOURCE_SUMMARY' .github/workflows/workflow_macos.yml
fi

if [[ -f scripts/macos/graphics-app-smoke.sh ]]; then
  require_present "app smoke enables Metal frame diagnostics" \
    'OPENTOONZ_GRAPHICS_METAL_FRAME_DIAGNOSTICS=1' \
    scripts/macos/graphics-app-smoke.sh
  require_present "app smoke startup trace gate" \
    'OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_STARTUP_TRACE' \
    scripts/macos/graphics-app-smoke.sh
  require_present "app smoke direct Metal frame trace gate" \
    'OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_METAL_FRAME_TRACE' \
    scripts/macos/graphics-app-smoke.sh
  require_present "app smoke internal basic-viewer action mode" \
    'internal-basic-viewer' scripts/macos/graphics-app-smoke.sh
  require_present "app smoke internal editing-context action mode" \
    'internal-editing-context' scripts/macos/graphics-app-smoke.sh
  require_present "app smoke internal viewer-input action mode" \
    'internal-viewer-input' scripts/macos/graphics-app-smoke.sh
  require_present "app smoke internal style-editor action mode" \
    'internal-style-editor' scripts/macos/graphics-app-smoke.sh
  require_present "app smoke internal drawing gesture action mode" \
    'internal-drawing-gesture' scripts/macos/graphics-app-smoke.sh
  require_present "app smoke internal action environment" \
    'OPENTOONZ_GRAPHICS_SMOKE_INTERNAL_ACTIONS' \
    scripts/macos/graphics-app-smoke.sh
  require_present "app smoke frame environment" \
    'OPENTOONZ_GRAPHICS_SMOKE_FRAME' scripts/macos/graphics-app-smoke.sh
  require_present "app smoke waits for requested frame trace" \
    'did not reach requested smoke frame' scripts/macos/graphics-app-smoke.sh
  require_present "app smoke retries blank screenshots" \
    'OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT_RETRIES' \
    scripts/macos/graphics-app-smoke.sh
  require_present "app smoke requests internal screenshots" \
    'OPENTOONZ_GRAPHICS_SMOKE_INTERNAL_SCREENSHOT' \
    scripts/macos/graphics-app-smoke.sh
fi

if [[ -f scripts/verify_graphics_app_smoke_artifacts.sh ]]; then
  require_present "artifact verifier startup trace gate" \
    'main_after_main_window' scripts/verify_graphics_app_smoke_artifacts.sh
  require_present "artifact verifier direct Metal frame trace gate" \
    'OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_METAL_FRAME_TRACE' \
    scripts/verify_graphics_app_smoke_artifacts.sh
  require_present "direct Metal frame verifier option" \
    '--require-direct-metal-frame' scripts/verify_graphics_app_smoke_artifacts.sh
  require_present "direct Metal smoke requires direct frame diagnostics" \
    'metal_frame direct_content=1 compatibility_snapshot=0' \
    scripts/verify_graphics_app_smoke_artifacts.sh
  require_present "artifact verifier internal basic-viewer action mode" \
    'internal-basic-viewer' scripts/verify_graphics_app_smoke_artifacts.sh
  require_present "artifact verifier basic-viewer system action result" \
    'basic-viewer system action result missing' \
    scripts/verify_graphics_app_smoke_artifacts.sh
  require_present "artifact verifier basic-viewer system mouse metadata" \
    'system_mouse=center-window-click' \
    scripts/verify_graphics_app_smoke_artifacts.sh
  require_present "artifact verifier basic-viewer system keyboard metadata" \
    'system_keyboard=space,space,right,left,plus,minus' \
    scripts/verify_graphics_app_smoke_artifacts.sh
  require_present "artifact verifier internal editing-context action mode" \
    'internal-editing-context' scripts/verify_graphics_app_smoke_artifacts.sh
  require_present "artifact verifier internal viewer-input action mode" \
    'internal-viewer-input' scripts/verify_graphics_app_smoke_artifacts.sh
  require_present "artifact verifier internal style-editor action mode" \
    'internal-style-editor' scripts/verify_graphics_app_smoke_artifacts.sh
  require_present "artifact verifier internal drawing gesture action mode" \
    'internal-drawing-gesture' scripts/verify_graphics_app_smoke_artifacts.sh
  require_present "artifact verifier internal action trace" \
    'main_internal_actions_done' scripts/verify_graphics_app_smoke_artifacts.sh
  require_present "artifact verifier internal style editor trace" \
    'main_internal_style_editor_changed' \
    scripts/verify_graphics_app_smoke_artifacts.sh
  require_present "artifact verifier internal viewer input trace" \
    'main_internal_input_\$event' \
    scripts/verify_graphics_app_smoke_artifacts.sh
  require_present "artifact verifier preview-raster export gate" \
    '--require-preview-raster-export' \
    scripts/verify_graphics_app_smoke_artifacts.sh
  require_present "artifact verifier drawing gesture image-change gate" \
    'main_internal_drawing_changed changed=1' \
    scripts/verify_graphics_app_smoke_artifacts.sh
  require_present "artifact verifier preview-raster source trace" \
    'source=preview_raster' scripts/verify_graphics_app_smoke_artifacts.sh
  require_present "artifact verifier internal editing tool trace" \
    'for tool in T_Edit T_Selection T_Brush T_Geometric T_Skeleton T_Hand' \
    scripts/verify_graphics_app_smoke_artifacts.sh
  require_present "artifact verifier smoke frame trace" \
    'main_smoke_frame_set frame=' scripts/verify_graphics_app_smoke_artifacts.sh
  require_present "artifact verifier bounded screenshot shift tolerance" \
    'OPENTOONZ_GRAPHICS_SMOKE_MAX_SHIFT' \
    scripts/verify_graphics_app_smoke_artifacts.sh
  require_present "main app internal smoke screenshot hook" \
    'internal_screenshot_saved' "$ROOT/toonz/main.cpp"
fi

if [[ -f scripts/verify_metal_probe_images.sh ]]; then
  require_present "editing tool overlay Metal probe artifact gate" \
    'editing_tool_overlay' scripts/verify_metal_probe_images.sh
fi

if [[ -f scripts/verify_macos_preview_export_probe.sh ]]; then
  require_present "preview/export OpenGL active exact-match gate" \
    'preview_export_opengl\.png' scripts/verify_macos_preview_export_probe.sh
  require_present "preview/export Metal active exact-match gate" \
    'preview_export_metal\.png' scripts/verify_macos_preview_export_probe.sh
  require_present "preview/export legacy cross-backend exact-match gate" \
    'metal/preview_export_legacy_opengl\.png' \
    scripts/verify_macos_preview_export_probe.sh
fi

if [[ -f scripts/verify_macos_preview_export_app_smoke.sh ]]; then
  require_present "preview/export app smoke uses internal preview-export action" \
    'internal-preview-export' scripts/verify_macos_preview_export_app_smoke.sh
  require_present "preview/export app smoke requires Previewer raster source" \
    '--require-preview-raster-export' \
    scripts/verify_macos_preview_export_app_smoke.sh
  require_present "preview/export app smoke exact backend PNG match" \
    '--max-differing-ratio 0' scripts/verify_macos_preview_export_app_smoke.sh
  require_present "preview/export app smoke includes generated color-card scene" \
    'tcomposer_color_card\.tnz' scripts/verify_macos_preview_export_app_smoke.sh
  require_present "preview/export app smoke includes committed TLV scene" \
    'doc/sample_data/tga_paint\.tnz' scripts/verify_macos_preview_export_app_smoke.sh
  require_present "preview/export app smoke includes committed FX/vector scene" \
    'doc/sample_data/dwanko_run\.tnz' scripts/verify_macos_preview_export_app_smoke.sh
fi

if [[ -f scripts/verify_macos_style_editor_app_smoke.sh ]]; then
  require_present "style editor app smoke uses internal style-editor action" \
    'internal-style-editor' scripts/verify_macos_style_editor_app_smoke.sh
  require_present "style editor app smoke verifies artifact traces" \
    'verify_graphics_app_smoke_artifacts\.sh' \
    scripts/verify_macos_style_editor_app_smoke.sh
fi

if [[ -f scripts/verify_macos_viewer_input_app_smoke.sh ]]; then
  require_present "viewer input app smoke uses internal viewer-input action" \
    'internal-viewer-input' scripts/verify_macos_viewer_input_app_smoke.sh
  require_present "viewer input app smoke verifies artifact traces" \
    'verify_graphics_app_smoke_artifacts\.sh' \
    scripts/verify_macos_viewer_input_app_smoke.sh
fi

if [[ -f scripts/verify_macos_system_viewer_app_smoke.sh ]]; then
  require_present "system viewer app smoke uses System Events action mode" \
    'OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=basic-viewer' \
    scripts/verify_macos_system_viewer_app_smoke.sh
  require_present "system viewer app smoke requires screenshot evidence" \
    '--require-screenshot' scripts/verify_macos_system_viewer_app_smoke.sh
  require_present "system viewer app smoke verifies artifact traces" \
    'verify_graphics_app_smoke_artifacts\.sh' \
    scripts/verify_macos_system_viewer_app_smoke.sh
fi

if [[ -f scripts/verify_macos_drawing_gesture_app_smoke.sh ]]; then
  require_present "drawing gesture app smoke uses internal drawing action" \
    'internal-drawing-gesture' scripts/verify_macos_drawing_gesture_app_smoke.sh
  require_present "drawing gesture app smoke requires direct Metal frame" \
    '--require-direct-metal-frame' \
    scripts/verify_macos_drawing_gesture_app_smoke.sh
  require_present "drawing gesture app smoke verifies artifact traces" \
    'verify_graphics_app_smoke_artifacts\.sh' \
    scripts/verify_macos_drawing_gesture_app_smoke.sh
fi

if [[ -f scripts/verify_macos_tcomposer_scene_export.sh ]]; then
  require_present "tcomposer export verifier uses golden scene manifest" \
    'doc/macos_graphics_golden_scenes\.tsv' scripts/verify_macos_tcomposer_scene_export.sh
  require_present "tcomposer export verifier selects explicit tcomposer rows" \
    'scripts/verify_macos_tcomposer_scene_export\.sh' scripts/verify_macos_tcomposer_scene_export.sh
  require_present "tcomposer export verifier has optional committed scene diagnostics" \
    'OPENTOONZ_TCOMPOSER_INCLUDE_REPO_SCENES' scripts/verify_macos_tcomposer_scene_export.sh
  require_present "tcomposer export verifier selects tcomposer scenes" \
    '\[\[ "\$scene_path" == \*\.tnz \]\]' scripts/verify_macos_tcomposer_scene_export.sh
  require_present "tcomposer export verifier runs OpenGL backend" \
    'run_backend "\$scene_id" "\$scene_path" "\$frame" opengl' \
    scripts/verify_macos_tcomposer_scene_export.sh
  require_present "tcomposer export verifier runs Metal backend" \
    'run_backend "\$scene_id" "\$scene_path" "\$frame" metal' \
    scripts/verify_macos_tcomposer_scene_export.sh
  require_present "tcomposer export verifier compares backend output" \
    'cmp -s "\$opengl_output" "\$metal_output"' \
    scripts/verify_macos_tcomposer_scene_export.sh
  require_present "tcomposer export verifier rejects blank black output" \
    'verify_tga_nonblank\.py' scripts/verify_macos_tcomposer_scene_export.sh
  require_present "tcomposer export verifier avoids ImageMagick dependency" \
    'verify_tga_nonblank\.py' scripts/verify_macos_tcomposer_scene_export.sh
  require_present "tcomposer export verifier documents helper debug diagnostics" \
    'OPENTOONZ_TCOMPOSER_DEBUG_LEVELS' "$ROOT/tcomposer/tcomposer.cpp"
fi

if [[ -f scripts/graphics_app_smoke_manifest.sh ]]; then
  require_present "manifest smoke screenshot evidence gate" \
    '--require-screenshot' scripts/graphics_app_smoke_manifest.sh
  require_present "manifest smoke propagates frame column" \
    'OPENTOONZ_GRAPHICS_SMOKE_FRAME="\$frame"' \
    scripts/graphics_app_smoke_manifest.sh
  require_absent_file "manifest smoke path-only dedupe" \
    'seen_paths' scripts/graphics_app_smoke_manifest.sh
  require_present "manifest smoke has per-scene timeout" \
    'OPENTOONZ_GRAPHICS_SMOKE_MANIFEST_SCENE_TIMEOUT_SECONDS' \
    scripts/graphics_app_smoke_manifest.sh
  require_present "manifest smoke uses timeout runner" \
    'run_with_timeout\.py' scripts/graphics_app_smoke_manifest.sh
fi

if [[ -f scripts/verify_macos_release_readiness_prereqs.sh ]]; then
  require_present "release readiness preflight checks strict metallib tools" \
    'require_xcrun_tool metallib' scripts/verify_macos_release_readiness_prereqs.sh
  require_present "release readiness preflight checks signing identity" \
    'MACOS_DEVELOPER_ID_APPLICATION' scripts/verify_macos_release_readiness_prereqs.sh
  require_present "release readiness preflight checks notarization credentials" \
    'MACOS_NOTARY_KEYCHAIN_PROFILE' scripts/verify_macos_release_readiness_prereqs.sh
  require_present "release readiness preflight prints strict metallib dispatch" \
    '-f strict_metallib=true' scripts/verify_macos_release_readiness_prereqs.sh
  require_present "release readiness preflight prints system GUI dispatch" \
    '-f system_gui_smoke=true' scripts/verify_macos_release_readiness_prereqs.sh
fi

if [[ -f scripts/verify_macos_manual_walkthrough_checklist.sh ]]; then
  bash scripts/verify_macos_manual_walkthrough_checklist.sh
  require_present "manual walkthrough checklist exists" \
    'macOS Graphics Manual Walkthrough Checklist' \
    doc/macos_graphics_manual_walkthrough_checklist.md
  require_present "manual walkthrough keeps Metal opt-in decision" \
    'Metal remains opt-in' doc/macos_graphics_manual_walkthrough_checklist.md
  require_present "manual walkthrough requires release preflight" \
    'verify_macos_release_readiness_prereqs\.sh' \
    doc/macos_graphics_manual_walkthrough_checklist.md
fi

if [[ -f .github/workflows/workflow_macos.yml ]]; then
  require_present "macOS CI runs packaged preview export app smoke" \
    'verify_macos_preview_export_app_smoke\.sh' \
    .github/workflows/workflow_macos.yml
  require_present "macOS CI runs packaged style editor app smoke" \
    'verify_macos_style_editor_app_smoke\.sh' \
    .github/workflows/workflow_macos.yml
  require_present "macOS CI runs packaged viewer input app smoke" \
    'verify_macos_viewer_input_app_smoke\.sh' \
    .github/workflows/workflow_macos.yml
  require_present "macOS CI bounds manifest smoke step" \
    'timeout-minutes: 45' .github/workflows/workflow_macos.yml
  require_present "macOS CI sets manifest scene timeout" \
    'OPENTOONZ_GRAPHICS_SMOKE_MANIFEST_SCENE_TIMEOUT_SECONDS=90' \
    .github/workflows/workflow_macos.yml
  require_present "macOS CI exposes packaged system viewer app smoke" \
    'verify_macos_system_viewer_app_smoke\.sh' \
    .github/workflows/workflow_macos.yml
  require_present "macOS CI gates system viewer smoke behind dispatch input" \
    'system_gui_smoke' .github/workflows/workflow_macos.yml
  require_present "macOS CI exposes strict metallib dispatch input" \
    'strict_metallib' .github/workflows/workflow_macos.yml
  require_present "macOS CI strict metallib configure gate" \
    'WITH_GRAPHICS_METAL_REQUIRE_METALLIB=ON' \
    .github/workflows/workflow_macos.yml
  require_present "macOS CI strict metallib package verifier gate" \
    'OPENTOONZ_REQUIRE_METALLIB' .github/workflows/workflow_macos.yml
  require_present "macOS CI runs packaged drawing gesture app smoke" \
    'verify_macos_drawing_gesture_app_smoke\.sh' \
    .github/workflows/workflow_macos.yml
  require_present "macOS CI uploads preview export app smoke artifacts" \
    'opentoonz-preview-export-app-smoke' .github/workflows/workflow_macos.yml
  require_present "macOS CI uploads style editor app smoke artifacts" \
    'opentoonz-style-editor-app-smoke' .github/workflows/workflow_macos.yml
  require_present "macOS CI uploads viewer input app smoke artifacts" \
    'opentoonz-viewer-input-app-smoke' .github/workflows/workflow_macos.yml
  require_present "macOS CI uploads system viewer app smoke artifacts" \
    'opentoonz-system-viewer-app-smoke' .github/workflows/workflow_macos.yml
  require_present "macOS CI uploads drawing gesture app smoke artifacts" \
    'opentoonz-drawing-gesture-app-smoke' .github/workflows/workflow_macos.yml
fi

if [[ -f scripts/verify_macos_ci_artifacts.sh ]]; then
  require_present "CI artifact verifier checks OpenGL build summary" \
    'missing OpenGL fallback build summary' scripts/verify_macos_ci_artifacts.sh
  require_present "CI artifact verifier checks Metal build summary" \
    'missing Metal build summary' scripts/verify_macos_ci_artifacts.sh
  require_present "CI artifact verifier checks Metal resource summary" \
    'source-only-toolchain-unavailable' scripts/verify_macos_ci_artifacts.sh
  require_present "CI artifact verifier checks direct Metal frame traces" \
    'metal_frame direct_content=1 compatibility_snapshot=0' \
    scripts/verify_macos_ci_artifacts.sh
  require_present "CI artifact verifier checks preview export traces" \
    'main_internal_preview_export_source source=' \
    scripts/verify_macos_ci_artifacts.sh
  require_present "CI artifact verifier checks viewer input traces" \
    'main_internal_input_press_hand' scripts/verify_macos_ci_artifacts.sh
  require_present "CI artifact verifier checks drawing gesture traces" \
    'main_internal_drawing_changed changed=1' \
    scripts/verify_macos_ci_artifacts.sh
  require_present "CI artifact verifier checks tcomposer output statistics" \
    'nonzero=' scripts/verify_macos_ci_artifacts.sh
fi

require_present "golden vector scene is app-smoke loadable" \
  '^vector-basic[[:space:]]+vector[[:space:]]+repo[[:space:]]+doc/sample_data/dwanko_run\.tnz' \
  doc/macos_graphics_golden_scenes.tsv

require_present "golden committed FX/vector scene is tcomposer export verified" \
  '^offscreen-export[[:space:]]+offscreen-render[[:space:]]+repo[[:space:]]+doc/sample_data/dwanko_run\.tnz[[:space:]]+24[[:space:]]+scripts/verify_macos_tcomposer_scene_export\.sh' \
  doc/macos_graphics_golden_scenes.tsv

require_present "golden committed cleanup scene is tcomposer export verified" \
  '^tcomposer-cleanup-scan[[:space:]]+offscreen-render[[:space:]]+repo[[:space:]]+doc/sample_data/cleanup\.tnz[[:space:]]+1[[:space:]]+scripts/verify_macos_tcomposer_scene_export\.sh' \
  doc/macos_graphics_golden_scenes.tsv

require_present "golden committed TLV paint scene is tcomposer export verified" \
  '^tcomposer-tlv-paint[[:space:]]+offscreen-render[[:space:]]+repo[[:space:]]+doc/sample_data/tga_paint\.tnz[[:space:]]+1[[:space:]]+scripts/verify_macos_tcomposer_scene_export\.sh' \
  doc/macos_graphics_golden_scenes.tsv

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

if [[ -x scripts/verify_macos_default_backend_decision.sh ]]; then
  bash scripts/verify_macos_default_backend_decision.sh
fi

if (( fail != 0 )); then
  exit 1
fi

echo "graphics-modernization-lint: ok"
