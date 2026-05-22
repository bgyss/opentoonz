#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-toonz/sources}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: ripgrep (rg) is required" >&2
  exit 1
fi

if [[ ! -d "$ROOT" ]]; then
  echo "error: source root not found: $ROOT" >&2
  exit 1
fi

RG_CODE_GLOBS=(
  --glob '*.c'
  --glob '*.cc'
  --glob '*.cpp'
  --glob '*.cxx'
  --glob '*.h'
  --glob '*.hh'
  --glob '*.hpp'
  --glob '*.m'
  --glob '*.mm'
  --glob '*.frag'
  --glob '*.glsl'
  --glob '*.metal'
)

count_files() {
  local pattern="$1"
  local matches
  matches="$(rg "${RG_CODE_GLOBS[@]}" -l -e "$pattern" "$ROOT" || true)"
  if [[ -z "$matches" ]]; then
    echo 0
  else
    printf '%s\n' "$matches" | wc -l | tr -d '[:space:]'
  fi
}

count_matches() {
  local pattern="$1"
  local matches
  matches="$(rg "${RG_CODE_GLOBS[@]}" -n -e "$pattern" "$ROOT" || true)"
  if [[ -z "$matches" ]]; then
    echo 0
  else
    printf '%s\n' "$matches" | wc -l | tr -d '[:space:]'
  fi
}

print_metric() {
  local name="$1"
  local pattern="$2"
  printf '%-34s files=%5s matches=%6s\n' \
    "$name" "$(count_files "$pattern")" "$(count_matches "$pattern")"
}

combined_pattern='QGL[A-Za-z0-9_]*|QGLWidget::convertToGLFormat|QOpenGL[A-Za-z0-9_]*|GLEW|GLUT|glu[A-Z][A-Za-z0-9_]*|GLU_[A-Z0-9_]+|gl(Begin|End|Vertex[0-9A-Za-z]*|Color[0-9A-Za-z]*|TexCoord[0-9A-Za-z]*|MatrixMode|LoadIdentity|PushMatrix|PopMatrix|Ortho|Frustum|DrawPixels|RenderMode|SelectBuffer|InitNames|PushName|PopName|LoadName)|GL_SELECT'

echo "OpenToonz graphics API inventory"
echo "source_root=$ROOT"
echo

print_metric "all graphics markers" "$combined_pattern"
print_metric "Qt legacy QGL" 'QGL[A-Za-z0-9_]*|QGLWidget::convertToGLFormat'
print_metric "Qt QOpenGL" 'QOpenGL[A-Za-z0-9_]*'
print_metric "GLU" 'glu[A-Z][A-Za-z0-9_]*|GLU_[A-Z0-9_]+'
print_metric "GLEW or GLUT" 'GLEW|GLUT'
print_metric "fixed-function drawing" 'gl(Begin|End|Vertex[0-9A-Za-z]*|Color[0-9A-Za-z]*|TexCoord[0-9A-Za-z]*)'
print_metric "fixed-function matrix" 'gl(MatrixMode|LoadIdentity|PushMatrix|PopMatrix|Ortho|Frustum)'
print_metric "glDrawPixels" 'glDrawPixels'
print_metric "OpenGL selection" 'gl(RenderMode|SelectBuffer|InitNames|PushName|PopName|LoadName)|GL_SELECT'

echo
echo "Top files by graphics marker matches:"
top_matches="$(rg "${RG_CODE_GLOBS[@]}" -n -e "$combined_pattern" "$ROOT" || true)"
if [[ -z "$top_matches" ]]; then
  echo "  none"
else
  printf '%s\n' "$top_matches" \
    | cut -d: -f1 \
    | sort \
    | uniq -c \
    | sort -nr \
    | head -n 20 \
    | sed 's/^/  /'
fi
