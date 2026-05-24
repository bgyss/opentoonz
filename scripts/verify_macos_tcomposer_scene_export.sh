#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_path="${OPENTOONZ_APP:-$repo_root/toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app}"
artifact_dir="${1:-${OPENTOONZ_TCOMPOSER_EXPORT_DIR:-${TMPDIR:-/tmp}/opentoonz-tcomposer-scene-export}}"
timeout_seconds="${OPENTOONZ_TCOMPOSER_TIMEOUT_SECONDS:-60}"
manifest_path="${OPENTOONZ_TCOMPOSER_MANIFEST:-$repo_root/doc/macos_graphics_golden_scenes.tsv}"
fixture_dir="${OPENTOONZ_GRAPHICS_FIXTURE_DIR:-/tmp/opentoonz-graphics-fixtures}"
include_repo_scenes="${OPENTOONZ_TCOMPOSER_INCLUDE_REPO_SCENES:-0}"
min_nonzero_pixels="${OPENTOONZ_TCOMPOSER_MIN_NONZERO_PIXELS:-1}"

case "$timeout_seconds" in
  ''|*[!0-9]*)
    echo "verify-macos-tcomposer-scene-export: OPENTOONZ_TCOMPOSER_TIMEOUT_SECONDS must be an integer" >&2
    exit 1
    ;;
esac
case "$min_nonzero_pixels" in
  ''|*[!0-9]*)
    echo "verify-macos-tcomposer-scene-export: OPENTOONZ_TCOMPOSER_MIN_NONZERO_PIXELS must be an integer" >&2
    exit 1
    ;;
esac

if [[ ! -d "$app_path" ]]; then
  echo "verify-macos-tcomposer-scene-export: missing app bundle: $app_path" >&2
  echo "build and package it with: cmake --build toonz/build/nix-relwithdebinfo --target tcomposer && scripts/macos/package-nix-app.sh" >&2
  exit 1
fi

tcomposer="$app_path/Contents/MacOS/tcomposer"
toonzroot="$app_path/Contents/Resources/portablestuff"
if [[ ! -x "$tcomposer" ]]; then
  echo "verify-macos-tcomposer-scene-export: missing bundled tcomposer: $tcomposer" >&2
  exit 1
fi
if [[ ! -d "$toonzroot" ]]; then
  echo "verify-macos-tcomposer-scene-export: missing bundled TOONZROOT: $toonzroot" >&2
  exit 1
fi
nonblank_verifier="$repo_root/scripts/verify_tga_nonblank.py"
if [[ ! -x "$nonblank_verifier" ]]; then
  echo "verify-macos-tcomposer-scene-export: missing TGA nonblank verifier: $nonblank_verifier" >&2
  exit 1
fi
timeout_runner="$repo_root/scripts/run_with_timeout.py"
if [[ ! -x "$timeout_runner" ]]; then
  echo "verify-macos-tcomposer-scene-export: missing timeout runner: $timeout_runner" >&2
  exit 1
fi
rm -rf "$artifact_dir"
mkdir -p "$artifact_dir"

if [[ -x "$repo_root/scripts/macos/verify-bundled-qt-runtime.sh" ]]; then
  "$repo_root/scripts/macos/verify-bundled-qt-runtime.sh" "$app_path" \
    >"$artifact_dir/bundled-qt-runtime.txt"
fi

if [[ -x "$repo_root/scripts/generate_graphics_fixture_scenes.sh" ]]; then
  "$repo_root/scripts/generate_graphics_fixture_scenes.sh" "$fixture_dir" \
    >"$artifact_dir/generated-fixtures.txt"
fi

scene_specs=()
if [[ -n "${OPENTOONZ_TCOMPOSER_SCENE:-}" ]]; then
  scene_path="$OPENTOONZ_TCOMPOSER_SCENE"
  if [[ "$scene_path" != /* ]]; then
    scene_path="$repo_root/$scene_path"
  fi
  scene_id="$(basename "$scene_path" .tnz)"
  scene_specs+=("$scene_id|$scene_path|${OPENTOONZ_TCOMPOSER_FRAME:-1}")
else
  if [[ ! -f "$manifest_path" ]]; then
    echo "verify-macos-tcomposer-scene-export: missing manifest: $manifest_path" >&2
    exit 1
  fi
  while IFS=$'\t' read -r scene_id _category status scene_path frame validation _notes; do
    [[ "$scene_id" == "id" || -z "$scene_id" ]] && continue
    if [[ "$validation" != "scripts/verify_macos_tcomposer_scene_export.sh" &&
          !( "$include_repo_scenes" == "1" && "$status" == "repo" ) ]]; then
      continue
    fi
    [[ "$scene_path" == *.tnz ]] || continue
    case "$frame" in
      ''|*[!0-9]*|0)
        echo "verify-macos-tcomposer-scene-export: invalid frame for $scene_id: $frame" >&2
        exit 1
        ;;
    esac
    if [[ "$scene_path" != /* ]]; then
      scene_path="$repo_root/$scene_path"
    fi
    scene_specs+=("$scene_id|$scene_path|$frame")
  done <"$manifest_path"
fi

if [[ "${#scene_specs[@]}" -eq 0 ]]; then
  echo "verify-macos-tcomposer-scene-export: no scene specs selected" >&2
  exit 1
fi

run_backend() {
  local scene_id="$1"
  local scene_path="$2"
  local frame="$3"
  local backend="$4"
  local backend_dir="$artifact_dir/$scene_id/$backend"
  local output_template="$backend_dir/$scene_id.tga"
  local output_frame
  printf -v output_frame '%s/%s.%04d.tga' "$backend_dir" "$scene_id" "$frame"
  mkdir -p "$backend_dir"

  (
    cd "$repo_root"
    OPENTOONZ_GRAPHICS_BACKEND="$backend" \
      "$timeout_runner" "$timeout_seconds" "$tcomposer" "$scene_path" \
        -o "$output_template" -frame "$frame" -nthreads 1 -TOONZROOT "$toonzroot"
  ) >"$backend_dir/tcomposer.log" 2>&1

  if [[ ! -s "$output_frame" ]]; then
    echo "verify-macos-tcomposer-scene-export: missing output frame for $backend: $output_frame" >&2
    echo "verify-macos-tcomposer-scene-export: log: $backend_dir/tcomposer.log" >&2
    exit 1
  fi
  if ! grep -q 'computed' "$backend_dir/tcomposer.log"; then
    echo "verify-macos-tcomposer-scene-export: tcomposer did not report a computed frame for $backend" >&2
    echo "verify-macos-tcomposer-scene-export: log: $backend_dir/tcomposer.log" >&2
    exit 1
  fi
  local image_stats nonzero_pixels
  image_stats="$("$nonblank_verifier" --min-nonzero "$min_nonzero_pixels" \
    "$output_frame")"
  nonzero_pixels="$(awk '
    {
      for (i = 1; i <= NF; ++i) {
        if ($i ~ /^nonzero=/) {
          sub(/^nonzero=/, "", $i)
          print $i
          exit
        }
      }
    }' <<<"$image_stats")"
  if (( nonzero_pixels < min_nonzero_pixels )); then
    echo "verify-macos-tcomposer-scene-export: insufficient nonzero pixels for $backend: $output_frame nonzero_pixels=$nonzero_pixels min=$min_nonzero_pixels" >&2
    echo "verify-macos-tcomposer-scene-export: log: $backend_dir/tcomposer.log" >&2
    exit 1
  fi
  {
    echo "$image_stats"
    echo "nonzero_pixels=$nonzero_pixels"
    echo "min_nonzero_pixels=$min_nonzero_pixels"
  } >"$backend_dir/image-stats.txt"
}

summary_tmp="$artifact_dir/summary.tmp"
: >"$summary_tmp"

for spec in "${scene_specs[@]}"; do
  IFS='|' read -r scene_id scene_path frame <<< "$spec"
  if [[ ! -f "$scene_path" ]]; then
    echo "verify-macos-tcomposer-scene-export: missing scene: $scene_path" >&2
    exit 1
  fi

  run_backend "$scene_id" "$scene_path" "$frame" opengl
  run_backend "$scene_id" "$scene_path" "$frame" metal

  printf -v opengl_output '%s/%s/opengl/%s.%04d.tga' \
    "$artifact_dir" "$scene_id" "$scene_id" "$frame"
  printf -v metal_output '%s/%s/metal/%s.%04d.tga' \
    "$artifact_dir" "$scene_id" "$scene_id" "$frame"
  if ! cmp -s "$opengl_output" "$metal_output"; then
    echo "verify-macos-tcomposer-scene-export: OpenGL and Metal tcomposer exports differ for $scene_id" >&2
    exit 1
  fi

  {
    echo "scene_id=$scene_id"
    echo "scene=$scene_path"
    echo "frame=$frame"
    echo "opengl_output=$opengl_output"
    echo "metal_output=$metal_output"
    sed 's/^/opengl_/' "$artifact_dir/$scene_id/opengl/image-stats.txt"
    sed 's/^/metal_/' "$artifact_dir/$scene_id/metal/image-stats.txt"
    shasum -a 256 "$opengl_output" "$metal_output"
  } >>"$summary_tmp"
done

{
  echo "app_path=$app_path"
  echo "toonzroot=$toonzroot"
  echo "manifest=$manifest_path"
  echo "fixture_dir=$fixture_dir"
  echo "include_repo_scenes=$include_repo_scenes"
  echo "min_nonzero_pixels=$min_nonzero_pixels"
  echo "scene_count=${#scene_specs[@]}"
  cat "$summary_tmp"
} >"$artifact_dir/summary.txt"
rm -f "$summary_tmp"

echo "verify-macos-tcomposer-scene-export: ok artifacts=$artifact_dir"
