#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
app_path="${OPENTOONZ_APP:-$repo_root/toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app}"
artifact_dir="${1:-${OPENTOONZ_GRAPHICS_SMOKE_DIR:-/private/tmp/opentoonz-graphics-app-smoke}}"
backend_list="${OPENTOONZ_GRAPHICS_SMOKE_BACKENDS:-opengl metal}"
duration="${OPENTOONZ_GRAPHICS_SMOKE_SECONDS:-10}"
cooldown="${OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS:-2}"
capture_screenshot="${OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT:-1}"
direct_only="${OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY:-0}"
scene_path="${OPENTOONZ_GRAPHICS_SMOKE_SCENE:-}"
bundle_id="${OPENTOONZ_GRAPHICS_SMOKE_BUNDLE_ID:-io.github.opentoonz.OpenToonz}"

if [[ ! -d "$app_path" ]]; then
  echo "graphics-app-smoke: missing app bundle: $app_path" >&2
  echo "build it with: cmake --build toonz/build/nix-relwithdebinfo --target OpenToonz" >&2
  exit 1
fi

app_exe="$app_path/Contents/MacOS/OpenToonz"
if [[ ! -x "$app_exe" ]]; then
  echo "graphics-app-smoke: missing app executable: $app_exe" >&2
  exit 1
fi

case "$duration" in
  ''|*[!0-9]*)
    echo "graphics-app-smoke: OPENTOONZ_GRAPHICS_SMOKE_SECONDS must be an integer" >&2
    exit 1
    ;;
esac
case "$cooldown" in
  ''|*[!0-9]*)
    echo "graphics-app-smoke: OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS must be an integer" >&2
    exit 1
    ;;
esac

if [[ -n "$scene_path" ]]; then
  if [[ "$scene_path" != /* ]]; then
    scene_path="$repo_root/$scene_path"
  fi
  if [[ ! -f "$scene_path" ]]; then
    echo "graphics-app-smoke: missing scene: $scene_path" >&2
    exit 1
  fi
fi

mkdir -p "$artifact_dir"

terminate_app() {
  local pid="$1"
  if ! kill -0 "$pid" 2>/dev/null; then
    return 0
  fi

  if command -v osascript >/dev/null 2>&1; then
    osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5; do
      if ! kill -0 "$pid" 2>/dev/null; then
        return 0
      fi
      sleep 1
    done
  fi

  kill "$pid" 2>/dev/null || true
  for _ in 1 2 3 4 5; do
    if ! kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    sleep 1
  done

  kill -9 "$pid" 2>/dev/null || true
}

check_log_for_startup_failure() {
  local backend="$1"
  local log_file="$2"

  if grep -E \
    "This application failed to start|Could not find the Qt platform plugin|no Qt platform plugin could be initialized|Symbol not found|dyld\\[[0-9]+\\]:|Trace/BPT trap|Abort trap|Segmentation fault" \
    "$log_file" >/dev/null 2>&1; then
    echo "graphics-app-smoke: backend=$backend logged a startup failure" >&2
    echo "graphics-app-smoke: log: $log_file" >&2
    return 1
  fi
}

capture_backend_screenshot() {
  local backend="$1"
  local screenshot_file="$2"
  local screenshot_info_file="$3"

  if [[ "$capture_screenshot" == "0" ]]; then
    echo "screenshot=disabled" >"$screenshot_info_file"
    return 0
  fi

  if ! command -v screencapture >/dev/null 2>&1; then
    echo "screenshot=unavailable" >"$screenshot_info_file"
    echo "graphics-app-smoke: screencapture is unavailable for backend=$backend" >&2
    return 1
  fi

  rm -f "$screenshot_file"
  screencapture -x "$screenshot_file" || {
    echo "graphics-app-smoke: screenshot capture failed for backend=$backend" >&2
    return 1
  }

  if [[ ! -s "$screenshot_file" ]]; then
    echo "graphics-app-smoke: screenshot is missing or empty for backend=$backend" >&2
    return 1
  fi

  {
    echo "screenshot=$screenshot_file"
    if command -v file >/dev/null 2>&1; then
      file "$screenshot_file"
    fi
    if command -v sips >/dev/null 2>&1; then
      sips -g pixelWidth -g pixelHeight "$screenshot_file" 2>/dev/null || true
    fi
  } >"$screenshot_info_file"
}

run_backend() {
  local backend="$1"
  local backend_dir="$artifact_dir/$backend"
  local log_file="$backend_dir/OpenToonz.log"
  local env_file="$backend_dir/environment.txt"
  local screenshot_file="$backend_dir/screenshot.png"
  local screenshot_info_file="$backend_dir/screenshot.txt"

  mkdir -p "$backend_dir"
  {
    echo "OPENTOONZ_GRAPHICS_BACKEND=$backend"
    echo "OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=$direct_only"
    echo "OPENTOONZ_GRAPHICS_SMOKE_SCENE=$scene_path"
    echo "OPENTOONZ_GRAPHICS_SMOKE_BUNDLE_ID=$bundle_id"
    echo "OPENTOONZ_APP=$app_path"
    echo "duration_seconds=$duration"
    echo "cooldown_seconds=$cooldown"
  } >"$env_file"

  echo "graphics-app-smoke: launching backend=$backend"
  local app_args=()
  if [[ -n "$scene_path" ]]; then
    app_args+=("$scene_path")
  fi
  (
    cd "$repo_root"
    OPENTOONZ_GRAPHICS_BACKEND="$backend" \
      OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY="$direct_only" \
      "$app_exe" "${app_args[@]}"
  ) >"$log_file" 2>&1 &
  local pid="$!"

  sleep "$duration"

  if ! check_log_for_startup_failure "$backend" "$log_file"; then
    terminate_app "$pid"
    wait "$pid" 2>/dev/null || true
    return 1
  fi

  if ! kill -0 "$pid" 2>/dev/null; then
    set +e
    wait "$pid"
    local status="$?"
    set -e
    check_log_for_startup_failure "$backend" "$log_file"
    echo "graphics-app-smoke: backend=$backend exited early with status $status" >&2
    echo "graphics-app-smoke: log: $log_file" >&2
    return "$status"
  fi

  if ! capture_backend_screenshot "$backend" "$screenshot_file" "$screenshot_info_file"; then
    terminate_app "$pid"
    wait "$pid" 2>/dev/null || true
    return 1
  fi

  terminate_app "$pid"
  wait "$pid" 2>/dev/null || true

  echo "graphics-app-smoke: backend=$backend passed"
  sleep "$cooldown"
}

for backend in $backend_list; do
  case "$backend" in
    opengl|metal) run_backend "$backend" ;;
    *)
      echo "graphics-app-smoke: unsupported backend: $backend" >&2
      exit 1
      ;;
  esac
done

echo "graphics-app-smoke: artifacts: $artifact_dir"
