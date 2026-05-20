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

write_launch_report() {
  local status="$1"
  local detail="${2:-}"
  local report_path="$run_dir/report.md"
  mkdir -p "$run_dir"
  {
    echo "# OpenToonz GUI Smoke Report"
    echo
    echo "- generated_at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "- phase: launch"
    echo "- status: $status"
    echo "- detail: ${detail:-n/a}"
    echo "- local_only: true"
    echo "- ignored_by_git: /test-results/gui-smoke/"
    echo "- run_dir: $run_dir"
    echo "- app: ${app_binary:-n/a}"
    echo "- pid: ${app_pid:-n/a}"
    echo "- monitor_pid: ${monitor_pid:-n/a}"
    echo "- stdout: ${stdout_path:-n/a}"
    echo "- stderr: ${stderr_path:-n/a}"
    echo "- TOONZROOT: ${OPENTOONZ_GUI_TOONZROOT:-n/a}"
    echo
    echo "## Next step"
    echo
    echo '```sh'
    echo "mise run gui-smoke-summarize"
    echo '```'
  } > "$report_path"
}

run_dir="$(resolve_path "${OPENTOONZ_GUI_RUN_DIR:-test-results/gui-smoke/latest}")"
run_env="$run_dir/run.env"
if [[ ! -f "$run_env" ]]; then
  app_binary=""
  app_pid=""
  monitor_pid=""
  stdout_path=""
  stderr_path=""
  write_launch_report "failed" "run.env not found; run mise run gui-smoke-prepare first"
  echo "error: run.env not found. Run mise run gui-smoke-prepare first." >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$run_env"

app_path="${OPENTOONZ_APP:-$repo_root/toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app}"
app_path="$(resolve_path "$app_path")"
if [[ -d "$app_path" ]]; then
  app_binary="$app_path/Contents/MacOS/OpenToonz"
else
  app_binary="$app_path"
fi

if [[ ! -x "$app_binary" ]]; then
  app_pid=""
  monitor_pid=""
  stdout_path=""
  stderr_path=""
  write_launch_report "failed" "OpenToonz executable not found or not executable"
  echo "error: OpenToonz executable not found or not executable: $app_binary" >&2
  echo "       Run mise run build and mise run package-macos, or set OPENTOONZ_APP." >&2
  exit 1
fi

if [[ -n "${OPENTOONZ_GUI_PID:-}" ]] && kill -0 "$OPENTOONZ_GUI_PID" 2>/dev/null; then
  app_pid="$OPENTOONZ_GUI_PID"
  monitor_pid="${OPENTOONZ_GUI_MONITOR_PID:-}"
  stdout_path="${OPENTOONZ_GUI_STDOUT:-}"
  stderr_path="${OPENTOONZ_GUI_STDERR:-}"
  write_launch_report "failed" "existing OpenToonz smoke process is still running"
  echo "error: existing OpenToonz smoke process is still running: $OPENTOONZ_GUI_PID" >&2
  exit 3
fi

stdout_path="$run_dir/opentoonz.stdout.log"
stderr_path="$run_dir/opentoonz.stderr.log"
exit_status_path="$run_dir/exit-status.txt"
start_epoch_path="$run_dir/start-epoch.txt"
end_epoch_path="$run_dir/end-epoch.txt"
app_pid_path="$run_dir/app.pid"
monitor_pid_path="$run_dir/monitor.pid"

rm -f "$stdout_path" "$stderr_path" "$exit_status_path" "$end_epoch_path" \
  "$app_pid_path" "$monitor_pid_path"
date +%s > "$start_epoch_path"

(
  trap '' HUP
  "$app_binary" \
    -TOONZROOT "$OPENTOONZ_GUI_TOONZROOT" \
    -TOONZLIBRARY "$OPENTOONZ_GUI_TOONZLIBRARY" \
    -TOONZSTUDIOPALETTE "$OPENTOONZ_GUI_TOONZSTUDIOPALETTE" \
    -TOONZFXPRESETS "$OPENTOONZ_GUI_TOONZFXPRESETS" \
    -TOONZPROFILES "$OPENTOONZ_GUI_TOONZPROFILES" \
    -TOONZCONFIG "$OPENTOONZ_GUI_TOONZCONFIG" \
    -TOONZPROJECTS "$OPENTOONZ_GUI_TOONZPROJECTS" \
    >"$stdout_path" 2>"$stderr_path" &
  app_pid=$!
  echo "$app_pid" > "$app_pid_path"
  wait "$app_pid"
  status=$?
  echo "$status" > "$exit_status_path"
  date +%s > "$end_epoch_path"
) &
monitor_pid=$!
disown "$monitor_pid" 2>/dev/null || true
echo "$monitor_pid" > "$monitor_pid_path"

for _ in $(seq 1 50); do
  [[ -s "$app_pid_path" ]] && break
  sleep 0.1
done

if [[ ! -s "$app_pid_path" ]]; then
  app_pid=""
  write_launch_report "failed" "OpenToonz process did not publish a PID"
  echo "error: OpenToonz process did not publish a PID" >&2
  exit 1
fi

app_pid="$(cat "$app_pid_path")"
sleep 2

{
  grep -v '^OPENTOONZ_GUI_PID=' "$run_env" |
    grep -v '^OPENTOONZ_GUI_MONITOR_PID=' |
    grep -v '^OPENTOONZ_GUI_APP_BINARY=' |
    grep -v '^OPENTOONZ_GUI_STDOUT=' |
    grep -v '^OPENTOONZ_GUI_STDERR=' |
    grep -v '^OPENTOONZ_GUI_EXIT_STATUS_FILE=' |
    grep -v '^OPENTOONZ_GUI_START_EPOCH_FILE=' |
    grep -v '^OPENTOONZ_GUI_END_EPOCH_FILE=' || true
  echo "OPENTOONZ_GUI_PID=$(shell_quote "$app_pid")"
  echo "OPENTOONZ_GUI_MONITOR_PID=$(shell_quote "$monitor_pid")"
  echo "OPENTOONZ_GUI_APP_BINARY=$(shell_quote "$app_binary")"
  echo "OPENTOONZ_GUI_STDOUT=$(shell_quote "$stdout_path")"
  echo "OPENTOONZ_GUI_STDERR=$(shell_quote "$stderr_path")"
  echo "OPENTOONZ_GUI_EXIT_STATUS_FILE=$(shell_quote "$exit_status_path")"
  echo "OPENTOONZ_GUI_START_EPOCH_FILE=$(shell_quote "$start_epoch_path")"
  echo "OPENTOONZ_GUI_END_EPOCH_FILE=$(shell_quote "$end_epoch_path")"
} > "$run_env.tmp"
mv "$run_env.tmp" "$run_env"

if [[ -f "$exit_status_path" ]]; then
  write_launch_report "failed" "OpenToonz exited during startup with status $(cat "$exit_status_path")"
  echo "error: OpenToonz exited during startup with status $(cat "$exit_status_path")" >&2
  echo "stderr: $stderr_path" >&2
  exit 1
fi

if ! kill -0 "$app_pid" 2>/dev/null; then
  write_launch_report "failed" "OpenToonz process is not running after launch"
  echo "error: OpenToonz process is not running after launch: $app_pid" >&2
  exit 1
fi

write_launch_report "launched" "process started and was alive after initial wait"

echo "Launched OpenToonz GUI smoke run:"
echo "  pid: $app_pid"
echo "  monitor_pid: $monitor_pid"
echo "  app: $app_binary"
echo "  run_env: $run_env"
echo "  stdout: $stdout_path"
echo "  stderr: $stderr_path"
echo "  report: $run_dir/report.md"
