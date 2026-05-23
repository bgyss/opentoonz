#!/usr/bin/env bash
set -euo pipefail

artifact_dir="${1:-/private/tmp/opentoonz-shaderfx-compare}"
summary_file="$artifact_dir/shaderfx-scene-fixtures-summary.txt"

expected_scenes=(
  HSLBlendGPU-metal.tnz
  radialblurGPU-metal.tnz
  spinblurGPU-metal.tnz
  glitter-metal.tnz
)

expected_pams=(
  HSLBlendGPU-metal-saved-scene.pam
  radialblurGPU-metal-saved-scene.pam
  spinblurGPU-metal-saved-scene.pam
  glitter-metal-saved-scene.pam
)

if [[ ! -d "$artifact_dir" ]]; then
  echo "verify-shaderfx-scene-fixtures: missing artifact directory: $artifact_dir" >&2
  echo "run: nix develop path:. --command bash scripts/graphics_shaderfx_compare.sh $artifact_dir" >&2
  exit 1
fi

missing=0
{
  echo "artifact_dir=$artifact_dir"
  echo "scene_count=${#expected_scenes[@]}"
  echo "pam_count=${#expected_pams[@]}"
} >"$summary_file"

for file_name in "${expected_scenes[@]}" "${expected_pams[@]}"; do
  path="$artifact_dir/$file_name"
  if [[ ! -s "$path" ]]; then
    echo "verify-shaderfx-scene-fixtures: missing or empty artifact: $path" >&2
    missing=1
    continue
  fi
  if command -v file >/dev/null 2>&1; then
    file "$path" >>"$summary_file"
  else
    echo "$path" >>"$summary_file"
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" >>"$summary_file"
  fi
done

if (( missing != 0 )); then
  exit 1
fi

echo "verify-shaderfx-scene-fixtures: scenes=${#expected_scenes[@]} pams=${#expected_pams[@]} artifacts=$artifact_dir"
echo "verify-shaderfx-scene-fixtures: summary=$summary_file"
