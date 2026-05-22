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
  for shader in SHADER_sunflare SHADER_caustics SHADER_starsky SHADER_wavy SHADER_fireball; do
    shader_tolerance="$tolerance"
    if [[ "$shader" == "SHADER_fireball" ]]; then
      shader_tolerance="${SHADERFX_FIREBALL_COMPARE_TOLERANCE:-32}"
    fi

    stem="${shader#SHADER_}"
    opengl_pam="$artifact_dir/$stem-opengl.pam"
    metal_pam="$artifact_dir/$stem-metal.pam"
    diff_pam="$artifact_dir/$stem-diff.pam"
    opengl_scene_pam="$artifact_dir/$stem-opengl-scene.pam"
    metal_scene_pam="$artifact_dir/$stem-metal-scene.pam"
    scene_diff_pam="$artifact_dir/$stem-scene-diff.pam"
    opengl_saved_scene_pam="$artifact_dir/$stem-opengl-saved-scene.pam"
    metal_saved_scene_pam="$artifact_dir/$stem-metal-saved-scene.pam"
    saved_scene_diff_pam="$artifact_dir/$stem-saved-scene-diff.pam"
    opengl_saved_scene="$artifact_dir/$stem-opengl.tnz"
    metal_saved_scene="$artifact_dir/$stem-metal.tnz"

    OPENTOONZ_GRAPHICS_BACKEND=opengl "$probe" \
      --shader "$shader" \
      --write-pam "$opengl_pam"
    OPENTOONZ_GRAPHICS_BACKEND=metal "$probe" \
      --shader "$shader" \
      --compare-pam "$opengl_pam" \
      --write-pam "$metal_pam" \
      --write-diff-pam "$diff_pam" \
      --tolerance "$shader_tolerance"
    OPENTOONZ_GRAPHICS_BACKEND=metal "$probe" \
      --shader "$shader" \
      --renderer \
      --write-pam "$artifact_dir/$stem-metal-renderer.pam"
    OPENTOONZ_GRAPHICS_BACKEND=opengl "$probe" \
      --shader "$shader" \
      --scene-render \
      --write-pam "$opengl_scene_pam"
    OPENTOONZ_GRAPHICS_BACKEND=metal "$probe" \
      --shader "$shader" \
      --scene-render \
      --compare-pam "$opengl_scene_pam" \
      --write-pam "$metal_scene_pam" \
      --write-diff-pam "$scene_diff_pam" \
      --tolerance "$shader_tolerance"
    OPENTOONZ_GRAPHICS_BACKEND=opengl "$probe" \
      --shader "$shader" \
      --scene-render \
      --save-load-scene "$opengl_saved_scene" \
      --write-pam "$opengl_saved_scene_pam"
    OPENTOONZ_GRAPHICS_BACKEND=metal "$probe" \
      --shader "$shader" \
      --scene-render \
      --save-load-scene "$metal_saved_scene" \
      --compare-pam "$opengl_saved_scene_pam" \
      --write-pam "$metal_saved_scene_pam" \
      --write-diff-pam "$saved_scene_diff_pam" \
      --tolerance "$shader_tolerance"
  done

  OPENTOONZ_GRAPHICS_BACKEND=metal "$probe" \
    --shader SHADER_HSLBlendGPU \
    --write-pam "$artifact_dir/HSLBlendGPU-metal.pam"
  OPENTOONZ_GRAPHICS_BACKEND=metal "$probe" \
    --shader SHADER_HSLBlendGPU \
    --renderer \
    --write-pam "$artifact_dir/HSLBlendGPU-metal-renderer.pam"
  OPENTOONZ_GRAPHICS_BACKEND=metal "$probe" \
    --shader SHADER_HSLBlendGPU \
    --scene-render \
    --write-pam "$artifact_dir/HSLBlendGPU-metal-scene.pam"
  OPENTOONZ_GRAPHICS_BACKEND=metal "$probe" \
    --shader SHADER_HSLBlendGPU \
    --scene-render \
    --save-load-scene "$artifact_dir/HSLBlendGPU-metal.tnz" \
    --write-pam "$artifact_dir/HSLBlendGPU-metal-saved-scene.pam"
  OPENTOONZ_GRAPHICS_BACKEND=metal "$probe" \
    --shader SHADER_radialblurGPU \
    --write-pam "$artifact_dir/radialblurGPU-metal.pam"
  OPENTOONZ_GRAPHICS_BACKEND=metal "$probe" \
    --shader SHADER_radialblurGPU \
    --renderer \
    --write-pam "$artifact_dir/radialblurGPU-metal-renderer.pam"
  OPENTOONZ_GRAPHICS_BACKEND=metal "$probe" \
    --shader SHADER_radialblurGPU \
    --scene-render \
    --write-pam "$artifact_dir/radialblurGPU-metal-scene.pam"
  OPENTOONZ_GRAPHICS_BACKEND=metal "$probe" \
    --shader SHADER_radialblurGPU \
    --scene-render \
    --save-load-scene "$artifact_dir/radialblurGPU-metal.tnz" \
    --write-pam "$artifact_dir/radialblurGPU-metal-saved-scene.pam"
  OPENTOONZ_GRAPHICS_BACKEND=metal "$probe" \
    --shader SHADER_spinblurGPU \
    --write-pam "$artifact_dir/spinblurGPU-metal.pam"
  OPENTOONZ_GRAPHICS_BACKEND=metal "$probe" \
    --shader SHADER_spinblurGPU \
    --renderer \
    --write-pam "$artifact_dir/spinblurGPU-metal-renderer.pam"
  OPENTOONZ_GRAPHICS_BACKEND=metal "$probe" \
    --shader SHADER_spinblurGPU \
    --scene-render \
    --write-pam "$artifact_dir/spinblurGPU-metal-scene.pam"
  OPENTOONZ_GRAPHICS_BACKEND=metal "$probe" \
    --shader SHADER_spinblurGPU \
    --scene-render \
    --save-load-scene "$artifact_dir/spinblurGPU-metal.tnz" \
    --write-pam "$artifact_dir/spinblurGPU-metal-saved-scene.pam"
)

echo "graphics_shaderfx_compare: ok"
echo "  artifacts: $artifact_dir"
