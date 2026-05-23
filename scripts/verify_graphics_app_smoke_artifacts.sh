#!/usr/bin/env bash
set -euo pipefail

artifact_dir="${1:?usage: verify_graphics_app_smoke_artifacts.sh ARTIFACT_DIR [backend ...]}"
shift || true

backends=("$@")
if (( ${#backends[@]} == 0 )); then
  backends=(opengl metal)
fi

if [[ ! -d "$artifact_dir" ]]; then
  echo "verify-graphics-app-smoke-artifacts: missing artifact directory: $artifact_dir" >&2
  exit 1
fi

png_verifier="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify_png_nonblank.py"
fail=0
scene_path=""
for backend in "${backends[@]}"; do
  backend_dir="$artifact_dir/$backend"
  env_file="$backend_dir/environment.txt"
  log_file="$backend_dir/OpenToonz.log"
  screenshot_info_file="$backend_dir/screenshot.txt"

  if [[ ! -d "$backend_dir" ]]; then
    echo "verify-graphics-app-smoke-artifacts: missing backend directory: $backend_dir" >&2
    fail=1
    continue
  fi
  if [[ ! -s "$env_file" ]]; then
    echo "verify-graphics-app-smoke-artifacts: missing environment metadata: $env_file" >&2
    fail=1
  elif ! grep -qx "OPENTOONZ_GRAPHICS_BACKEND=$backend" "$env_file"; then
    echo "verify-graphics-app-smoke-artifacts: backend metadata mismatch in $env_file" >&2
    fail=1
  fi

  if [[ ! -f "$log_file" ]]; then
    echo "verify-graphics-app-smoke-artifacts: missing log: $log_file" >&2
    fail=1
  elif grep -E \
    "This application failed to start|Could not find the Qt platform plugin|no Qt platform plugin could be initialized|Symbol not found|dyld\\[[0-9]+\\]:|Trace/BPT trap|Abort trap|Segmentation fault" \
    "$log_file" >/dev/null 2>&1; then
    echo "verify-graphics-app-smoke-artifacts: startup failure marker in $log_file" >&2
    fail=1
  fi

  if [[ ! -s "$screenshot_info_file" ]]; then
    echo "verify-graphics-app-smoke-artifacts: missing screenshot metadata: $screenshot_info_file" >&2
    fail=1
  elif grep -qx "screenshot=disabled" "$screenshot_info_file"; then
    :
  else
    screenshot_file="$(sed -n 's/^screenshot=//p' "$screenshot_info_file" | head -n 1)"
    if [[ -z "$screenshot_file" || ! -s "$screenshot_file" ]]; then
      echo "verify-graphics-app-smoke-artifacts: missing screenshot file referenced by $screenshot_info_file" >&2
      fail=1
    elif ! grep -Eq 'PNG image data|pixelWidth: [1-9][0-9]*|pixelHeight: [1-9][0-9]*' "$screenshot_info_file"; then
      echo "verify-graphics-app-smoke-artifacts: screenshot metadata lacks image details: $screenshot_info_file" >&2
      fail=1
    elif [[ -x "$png_verifier" ]]; then
      if ! "$png_verifier" "$screenshot_file" >/dev/null; then
        echo "verify-graphics-app-smoke-artifacts: screenshot appears blank: $screenshot_file" >&2
        fail=1
      fi
    fi
  fi

  current_scene="$(sed -n 's/^OPENTOONZ_GRAPHICS_SMOKE_SCENE=//p' "$env_file" | head -n 1)"
  if [[ -n "$current_scene" ]]; then
    if [[ ! -f "$current_scene" ]]; then
      echo "verify-graphics-app-smoke-artifacts: scene metadata path does not exist: $current_scene" >&2
      fail=1
    fi
    if [[ -z "$scene_path" ]]; then
      scene_path="$current_scene"
    elif [[ "$scene_path" != "$current_scene" ]]; then
      echo "verify-graphics-app-smoke-artifacts: scene metadata differs across backends" >&2
      fail=1
    fi
  fi
done

if (( fail != 0 )); then
  exit 1
fi

echo "verify-graphics-app-smoke-artifacts: ok backends=${backends[*]} artifacts=$artifact_dir"
