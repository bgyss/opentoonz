#!/usr/bin/env bash
set -euo pipefail

ref="${1:-${OPENTOONZ_RELEASE_READINESS_REF:-codex/complete-macos-graphics-modernize}}"
workflow="${OPENTOONZ_RELEASE_READINESS_WORKFLOW:-MacOS Build}"
failed=0

check_ok() {
  echo "ok: $1"
}

check_warn() {
  echo "warn: $1" >&2
}

check_fail() {
  echo "missing: $1" >&2
  failed=1
}

require_command() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    check_ok "command available: $name"
  else
    check_fail "command unavailable: $name"
  fi
}

require_xcrun_tool() {
  local name="$1"
  if command -v xcrun >/dev/null 2>&1 && xcrun --find "$name" >/dev/null 2>&1; then
    check_ok "xcrun tool available: $name"
  else
    check_fail "xcrun tool unavailable: $name"
  fi
}

if [[ "$(uname -s)" == "Darwin" ]]; then
  check_ok "running on macOS"
else
  check_fail "release/default readiness preflight must run on macOS"
fi

require_command gh
require_command xcrun
require_command codesign
require_command security
require_command osascript
require_xcrun_tool metal
require_xcrun_tool metallib
require_xcrun_tool notarytool
require_xcrun_tool stapler

if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    check_ok "GitHub CLI is authenticated"
  else
    check_fail "GitHub CLI is not authenticated"
  fi
fi

if [[ -n "${MACOS_DEVELOPER_ID_APPLICATION:-}" ]]; then
  check_ok "MACOS_DEVELOPER_ID_APPLICATION is set"
else
  check_fail "MACOS_DEVELOPER_ID_APPLICATION is not set"
fi

if [[ -n "${MACOS_CERTIFICATE_P12_BASE64:-}" && -n "${MACOS_CERTIFICATE_PASSWORD:-}" ]]; then
  check_ok "release certificate import secrets are set"
else
  check_warn "MACOS_CERTIFICATE_P12_BASE64/MACOS_CERTIFICATE_PASSWORD are not both set; local signing may still work if the identity is already installed"
fi

if [[ -n "${MACOS_NOTARY_KEYCHAIN_PROFILE:-}" || \
      ( -n "${MACOS_NOTARY_APPLE_ID:-}" && \
        -n "${MACOS_NOTARY_TEAM_ID:-}" && \
        -n "${MACOS_NOTARY_PASSWORD:-}" ) ]]; then
  check_ok "notarytool credentials are configured"
else
  check_fail "notarytool credentials are not configured"
fi

if osascript -e 'id of application "System Events"' >/dev/null 2>&1; then
  check_ok "System Events is reachable through osascript"
else
  check_fail "System Events is not reachable through osascript"
fi

cat <<EOF

Release/default readiness dispatch commands:

gh workflow run "$workflow" \\
  --ref "$ref" \\
  -f strict_metallib=true \\
  -f system_gui_smoke=false

gh workflow run "$workflow" \\
  --ref "$ref" \\
  -f strict_metallib=false \\
  -f system_gui_smoke=true

For a final release/default-readiness pass, run these on a macOS machine or
runner with the Metal command-line tools, signing/notarization credentials, and
Accessibility/Automation permissions for System Events. Then download artifacts
and verify them with:

gh run download <run-id> --dir /tmp/opentoonz-macos-ci-artifacts
bash scripts/verify_macos_ci_artifacts.sh /tmp/opentoonz-macos-ci-artifacts
EOF

if (( failed != 0 )); then
  echo "verify-macos-release-readiness-prereqs: missing required prerequisites" >&2
  exit 1
fi

echo "verify-macos-release-readiness-prereqs: ok"
