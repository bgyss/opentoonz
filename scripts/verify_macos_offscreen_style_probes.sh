#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${BUILD_DIR:-$repo_root/toonz/build/nix-relwithdebinfo}"
tofflinegl_probe="${TOFFLINEGL_PROBE:-$build_dir/tnzcore/tofflinegl_probe}"
style_probe="${STYLEEDITOR_COLORWHEEL_PROBE:-$build_dir/toonzqt/styleeditor_colorwheel_probe}"
runtime_dir="${OPENTOONZ_OFFSCREEN_STYLE_PROBE_RUNTIME_DIR:-${TMPDIR:-/tmp}/opentoonz-offscreen-style-probes-$$}"
if [[ -z "${OPENTOONZ_OFFSCREEN_STYLE_PROBE_RUNTIME_DIR:-}" ]]; then
  trap 'rm -rf "$runtime_dir"' EXIT
fi

if [[ ! -x "$tofflinegl_probe" ]]; then
  echo "verify-macos-offscreen-style-probes: missing probe: $tofflinegl_probe" >&2
  echo "build it with: cmake --build $build_dir --target tofflinegl_probe" >&2
  exit 1
fi

if [[ ! -x "$style_probe" ]]; then
  echo "verify-macos-offscreen-style-probes: missing probe: $style_probe" >&2
  echo "build it with: cmake --build $build_dir --target styleeditor_colorwheel_probe" >&2
  exit 1
fi

(
  cd "$repo_root"
  OPENTOONZ_GRAPHICS_BACKEND=opengl "$tofflinegl_probe"
  OPENTOONZ_GRAPHICS_BACKEND=metal "$tofflinegl_probe"
  mkdir -p "$runtime_dir/profiles" "$runtime_dir/config"
  (
    cd "$runtime_dir"
    TOONZROOT="$runtime_dir" \
      TOONZPROFILES="$runtime_dir/profiles" \
      TOONZCONFIG="$runtime_dir/config" \
      QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}" \
      "$style_probe"
  )
)

echo "verify-macos-offscreen-style-probes: ok"
