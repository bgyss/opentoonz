#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "$#" -gt 0 ]; then
  targets=("$@")
else
  targets=(
    "doc/how_to_run_codex_gui_tests.md"
    "skills/opentoonz-gui-verification"
  )
fi

existing_targets=()
for target in "${targets[@]}"; do
  if [ -e "$target" ]; then
    existing_targets+=("$target")
  else
    echo "codex-doc lint: skipping missing target: $target" >&2
  fi
done

if [ "${#existing_targets[@]}" -eq 0 ]; then
  echo "codex-doc lint: no targets to scan"
  exit 0
fi

failed=0
regex_patterns=(
  '/Users/[[:alnum:]_.-]+'
  '/home/[[:alnum:]_.-]+'
  'C:\\Users\\[[:alnum:]_.-]+'
  '~[[:alnum:]_.-]*/'
  '/private/tmp([/[:space:]]|$)'
  '/private/var/folders/'
  '/Applications([^[:alnum:]_.-]|$)'
  '/\.codex/'
)

for pattern in "${regex_patterns[@]}"; do
  if grep -RInE -- "$pattern" "${existing_targets[@]}"; then
    echo "codex-doc lint: found machine-local path pattern: $pattern" >&2
    failed=1
  fi
done

current_user="${USER:-}"
if [ -n "$current_user" ] && [ "$current_user" != "root" ]; then
  if grep -RInF -- "$current_user" "${existing_targets[@]}"; then
    echo "codex-doc lint: found current username in generated docs: $current_user" >&2
    failed=1
  fi
fi

if [ "$failed" -ne 0 ]; then
  cat >&2 <<'EOF'
codex-doc lint: replace personal or machine-local paths with project-root-relative
paths, environment variables, or neutral placeholders such as /path/to/...
EOF
  exit 1
fi

echo "codex-doc lint: no personal machine paths found"
