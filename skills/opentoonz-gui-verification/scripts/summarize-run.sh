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

run_dir="$(resolve_path "${OPENTOONZ_GUI_RUN_DIR:-test-results/gui-smoke/latest}")"
run_env="$run_dir/run.env"
report="$run_dir/report.md"
summary="$run_dir/summary.md"
if [[ ! -f "$run_env" ]]; then
  mkdir -p "$run_dir"
  {
    echo "# OpenToonz GUI Smoke Report"
    echo
    echo "- generated_at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "- phase: summarize"
    echo "- status: failed"
    echo "- detail: run.env not found; run mise run gui-smoke-prepare first"
    echo "- local_only: true"
    echo "- ignored_by_git: /test-results/gui-smoke/"
    echo "- run_dir: $run_dir"
  } > "$report"
  cp "$report" "$summary"
  echo "error: run.env not found. Run mise run gui-smoke-prepare first." >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$run_env"
now_epoch="$(date +%s)"
start_epoch=""
if [[ -n "${OPENTOONZ_GUI_START_EPOCH_FILE:-}" && -f "$OPENTOONZ_GUI_START_EPOCH_FILE" ]]; then
  start_epoch="$(cat "$OPENTOONZ_GUI_START_EPOCH_FILE")"
fi
end_epoch=""
if [[ -n "${OPENTOONZ_GUI_END_EPOCH_FILE:-}" && -f "$OPENTOONZ_GUI_END_EPOCH_FILE" ]]; then
  end_epoch="$(cat "$OPENTOONZ_GUI_END_EPOCH_FILE")"
fi

status="not launched"
exit_status="unknown"
rss_kib="n/a"
pid="${OPENTOONZ_GUI_PID:-}"
if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
  status="running"
  rss_kib="$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
  [[ -n "$rss_kib" ]] || rss_kib="n/a"
elif [[ -n "${OPENTOONZ_GUI_EXIT_STATUS_FILE:-}" && -f "$OPENTOONZ_GUI_EXIT_STATUS_FILE" ]]; then
  status="exited"
  exit_status="$(cat "$OPENTOONZ_GUI_EXIT_STATUS_FILE")"
elif [[ -n "$pid" ]]; then
  status="not running, exit status unavailable"
fi

elapsed_seconds="unknown"
if [[ "$start_epoch" =~ ^[0-9]+$ ]]; then
  stop_epoch="$now_epoch"
  if [[ "$end_epoch" =~ ^[0-9]+$ ]]; then
    stop_epoch="$end_epoch"
  fi
  elapsed_seconds=$((stop_epoch - start_epoch))
fi

{
  echo "# OpenToonz GUI Smoke Report"
  echo
  echo "- generated_at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "- phase: summarize"
  echo "- run_dir: $run_dir"
  echo "- status: $status"
  echo "- exit_status: $exit_status"
  echo "- local_only: true"
  echo "- ignored_by_git: /test-results/gui-smoke/"
  echo "- pid: ${pid:-n/a}"
  echo "- monitor_pid: ${OPENTOONZ_GUI_MONITOR_PID:-n/a}"
  echo "- elapsed_seconds: $elapsed_seconds"
  echo "- rss_kib: $rss_kib"
  echo "- app: ${OPENTOONZ_GUI_APP_BINARY:-n/a}"
  echo "- TOONZROOT: ${OPENTOONZ_GUI_TOONZROOT:-n/a}"
  echo
  echo "## stdout tail"
  echo
  echo '```'
  if [[ -n "${OPENTOONZ_GUI_STDOUT:-}" && -f "$OPENTOONZ_GUI_STDOUT" ]]; then
    tail -n 80 "$OPENTOONZ_GUI_STDOUT"
  else
    echo "stdout log not found"
  fi
  echo '```'
  echo
  echo "## stderr tail"
  echo
  echo '```'
  if [[ -n "${OPENTOONZ_GUI_STDERR:-}" && -f "$OPENTOONZ_GUI_STDERR" ]]; then
    tail -n 120 "$OPENTOONZ_GUI_STDERR"
  else
    echo "stderr log not found"
  fi
  echo '```'
} > "$report"
cp "$report" "$summary"

cat "$report"
