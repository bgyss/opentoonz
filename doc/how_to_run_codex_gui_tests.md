# Running Codex GUI Smoke Tests

This checkout includes a repo-local Codex skill for macOS-first GUI smoke
verification:

```text
skills/opentoonz-gui-verification/
```

The skill is an additional testing layer on top of normal configure, build,
packaging, and manual validation. It prepares an isolated OpenToonz runtime
root, launches the packaged app, and uses Codex Computer Use to inspect and
drive the visible Qt GUI.

## Requirements

- Codex with the Computer Use plugin available.
- macOS for the interactive GUI-driving layer.
- Nix and mise configured as described in `doc/how_to_build_nix_mise.md`.
- A packaged OpenToonz app bundle at
  `toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app`.

Install or prepare the local build environment:

```sh
mise trust ./mise.toml
mise run doctor
mise run configure
mise run build
mise run package-macos
```

The GUI smoke scripts are already part of this repository. There is no separate
test package to install.

## Running From Codex

From the repository root, ask Codex to use the repo-local skill explicitly:

```text
Use $opentoonz-gui-verification to run the macOS OpenToonz GUI smoke test for
this checkout. Prepare an isolated run, launch the packaged app, use Computer
Use for startup and room-tab verification, then summarize the evidence.
```

If the skill is not auto-discovered, point Codex at the skill file:

```text
Open skills/opentoonz-gui-verification/SKILL.md and follow it to run an
OpenToonz GUI smoke verification pass.
```

Codex should run the harness commands in this order:

```sh
mise run gui-smoke-prepare
mise run gui-smoke-launch
mise run gui-smoke-summarize
```

After launch, Codex should use Computer Use against the built app bundle under
the repository root:

```text
toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app
```

Codex should call `get_app_state` before interacting, prefer accessibility
element indexes for clicks, and only fall back to coordinate clicks when the
accessibility tree does not expose a usable control.

## Running Shell-Only Checks

When Computer Use is unavailable, or when a GUI launch is not safe in the
current environment, run the deterministic script checks only:

```sh
bash -n skills/opentoonz-gui-verification/scripts/prepare-run.sh
bash -n skills/opentoonz-gui-verification/scripts/launch-run.sh
bash -n skills/opentoonz-gui-verification/scripts/summarize-run.sh
mise run gui-smoke-prepare
mise run gui-smoke-summarize
```

This does not prove GUI behavior, but it verifies that the local report and
isolated runtime setup still work.

## Local Reports

Every `gui-smoke-*` task writes a local Markdown report:

```text
test-results/gui-smoke/<run-name>/report.md
```

`gui-smoke-summarize` also writes `summary.md` as a compatibility copy. The
entire `test-results/gui-smoke/` tree is ignored by Git and must remain local.
Do not stage generated GUI smoke reports, logs, runtime data, or copied `stuff`
directories.

The default run directory is:

```text
test-results/gui-smoke/latest
```

Use a named run when comparing scenarios:

```sh
OPENTOONZ_GUI_RUN_DIR=test-results/gui-smoke/startup-popup \
  OPENTOONZ_GUI_STARTUP_POPUP=1 \
  mise run gui-smoke-prepare
```

## Verifying The Correct App Instance

The GUI smoke pass only counts if Codex observes the harness-launched app using
the isolated runtime root. Do not count a GUI observation as an isolated smoke
pass if visible project paths point at a user profile OpenToonz data directory
or a system-wide installed OpenToonz application instead of the harness run
directory.

The expected isolated root appears in `run.env` and the generated report as
`OPENTOONZ_GUI_TOONZROOT`.

## Adding New GUI Tests

Add new scenarios in small, deterministic slices:

1. Extend `skills/opentoonz-gui-verification/references/gui-smoke-matrix.md`
   with the new room, dialog, tool, or workflow checks.
2. Keep the expected evidence observable through screenshots, accessibility
   tree text, process status, logs, or a generated file under the ignored run
   directory.
3. If the scenario needs setup, add the smallest possible environment option or
   script behavior under `skills/opentoonz-gui-verification/scripts/`.
4. Document any new environment variable in both `SKILL.md` and this file.
5. Re-run the script syntax checks and skill validation.

Prefer checks that catch obvious regressions without depending on user data,
network access, device hardware, or timing-sensitive drawing gestures. Good
first additions are menu/dialog presence checks, room-specific panel checks,
simple file-open flows using fixtures under the isolated runtime root, and
startup/performance thresholds measured from harness timestamps.

## Validation Before Submitting A GUI-Test Change

Run:

```sh
bash -n skills/opentoonz-gui-verification/scripts/prepare-run.sh
bash -n skills/opentoonz-gui-verification/scripts/launch-run.sh
bash -n skills/opentoonz-gui-verification/scripts/summarize-run.sh
mise run lint-codex-docs
git diff --check
git check-ignore -v test-results/gui-smoke/latest/report.md
```

If the Codex skill validator is available, also run:

```sh
SKILL_VALIDATOR=/path/to/quick_validate.py
uv run --with PyYAML python "$SKILL_VALIDATOR" \
  skills/opentoonz-gui-verification
```

When a full GUI launch is possible, also run the actual smoke path:

```sh
mise run gui-smoke-prepare
mise run gui-smoke-launch
mise run gui-smoke-summarize
```

Include the generated local report path in the final handoff, but do not commit
the report itself.
