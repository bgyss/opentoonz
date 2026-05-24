#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact_dir="${1:-${OPENTOONZ_DRAWING_GESTURE_APP_SMOKE_DIR:-${TMPDIR:-/tmp}/opentoonz-drawing-gesture-app-smoke}}"

OPENTOONZ_GRAPHICS_SMOKE_SCENE="${OPENTOONZ_GRAPHICS_SMOKE_SCENE:-doc/sample_data/tga_paint.tnz}" \
OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=internal-drawing-gesture \
OPENTOONZ_GRAPHICS_SMOKE_BACKENDS="${OPENTOONZ_GRAPHICS_SMOKE_BACKENDS:-opengl metal}" \
OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY="${OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY:-1}" \
OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_STARTUP_TRACE="${OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_STARTUP_TRACE:-1}" \
OPENTOONZ_GRAPHICS_SMOKE_FRAME="${OPENTOONZ_GRAPHICS_SMOKE_FRAME:-1}" \
OPENTOONZ_GRAPHICS_SMOKE_SECONDS="${OPENTOONZ_GRAPHICS_SMOKE_SECONDS:-25}" \
OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS="${OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS:-1}" \
OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 \
  "$repo_root/scripts/macos/graphics-app-smoke.sh" "$artifact_dir"

"$repo_root/scripts/verify_graphics_app_smoke_artifacts.sh" "$artifact_dir"
"$repo_root/scripts/verify_graphics_app_smoke_artifacts.sh" \
  "$artifact_dir" --require-direct-metal-frame metal

echo "verify-macos-drawing-gesture-app-smoke: ok artifacts=$artifact_dir"
