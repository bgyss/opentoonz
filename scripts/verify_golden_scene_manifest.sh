#!/usr/bin/env bash
set -euo pipefail

require_complete=0
manifest="doc/macos_graphics_golden_scenes.tsv"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --require-complete)
      require_complete=1
      shift
      ;;
    --help|-h)
      echo "usage: verify_golden_scene_manifest.sh [--require-complete] [manifest.tsv]"
      exit 0
      ;;
    *)
      manifest="$1"
      shift
      ;;
  esac
done

if [[ ! -f "$manifest" ]]; then
  echo "verify-golden-scene-manifest: missing manifest: $manifest" >&2
  exit 1
fi

required_categories=(
  raster
  vector
  palette-style
  mesh-skeleton
  camera-overlays
  onion-skin
  sub-xsheet
  shader-effects
  offscreen-render
)

declare -A seen=()
required_rows=0
line_number=0
while IFS=$'\t' read -r id category status path frame validation notes; do
  line_number=$((line_number + 1))
  if (( line_number == 1 )); then
    expected_header=$'id\tcategory\tstatus\tpath\tframe\tvalidation\tnotes'
    actual_header="${id}"$'\t'"${category}"$'\t'"${status}"$'\t'"${path}"$'\t'"${frame}"$'\t'"${validation}"$'\t'"${notes}"
    if [[ "$actual_header" != "$expected_header" ]]; then
      echo "verify-golden-scene-manifest: unexpected header in $manifest" >&2
      exit 1
    fi
    continue
  fi

  if [[ -z "${id:-}" || -z "${category:-}" || -z "${status:-}" ||
        -z "${path:-}" || -z "${frame:-}" || -z "${validation:-}" ]]; then
    echo "verify-golden-scene-manifest: incomplete row $line_number" >&2
    exit 1
  fi

  case "$status" in
    repo|generated) ;;
    required)
      required_rows=$((required_rows + 1))
      ;;
    *)
      echo "verify-golden-scene-manifest: unsupported status '$status' on row $line_number" >&2
      exit 1
      ;;
  esac

  case "$frame" in
    ''|*[!0-9]*)
      echo "verify-golden-scene-manifest: non-integer frame '$frame' on row $line_number" >&2
      exit 1
      ;;
  esac

  if [[ "$status" == "repo" && ! -f "$path" ]]; then
    echo "verify-golden-scene-manifest: repo fixture does not exist: $path" >&2
    exit 1
  fi

  seen["$category"]=1
done <"$manifest"

missing=0
for category in "${required_categories[@]}"; do
  if [[ -z "${seen[$category]:-}" ]]; then
    echo "verify-golden-scene-manifest: missing category: $category" >&2
    missing=1
  fi
done

if (( missing != 0 )); then
  exit 1
fi

if (( require_complete != 0 && required_rows != 0 )); then
  echo "verify-golden-scene-manifest: $required_rows required fixture gap(s) remain" >&2
  echo "verify-golden-scene-manifest: replace status=required rows before defaulting Metal" >&2
  exit 1
fi

echo "verify-golden-scene-manifest: ok"
