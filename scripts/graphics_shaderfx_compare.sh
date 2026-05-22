#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${BUILD_DIR:-$repo_root/toonz/build/nix-relwithdebinfo}"
probe="${SHADERFX_PROBE:-$build_dir/stdfx/shaderfx_metal_probe}"
artifact_dir="${1:-/private/tmp/opentoonz-shaderfx-compare}"
tolerance="${SHADERFX_COMPARE_TOLERANCE:-2}"

mkdir -p "$artifact_dir"

if [[ ! -x "$probe" ]]; then
  echo "graphics_shaderfx_compare: missing probe: $probe" >&2
  echo "build it with: cmake --build $build_dir --target shaderfx_metal_probe" >&2
  exit 1
fi

(
  cd "$repo_root"
  for shader in SHADER_sunflare SHADER_caustics SHADER_starsky; do
    stem="${shader#SHADER_}"
    opengl_pam="$artifact_dir/$stem-opengl.pam"
    metal_pam="$artifact_dir/$stem-metal.pam"
    diff_pam="$artifact_dir/$stem-diff.pam"

    OPENTOONZ_GRAPHICS_BACKEND=opengl "$probe" \
      --shader "$shader" \
      --write-pam "$opengl_pam"
    OPENTOONZ_GRAPHICS_BACKEND=metal "$probe" \
      --shader "$shader" \
      --compare-pam "$opengl_pam" \
      --write-pam "$metal_pam" \
      --write-diff-pam "$diff_pam" \
      --tolerance "$tolerance"
  done
)

echo "graphics_shaderfx_compare: ok"
echo "  artifacts: $artifact_dir"
