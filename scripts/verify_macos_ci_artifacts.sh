#!/usr/bin/env bash
set -euo pipefail

artifact_root="${1:-${OPENTOONZ_MACOS_CI_ARTIFACT_ROOT:-}}"

if [[ -z "$artifact_root" ]]; then
  echo "verify-macos-ci-artifacts: usage: $0 <downloaded-artifact-root>" >&2
  exit 2
fi

if [[ ! -d "$artifact_root" ]]; then
  echo "verify-macos-ci-artifacts: missing artifact root: $artifact_root" >&2
  exit 1
fi

fail=0

find_files() {
  local name_pattern="$1"
  find "$artifact_root" -type f -name "$name_pattern" -print
}

require_file() {
  local label="$1"
  local file="$2"

  if [[ -f "$file" ]]; then
    return 0
  fi

  echo "verify-macos-ci-artifacts: missing $label: $file" >&2
  fail=1
}

require_any_file() {
  local label="$1"
  local name_pattern="$2"
  local match

  match="$(find_files "$name_pattern" | head -n 1 || true)"
  if [[ -n "$match" ]]; then
    echo "$match"
    return 0
  fi

  echo "verify-macos-ci-artifacts: missing $label ($name_pattern)" >&2
  fail=1
  return 1
}

require_pattern() {
  local label="$1"
  local pattern="$2"
  local file="$3"

  require_file "$label" "$file"
  [[ -f "$file" ]] || return 0

  if ! grep -Eq -- "$pattern" "$file"; then
    echo "verify-macos-ci-artifacts: missing $label in $file" >&2
    fail=1
  fi
}

require_any_pattern() {
  local label="$1"
  local pattern="$2"
  local name_pattern="$3"
  local matches

  matches="$(find_files "$name_pattern" || true)"
  if [[ -z "$matches" ]]; then
    echo "verify-macos-ci-artifacts: missing files for $label ($name_pattern)" >&2
    fail=1
    return 0
  fi

  while IFS= read -r file; do
    if grep -Eq -- "$pattern" "$file"; then
      return 0
    fi
  done <<<"$matches"

  echo "verify-macos-ci-artifacts: no $name_pattern contains $label" >&2
  fail=1
}

find_file_with_pattern() {
  local name_pattern="$1"
  local pattern="$2"
  local file

  while IFS= read -r file; do
    if grep -Eq -- "$pattern" "$file"; then
      echo "$file"
      return 0
    fi
  done < <(find_files "$name_pattern")

  return 1
}

find_summary() {
  local label_pattern="$1"
  local metal_value="$2"
  local file

  while IFS= read -r file; do
    if grep -Eq -- "$label_pattern" "$file" &&
       grep -Eq -- "WITH_GRAPHICS_METAL: $metal_value" "$file"; then
      echo "$file"
      return 0
    fi
  done < <(find_files '*-summary.md')

  return 1
}

opengl_summary="$(find_summary 'macos-arm64-(opengl-fallback|4146-current)' 'OFF' || true)"
metal_summary="$(find_summary 'macos-arm64-(metal|4146-latest)' 'ON' || true)"

if [[ -z "$opengl_summary" ]]; then
  echo "verify-macos-ci-artifacts: missing OpenGL fallback build summary" >&2
  fail=1
else
  require_pattern "OpenGL summary status" '^- status: 0$' "$opengl_summary"
  require_pattern "OpenGL summary elapsed time" '^- elapsed_seconds: [1-9][0-9]*$' "$opengl_summary"
  require_pattern "OpenGL summary warning count" '^- apple_opengl_deprecation_warnings: [0-9]+$' "$opengl_summary"
  require_pattern "OpenGL summary Qt QGL warnings" '^- qt_qgl_warning_lines: 0$' "$opengl_summary"
  require_pattern "OpenGL summary ccache section" '^### ccache$' "$opengl_summary"
fi

if [[ -z "$metal_summary" ]]; then
  echo "verify-macos-ci-artifacts: missing Metal build summary" >&2
  fail=1
else
  require_pattern "Metal summary status" '^- status: 0$' "$metal_summary"
  require_pattern "Metal summary elapsed time" '^- elapsed_seconds: [1-9][0-9]*$' "$metal_summary"
  require_pattern "Metal summary warning count" '^- apple_opengl_deprecation_warnings: [0-9]+$' "$metal_summary"
  require_pattern "Metal summary Qt QGL warnings" '^- qt_qgl_warning_lines: 0$' "$metal_summary"
  require_pattern "Metal summary ccache section" '^### ccache$' "$metal_summary"
fi

metal_resource_summary="$(find_file_with_pattern 'summary.txt' '^require_metallib=1$' || true)"
if [[ -z "$metal_resource_summary" ]]; then
  echo "verify-macos-ci-artifacts: missing strict Metal resource summary" >&2
  fail=1
fi
if [[ -n "$metal_resource_summary" ]]; then
  require_pattern "strict metallib requirement" '^require_metallib=1$' "$metal_resource_summary"
  require_pattern "compiled metallib present" '^library_present=1$' "$metal_resource_summary"
  require_pattern "Metal resource verifier success" '^status=source-and-metallib$' "$metal_resource_summary"
fi

require_any_pattern "bundled Qt runtime preflight" \
  'verify-bundled-qt-runtime: ok' 'preflight.txt'
require_any_pattern "direct Metal frame trace" \
  'metal_frame direct_content=1 compatibility_snapshot=0' 'graphics-smoke-trace.txt'
require_any_pattern "internal app smoke completion" \
  'main_internal_actions_done' 'graphics-smoke-trace.txt'
require_any_pattern "preview export source trace" \
  'main_internal_preview_export_source source=' 'graphics-smoke-trace.txt'
require_any_pattern "style editor change trace" \
  'main_internal_style_editor_changed' 'graphics-smoke-trace.txt'
require_any_pattern "viewer input event trace" \
  'main_internal_input_press_hand' 'graphics-smoke-trace.txt'
require_any_pattern "drawing gesture image-change trace" \
  'main_internal_drawing_changed changed=1' 'graphics-smoke-trace.txt'
require_any_pattern "tcomposer nonblack statistics" \
  'nonzero=' 'image-stats.txt'
require_any_pattern "probe image hash summary" \
  'sha256|probe image counts|cases=' 'summary.txt'

if (( fail != 0 )); then
  exit 1
fi

echo "verify-macos-ci-artifacts: ok $artifact_root"
