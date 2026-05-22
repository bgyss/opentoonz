#!/usr/bin/env bash
set -euo pipefail

app_path="${1:-${OPENTOONZ_APP:-toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app}}"
resources_dir="$app_path/Contents/Resources"
source_resource="$resources_dir/tgraphics_metal_shaders.metal"
library_resource="$resources_dir/tgraphics_metal_shaders.metallib"

if [[ ! -d "$resources_dir" ]]; then
  echo "error: app resources directory not found: $resources_dir" >&2
  exit 1
fi

if [[ ! -f "$source_resource" ]]; then
  echo "error: Metal shader source resource is missing: $source_resource" >&2
  exit 1
fi

if xcrun --find metal >/dev/null 2>&1 &&
   xcrun --find metallib >/dev/null 2>&1 &&
   xcrun metal -v >/dev/null 2>&1; then
  if [[ ! -f "$library_resource" ]]; then
    echo "error: Metal toolchain is available, but metallib resource is missing: $library_resource" >&2
    exit 1
  fi
  echo "Metal shader resources present: source and metallib"
else
  echo "Metal shader source resource present; metallib build skipped because the Metal toolchain is unavailable"
fi
