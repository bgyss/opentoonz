#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if repo_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null)"; then
  :
else
  repo_root="$(cd "$script_dir/../../.." && pwd)"
fi

resolve_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$repo_root/$1" ;;
  esac
}

shell_quote() {
  printf '%q' "$1"
}

write_prepare_report() {
  local report_path="$run_dir/report.md"
  {
    echo "# OpenToonz GUI Smoke Report"
    echo
    echo "- generated_at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "- phase: prepare"
    echo "- status: prepared"
    echo "- local_only: true"
    echo "- ignored_by_git: /test-results/gui-smoke/"
    echo "- run_dir: $run_dir"
    echo "- TOONZROOT: $toonzroot"
    echo "- preferences: $settings_dir/preferences.ini"
    echo "- startup_popup: $startup_popup"
    echo
    echo "## Next step"
    echo
    echo '```sh'
    echo "mise run gui-smoke-launch"
    echo '```'
  } > "$report_path"
}

timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
run_dir="$(resolve_path "${OPENTOONZ_GUI_RUN_DIR:-test-results/gui-smoke/latest}")"
run_parent="$(dirname "$run_dir")"
mkdir -p "$run_parent"

if [[ -e "$run_dir" || -L "$run_dir" ]]; then
  archive_dir="$run_parent/archive-$timestamp"
  suffix=0
  while [[ -e "$archive_dir" ]]; do
    suffix=$((suffix + 1))
    archive_dir="$run_parent/archive-$timestamp-$suffix"
  done
  mv "$run_dir" "$archive_dir"
fi

mkdir -p "$run_dir"
runtime_dir="$run_dir/runtime"
toonzroot="$runtime_dir/stuff"
mkdir -p "$runtime_dir"
cp -pR "$repo_root/stuff" "$toonzroot"
toonzlibrary="$toonzroot/library"
toonzstudiopalette="$toonzroot/studiopalette"
toonzfxpresets="$toonzroot/fxs"
toonzprofiles="$toonzroot/profiles"
toonzconfig="$toonzroot/config"
toonzprojects="$toonzroot/projects"

user_name="${USER:-$(id -un)}"
settings_dir="$toonzroot/profiles/layouts/settings.$user_name"
mkdir -p "$settings_dir"

startup_popup="${OPENTOONZ_GUI_STARTUP_POPUP:-0}"
case "$startup_popup" in
  0|false|FALSE|no|NO) startup_popup="0" ;;
  1|true|TRUE|yes|YES) startup_popup="1" ;;
  *)
    echo "error: OPENTOONZ_GUI_STARTUP_POPUP must be 0 or 1" >&2
    exit 2
    ;;
esac

cat > "$settings_dir/preferences.ini" <<EOF
startupPopupEnabled=$startup_popup
latestVersionCheckEnabled=0
CurrentRoomChoice=Default
CurrentStyleSheetName=Default
CurrentLanguageName=English
watchFileSystemEnabled=0
SVNEnabled=0
EOF

cat > "$run_dir/run.env" <<EOF
OPENTOONZ_GUI_REPO_ROOT=$(shell_quote "$repo_root")
OPENTOONZ_GUI_RUN_DIR=$(shell_quote "$run_dir")
OPENTOONZ_GUI_TOONZROOT=$(shell_quote "$toonzroot")
OPENTOONZ_GUI_TOONZLIBRARY=$(shell_quote "$toonzlibrary")
OPENTOONZ_GUI_TOONZSTUDIOPALETTE=$(shell_quote "$toonzstudiopalette")
OPENTOONZ_GUI_TOONZFXPRESETS=$(shell_quote "$toonzfxpresets")
OPENTOONZ_GUI_TOONZPROFILES=$(shell_quote "$toonzprofiles")
OPENTOONZ_GUI_TOONZCONFIG=$(shell_quote "$toonzconfig")
OPENTOONZ_GUI_TOONZPROJECTS=$(shell_quote "$toonzprojects")
OPENTOONZ_GUI_PREFERENCES=$(shell_quote "$settings_dir/preferences.ini")
OPENTOONZ_GUI_STARTUP_POPUP=$(shell_quote "$startup_popup")
OPENTOONZ_GUI_PREPARED_AT=$(shell_quote "$timestamp")
EOF

cat > "$run_dir/README.txt" <<EOF
OpenToonz GUI smoke run
prepared_at=$timestamp
toonzroot=$toonzroot
preferences=$settings_dir/preferences.ini
startup_popup=$startup_popup
EOF

write_prepare_report

echo "Prepared OpenToonz GUI smoke run:"
echo "  run_dir: $run_dir"
echo "  TOONZROOT: $toonzroot"
echo "  preferences: $settings_dir/preferences.ini"
echo "  report: $run_dir/report.md"
