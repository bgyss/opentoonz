#!/usr/bin/env bash
set -euo pipefail

manifest="${1:-doc/macos_graphics_golden_scenes.tsv}"
artifact_root="${2:-${OPENTOONZ_GRAPHICS_SMOKE_MANIFEST_DIR:-/private/tmp/opentoonz-graphics-app-smoke-manifest}}"

if [[ ! -f "$manifest" ]]; then
  echo "graphics-app-smoke-manifest: missing manifest: $manifest" >&2
  exit 1
fi

mkdir -p "$artifact_root"

declare -A seen_paths=()
scene_count=0
while IFS=$'\t' read -r id category status path frame validation notes; do
  if [[ "$id" == "id" ]]; then
    continue
  fi
  if [[ "$status" != "repo" || "$path" != *.tnz ]]; then
    continue
  fi
  if [[ -n "${seen_paths[$path]:-}" ]]; then
    continue
  fi
  seen_paths["$path"]=1
  scene_count=$((scene_count + 1))

  safe_id="$(printf '%s' "$id" | tr -c 'A-Za-z0-9_.-' '_')"
  scene_artifacts="$artifact_root/$safe_id"
  echo "graphics-app-smoke-manifest: scene=$path artifacts=$scene_artifacts"
  OPENTOONZ_GRAPHICS_SMOKE_SCENE="$path" \
    bash scripts/macos/graphics-app-smoke.sh "$scene_artifacts"
  bash scripts/verify_graphics_app_smoke_artifacts.sh "$scene_artifacts"
done <"$manifest"

if (( scene_count == 0 )); then
  echo "graphics-app-smoke-manifest: no committed .tnz scene rows found in $manifest" >&2
  exit 1
fi

echo "graphics-app-smoke-manifest: ok scenes=$scene_count artifacts=$artifact_root"
