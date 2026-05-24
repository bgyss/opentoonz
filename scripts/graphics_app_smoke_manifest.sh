#!/usr/bin/env bash
set -euo pipefail

manifest="${1:-doc/macos_graphics_golden_scenes.tsv}"
artifact_root="${2:-${OPENTOONZ_GRAPHICS_SMOKE_MANIFEST_DIR:-/private/tmp/opentoonz-graphics-app-smoke-manifest}}"
fixture_dir="${OPENTOONZ_GRAPHICS_FIXTURE_DIR:-/tmp/opentoonz-graphics-fixtures}"
shaderfx_dir="${OPENTOONZ_SHADERFX_COMPARE_DIR:-/tmp/opentoonz-shaderfx-compare}"

if [[ ! -f "$manifest" ]]; then
  echo "graphics-app-smoke-manifest: missing manifest: $manifest" >&2
  exit 1
fi

mkdir -p "$artifact_root"

if [[ -x scripts/generate_graphics_fixture_scenes.sh ]]; then
  bash scripts/generate_graphics_fixture_scenes.sh "$fixture_dir" >/dev/null
fi

scene_count=0
while IFS=$'\t' read -r id category status path frame validation notes; do
  if [[ "$id" == "id" ]]; then
    continue
  fi
  if [[ "$status" != "repo" && "$status" != "generated" ]]; then
    continue
  fi
  if [[ "$path" != *.tnz ]]; then
    continue
  fi
  if [[ "$status" == "generated" ]]; then
    path="${path/#\/tmp\/opentoonz-graphics-fixtures/$fixture_dir}"
    path="${path/#\/tmp\/opentoonz-shaderfx-compare/$shaderfx_dir}"
  fi
  if [[ ! -f "$path" ]]; then
    if [[ "$status" == "generated" ]]; then
      continue
    fi
    echo "graphics-app-smoke-manifest: missing scene: $path" >&2
    exit 1
  fi
  scene_count=$((scene_count + 1))

  safe_id="$(printf '%s' "$id" | tr -c 'A-Za-z0-9_.-' '_')"
  scene_artifacts="$artifact_root/$safe_id"
  echo "graphics-app-smoke-manifest: scene=$path artifacts=$scene_artifacts"
  OPENTOONZ_GRAPHICS_SMOKE_SCENE="$path" \
  OPENTOONZ_GRAPHICS_SMOKE_FRAME="$frame" \
    bash scripts/macos/graphics-app-smoke.sh "$scene_artifacts"
  verify_args=()
  if [[ "${OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT:-1}" != "0" ]]; then
    verify_args+=(--require-screenshot)
  fi
  bash scripts/verify_graphics_app_smoke_artifacts.sh \
    "$scene_artifacts" "${verify_args[@]}"
done <"$manifest"

if (( scene_count == 0 )); then
  echo "graphics-app-smoke-manifest: no repo or generated .tnz scene rows found in $manifest" >&2
  exit 1
fi

echo "graphics-app-smoke-manifest: ok scenes=$scene_count artifacts=$artifact_root"
