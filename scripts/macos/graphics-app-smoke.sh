#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
app_path="${OPENTOONZ_APP:-$repo_root/toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app}"
artifact_dir="${1:-${OPENTOONZ_GRAPHICS_SMOKE_DIR:-/private/tmp/opentoonz-graphics-app-smoke}}"
backend_list="${OPENTOONZ_GRAPHICS_SMOKE_BACKENDS:-opengl metal}"
duration="${OPENTOONZ_GRAPHICS_SMOKE_SECONDS:-10}"
capture_screenshot="${OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT:-1}"
direct_only="${OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY:-0}"

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

mkdir -p "$artifact_dir"

terminate_app() {
  local pid="$1"
  if ! kill -0 "$pid" 2>/dev/null; then
    return 0
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

run_backend() {
  local backend="$1"
  local backend_dir="$artifact_dir/$backend"
  local log_file="$backend_dir/OpenToonz.log"
  local env_file="$backend_dir/environment.txt"
  local screenshot_file="$backend_dir/screenshot.png"

  mkdir -p "$backend_dir"
  {
    echo "OPENTOONZ_GRAPHICS_BACKEND=$backend"
    echo "OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=$direct_only"
    echo "OPENTOONZ_APP=$app_path"
    echo "duration_seconds=$duration"
  } >"$env_file"

  echo "graphics-app-smoke: launching backend=$backend"
  (
    cd "$repo_root"
    OPENTOONZ_GRAPHICS_BACKEND="$backend" \
      OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY="$direct_only" \
      "$app_exe"
  ) >"$log_file" 2>&1 &
  local pid="$!"

  sleep "$duration"

  check_log_for_startup_failure "$backend" "$log_file"

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

  if [[ "$capture_screenshot" != "0" ]] && command -v screencapture >/dev/null 2>&1; then
    screencapture -x "$screenshot_file" || {
      echo "graphics-app-smoke: screenshot capture failed for backend=$backend" >&2
      echo "graphics-app-smoke: continuing; launch smoke already passed" >&2
    }
  fi

  terminate_app "$pid"
  wait "$pid" 2>/dev/null || true

  echo "graphics-app-smoke: backend=$backend passed"
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
