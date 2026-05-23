#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-toonz/sources}"
SCENEVIEWER="$ROOT/toonz/sceneviewer.cpp"
EDITTOOL="$ROOT/tnztools/edittool.cpp"
EDITTOOLGADGETS="$ROOT/tnztools/edittoolgadgets.cpp"
SKELETONTOOL="$ROOT/tnztools/skeletontool.cpp"

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

for source in "$EDITTOOL" "$EDITTOOLGADGETS" "$SKELETONTOOL"; do
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
require_present "Edit Tool main handle CPU picking" \
  'int EditTool::pickMainHandleCpu\(const TPointD &pos\)' "$EDITTOOL"
require_present "Edit Tool FX gadget CPU hover picking" \
  'm_fxGadgetController->pickCpu\(e\.m_pos\)' "$EDITTOOL"
require_present "FX gadget controller CPU picking" \
  'int FxGadgetController::pickCpu\(const TPointD &viewerPos\)' \
  "$EDITTOOLGADGETS"
require_present "Skeleton Tool CPU picking" \
  'int SkeletonTool::pickCpu\(const TPointD& viewerPos\)' "$SKELETONTOOL"
require_present "Skeleton Tool 2D CPU picking gate" \
  'const bool useCpuPicking = !getViewer\(\)->is3DView\(\)' "$SKELETONTOOL"

if [[ -x scripts/verify_sample_data.sh ]]; then
  bash scripts/verify_sample_data.sh
fi

if (( fail != 0 )); then
  exit 1
fi

echo "graphics-modernization-lint: ok"
