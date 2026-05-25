# macOS Graphics Manual Walkthrough Checklist

Use this checklist for the final release/default-readiness GUI pass after the
automated Metal CI gates are green. Keep OpenGL and Metal results side by side;
do not use this checklist to change the default backend unless every required
row is completed and reviewed.

## Run Metadata

- Date:
- Tester:
- macOS version:
- Hardware:
- OpenToonz ref:
- App artifact:
- Metal run id:
- OpenGL fallback run id:
- Strict `.metallib` run id:
- System GUI smoke run id:
- Signing/notarization run id:

## Required Preflight

- `bash scripts/verify_macos_release_readiness_prereqs.sh <branch-or-sha>`:
- `gh workflow run "MacOS Build" --ref <branch-or-sha> -f strict_metallib=true -f system_gui_smoke=false`:
- `gh workflow run "MacOS Build" --ref <branch-or-sha> -f strict_metallib=false -f system_gui_smoke=true`:
- `bash scripts/verify_macos_ci_artifacts.sh <downloaded-artifact-dir>`:
- Release app `codesign --verify --deep --strict --verbose=2`:
- Release DMG `codesign --verify --verbose=2`:
- Release DMG `xcrun stapler validate`:

## Manual Matrix

For each row, record OpenGL result, Metal result, evidence path, and reviewer
notes. Evidence should include screenshots or exported frames when the workflow
has a visible output.

| Category | Scene | Frame | Workflow | OpenGL result | Metal result | Evidence | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| raster | `doc/sample_data/tga_paint.tnz` | 1 | Open scene, pan, zoom, scrub, toggle camera view, capture viewer screenshot. | | | | |
| vector | `doc/sample_data/dwanko_run.tnz` | 24 | Open scene, pan, zoom, scrub, capture viewer screenshot and confirm vector layers remain visible. | | | | |
| palette-style | `doc/sample_data/tga_paint.tnz` | 1 | Open Style Editor, change a palette color, verify viewer update, undo or restore color. | | | | |
| mesh-skeleton | generated `mesh_skeleton_basic.tnz` | 1 | Open generated mesh/skeleton fixture, inspect deformation view, exercise Plastic/Skeleton tool selection where available. | | | | |
| camera-overlays | `doc/sample_data/dwanko_run.tnz` | 24 | Toggle camera view and overlays, compare camera mask and background presentation. | | | | |
| onion-skin | `doc/sample_data/tga_paint.tnz` | 3 | Enable onion skin, scrub adjacent frames, compare overlay visibility and alignment. | | | | |
| sub-xsheet | generated `sub_xsheet_basic.tnz` | 1 | Open generated sub-xsheet fixture, enter/exit child xsheet, verify compositing. | | | | |
| shader-effects | `doc/sample_data/dwanko_run.tnz` | 24 | Preview FX result, render or export a frame, compare with OpenGL baseline. | | | | |
| offscreen-render | `doc/sample_data/dwanko_run.tnz` | 24 | Run preview/export/render path, compare exported frame and confirm nonblank output. | | | | |

## Sign-Off

- OpenGL fallback remains selectable and usable:
- Metal remains opt-in unless all release/default gates above pass:
- Known differences accepted by reviewers:
- Decision:
- Reviewer:
