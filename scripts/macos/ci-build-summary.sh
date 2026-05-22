#!/usr/bin/env bash
set -euo pipefail

repo_root="${OPENTOONZ_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
build_dir="${OPENTOONZ_BUILD_DIR:-toonz/build/nix-relwithdebinfo}"
log_dir="${OPENTOONZ_CI_LOG_DIR:-${RUNNER_TEMP:-/tmp}/opentoonz-ci}"
label="${OPENTOONZ_CI_BUILD_LABEL:-macos-arm64}"
build_log="$log_dir/${label}-build.log"
summary_file="$log_dir/${label}-summary.md"
parallel="${OPENTOONZ_BUILD_PARALLEL:-}"

mkdir -p "$log_dir"
: >"$build_log"

cd "$repo_root"

read -r -a cmake_extra_args <<<"${OPENTOONZ_CMAKE_EXTRA_ARGS:-}"

run_logged() {
  local title="$1"
  shift

  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "::group::$title"
  else
    echo "==> $title"
  fi

  set +e
  "$@" 2>&1 | tee -a "$build_log"
  local status="${PIPESTATUS[0]}"
  set -e

  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "::endgroup::"
  fi

  return "$status"
}

count_warning_pattern() {
  local pattern="$1"
  grep -Eic "$pattern" "$build_log" 2>/dev/null || true
}

build_status=0
start_epoch="$(date +%s)"

if run_logged "prepare bundled libtiff" \
  nix develop path:. --command bash scripts/nix/prepare-tiff.sh; then
  :
else
  build_status="$?"
fi

if [[ "$build_status" == "0" ]]; then
  if run_logged "configure OpenToonz ${label}" \
    nix develop path:. --command cmake -S toonz/sources --preset nix-relwithdebinfo \
      "${cmake_extra_args[@]}"; then
    :
  else
    build_status="$?"
  fi
fi

if [[ "$build_status" == "0" ]]; then
  build_cmd=(nix develop path:. --command cmake --build "$build_dir")
  if [[ -n "$parallel" ]]; then
    build_cmd+=(--parallel "$parallel")
  else
    build_cmd+=(--parallel)
  fi

  if run_logged "build OpenToonz ${label}" "${build_cmd[@]}"; then
    :
  else
    build_status="$?"
  fi
fi

end_epoch="$(date +%s)"
elapsed_seconds=$((end_epoch - start_epoch))

total_warnings="$(count_warning_pattern '(^|[[:space:]])warning:')"
opengl_deprecation_warnings="$(count_warning_pattern 'OpenGL.*deprecated|deprecated.*OpenGL|GL_SILENCE_DEPRECATION')"
qt_qgl_warnings="$(count_warning_pattern 'QGL[A-Za-z0-9_]*|QGLWidget::convertToGLFormat')"
qopengl_warnings="$(count_warning_pattern 'QOpenGL[A-Za-z0-9_]*.*deprecated|deprecated.*QOpenGL[A-Za-z0-9_]*')"

metal_cache_value="not configured"
if [[ -f "$build_dir/CMakeCache.txt" ]]; then
  metal_cache_value="$(grep -E '^WITH_GRAPHICS_METAL:BOOL=' "$build_dir/CMakeCache.txt" | cut -d= -f2 || true)"
  [[ -n "$metal_cache_value" ]] || metal_cache_value="missing"
fi

ccache_stats="$log_dir/${label}-ccache.txt"
if nix develop path:. --command ccache --show-stats >"$ccache_stats" 2>&1; then
  :
else
  echo "ccache stats unavailable" >"$ccache_stats"
fi

{
  echo "## macOS arm64 build summary: $label"
  echo
  echo "- status: $build_status"
  echo "- elapsed_seconds: $elapsed_seconds"
  echo "- build_log: $build_log"
  echo "- WITH_GRAPHICS_METAL: $metal_cache_value"
  echo "- total_warnings: $total_warnings"
  echo "- apple_opengl_deprecation_warnings: $opengl_deprecation_warnings"
  echo "- qt_qgl_warning_lines: $qt_qgl_warnings"
  echo "- qt_qopengl_deprecation_warning_lines: $qopengl_warnings"
  echo
  echo "### ccache"
  echo
  echo '```'
  cat "$ccache_stats"
  echo '```'
} >"$summary_file"

cat "$summary_file"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat "$summary_file" >>"$GITHUB_STEP_SUMMARY"
fi

exit "$build_status"
