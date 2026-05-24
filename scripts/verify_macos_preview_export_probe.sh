#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${BUILD_DIR:-$repo_root/toonz/build/nix-relwithdebinfo}"
tofflinegl_probe="${TOFFLINEGL_PROBE:-$build_dir/tnzcore/tofflinegl_probe}"
artifact_dir="${1:-${OPENTOONZ_PREVIEW_EXPORT_PROBE_DIR:-${TMPDIR:-/tmp}/opentoonz-preview-export-probe}}"

if [[ ! -x "$tofflinegl_probe" ]]; then
  echo "verify-macos-preview-export-probe: missing probe: $tofflinegl_probe" >&2
  echo "build it with: cmake --build $build_dir --target tofflinegl_probe" >&2
  exit 1
fi

rm -rf "$artifact_dir"
mkdir -p "$artifact_dir/opengl" "$artifact_dir/metal"

(
  cd "$repo_root"
  OPENTOONZ_GRAPHICS_BACKEND=opengl "$tofflinegl_probe" \
    --write-preview-export-images "$artifact_dir/opengl"
  OPENTOONZ_GRAPHICS_BACKEND=metal "$tofflinegl_probe" \
    --write-preview-export-images "$artifact_dir/metal"
)

required_files=(
  opengl/preview_export_opengl.png
  opengl/preview_export_legacy_opengl.png
  opengl/preview_export_opengl_diff.png
  metal/preview_export_metal.png
  metal/preview_export_legacy_opengl.png
  metal/preview_export_metal_diff.png
)

for file in "${required_files[@]}"; do
  if [[ ! -s "$artifact_dir/$file" ]]; then
    echo "verify-macos-preview-export-probe: missing artifact: $artifact_dir/$file" >&2
    exit 1
  fi
done

python3 "$repo_root/scripts/verify_png_nonblank.py" \
  "$artifact_dir/opengl/preview_export_opengl.png" \
  "$artifact_dir/metal/preview_export_metal.png" \
  "$artifact_dir/opengl/preview_export_legacy_opengl.png" \
  "$artifact_dir/metal/preview_export_legacy_opengl.png"

python3 "$repo_root/scripts/verify_png_match.py" \
  --max-mean-delta 0 \
  --max-channel-delta 0 \
  --max-differing-ratio 0 \
  "$artifact_dir/opengl/preview_export_legacy_opengl.png" \
  "$artifact_dir/metal/preview_export_metal.png"

echo "verify-macos-preview-export-probe: ok artifacts=$artifact_dir"
