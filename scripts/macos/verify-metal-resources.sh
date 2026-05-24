#!/usr/bin/env bash
set -euo pipefail

app_path="${1:-${OPENTOONZ_APP:-toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app}}"
repo_root="${OPENTOONZ_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
resources_dir="$app_path/Contents/Resources"
source_resource="$resources_dir/tgraphics_metal_shaders.metal"
repo_source="$repo_root/toonz/sources/common/tgraphics/tgraphics_metal_shaders.metal"
library_resource="$resources_dir/tgraphics_metal_shaders.metallib"
summary_file="${OPENTOONZ_METAL_RESOURCE_SUMMARY:-}"
require_metallib="${OPENTOONZ_REQUIRE_METALLIB:-0}"
status="unknown"
message=""
metal_toolchain_available=0

file_hash() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo 0
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    echo unavailable
  fi
}

write_summary() {
  [[ -n "$summary_file" ]] || return 0
  mkdir -p "$(dirname "$summary_file")"
  {
    echo "app_path=$app_path"
    echo "repo_source=$repo_source"
    echo "repo_source_present=$([[ -f "$repo_source" ]] && echo 1 || echo 0)"
    echo "repo_source_bytes=$([[ -f "$repo_source" ]] && wc -c <"$repo_source" | tr -d '[:space:]' || echo 0)"
    echo "repo_source_sha256=$(file_hash "$repo_source")"
    echo "source_resource=$source_resource"
    echo "source_present=$([[ -f "$source_resource" ]] && echo 1 || echo 0)"
    echo "source_bytes=$([[ -f "$source_resource" ]] && wc -c <"$source_resource" | tr -d '[:space:]' || echo 0)"
    echo "source_sha256=$(file_hash "$source_resource")"
    echo "library_resource=$library_resource"
    echo "library_present=$([[ -f "$library_resource" ]] && echo 1 || echo 0)"
    echo "library_bytes=$([[ -f "$library_resource" ]] && wc -c <"$library_resource" | tr -d '[:space:]' || echo 0)"
    echo "require_metallib=$require_metallib"
    echo "metal_toolchain_available=$metal_toolchain_available"
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

if [[ ! -f "$repo_source" ]]; then
  status="error"
  message="repository Metal shader source missing"
  echo "error: repository Metal shader source is missing: $repo_source" >&2
  exit 1
fi

if ! cmp -s "$repo_source" "$source_resource"; then
  status="error"
  message="bundled Metal shader source differs from repository source"
  echo "error: bundled Metal shader source differs from repository source" >&2
  echo "repo: $repo_source" >&2
  echo "bundle: $source_resource" >&2
  exit 1
fi

if xcrun --find metal >/dev/null 2>&1 &&
   xcrun --find metallib >/dev/null 2>&1 &&
   xcrun metal -v >/dev/null 2>&1; then
  metal_toolchain_available=1
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
  if [[ "$require_metallib" == "1" && ! -f "$library_resource" ]]; then
    status="error"
    message="required Metal shader metallib missing"
    echo "error: required Metal shader metallib is missing: $library_resource" >&2
    exit 1
  fi
  status="source-only-toolchain-unavailable"
  message="Metal shader source resource present; metallib build skipped because the Metal toolchain is unavailable"
  echo "$message"
fi
