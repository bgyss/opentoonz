---
name: opentoonz-gui-verification
description: Run macOS-first OpenToonz GUI smoke verification with an isolated runtime profile, deterministic launch scripts, and Computer Use interaction. Use when validating OpenToonz Qt GUI behavior, room layouts, startup dialogs, app launch regressions, basic responsiveness, or GUI-affecting changes in this checkout.
---

# OpenToonz GUI Verification

## Overview

Use this skill as the GUI layer on top of normal configure/build validation. It prepares an isolated OpenToonz runtime root, launches the packaged macOS app bundle, then uses Computer Use to observe and drive the visible Qt UI.

## Workflow

1. Build and package the app when needed:

   ```sh
   mise run configure
   mise run build
   mise run package-macos
   ```

2. Prepare an isolated run:

   ```sh
   mise run gui-smoke-prepare
   ```

   Set `OPENTOONZ_GUI_STARTUP_POPUP=1` to verify the startup popup path. The default run directory is `test-results/gui-smoke/latest`; override it with `OPENTOONZ_GUI_RUN_DIR`.

3. Launch the app:

   ```sh
   mise run gui-smoke-launch
   ```

   The default app binary is `toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app/Contents/MacOS/OpenToonz`. Override it with `OPENTOONZ_APP`, which may point to either the `.app` bundle or the executable.

4. Use Computer Use against `OpenToonz`:

   - Run `mise run gui-smoke-summarize` first and confirm the harness PID is still `running`.
   - Pass the exact app bundle path from `OPENTOONZ_GUI_APP_BINARY`'s parent `.app` when possible; avoid the generic app name if another OpenToonz install may exist.
   - If Computer Use opens a new Launch Services instance or the UI reports project paths outside `OPENTOONZ_GUI_TOONZROOT`, do not count that observation as an isolated harness pass.
   - Call `get_app_state` before every interaction sequence.
   - Prefer accessibility element indexes for clicks.
   - Type text only when a scenario requires it.
   - Use coordinate clicks only when the accessibility tree lacks a usable element; record the reason and target region in the report.
   - Do not use destructive GUI actions, overwrite files, change system settings, or transmit data without explicit user approval.

5. Record evidence:

   - Screenshot and accessibility tree observations from `get_app_state`.
   - Pass/fail for each checked room or dialog.
   - Startup time, responsiveness notes, and visible fatal/crash dialogs.
   - Relevant stdout/stderr tails and process status from `mise run gui-smoke-summarize`.
   - Local report files under `test-results/gui-smoke/`; this ignored tree is the required destination for automated Codex GUI smoke reports.

6. Summarize:

   ```sh
   mise run gui-smoke-summarize
   ```

## Smoke Matrix

Read `references/gui-smoke-matrix.md` before interacting with the app. Use the matrix as the minimum v1 scenario set for startup, rooms, core panels, and obvious responsiveness regressions.

## Using Inside Codex

Read `references/codex-usage.md` when the user asks how to invoke this skill from Codex, when a Codex run cannot find the skill automatically, or when preparing a prompt for another Codex agent.

## Harness Contract

The scripts communicate through `${OPENTOONZ_GUI_RUN_DIR:-test-results/gui-smoke/latest}/run.env`. Source it only from this checkout's generated run directory. It contains `OPENTOONZ_GUI_PID`, `OPENTOONZ_GUI_MONITOR_PID`, `OPENTOONZ_GUI_TOONZROOT`, `OPENTOONZ_GUI_STDOUT`, `OPENTOONZ_GUI_STDERR`, and timing paths.

Every `gui-smoke-*` task writes `${OPENTOONZ_GUI_RUN_DIR:-test-results/gui-smoke/latest}/report.md`. `gui-smoke-summarize` also writes `summary.md` as a compatibility copy. These reports must remain local and ignored by Git.

Use the isolated `OPENTOONZ_GUI_TOONZROOT` for every GUI run. Do not launch smoke tests against the user's normal OpenToonz profile unless the user explicitly asks.

If a full build or GUI launch is not feasible, still run the syntax/prepare checks and report the exact missing prerequisite.
