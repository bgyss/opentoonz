#!/usr/bin/env bash
set -euo pipefail

artifact_dir="${1:?usage: verify_graphics_app_smoke_artifacts.sh ARTIFACT_DIR [--require-direct-metal] [--require-screenshot] [backend ...]}"
shift || true

require_direct_metal=0
require_direct_metal_frame=0
require_screenshot=0
backends=()
for arg in "$@"; do
  case "$arg" in
    --require-direct-metal)
      require_direct_metal=1
      ;;
    --require-direct-metal-frame)
      require_direct_metal=1
      require_direct_metal_frame=1
      ;;
    --require-screenshot)
      require_screenshot=1
      ;;
    --*)
      echo "verify-graphics-app-smoke-artifacts: unknown option: $arg" >&2
      exit 1
      ;;
    *)
      backends+=("$arg")
      ;;
  esac
done

if (( ${#backends[@]} == 0 )); then
  backends=()
  for backend in opengl metal; do
    if [[ -d "$artifact_dir/$backend" ]]; then
      backends+=("$backend")
    fi
  done
  if (( ${#backends[@]} == 0 )); then
    backends=(opengl metal)
  fi
fi

if [[ ! -d "$artifact_dir" ]]; then
  echo "verify-graphics-app-smoke-artifacts: missing artifact directory: $artifact_dir" >&2
  exit 1
fi

preflight_file="$artifact_dir/preflight.txt"
if [[ ! -s "$preflight_file" ]]; then
  echo "verify-graphics-app-smoke-artifacts: missing smoke preflight metadata: $preflight_file" >&2
  exit 1
fi
if grep -qx 'qt_runtime_verifier=not-run' "$preflight_file"; then
  echo "verify-graphics-app-smoke-artifacts: Qt runtime verifier did not run: $preflight_file" >&2
  exit 1
fi
if ! grep -q '^verify-bundled-qt-runtime: ok ' "$preflight_file"; then
  echo "verify-graphics-app-smoke-artifacts: Qt runtime verifier did not pass: $preflight_file" >&2
  exit 1
fi

png_verifier="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify_png_nonblank.py"
png_matcher="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify_png_match.py"
max_mean_delta="${OPENTOONZ_GRAPHICS_SMOKE_MAX_MEAN_DELTA:-1.0}"
max_channel_delta="${OPENTOONZ_GRAPHICS_SMOKE_MAX_CHANNEL_DELTA:-255}"
max_differing_ratio="${OPENTOONZ_GRAPHICS_SMOKE_MAX_DIFFERING_RATIO:-0.02}"
fail=0
scene_path=""
declare -A screenshots=()
for backend in "${backends[@]}"; do
  backend_dir="$artifact_dir/$backend"
  env_file="$backend_dir/environment.txt"
  log_file="$backend_dir/OpenToonz.log"
  screenshot_info_file="$backend_dir/screenshot.txt"
  action_file="$backend_dir/actions.txt"

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
  if (( require_direct_metal != 0 )); then
    if [[ "$backend" != "metal" ]]; then
      echo "verify-graphics-app-smoke-artifacts: --require-direct-metal only applies to metal artifacts, got $backend" >&2
      fail=1
    elif [[ ! -s "$env_file" ]] ||
         ! grep -qx 'OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=1' "$env_file"; then
      echo "verify-graphics-app-smoke-artifacts: direct Metal metadata missing in $env_file" >&2
      fail=1
    fi
  fi

  if [[ -f "$action_file" ]] &&
     ! grep -Eq '^actions=(disabled|basic-viewer)$' "$action_file"; then
    echo "verify-graphics-app-smoke-artifacts: invalid action metadata: $action_file" >&2
    fail=1
  fi

  if [[ ! -f "$log_file" ]]; then
    echo "verify-graphics-app-smoke-artifacts: missing log: $log_file" >&2
    fail=1
  elif grep -E \
    "You might be loading two sets of Qt binaries|Class .* is implemented in both .*Qt5|Could not load the Qt platform plugin \"cocoa\"" \
    "$log_file" >/dev/null 2>&1; then
    echo "verify-graphics-app-smoke-artifacts: duplicate Qt runtime marker in $log_file" >&2
    fail=1
  elif grep -E \
    "This application failed to start|Could not find the Qt platform plugin|no Qt platform plugin could be initialized|Symbol not found|dyld\\[[0-9]+\\]:|Trace/BPT trap|Abort trap|Segmentation fault" \
    "$log_file" >/dev/null 2>&1; then
    echo "verify-graphics-app-smoke-artifacts: startup failure marker in $log_file" >&2
    fail=1
  fi
  if (( require_direct_metal_frame != 0 )) && [[ "$backend" == "metal" ]]; then
    if ! grep -Eq '^OpenToonz graphics smoke: metal_frame direct_content=1 compatibility_snapshot=0 width=[1-9][0-9]* height=[1-9][0-9]*$' "$log_file"; then
      echo "verify-graphics-app-smoke-artifacts: direct Metal frame diagnostic missing in $log_file" >&2
      fail=1
    fi
  fi

  if [[ ! -s "$screenshot_info_file" ]]; then
    echo "verify-graphics-app-smoke-artifacts: missing screenshot metadata: $screenshot_info_file" >&2
    fail=1
  elif grep -qx "screenshot=disabled" "$screenshot_info_file"; then
    if (( require_screenshot != 0 )); then
      echo "verify-graphics-app-smoke-artifacts: screenshot is disabled in $screenshot_info_file" >&2
      fail=1
    fi
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
      else
        screenshots["$backend"]="$screenshot_file"
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

if [[ -n "${screenshots[opengl]:-}" && -n "${screenshots[metal]:-}" &&
      -x "$png_matcher" ]]; then
  if ! "$png_matcher" \
      --max-mean-delta "$max_mean_delta" \
      --max-channel-delta "$max_channel_delta" \
      --max-differing-ratio "$max_differing_ratio" \
      "${screenshots[metal]}" "${screenshots[opengl]}"; then
    echo "verify-graphics-app-smoke-artifacts: OpenGL/Metal screenshot comparison exceeded tolerance" >&2
    fail=1
  fi
fi

if (( fail != 0 )); then
  exit 1
fi

echo "verify-graphics-app-smoke-artifacts: ok backends=${backends[*]} artifacts=$artifact_dir"
