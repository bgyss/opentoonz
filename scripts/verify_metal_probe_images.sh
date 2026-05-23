#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
probe="${OPENTOONZ_METAL_PROBE:-$repo_root/toonz/build/nix-relwithdebinfo/tnzcore/tgraphics_metal_probe}"
artifact_dir="${1:-${OPENTOONZ_METAL_PROBE_IMAGE_DIR:-/private/tmp/opentoonz-metal-probe-images}}"
summary_file="$artifact_dir/summary.txt"

if [[ ! -x "$probe" ]]; then
  echo "verify-metal-probe-images: missing probe binary: $probe" >&2
  echo "build it with: cmake --build toonz/build/nix-relwithdebinfo --target tgraphics_metal_probe" >&2
  exit 1
fi

mkdir -p "$artifact_dir"
find "$artifact_dir" -maxdepth 1 -type f \
  \( -name '*_metal.png' -o -name '*_opengl.png' -o -name '*_diff.png' -o -name 'summary.txt' \) \
  -delete
"$probe" --write-images "$artifact_dir"

mapfile -t metal_images < <(find "$artifact_dir" -maxdepth 1 -type f -name '*_metal.png' | sort)
mapfile -t opengl_images < <(find "$artifact_dir" -maxdepth 1 -type f -name '*_opengl.png' | sort)
mapfile -t diff_images < <(find "$artifact_dir" -maxdepth 1 -type f -name '*_diff.png' | sort)
if (( ${#metal_images[@]} == 0 )); then
  echo "verify-metal-probe-images: no *_metal.png files written in $artifact_dir" >&2
  exit 1
fi

if (( ${#metal_images[@]} != ${#opengl_images[@]} ||
      ${#metal_images[@]} != ${#diff_images[@]} )); then
  echo "verify-metal-probe-images: mismatched artifact counts in $artifact_dir" >&2
  echo "  metal=${#metal_images[@]} opengl=${#opengl_images[@]} diff=${#diff_images[@]}" >&2
  exit 1
fi

missing=0
{
  echo "artifact_dir=$artifact_dir"
  echo "probe=$probe"
  echo "case_count=${#metal_images[@]}"
  echo "metal_image_count=${#metal_images[@]}"
  echo "opengl_image_count=${#opengl_images[@]}"
  echo "diff_image_count=${#diff_images[@]}"
} >"$summary_file"

for metal_image in "${metal_images[@]}"; do
  case_name="$(basename "$metal_image" _metal.png)"
  opengl_image="$artifact_dir/${case_name}_opengl.png"
  diff_image="$artifact_dir/${case_name}_diff.png"

  for image in "$metal_image" "$opengl_image" "$diff_image"; do
    if [[ ! -s "$image" ]]; then
      echo "verify-metal-probe-images: missing or empty image: $image" >&2
      missing=1
      continue
    fi
    if command -v file >/dev/null 2>&1; then
      file "$image" >>"$summary_file"
    else
      echo "$image" >>"$summary_file"
    fi
    if command -v shasum >/dev/null 2>&1; then
      shasum -a 256 "$image" >>"$summary_file"
    fi
  done
done

if (( missing != 0 )); then
  exit 1
fi

echo "verify-metal-probe-images: cases=${#metal_images[@]} artifacts=$artifact_dir"
echo "verify-metal-probe-images: summary=$summary_file"
