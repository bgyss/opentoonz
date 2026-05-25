#!/usr/bin/env bash
set -euo pipefail

manifest="${1:-doc/macos_graphics_golden_scenes.tsv}"
checklist="${2:-doc/macos_graphics_manual_walkthrough_checklist.md}"

if [[ ! -f "$manifest" ]]; then
  echo "verify-macos-manual-walkthrough-checklist: missing manifest: $manifest" >&2
  exit 1
fi

if [[ ! -f "$checklist" ]]; then
  echo "verify-macos-manual-walkthrough-checklist: missing checklist: $checklist" >&2
  exit 1
fi

required_patterns=(
  'verify_macos_release_readiness_prereqs\.sh'
  'strict_metallib=true'
  'system_gui_smoke=true'
  'verify_macos_ci_artifacts\.sh'
  'codesign --verify --deep --strict'
  'xcrun stapler validate'
  'OpenGL fallback remains selectable'
  'Metal remains opt-in'
  'Decision:'
)

for pattern in "${required_patterns[@]}"; do
  if ! rg -q "$pattern" "$checklist"; then
    echo "verify-macos-manual-walkthrough-checklist: missing required pattern: $pattern" >&2
    exit 1
  fi
done

missing=0
while IFS=$'\t' read -r id category status path frame validation notes; do
  if [[ "$id" == "id" ]]; then
    continue
  fi
  if [[ "$status" != "repo" && "$status" != "generated" ]]; then
    continue
  fi
  if [[ "$path" != *.tnz ]]; then
    continue
  fi
  if ! rg -q "\| ${category} \|" "$checklist"; then
    echo "verify-macos-manual-walkthrough-checklist: missing category row: $category" >&2
    missing=1
  fi
done <"$manifest"

if (( missing != 0 )); then
  exit 1
fi

echo "verify-macos-manual-walkthrough-checklist: ok"
