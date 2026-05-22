#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:-.}"
shader_dir="$repo_root/stuff/library/shaders"
program_dir="$shader_dir/programs"
metal_dir="$repo_root/toonz/sources/common/tgraphics"

if [[ ! -d "$shader_dir" ]]; then
  echo "shader directory not found: $shader_dir" >&2
  exit 1
fi

echo "OpenToonz graphics shader inventory"
echo "repo_root=$repo_root"
echo

xml_count=$(find "$shader_dir" -maxdepth 1 -type f -name '*.xml' | wc -l | tr -d ' ')
glsl_count=$(find "$program_dir" -type f \( -name '*.frag' -o -name '*.vert' -o -name '*.glsl' \) | wc -l | tr -d ' ')
metal_count=$(find "$metal_dir" -type f -name '*.metal' | wc -l | tr -d ' ')

printf "%-36s %5s\n" "shader interface XML files" "$xml_count"
printf "%-36s %5s\n" "packaged GLSL shader files" "$glsl_count"
printf "%-36s %5s\n" "tgraphics Metal shader files" "$metal_count"
echo

echo "Shader interfaces:"
for xml in "$shader_dir"/*.xml; do
  [[ -e "$xml" ]] || continue
  name=$(basename "$xml")
  programs=$(awk '
    /<ProgramFile>/ { getline; gsub(/[[:space:]"]/, "", $0); print $0 }
  ' "$xml" | paste -sd ',' -)
  ports=$(grep -c '<InputPort>' "$xml" || true)
  bbox=$(grep -c '<BBoxProgram>' "$xml" || true)
  hwt=$(awk '
    /<HandledWorldTransforms>/ { getline; gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); print $0 }
  ' "$xml" | paste -sd ',' -)
  [[ -n "$hwt" ]] || hwt="any"
  printf "  %-22s ports=%s bbox=%s hwt=%s programs=%s\n" "$name" "$ports" "$bbox" "$hwt" "$programs"
done
echo

echo "Shader source classification:"
find "$program_dir" -type f \( -name '*.frag' -o -name '*.vert' -o -name '*.glsl' \) | sort | while read -r shader; do
  rel=${shader#"$repo_root/"}
  lines=$(wc -l < "$shader" | tr -d ' ')
  uniforms=$(grep -c '\buniform\b' "$shader" || true)
  samplers=$(grep -c '\bsampler[123]D\b' "$shader" || true)
  texture_reads=$(grep -c '\btexture2D\b' "$shader" || true)
  varyings=$(grep -c '\bvarying\b' "$shader" || true)
  frag_outputs=$(grep -c '\bgl_FragColor\b' "$shader" || true)

  classification="direct_msl_rewrite_candidate"
  notes="fragment_or_procedural_shader"
  case "$(basename "$shader")" in
    HSLBlendGPU.frag)
      classification="migrated_hand_routed_metal_input"
      notes="has explicit tgraphics Metal helper; GLSL source is still packaged for OpenGL fallback"
      ;;
    radialblurGPU.frag)
      classification="migrated_hand_routed_metal_input"
      notes="has explicit tgraphics Metal helper and ShaderFx Metal route"
      ;;
    spinblurGPU.frag)
      classification="migrated_hand_routed_metal_input"
      notes="has explicit tgraphics Metal helper and ShaderFx Metal route"
      ;;
    glitter.frag)
      classification="migrated_hand_routed_metal_input"
      notes="has explicit tgraphics Metal helper and ShaderFx Metal route"
      ;;
    *_ports.vert|*_bbox.vert)
      classification="blocked_by_opengl_transform_feedback"
      notes="ShaderFx uses GL transform feedback varyings for geometry/bbox"
      ;;
    *.frag)
      if [[ "$samplers" != "0" || "$texture_reads" != "0" ]]; then
        classification="shared_shader_generation_candidate"
        notes="samples inputImage with OpenGL GLSL texture/matrix conventions"
      else
        classification="direct_msl_rewrite_candidate"
        notes="procedural fragment shader without input texture sampling"
      fi
      ;;
  esac

  printf "  %-58s class=%-35s lines=%3s uniforms=%2s samplers=%2s texture2D=%2s varying=%2s gl_FragColor=%2s note=%s\n" \
    "$rel" "$classification" "$lines" "$uniforms" "$samplers" "$texture_reads" "$varyings" "$frag_outputs" "$notes"
done
echo

echo "OpenGL shader call sites:"
for pattern in QOpenGLShader QOpenGLShaderProgram glTransformFeedbackVaryings glGetBufferSubData; do
  matches=$(grep -R --include='*.cpp' --include='*.h' -n "$pattern" "$repo_root/toonz/sources" | wc -l | tr -d ' ')
  printf "  %-32s %5s\n" "$pattern" "$matches"
done
