#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact_dir="${1:?usage: verify_graphics_app_smoke_artifacts.sh ARTIFACT_DIR [--require-direct-metal] [--require-screenshot] [--require-preview-raster-export] [backend ...]}"
shift || true

require_direct_metal=0
require_direct_metal_frame=0
require_screenshot=0
require_preview_raster_export=0
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
    --require-preview-raster-export)
      require_preview_raster_export=1
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
max_mean_delta="${OPENTOONZ_GRAPHICS_SMOKE_MAX_MEAN_DELTA:-8.0}"
max_channel_delta="${OPENTOONZ_GRAPHICS_SMOKE_MAX_CHANNEL_DELTA:-255}"
max_differing_ratio="${OPENTOONZ_GRAPHICS_SMOKE_MAX_DIFFERING_RATIO:-0.95}"
max_shift="${OPENTOONZ_GRAPHICS_SMOKE_MAX_SHIFT:-16}"
fail=0
scene_path=""
smoke_frame=""
declare -A screenshots=()
for backend in "${backends[@]}"; do
  backend_dir="$artifact_dir/$backend"
  env_file="$backend_dir/environment.txt"
  log_file="$backend_dir/OpenToonz.log"
  trace_file="$backend_dir/graphics-smoke-trace.txt"
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
  if [[ -s "$env_file" ]] &&
     grep -qx 'OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_STARTUP_TRACE=1' "$env_file"; then
    if [[ ! -s "$trace_file" ]] ||
       ! grep -Eq '^OpenToonz graphics smoke: main_after_main_window$' "$trace_file"; then
      echo "verify-graphics-app-smoke-artifacts: required startup trace missing in $trace_file" >&2
      fail=1
    fi
  fi
  if [[ -s "$env_file" ]] &&
     grep -qx 'OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_METAL_FRAME_TRACE=1' "$env_file"; then
    if [[ "$backend" != "metal" ]]; then
      echo "verify-graphics-app-smoke-artifacts: Metal frame trace gate only applies to metal artifacts, got $backend" >&2
      fail=1
    elif [[ ! -s "$trace_file" ]] ||
       ! grep -Eq '^OpenToonz graphics smoke: metal_frame direct_content=1 compatibility_snapshot=0 width=[1-9][0-9]* height=[1-9][0-9]*$' "$trace_file"; then
      echo "verify-graphics-app-smoke-artifacts: required direct Metal frame trace missing in $trace_file" >&2
      fail=1
    fi
  fi

  if [[ -f "$action_file" ]] &&
     ! grep -Eq '^actions=(disabled|basic-viewer|internal-basic-viewer|internal-editing-context|internal-viewer-input|internal-style-editor|internal-drawing-gesture|internal-preview-export)$' "$action_file"; then
    echo "verify-graphics-app-smoke-artifacts: invalid action metadata: $action_file" >&2
    fail=1
  fi

  if [[ -f "$action_file" ]] &&
     grep -Eqx 'actions=(internal-basic-viewer|internal-editing-context|internal-viewer-input|internal-style-editor|internal-drawing-gesture|internal-preview-export)' "$action_file"; then
    if [[ ! -s "$trace_file" ]] ||
       ! grep -qx 'OpenToonz graphics smoke: main_internal_actions_done' "$trace_file"; then
      echo "verify-graphics-app-smoke-artifacts: internal action trace missing in $trace_file" >&2
      fail=1
    fi
  fi

  if [[ -f "$action_file" ]] &&
     grep -qx 'actions=basic-viewer' "$action_file"; then
    if ! grep -qx 'result=ok' "$action_file"; then
      echo "verify-graphics-app-smoke-artifacts: basic-viewer system action result missing in $action_file" >&2
      fail=1
    fi
    if ! grep -qx 'system_mouse=center-window-click' "$action_file"; then
      echo "verify-graphics-app-smoke-artifacts: basic-viewer system mouse metadata missing in $action_file" >&2
      fail=1
    fi
    if ! grep -qx 'system_keyboard=space,space,right,left,plus,minus' "$action_file"; then
      echo "verify-graphics-app-smoke-artifacts: basic-viewer system keyboard metadata missing in $action_file" >&2
      fail=1
    fi
  fi

  if [[ -f "$action_file" ]] &&
     grep -qx 'actions=internal-editing-context' "$action_file"; then
    for tool in T_Edit T_Selection T_Brush T_Geometric T_Skeleton T_Hand; do
      if [[ ! -s "$trace_file" ]] ||
         ! grep -qx "OpenToonz graphics smoke: main_internal_tool_$tool" "$trace_file"; then
        echo "verify-graphics-app-smoke-artifacts: internal editing tool trace $tool missing in $trace_file" >&2
        fail=1
      fi
    done
  fi

  if [[ -f "$action_file" ]] &&
     grep -qx 'actions=internal-viewer-input' "$action_file"; then
    for tool in T_Hand T_Selection; do
      if [[ ! -s "$trace_file" ]] ||
         ! grep -qx "OpenToonz graphics smoke: main_internal_input_tool_$tool" "$trace_file"; then
        echo "verify-graphics-app-smoke-artifacts: internal input tool trace $tool missing in $trace_file" >&2
        fail=1
      fi
    done
    for event in press_hand move_hand release_hand press_selection move_selection release_selection; do
      if [[ ! -s "$trace_file" ]] ||
         ! grep -qx "OpenToonz graphics smoke: main_internal_input_$event" "$trace_file"; then
        echo "verify-graphics-app-smoke-artifacts: internal input event trace $event missing in $trace_file" >&2
        fail=1
      fi
    done
  fi

  if [[ -f "$action_file" ]] &&
     grep -qx 'actions=internal-style-editor' "$action_file"; then
    if [[ ! -s "$trace_file" ]] ||
       ! grep -Eq '^OpenToonz graphics smoke: main_internal_style_editor_changed style=[1-9][0-9]*$' "$trace_file"; then
      echo "verify-graphics-app-smoke-artifacts: internal style editor change trace missing in $trace_file" >&2
      fail=1
    fi
    if [[ ! -s "$trace_file" ]] ||
       ! grep -Eq '^OpenToonz graphics smoke: main_internal_style_editor_restored style=[1-9][0-9]*$' "$trace_file"; then
      echo "verify-graphics-app-smoke-artifacts: internal style editor restore trace missing in $trace_file" >&2
      fail=1
    fi
  fi

  if [[ -f "$action_file" ]] &&
     grep -qx 'actions=internal-drawing-gesture' "$action_file"; then
    for event in tool_T_Brush before press move_1 move_2 release after; do
      if [[ ! -s "$trace_file" ]] ||
         ! grep -Eq "^OpenToonz graphics smoke: main_internal_drawing_$event( |$)" "$trace_file"; then
        echo "verify-graphics-app-smoke-artifacts: internal drawing gesture trace $event missing in $trace_file" >&2
        fail=1
      fi
    done
    if [[ ! -s "$trace_file" ]] ||
       ! grep -qx 'OpenToonz graphics smoke: main_internal_drawing_changed changed=1' "$trace_file"; then
      echo "verify-graphics-app-smoke-artifacts: internal drawing gesture did not change image state in $trace_file" >&2
      fail=1
    fi
  fi

  if [[ -f "$action_file" ]] &&
     grep -qx 'actions=internal-preview-export' "$action_file"; then
    preview_export_file="$backend_dir/preview-export.png"
    if [[ ! -s "$trace_file" ]] ||
       ! grep -Eq '^OpenToonz graphics smoke: main_internal_preview_frame_ready frame=[1-9][0-9]*$' "$trace_file"; then
      echo "verify-graphics-app-smoke-artifacts: internal preview frame-ready trace missing in $trace_file" >&2
      fail=1
    fi
    if [[ ! -s "$trace_file" ]] ||
       ! grep -Eq '^OpenToonz graphics smoke: main_internal_preview_export_saved path=.* width=[1-9][0-9]* height=[1-9][0-9]*$' "$trace_file"; then
      echo "verify-graphics-app-smoke-artifacts: internal preview export trace missing in $trace_file" >&2
      fail=1
    fi
    if [[ ! -s "$trace_file" ]] ||
       ! grep -Eq '^OpenToonz graphics smoke: main_internal_preview_export_source source=(preview_raster|scene_renderer|viewer_framebuffer|viewer_widget)$' "$trace_file"; then
      echo "verify-graphics-app-smoke-artifacts: internal preview export source trace missing in $trace_file" >&2
      fail=1
    fi
    if (( require_preview_raster_export )) &&
       ! grep -qx 'OpenToonz graphics smoke: main_internal_preview_export_source source=preview_raster' "$trace_file"; then
      echo "verify-graphics-app-smoke-artifacts: internal preview export did not come from Previewer raster in $trace_file" >&2
      fail=1
    fi
    if [[ ! -s "$preview_export_file" ]]; then
      echo "verify-graphics-app-smoke-artifacts: missing internal preview export: $preview_export_file" >&2
      fail=1
    elif [[ -x "$repo_root/scripts/verify_png_nonblank.py" ]] &&
         ! "$repo_root/scripts/verify_png_nonblank.py" "$preview_export_file" >/dev/null; then
      echo "verify-graphics-app-smoke-artifacts: internal preview export is blank: $preview_export_file" >&2
      fail=1
    fi
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
    if ! grep -E \
      '^OpenToonz graphics smoke: metal_frame direct_content=1 compatibility_snapshot=0 width=[1-9][0-9]* height=[1-9][0-9]*$' \
      "$log_file" "$trace_file" >/dev/null 2>&1; then
      echo "verify-graphics-app-smoke-artifacts: direct Metal frame diagnostic missing in $log_file or $trace_file" >&2
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
  current_frame="$(sed -n 's/^OPENTOONZ_GRAPHICS_SMOKE_FRAME=//p' "$env_file" | head -n 1)"
  if [[ -n "$current_frame" ]]; then
    case "$current_frame" in
      ''|*[!0-9]*|0)
        echo "verify-graphics-app-smoke-artifacts: invalid smoke frame metadata in $env_file" >&2
        fail=1
        ;;
      *)
        if [[ -z "$trace_file" || ! -s "$trace_file" ]] ||
           ! grep -Eq "^OpenToonz graphics smoke: main_smoke_frame_set frame=$current_frame index=[0-9]+$" "$trace_file"; then
          echo "verify-graphics-app-smoke-artifacts: smoke frame trace frame=$current_frame missing in $trace_file" >&2
          fail=1
        fi
        if [[ -z "$smoke_frame" ]]; then
          smoke_frame="$current_frame"
        elif [[ "$smoke_frame" != "$current_frame" ]]; then
          echo "verify-graphics-app-smoke-artifacts: smoke frame metadata differs across backends" >&2
          fail=1
        fi
        ;;
    esac
  fi
done

if [[ -n "${screenshots[opengl]:-}" && -n "${screenshots[metal]:-}" &&
      -x "$png_matcher" ]]; then
  if ! "$png_matcher" \
      --max-mean-delta "$max_mean_delta" \
      --max-channel-delta "$max_channel_delta" \
      --max-differing-ratio "$max_differing_ratio" \
      --max-shift "$max_shift" \
      "${screenshots[metal]}" "${screenshots[opengl]}"; then
    echo "verify-graphics-app-smoke-artifacts: OpenGL/Metal screenshot comparison exceeded tolerance" >&2
    fail=1
  fi
fi

if (( fail != 0 )); then
  exit 1
fi

echo "verify-graphics-app-smoke-artifacts: ok backends=${backends[*]} artifacts=$artifact_dir"
