# Using This Skill From Codex

This reference is for Codex agents and users who want to run the OpenToonz GUI smoke layer from inside a Codex session.

## Invocation Patterns

Use the skill explicitly from the OpenToonz repo root:

```text
Use $opentoonz-gui-verification to run the macOS OpenToonz GUI smoke test for this checkout. Prepare an isolated run, launch the packaged app, use Computer Use for startup and room-tab verification, then summarize the evidence.
```

If the local skill is not auto-discovered, point Codex at the repo-tracked file:

```text
Open skills/opentoonz-gui-verification/SKILL.md and follow it to run an OpenToonz GUI smoke verification pass.
```

For a quick non-GUI harness check:

```text
Use $opentoonz-gui-verification, but only run the script syntax checks, skill validation, gui-smoke-prepare, and gui-smoke-summarize. Do not launch the GUI.
```

For startup popup coverage:

```text
Use $opentoonz-gui-verification with OPENTOONZ_GUI_STARTUP_POPUP=1 and verify the OpenToonz Startup window before dismissing it.
```

## Expected Codex Flow

1. Confirm the checkout is `/Users/briangyss/src/opentoonz` or another OpenToonz repo root.
2. Run the normal build/package commands if the app bundle is missing:

   ```sh
   mise run configure
   mise run build
   mise run package-macos
   ```

3. Prepare and launch the isolated smoke run:

   ```sh
   mise run gui-smoke-prepare
   mise run gui-smoke-launch
   ```

4. Summarize before interacting:

   ```sh
   mise run gui-smoke-summarize
   ```

   Continue to Computer Use only if the summary says the harness PID is `running`.

5. Use Computer Use with the exact built app bundle when possible:

   ```text
   app=/Users/briangyss/src/opentoonz/toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app
   ```

   Start with `get_app_state`, then click by accessibility element index. Use coordinate clicks only when the tree does not expose a usable control.

6. Re-run `mise run gui-smoke-summarize` at the end and include the summary in the final handoff.

Each `gui-smoke-*` task writes `report.md` in the selected run directory. Treat this as the local Codex test report for the run. Reports live under `test-results/gui-smoke/`, which is ignored by Git and should not be staged.

## Environment Overrides

Use shell environment variables when Codex needs a different scenario:

```sh
OPENTOONZ_GUI_STARTUP_POPUP=1 mise run gui-smoke-prepare
OPENTOONZ_GUI_RUN_DIR=test-results/gui-smoke/startup mise run gui-smoke-prepare
OPENTOONZ_APP=/absolute/path/to/OpenToonz.app mise run gui-smoke-launch
```

`OPENTOONZ_APP` may point to either the `.app` bundle or `Contents/MacOS/OpenToonz`.

## Evidence To Report

The final Codex response should include:

- whether `gui-smoke-prepare`, `gui-smoke-launch`, and `gui-smoke-summarize` passed
- the local report path, usually `test-results/gui-smoke/latest/report.md`
- whether Computer Use observed the harness-launched app, not a normal user-profile Launch Services fallback
- visible startup state, room tabs, and core panel checks from `gui-smoke-matrix.md`
- relevant stdout/stderr tail from `test-results/gui-smoke/latest/summary.md`
- any skipped step and the concrete blocker

Do not count a GUI observation as an isolated smoke pass if visible project paths point at `~/Library/Application Support/OpenToonz`, `/Applications/OpenToonz`, or any path outside `OPENTOONZ_GUI_TOONZROOT`.

## Common Failure Modes

- `run.env not found`: run `mise run gui-smoke-prepare` first.
- `OpenToonz executable not found`: run `mise run build` and `mise run package-macos`, or set `OPENTOONZ_APP`.
- Computer Use sees an installed OpenToonz instead of the build artifact: pass the full `.app` path and verify visible paths against `OPENTOONZ_GUI_TOONZROOT`.
- Computer Use is unavailable in the current Codex environment: run the harness scripts and report GUI interaction as blocked, not passed.
- The app exits before interaction: include `mise run gui-smoke-summarize` output and the stderr tail in the handoff.
