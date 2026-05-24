#!/usr/bin/env bash
set -euo pipefail

app_path="${1:-${OPENTOONZ_APP:-toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app}}"
resources_dir="$app_path/Contents/Resources"
source_resource="$resources_dir/tgraphics_metal_shaders.metal"
library_resource="$resources_dir/tgraphics_metal_shaders.metallib"
summary_file="${OPENTOONZ_METAL_RESOURCE_SUMMARY:-}"
status="unknown"
message=""

write_summary() {
  [[ -n "$summary_file" ]] || return 0
  mkdir -p "$(dirname "$summary_file")"
  {
    echo "app_path=$app_path"
    echo "source_resource=$source_resource"
    echo "source_present=$([[ -f "$source_resource" ]] && echo 1 || echo 0)"
    echo "source_bytes=$([[ -f "$source_resource" ]] && wc -c <"$source_resource" | tr -d '[:space:]' || echo 0)"
    echo "library_resource=$library_resource"
    echo "library_present=$([[ -f "$library_resource" ]] && echo 1 || echo 0)"
    echo "library_bytes=$([[ -f "$library_resource" ]] && wc -c <"$library_resource" | tr -d '[:space:]' || echo 0)"
    echo "metal_tool=$(xcrun --find metal 2>/dev/null || true)"
    echo "metallib_tool=$(xcrun --find metallib 2>/dev/null || true)"
    echo "status=$status"
    echo "message=$message"
  } >"$summary_file"
}

trap write_summary EXIT

if [[ ! -d "$resources_dir" ]]; then
  status="error"
  message="app resources directory not found"
  echo "error: app resources directory not found: $resources_dir" >&2
  exit 1
fi

if [[ ! -f "$source_resource" ]]; then
  status="error"
  message="Metal shader source resource missing"
  echo "error: Metal shader source resource is missing: $source_resource" >&2
  exit 1
fi

if xcrun --find metal >/dev/null 2>&1 &&
   xcrun --find metallib >/dev/null 2>&1 &&
   xcrun metal -v >/dev/null 2>&1; then
  if [[ ! -f "$library_resource" ]]; then
    status="error"
    message="Metal toolchain available but metallib missing"
    echo "error: Metal toolchain is available, but metallib resource is missing: $library_resource" >&2
    exit 1
  fi
  status="source-and-metallib"
  message="Metal shader resources present: source and metallib"
  echo "$message"
else
  status="source-only-toolchain-unavailable"
  message="Metal shader source resource present; metallib build skipped because the Metal toolchain is unavailable"
  echo "$message"
fi
