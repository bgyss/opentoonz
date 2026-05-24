#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-toonz/sources}"

if ! command -v rg >/dev/null 2>&1; then
  echo "verify-opengl-selection-compatibility: rg is required" >&2
  exit 1
fi

if [[ ! -d "$ROOT" ]]; then
  echo "verify-opengl-selection-compatibility: source root not found: $ROOT" >&2
  exit 1
fi

pattern='gl(RenderMode|SelectBuffer|InitNames|PushName|PopName|LoadName)[[:space:]]*\(|GL_SELECT'
allowed_files=(
  "$ROOT/tnztools/skeletontool.cpp"
)

tmp="/tmp/opentoonz-opengl-selection-compatibility.$$"
trap 'rm -f "$tmp"' EXIT

rg -n -e "$pattern" \
  --glob '*.c' --glob '*.cc' --glob '*.cpp' --glob '*.cxx' \
  --glob '*.h' --glob '*.hh' --glob '*.hpp' \
  "$ROOT" | grep -vE '//.*(gl(RenderMode|SelectBuffer|InitNames|PushName|PopName|LoadName)[[:space:]]*\(|GL_SELECT)' >"$tmp" || true

fail=0
while IFS=: read -r file _line _rest; do
  [[ -n "$file" ]] || continue
  allowed=0
  for allowed_file in "${allowed_files[@]}"; do
    if [[ "$file" == "$allowed_file" ]]; then
      allowed=1
      break
    fi
  done
  if (( allowed == 0 )); then
    if (( fail == 0 )); then
      echo "verify-opengl-selection-compatibility: unexpected OpenGL selection markers:" >&2
    fi
    rg -n -e "$pattern" "$file" >&2
    fail=1
  fi
done <"$tmp"

if (( fail != 0 )); then
  exit 1
fi

for allowed_file in "${allowed_files[@]}"; do
  if [[ ! -f "$allowed_file" ]]; then
    echo "verify-opengl-selection-compatibility: allowed file missing: $allowed_file" >&2
    exit 1
  fi
done

if rg -n -e "$pattern" "$ROOT/toonz/sceneviewer.cpp" >/dev/null; then
  echo "verify-opengl-selection-compatibility: SceneViewer OpenGL selection markers must stay removed" >&2
  exit 1
fi

if ! rg -n -e 'int SkeletonTool::pickCpu\(const TPointD& viewerPos\)' \
  "$ROOT/tnztools/skeletontool.cpp" >/dev/null; then
  echo "verify-opengl-selection-compatibility: Skeleton Tool CPU picker missing" >&2
  exit 1
fi

if rg -n -e 'pick\(e\.m_pos\)' "$ROOT/tnztools/skeletontool.cpp" >/dev/null; then
  echo "verify-opengl-selection-compatibility: Skeleton Tool still calls generic OpenGL selection pick" >&2
  exit 1
fi

file_count="$(cut -d: -f1 "$tmp" | sort -u | wc -l | tr -d '[:space:]')"
match_count="$(wc -l <"$tmp" | tr -d '[:space:]')"
echo "verify-opengl-selection-compatibility: ok files=$file_count matches=$match_count"
