#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-doc/sample_data}"

if [[ ! -d "$ROOT" ]]; then
  echo "verify-sample-data: missing sample data directory: $ROOT" >&2
  exit 1
fi

required_files=(
  LICENSE
  README.md
  cleanup.tnz
  dwanko_run.tnz
  tga_paint.tnz
  BG/01_sky.tif
  BG/02_trees.tif
  BG/03_ground.tif
  dwanko/A_colormodel.tlv
  dwanko/A_colormodel.tpl
  dwanko/A_erased.tlv
  dwanko/A_painted.tlv
  dwanko/scan/A.0001.tif
  dwanko/scan/A.0006.tif
  dwanko/scan/A.cln
  dwanko/tga/A_0001.tga
  dwanko/tga/A_0006.tga
  dwanko/tga/A_colormodel.png
  dwanko/tga/A_converted.tlv
  dwanko/tga/A_converted.tpl
  other_materials/raylit_source.pli
  other_materials/shadow.pli
)

fail=0
for file in "${required_files[@]}"; do
  path="$ROOT/$file"
  if [[ ! -s "$path" ]]; then
    echo "verify-sample-data: missing or empty required file: $path" >&2
    fail=1
  fi
done

if ! grep -q "CC BY-NC 4.0" "$ROOT/LICENSE"; then
  echo "verify-sample-data: LICENSE does not mention CC BY-NC 4.0" >&2
  fail=1
fi

if ! grep -q "DWANGO Co., Ltd. 2018" "$ROOT/LICENSE"; then
  echo "verify-sample-data: LICENSE does not mention DWANGO copyright" >&2
  fail=1
fi

for scene in cleanup.tnz dwanko_run.tnz tga_paint.tnz; do
  scene_path="$ROOT/$scene"
  if [[ -s "$scene_path" ]] && ! grep -q '\$scenefolder' "$scene_path"; then
    echo "verify-sample-data: scene is not relocatable via \$scenefolder: $scene_path" >&2
    fail=1
  fi
done

while IFS= read -r scene_ref; do
  ref="${scene_ref#\"\$scenefolder\\\\}"
  ref="${ref%\"}"
  ref="${ref//\\\\//}"
  path="$ROOT/$ref"

  if [[ "$ref" == *"..tif" ]]; then
    sequence_prefix="${path%..tif}"
    if ! compgen -G "${sequence_prefix}.*.tif" >/dev/null; then
      echo "verify-sample-data: unresolved scene sequence: $scene_ref" >&2
      fail=1
    fi
  elif [[ ! -e "$path" ]]; then
    echo "verify-sample-data: unresolved scene dependency: $scene_ref" >&2
    fail=1
  fi
done < <(grep -hEo '"\$scenefolder\\\\[^"]+"' \
  "$ROOT/cleanup.tnz" "$ROOT/dwanko_run.tnz" "$ROOT/tga_paint.tnz" | sort -u)

if (( fail != 0 )); then
  exit 1
fi

echo "verify-sample-data: ok"
