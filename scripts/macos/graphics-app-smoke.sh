#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
app_path="${OPENTOONZ_APP:-$repo_root/toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app}"
artifact_dir="${1:-${OPENTOONZ_GRAPHICS_SMOKE_DIR:-/private/tmp/opentoonz-graphics-app-smoke}}"
backend_list="${OPENTOONZ_GRAPHICS_SMOKE_BACKENDS:-opengl metal}"
duration="${OPENTOONZ_GRAPHICS_SMOKE_SECONDS:-10}"
cooldown="${OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS:-2}"
capture_screenshot="${OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT:-1}"
screenshot_retries="${OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT_RETRIES:-3}"
direct_only="${OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY:-0}"
scene_path="${OPENTOONZ_GRAPHICS_SMOKE_SCENE:-}"
smoke_frame="${OPENTOONZ_GRAPHICS_SMOKE_FRAME:-}"
bundle_id="${OPENTOONZ_GRAPHICS_SMOKE_BUNDLE_ID:-io.github.opentoonz.OpenToonz}"
actions="${OPENTOONZ_GRAPHICS_SMOKE_ACTIONS:-}"
profile_dir="${OPENTOONZ_GRAPHICS_SMOKE_PROFILE_DIR:-$artifact_dir/profile}"
profile_room="${OPENTOONZ_GRAPHICS_SMOKE_PROFILE_ROOM:-Drawing}"
require_startup_trace="${OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_STARTUP_TRACE:-0}"
require_metal_frame_trace="${OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_METAL_FRAME_TRACE:-0}"

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

mkdir -p "$artifact_dir"
if [[ ! -d "$profile_dir" ]]; then
  bundled_profiles="$app_path/Contents/Resources/portablestuff/profiles"
  if [[ ! -d "$bundled_profiles" ]]; then
    echo "graphics-app-smoke: missing bundled profiles: $bundled_profiles" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$profile_dir")"
  cp -R "$bundled_profiles" "$profile_dir"
fi
mkdir -p "$profile_dir/layouts/rooms/Default"
printf '%s\n' "$profile_room" >"$profile_dir/layouts/rooms/Default/currentRoom.txt"
profile_user="${USER:-$(id -un 2>/dev/null || echo smoke)}"
profile_settings_dir="$profile_dir/layouts/settings.$profile_user"
mkdir -p "$profile_settings_dir"
cat >"$profile_settings_dir/preferences.ini" <<EOF
[General]
CurrentRoomChoice=Default
lazyLoadRooms=false
EOF
profile_env_dir="$profile_dir/env"
profile_env_file="$profile_env_dir/$profile_user.env"
mkdir -p "$profile_env_dir"
if [[ ! -f "$profile_env_file" ]]; then
  : >"$profile_env_file"
fi
if grep -q '^ViewBBoxToggleAction1 ' "$profile_env_file"; then
  perl -0pi -e 's/^ViewBBoxToggleAction1 ".*"$/ViewBBoxToggleAction1 "0"/m' "$profile_env_file"
else
  printf 'ViewBBoxToggleAction1 "0"\n' >>"$profile_env_file"
fi

preflight_file="$artifact_dir/preflight.txt"
{
  echo "app_path=$app_path"
  echo "app_exe=$app_exe"
  echo "profile_dir=$profile_dir"
  echo "profile_room=$profile_room"
  echo "profile_settings_dir=$profile_settings_dir"
  echo "profile_env_file=$profile_env_file"
  echo "qt_runtime_verifier=not-run"
} >"$preflight_file"

qt_runtime_verifier="$repo_root/scripts/macos/verify-bundled-qt-runtime.sh"
if [[ -x "$qt_runtime_verifier" ]]; then
  {
    echo "app_path=$app_path"
    echo "app_exe=$app_exe"
    echo "profile_dir=$profile_dir"
    echo "profile_room=$profile_room"
    echo "profile_settings_dir=$profile_settings_dir"
    echo "profile_env_file=$profile_env_file"
    echo "qt_runtime_verifier=$qt_runtime_verifier"
    "$qt_runtime_verifier" "$app_path"
  } >"$preflight_file"
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
case "$require_startup_trace" in
  0|1) ;;
  *)
    echo "graphics-app-smoke: OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_STARTUP_TRACE must be 0 or 1" >&2
    exit 1
    ;;
esac
case "$require_metal_frame_trace" in
  0|1) ;;
  *)
    echo "graphics-app-smoke: OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_METAL_FRAME_TRACE must be 0 or 1" >&2
    exit 1
    ;;
esac
if [[ -n "$smoke_frame" ]]; then
  case "$smoke_frame" in
    ''|*[!0-9]*|0)
      echo "graphics-app-smoke: OPENTOONZ_GRAPHICS_SMOKE_FRAME must be a positive integer" >&2
      exit 1
      ;;
  esac
fi
case "$screenshot_retries" in
  ''|*[!0-9]*)
    echo "graphics-app-smoke: OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT_RETRIES must be an integer" >&2
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

process_is_running() {
  local pid="$1"
  local state
  state="$(ps -p "$pid" -o stat= 2>/dev/null || true)"
  if [[ -n "$state" ]]; then
    [[ "$state" != Z* ]]
    return
  fi
  kill -0 "$pid" 2>/dev/null
}

wait_for_trace() {
  local pid="$1"
  local trace_file="$2"
  local pattern="$3"
  local timeout="$4"

  for ((i = 0; i < timeout; ++i)); do
    if [[ -s "$trace_file" ]] && grep -E "$pattern" "$trace_file" >/dev/null; then
      return 0
    fi
    if ! process_is_running "$pid"; then
      return 1
    fi
    sleep 1
  done
  return 1
}

terminate_app() {
  local pid="$1"
  if ! process_is_running "$pid"; then
    return 0
  fi

  if command -v osascript >/dev/null 2>&1; then
    osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 &
    local quit_pid="$!"
    for _ in 1 2 3; do
      if ! process_is_running "$quit_pid"; then
        break
      fi
      sleep 1
    done
    if process_is_running "$quit_pid"; then
      kill "$quit_pid" 2>/dev/null || true
    fi
    wait "$quit_pid" 2>/dev/null || true

    for _ in 1 2 3 4 5; do
      if ! process_is_running "$pid"; then
        return 0
      fi
      sleep 1
    done
  fi

  kill "$pid" 2>/dev/null || true
  for _ in 1 2 3 4 5; do
    if ! process_is_running "$pid"; then
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
    "You might be loading two sets of Qt binaries|Class .* is implemented in both .*Qt5|Could not load the Qt platform plugin \"cocoa\"" \
    "$log_file" >/dev/null 2>&1; then
    echo "graphics-app-smoke: backend=$backend appears to have loaded duplicate Qt runtime libraries" >&2
    echo "graphics-app-smoke: log: $log_file" >&2
    return 1
  fi

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

  local png_verifier="$repo_root/scripts/verify_png_nonblank.py"
  if [[ -s "$screenshot_file" ]]; then
    if [[ ! -x "$png_verifier" ]] || "$png_verifier" "$screenshot_file" >/dev/null; then
      {
        echo "screenshot=$screenshot_file"
        echo "source=internal"
        if command -v file >/dev/null 2>&1; then
          file "$screenshot_file"
        fi
        if command -v sips >/dev/null 2>&1; then
          sips -g pixelWidth -g pixelHeight "$screenshot_file" 2>/dev/null || true
        fi
      } >"$screenshot_info_file"
      return 0
    fi
    rm -f "$screenshot_file"
  fi

  if ! command -v screencapture >/dev/null 2>&1; then
    echo "screenshot=unavailable" >"$screenshot_info_file"
    echo "graphics-app-smoke: screencapture is unavailable for backend=$backend" >&2
    return 1
  fi

  rm -f "$screenshot_file"
  for ((attempt = 1; attempt <= screenshot_retries; ++attempt)); do
    screencapture -x "$screenshot_file" || {
      echo "graphics-app-smoke: screenshot capture attempt $attempt failed for backend=$backend" >&2
      sleep 1
      continue
    }

    if [[ ! -s "$screenshot_file" ]]; then
      echo "graphics-app-smoke: screenshot attempt $attempt is missing or empty for backend=$backend" >&2
      sleep 1
      continue
    fi

    if [[ -x "$png_verifier" ]] && ! "$png_verifier" "$screenshot_file" >/dev/null; then
      echo "graphics-app-smoke: screenshot attempt $attempt is blank for backend=$backend" >&2
      sleep 1
      continue
    fi

    break
  done

  if [[ ! -s "$screenshot_file" ]]; then
    echo "graphics-app-smoke: screenshot is missing or empty for backend=$backend" >&2
    return 1
  fi
  if [[ -x "$png_verifier" ]] && ! "$png_verifier" "$screenshot_file" >/dev/null; then
    echo "graphics-app-smoke: screenshot is blank after $screenshot_retries attempts for backend=$backend" >&2
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

run_backend_actions() {
  local backend="$1"
  local action_file="$2"
  local pid="$3"

  if [[ -z "$actions" || "$actions" == "none" ]]; then
    echo "actions=disabled" >"$action_file"
    return 0
  fi

  if [[ "$actions" == "internal-basic-viewer" ||
        "$actions" == "internal-editing-context" ||
        "$actions" == "internal-viewer-input" ||
        "$actions" == "internal-style-editor" ||
        "$actions" == "internal-drawing-gesture" ||
        "$actions" == "internal-preview-export" ]]; then
    {
      echo "actions=$actions"
      echo "backend=$backend"
      echo "bundle_id=$bundle_id"
      echo "pid=$pid"
    } >"$action_file"
    if wait_for_trace "$pid" "$artifact_dir/$backend/graphics-smoke-trace.txt" \
        '^OpenToonz graphics smoke: main_internal_actions_done$' "$duration"; then
      echo "result=ok" >>"$action_file"
      return 0
    fi
    echo "result=missing-internal-action-trace" >>"$action_file"
    return 1
  fi

  if [[ "$actions" != "basic-viewer" ]]; then
    echo "graphics-app-smoke: unsupported OPENTOONZ_GRAPHICS_SMOKE_ACTIONS: $actions" >&2
    return 1
  fi

  if ! command -v osascript >/dev/null 2>&1; then
    echo "graphics-app-smoke: osascript is unavailable for backend=$backend actions=$actions" >&2
    return 1
  fi

  {
    echo "actions=$actions"
    echo "backend=$backend"
    echo "bundle_id=$bundle_id"
    echo "pid=$pid"
    echo "system_mouse=center-window-click"
    echo "system_keyboard=space,space,right,left,plus,minus"
  } >"$action_file"

  osascript >>"$action_file" 2>&1 <<APPLESCRIPT &
tell application "System Events"
  set targetProcesses to every process whose unix id is $pid
  if (count of targetProcesses) is 0 then
    set targetProcesses to every process whose bundle identifier is "$bundle_id"
  end if
  if (count of targetProcesses) is 0 then
    set targetProcesses to every process whose name is "OpenToonz"
  end if
  if (count of targetProcesses) is 0 then error "OpenToonz process not found for pid $pid bundle $bundle_id"
  set targetProcess to item 1 of targetProcesses
  set resolvedUnixId to unix id of targetProcess
  set frontmost of targetProcess to true
  delay 1
  if (count of windows of targetProcess) is 0 then error "OpenToonz window not found for pid $pid"
  set targetWindow to front window of targetProcess
  set {windowX, windowY} to position of targetWindow
  set {windowWidth, windowHeight} to size of targetWindow
  click at {windowX + (windowWidth div 2), windowY + (windowHeight div 2)}
  delay 0.3
  keystroke " "
  delay 0.3
  keystroke " "
  delay 0.3
  key code 124
  delay 0.2
  key code 123
  delay 0.2
  keystroke "+"
  delay 0.2
  keystroke "-"
  return "resolved_unix_id=" & resolvedUnixId
end tell
APPLESCRIPT
  local action_pid="$!"
  for _ in 1 2 3 4 5; do
    if ! process_is_running "$action_pid"; then
      local action_status=0
      set +e
      wait "$action_pid"
      action_status="$?"
      set -e
      if [[ "$action_status" == "0" ]]; then
        echo "result=ok" >>"$action_file"
        return 0
      fi
      echo "result=failed status=$action_status" >>"$action_file"
      return "$action_status"
    fi
    sleep 1
  done

  echo "graphics-app-smoke: actions timed out for backend=$backend" >>"$action_file"
  echo "result=timeout" >>"$action_file"
  kill "$action_pid" 2>/dev/null || true
  wait "$action_pid" 2>/dev/null || true
  return 1
}

run_backend() {
  local backend="$1"
  local backend_dir="$artifact_dir/$backend"
  local log_file="$backend_dir/OpenToonz.log"
  local env_file="$backend_dir/environment.txt"
  local screenshot_file="$backend_dir/screenshot.png"
  local preview_export_file="$backend_dir/preview-export.png"
  local screenshot_info_file="$backend_dir/screenshot.txt"
  local action_file="$backend_dir/actions.txt"
  local trace_file="$backend_dir/graphics-smoke-trace.txt"

  mkdir -p "$backend_dir"
  {
    echo "OPENTOONZ_GRAPHICS_BACKEND=$backend"
    echo "OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=$direct_only"
    echo "OPENTOONZ_GRAPHICS_SMOKE_SCENE=$scene_path"
    echo "OPENTOONZ_GRAPHICS_SMOKE_FRAME=$smoke_frame"
    echo "OPENTOONZ_GRAPHICS_SMOKE_BUNDLE_ID=$bundle_id"
    echo "OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=$actions"
    echo "OPENTOONZ_GRAPHICS_SMOKE_PROFILE_DIR=$profile_dir"
    echo "OPENTOONZ_GRAPHICS_SMOKE_PROFILE_ROOM=$profile_room"
    echo "OPENTOONZ_GRAPHICS_SMOKE_TRACE_FILE=$trace_file"
    echo "OPENTOONZ_GRAPHICS_SMOKE_INTERNAL_SCREENSHOT=$screenshot_file"
    echo "OPENTOONZ_GRAPHICS_SMOKE_PREVIEW_EXPORT=$preview_export_file"
    echo "OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_STARTUP_TRACE=$require_startup_trace"
    echo "OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_METAL_FRAME_TRACE=$require_metal_frame_trace"
    echo "OPENTOONZ_APP=$app_path"
    echo "duration_seconds=$duration"
    echo "cooldown_seconds=$cooldown"
  } >"$env_file"

  echo "graphics-app-smoke: launching backend=$backend"
  rm -f "$trace_file"
  local app_args=()
  if [[ -n "$scene_path" ]]; then
    app_args+=("$scene_path")
  fi
  (
    cd "$repo_root"
      OPENTOONZ_GRAPHICS_BACKEND="$backend" \
      OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY="$direct_only" \
      OPENTOONZ_GRAPHICS_METAL_FRAME_DIAGNOSTICS=1 \
      OPENTOONZ_GRAPHICS_SMOKE_TRACE_FILE="$trace_file" \
      OPENTOONZ_GRAPHICS_SMOKE_INTERNAL_ACTIONS="$actions" \
      OPENTOONZ_GRAPHICS_SMOKE_FRAME="$smoke_frame" \
      OPENTOONZ_GRAPHICS_SMOKE_INTERNAL_SCREENSHOT="$screenshot_file" \
      OPENTOONZ_GRAPHICS_SMOKE_PREVIEW_EXPORT="$preview_export_file" \
      "$app_exe" -TOONZPROFILES "$profile_dir" "${app_args[@]}"
  ) >"$log_file" 2>&1 &
  local pid="$!"

  if (( require_startup_trace != 0 )); then
    if ! wait_for_trace "$pid" "$trace_file" \
        '^OpenToonz graphics smoke: main_after_main_window$' "$duration"; then
      echo "graphics-app-smoke: backend=$backend did not reach main window startup trace within ${duration}s" >&2
      echo "graphics-app-smoke: trace: $trace_file" >&2
      echo "graphics-app-smoke: log: $log_file" >&2
      terminate_app "$pid"
      wait "$pid" 2>/dev/null || true
      return 1
    fi
  fi

  if (( require_metal_frame_trace != 0 )) && [[ "$backend" == "metal" ]]; then
    if ! wait_for_trace "$pid" "$trace_file" \
        '^OpenToonz graphics smoke: metal_frame direct_content=1 compatibility_snapshot=0 width=[1-9][0-9]* height=[1-9][0-9]*$' "$duration"; then
      echo "graphics-app-smoke: backend=$backend did not reach direct Metal frame trace within ${duration}s" >&2
      echo "graphics-app-smoke: trace: $trace_file" >&2
      echo "graphics-app-smoke: log: $log_file" >&2
      terminate_app "$pid"
      wait "$pid" 2>/dev/null || true
      return 1
    fi
  elif (( require_startup_trace == 0 )); then
    sleep "$duration"
  fi

  if [[ -n "$smoke_frame" ]]; then
    if ! wait_for_trace "$pid" "$trace_file" \
        "^OpenToonz graphics smoke: main_smoke_frame_set frame=$smoke_frame index=[0-9]+$" \
        "$duration"; then
      echo "graphics-app-smoke: backend=$backend did not reach requested smoke frame $smoke_frame within ${duration}s" >&2
      echo "graphics-app-smoke: trace: $trace_file" >&2
      echo "graphics-app-smoke: log: $log_file" >&2
      terminate_app "$pid"
      wait "$pid" 2>/dev/null || true
      return 1
    fi
  fi

  if ! run_backend_actions "$backend" "$action_file" "$pid"; then
    terminate_app "$pid"
    wait "$pid" 2>/dev/null || true
    return 1
  fi

  if [[ "$capture_screenshot" != "0" ]]; then
    wait_for_trace "$pid" "$trace_file" \
      '^OpenToonz graphics smoke: main_internal_screenshot_saved width=[1-9][0-9]* height=[1-9][0-9]*$' \
      5 >/dev/null 2>&1 || true
  fi

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
