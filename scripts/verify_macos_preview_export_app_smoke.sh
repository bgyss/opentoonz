#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact_dir="${1:-${OPENTOONZ_PREVIEW_EXPORT_APP_SMOKE_DIR:-${TMPDIR:-/tmp}/opentoonz-preview-export-app-smoke}}"
fixture_dir="${OPENTOONZ_GRAPHICS_FIXTURE_DIR:-${TMPDIR:-/tmp}/opentoonz-graphics-fixtures}"

"$repo_root/scripts/generate_graphics_fixture_scenes.sh" "$fixture_dir" >/dev/null

run_preview_export_case() {
  local case_id="$1"
  local scene_path="$2"
  local frame="$3"
  local require_preview_raster="$4"
  local case_artifact_dir="$artifact_dir/$case_id"

  OPENTOONZ_GRAPHICS_SMOKE_SCENE="$scene_path" \
  OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=internal-preview-export \
  OPENTOONZ_GRAPHICS_SMOKE_BACKENDS="${OPENTOONZ_GRAPHICS_SMOKE_BACKENDS:-opengl metal}" \
  OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY="${OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY:-1}" \
  OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_STARTUP_TRACE="${OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_STARTUP_TRACE:-1}" \
  OPENTOONZ_GRAPHICS_SMOKE_FRAME="$frame" \
  OPENTOONZ_GRAPHICS_SMOKE_SECONDS="${OPENTOONZ_GRAPHICS_SMOKE_SECONDS:-25}" \
  OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS="${OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS:-1}" \
  OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 \
    "$repo_root/scripts/macos/graphics-app-smoke.sh" "$case_artifact_dir"

  verify_args=()
  if [[ "$require_preview_raster" == "1" ]]; then
    verify_args+=(--require-preview-raster-export)
  fi
  "$repo_root/scripts/verify_graphics_app_smoke_artifacts.sh" \
    "$case_artifact_dir" "${verify_args[@]}"

  python3 "$repo_root/scripts/verify_png_match.py" \
    --max-mean-delta 0 \
    --max-channel-delta 0 \
    --max-differing-ratio 0 \
    "$case_artifact_dir/opengl/preview-export.png" \
    "$case_artifact_dir/metal/preview-export.png"
}

run_preview_export_case \
  tcomposer-color-card "$fixture_dir/tcomposer_color_card.tnz" 1 1
run_preview_export_case \
  tga-paint doc/sample_data/tga_paint.tnz 1 0
run_preview_export_case \
  dwanko-run doc/sample_data/dwanko_run.tnz 24 1

echo "verify-macos-preview-export-app-smoke: ok artifacts=$artifact_dir"
