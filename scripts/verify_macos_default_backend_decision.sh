#!/usr/bin/env bash
set -euo pipefail

decision_doc="${1:-doc/macos_graphics_default_backend_decision.md}"
cmake_file="toonz/sources/CMakeLists.txt"
tgraphics_file="toonz/sources/common/tgraphics/tgraphics.cpp"
workflow_file=".github/workflows/workflow_macos.yml"
build_summary_script="scripts/macos/ci-build-summary.sh"

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "verify-macos-default-backend-decision: missing file: $path" >&2
    exit 1
  fi
}

require_pattern() {
  local label="$1"
  local pattern="$2"
  local path="$3"
  if ! rg -n -e "$pattern" "$path" >/dev/null 2>&1; then
    echo "verify-macos-default-backend-decision: missing $label in $path" >&2
    exit 1
  fi
}

for path in "$decision_doc" "$cmake_file" "$tgraphics_file" "$workflow_file" \
  "$build_summary_script"; do
  require_file "$path"
done

require_pattern "OpenGL default decision" \
  '^Status: keep OpenGL as the default macOS graphics backend\.$' \
  "$decision_doc"
require_pattern "Metal opt-in decision" \
  'remains opt-in through `OPENTOONZ_GRAPHICS_BACKEND=metal`' \
  "$decision_doc"
require_pattern "switch criteria" '^## Switch Criteria$' "$decision_doc"
require_pattern "system-level input evidence" \
  'System-level keyboard/mouse routing now has a focused' "$decision_doc"
require_pattern "broader gesture workflow gap" \
  'broader drawing/editing gesture workflows still need' "$decision_doc"
require_pattern "Apple-hosted CI gap" \
  'Apple-hosted CI run IDs and final logs' "$decision_doc"

require_pattern "CMake Metal option defaults OFF" \
  'option\(WITH_GRAPHICS_METAL "Build the experimental macOS Metal graphics backend" OFF\)' \
  "$cmake_file"
require_pattern "runtime backend environment selector" \
  'std::getenv\("OPENTOONZ_GRAPHICS_BACKEND"\)' "$tgraphics_file"
require_pattern "runtime Metal selector value" \
  'metal' "$tgraphics_file"

require_pattern "OpenGL fallback CI leg" 'graphics: opengl-fallback' \
  "$workflow_file"
require_pattern "Metal CI leg" 'graphics: metal' "$workflow_file"
require_pattern "OpenGL fallback disables Metal" \
  'cmake_extra_args: -DWITH_GRAPHICS_METAL=OFF' "$workflow_file"
require_pattern "Metal leg enables Metal" \
  'cmake_extra_args: -DWITH_GRAPHICS_METAL=ON -DWITH_GRAPHICS_METAL_REQUIRE_METALLIB=ON' \
  "$workflow_file"

require_pattern "build timing summary" 'elapsed_seconds' "$build_summary_script"
require_pattern "OpenGL warning summary" 'apple_opengl_deprecation_warnings' \
  "$build_summary_script"
require_pattern "Qt QGL warning summary" 'qt_qgl_warning_lines' \
  "$build_summary_script"
require_pattern "Metal cache summary" 'WITH_GRAPHICS_METAL' \
  "$build_summary_script"
require_pattern "ccache summary" 'ccache --show-stats' "$build_summary_script"

echo "verify-macos-default-backend-decision: ok"
