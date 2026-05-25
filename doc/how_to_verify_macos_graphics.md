# How to Verify macOS Graphics Modernization

This document is the Milestone 0 verification harness for
`doc/macos_graphics_modernization_goal_prompt.md`. Use it before and after each
OpenGL cleanup or Metal backend change so renderer work is backed by comparable
evidence.

## Baseline Inventory

Run the graphics API inventory from the repository root:

```sh
bash scripts/graphics_modernization_lint.sh
bash scripts/graphics_inventory.sh
bash scripts/verify_opengl_selection_compatibility.sh
```

The lint script enforces milestone invariants that should not regress, including
no direct Qt `QGL*` usage, no `glDrawPixels`, and no SceneViewer OpenGL
selection-mode implementation. It also checks that the Edit Tool and Skeleton
Tool keep their CPU picking paths, so those workflows do not silently fall back
to `GL_SELECT`.
For already-migrated viewer/style surfaces, it verifies that PlaneViewer
background and raster presentation still use `tgraphics` draw lists, the Style
Editor color wheel remains a QWidget/QPainter surface without direct OpenGL
drawing, and the camera-mask/color-card overlays remain on `DrawList2D`. It
also validates committed sample data and generated fixture scenes when those
verifier scripts are present, and checks that the macOS workflow still runs the
Metal probe image verifier, the offscreen/style probe verifier, the OpenGL
selection compatibility verifier, and the shader-effect scene-fixture verifier.
The inventory script reports file counts and match counts for:

- legacy Qt `QGL*` APIs
- Qt `QOpenGL*` APIs
- GLU symbols
- GLEW and GLUT markers
- fixed-function drawing calls
- fixed-function matrix calls
- `glDrawPixels`
- OpenGL selection-mode APIs

`scripts/verify_opengl_selection_compatibility.sh` is a stricter companion to
the inventory count. It requires SceneViewer selection-mode API use to stay
removed and allows the remaining OpenGL name-stack markers only in the Skeleton
Tool compatibility drawing code while verifying that Skeleton Tool no longer
calls the generic OpenGL selection picker.

Include the inventory output in each graphics milestone handoff. The important
trend is not that every count drops immediately; it is that each milestone can
show which legacy surface it changed and which surface remains.

## Baseline Warning Count

Capture a build log and count warnings from the current checkout:

```sh
nix develop path:. --command bash -lc 'bash scripts/nix/prepare-tiff.sh && cmake -S toonz/sources --preset nix-relwithdebinfo'
nix develop path:. --command bash -lc 'cmake --build toonz/build/nix-relwithdebinfo --parallel 3 > /private/tmp/opentoonz-build.log 2>&1'
rg -n "warning:" /private/tmp/opentoonz-build.log | wc -l
rg -n "OpenGL|QGL|QOpenGL|GLU|deprecated" /private/tmp/opentoonz-build.log | head -n 80
```

When comparing warning counts, keep the compiler, SDK, Qt version, CMake preset,
and build type unchanged.

For the CI-style build-time and warning summary used by the macOS matrix, run:

```sh
OPENTOONZ_CI_BUILD_LABEL=macos-arm64-local \
OPENTOONZ_BUILD_PARALLEL=3 \
scripts/macos/ci-build-summary.sh
```

The summary records elapsed seconds, `WITH_GRAPHICS_METAL`, total warnings,
Apple OpenGL deprecation warnings, Qt `QGL*` warning lines, deprecated
`QOpenGL*` warning lines, and ccache stats.

## Golden Scene Requirements

The Metal backend should not become the default until it matches OpenGL on a
small but representative set of scenes. If fixture scenes are not available in
the checkout, create or identify scenes with these characteristics:

- raster level with transparency and camera movement
- vector level with fills, strokes, palette edits, and antialiasing
- palette/style editor coverage with color changes
- mesh deformation or skeleton-driven deformation
- camera transform with pan, zoom, rotate, and field guide overlays
- onion skin enabled
- sub-xsheet compositing
- one or more common shader effects
- offscreen render/export path for at least one frame

Record the exact fixture paths, frame numbers, viewer settings, DPI scale, theme,
and backend used for captures.

The current golden-scene coverage manifest lives at
`doc/macos_graphics_golden_scenes.tsv`. Validate it with:

```sh
bash scripts/verify_sample_data.sh
bash scripts/verify_graphics_fixture_scenes.sh /tmp/opentoonz-graphics-fixtures
bash scripts/verify_golden_scene_manifest.sh
```

Rows with `status=repo` must point at committed fixture files. Rows with
`status=generated` are produced by probe or fixture-generation scripts. Rows
with `status=required` are explicit remaining fixture gaps that must be
replaced by committed or generated fixtures before Metal can become the default
backend.

Committed sample data lives under `doc/sample_data`. The sample pack includes
`dwanko_run.tnz`, `cleanup.tnz`, `tga_paint.tnz`, raster/TLV/TPL/TGA assets,
and the upstream CC BY-NC 4.0 license. Use these scenes for application-level
OpenGL/Metal smoke coverage where they match the manifest categories. The
sample data verifier checks the licensed pack, representative scene assets, and
that committed scene paths remain relocatable through `$scenefolder` with
resolved in-repository dependencies.

`scripts/generate_graphics_fixture_scenes.sh` materializes deterministic
fixtures that should not be maintained as large checked-in scene XML. The
current generated fixtures are `sub_xsheet_basic.tnz`, a nested child-level
scene backed by the committed sample TLV data, and `mesh_skeleton_basic.tnz`, a
mesh-column scene backed by a generated `.mesh` frame with triangular faces and
rigidity data. The fixture verifier checks that sub-xsheet level dependencies
are declared before the childLevel references them, matching the ordering needed
by the OpenToonz scene loader.

After generating shader-effect comparison artifacts, verify the generated
shader scene fixtures with:

```sh
nix develop path:. --command bash scripts/graphics_shaderfx_compare.sh /private/tmp/opentoonz-shaderfx-compare
bash scripts/verify_shaderfx_scene_fixtures.sh /private/tmp/opentoonz-shaderfx-compare
```

Before any default-backend decision, run the strict form:

```sh
bash scripts/verify_golden_scene_manifest.sh --require-complete
bash scripts/verify_macos_default_backend_decision.sh
```

The manifest verifier fails while any `status=required` row remains. The
default-backend decision verifier keeps the explicit OpenGL-default decision in
`doc/macos_graphics_default_backend_decision.md` aligned with the CMake default,
runtime selector, macOS CI matrix, and build-summary evidence until the Metal
switch criteria are satisfied.

## OpenGL Baseline Capture

Before changing renderer behavior, capture OpenGL output for each fixture:

```sh
OPENTOONZ_GRAPHICS_BACKEND=opengl <path-to-built-OpenToonz-app-or-binary>
```

For each fixture:

- open the scene
- set the documented frame and viewer settings
- capture the scene viewer at a fixed window size
- export or preview the documented frame when the fixture covers rendering
- save the image with backend, fixture name, and frame in the filename

If a scripted screenshot harness is unavailable, record the manual steps and
store screenshots as local artifacts outside the repository.

## Metal Comparison Capture

When the Metal backend exists, repeat the same captures with:

```sh
OPENTOONZ_GRAPHICS_BACKEND=metal <path-to-built-OpenToonz-app-or-binary>
```

For a narrow direct-Metal scene-viewer smoke on simple full-color raster scenes
or `TRaster32P` preview rasters, the experimental Metal path can skip the final
OpenGL framebuffer snapshot when direct Metal content was emitted:

```sh
OPENTOONZ_GRAPHICS_BACKEND=metal \
OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=1 \
<path-to-built-OpenToonz-app-or-binary>
```

This is intentionally not the default. If the current frame has no eligible
direct Metal scene or preview content, the viewer still presents the
compatibility OpenGL snapshot so unsupported vector, onion-skin, editing,
effect, and overlay cases remain visible.

Compare against the OpenGL baseline. A future automated harness can use
ImageMagick, perceptualdiff, or a small Python image comparison script, but the
comparison must report:

- fixture path
- frame
- backend pair
- image dimensions
- tolerance
- diff score or manual review result
- known expected differences

For the current Milestone 3 `DrawList2D` probe coverage, the Metal probe can
write deterministic Metal/OpenGL/diff PNG artifacts without launching the full
OpenToonz UI:

```sh
nix develop path:. --command bash -lc 'cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=ON'
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tgraphics_metal_probe --parallel 3
nix develop path:. --command toonz/build/nix-relwithdebinfo/tnzcore/tgraphics_metal_probe --write-images /private/tmp/opentoonz-metal-probe-images
find /private/tmp/opentoonz-metal-probe-images -maxdepth 1 -type f -name '*.png' | sort
```

The probe writes one `*_metal.png`, one `*_opengl.png`, and one amplified
`*_diff.png` for each validated case. The required cases include an editing
tool-overlay slice with selection outlines, transform handles, vector control
points, and skeleton guide strokes; the transparent style-icon offscreen path
used by solid style chips; and the legacy offline raster-placement slice used
to stage preview/export migration away from `TOfflineGL`. These guard migrated
renderer slices and interaction-overlay primitives, not full scene-viewer golden
scene parity.

To turn the probe image output into a pass/fail artifact check:

```sh
nix develop path:. --command bash scripts/verify_metal_probe_images.sh /private/tmp/opentoonz-metal-probe-images
```

The verifier removes stale probe PNGs from the artifact directory, runs the
probe, checks that each case has non-empty Metal, OpenGL, and diff PNGs,
requires the editing tool-overlay, transparent style-icon, and legacy offline
raster-placement case artifacts, and writes `summary.txt` with file metadata
and SHA-256 hashes when `shasum` is available.

For the narrower application-adjacent Milestone 5 probes, run:

```sh
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tofflinegl_probe styleeditor_colorwheel_probe --parallel 3
nix develop path:. --command bash scripts/verify_macos_offscreen_style_probes.sh
nix develop path:. --command bash scripts/verify_macos_preview_export_probe.sh /private/tmp/opentoonz-preview-export-probe
```

This runs the `TOfflineGL` clear/raster-placement baseline against the active
`tgraphics` backend in both OpenGL and Metal modes, then renders the migrated
style-editor color wheel with Qt's offscreen platform and fails if the result is
blank or lacks saturated color-wheel pixels. The preview/export verifier writes
OpenGL, Metal, legacy OpenGL, and amplified diff PNG artifacts for the legacy
offline raster-placement slice, rejects blank artifacts, and requires exact
zero-difference matches between OpenGL active, Metal active, and both legacy
reference artifacts. It is still a probe-level check; full
style-editor and preview/export workflow parity requires real application smoke
coverage.

After packaging the app bundle, run the focused app-level preview/export smoke:

```sh
bash scripts/verify_macos_preview_export_app_smoke.sh /private/tmp/opentoonz-preview-export-app-smoke
```

This generates the TIFF-backed `tcomposer-color-card` scene fixture, launches
the packaged app under OpenGL and Metal, runs
`OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=internal-preview-export`, requires the
color-card PNG to come from the Previewer cache raster, and exact-compares the
OpenGL and Metal preview-export PNGs. It also runs the committed
`doc/sample_data/tga_paint.tnz` TLV sample through the same app preview/export
path, requires traced nonblank OpenGL and Metal preview-export PNGs, and allows
the viewer framebuffer fallback when the Previewer cache raster is blank for
that scene. The TLV sample is intentionally not exact-compared because the
fallback export can be viewer-sized and differ by a small viewport extent while
still proving both backends launch, render, and export nonblank output.
It also runs the committed `doc/sample_data/dwanko_run.tnz` FX/vector sample at
frame 24, requires the saved PNG to come from the Previewer cache raster, and
exact-compares OpenGL and Metal output.

After packaging the app bundle, run the focused app-level style editor smoke:

```sh
bash scripts/verify_macos_style_editor_app_smoke.sh /private/tmp/opentoonz-style-editor-app-smoke
```

This launches the packaged app under OpenGL and Metal, runs
`OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=internal-style-editor`, opens the Style
Editor, changes a real palette style through the current palette handle,
notifies the style editor/listener path, restores the original style, and
requires change and restore traces in the smoke artifacts.

After packaging the app bundle, run the focused app-level viewer input smoke:

```sh
bash scripts/verify_macos_viewer_input_app_smoke.sh /private/tmp/opentoonz-viewer-input-app-smoke
```

This launches the packaged app under OpenGL and Metal, runs
`OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=internal-viewer-input`, switches to the Hand
and Selection tools, and sends Qt mouse press/move/release events directly to
the active SceneViewer. The artifact verifier requires tool and event traces for
both gestures. This covers SceneViewer mouse-event routing in CI without macOS
Accessibility permissions; it is still separate from an Accessibility-authorized
system input smoke.

On an interactive or CI macOS runner where `osascript` has
Automation/Accessibility permission to drive `System Events`, run the
system-level viewer smoke:

```sh
bash scripts/verify_macos_system_viewer_app_smoke.sh /private/tmp/opentoonz-system-viewer-app-smoke
```

This launches the packaged app under OpenGL and Metal, runs
`OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=basic-viewer`, sends a center-window mouse
click plus playback/scrub/zoom keyboard events through macOS System Events, and
requires nonblank screenshot evidence for both backends. The macOS workflow can
run this gate through `workflow_dispatch` with `system_gui_smoke=true`; it is
off by default because default GitHub-hosted runners may not grant the required
Accessibility/Automation permissions.

After packaging the app bundle, run the focused app-level drawing gesture smoke:

```sh
bash scripts/verify_macos_drawing_gesture_app_smoke.sh /private/tmp/opentoonz-drawing-gesture-app-smoke
```

This launches the packaged app under OpenGL and Metal, loads
`doc/sample_data/tga_paint.tnz`, switches to the Brush tool, sends a Qt
press/move/move/release gesture to the active SceneViewer, and compares a
before/after summary of the current tool image. The artifact verifier requires
the gesture traces and `main_internal_drawing_changed changed=1`; the wrapper
also requires the Metal run to emit a direct frame trace with
`direct_content=1` and `compatibility_snapshot=0`.

For a packaged helper scene-export check using committed sample data, build and
package the app bundle, then run:

```sh
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tcomposer --parallel 3
nix develop path:. --command bash scripts/macos/package-nix-app.sh
bash scripts/verify_macos_tcomposer_scene_export.sh /private/tmp/opentoonz-tcomposer-scene-export
```

By default this reads `doc/macos_graphics_golden_scenes.tsv`, generates the
`tcomposer-color-card` fixture row, includes the committed
`offscreen-export`, `tcomposer-cleanup-scan`, and `tcomposer-tlv-paint` sample
rows, and runs bundled `tcomposer` for each selected frame once with
`OPENTOONZ_GRAPHICS_BACKEND=opengl` and once with
`OPENTOONZ_GRAPHICS_BACKEND=metal`, using the packaged `portablestuff`
directory as an absolute `TOONZROOT`. It requires each rendered frame file,
checks that `tcomposer` reported a computed frame, rejects single-color black
TIFF output with ImageMagick, and byte-compares the OpenGL and Metal TIFF
outputs for each selected manifest row. It also writes per-backend
`image-stats.txt` files and includes the TIFF color/maxima/nonzero-pixel counts
in `summary.txt`; raise `OPENTOONZ_TCOMPOSER_MIN_NONZERO_PIXELS` above the
default of `1` when using a scene that should produce substantial camera
coverage. Set
`OPENTOONZ_TCOMPOSER_INCLUDE_REPO_SCENES=1` to also try committed sample `.tnz`
rows; those rows are useful diagnostics but must pass the same nonblack gate
before they count as parity evidence. To run one focused scene instead of the
manifest set, set `OPENTOONZ_TCOMPOSER_SCENE` and optionally
`OPENTOONZ_TCOMPOSER_FRAME`. Set `OPENTOONZ_TCOMPOSER_DEBUG_LEVELS=1` to print
decoded helper level paths, frame availability, xsheet bboxes, and built
render-FX bboxes into `tcomposer.log` while debugging missing or black sample
outputs. In restricted command sandboxes, `QApplication`
pasteboard setup can abort before rendering; run this verifier from a normal
macOS shell or CI runner when that happens. This is scene-level helper export
evidence only when the output is nonblack; it does not replace GUI
preview/export smoke.

## Scripted App Launch Smoke

For a bounded backend launch smoke of the actual macOS app bundle, run:

```sh
bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke
```

By default the script launches the built app bundle once with
`OPENTOONZ_GRAPHICS_BACKEND=opengl` and once with
`OPENTOONZ_GRAPHICS_BACKEND=metal`, waits 10 seconds, stores logs under the
artifact directory, captures screenshots with `screencapture` when available,
and then asks the app bundle to quit through Apple Events before falling back to
process signals. When screenshot capture is enabled, a missing, failed, or
empty screenshot fails the smoke; each backend artifact directory also gets
`screenshot.txt` with basic image metadata. Useful overrides:

```sh
OPENTOONZ_APP=toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app \
OPENTOONZ_GRAPHICS_SMOKE_BACKENDS="opengl metal" \
OPENTOONZ_GRAPHICS_SMOKE_SECONDS=15 \
OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=4 \
OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=1 \
OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/dwanko_run.tnz \
OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=basic-viewer \
OPENTOONZ_GRAPHICS_SMOKE_BUNDLE_ID=io.github.opentoonz.OpenToonz \
bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke
bash scripts/verify_graphics_app_smoke_artifacts.sh /private/tmp/opentoonz-graphics-app-smoke
```

This smoke proves backend startup and captures review artifacts. It does not
prove viewer, editing, preview, export, or golden-scene parity by itself. When
`OPENTOONZ_GRAPHICS_SMOKE_SCENE` is set, it also proves that the built app can
load one committed fixture scene under each requested backend before capture;
when `OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=basic-viewer` is set, it activates the
app and sends a small playback/scrub/zoom event sequence before screenshot
capture so the smoke covers basic event delivery in addition to startup. This
mode requires macOS Automation/Accessibility permission for `osascript` and
`System Events`; if macOS denies synthetic input, the action smoke fails with
the error recorded in `actions.txt`. On success, `actions.txt` records
`system_mouse=center-window-click`,
`system_keyboard=space,space,right,left,plus,minus`, and `result=ok`, and the
artifact verifier requires those lines for `basic-viewer` action smokes.
`OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=internal-basic-viewer` runs a smaller
in-process viewer action sequence after scene load. It resets the viewer, zooms
in/out, scrubs the current frame handle, invalidates the viewer, and requires
the `main_internal_actions_done` trace. Use
`OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=internal-editing-context` for the stronger CI
path: it performs the same viewer sequence, then switches through the Animate,
Selection, Brush, Geometric, Skeleton, and Hand tools and verifies each tool
trace. `OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=internal-viewer-input` switches to the
Hand and Selection tools and sends Qt mouse press/move/release events to the
active SceneViewer, requiring per-tool and per-event traces.
`OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=internal-drawing-gesture` switches to the
Brush tool, sends a Qt press/move/move/release gesture to the active
SceneViewer, and records before/after current-image summaries. The artifact
verifier requires `main_internal_drawing_changed changed=1`, so this mode fails
if the event path runs but no drawing data changes.
`OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=internal-preview-export` enables
SceneViewer full preview, waits for the current preview frame to become ready,
and asks the app to save `preview-export.png`. The app first attempts to use the
Previewer cache raster and records a raster summary; if that cache raster is
blank, it tries an in-app scene render for the same frame before falling back to
the visible full-preview SceneViewer framebuffer or widget grab, and records
`main_internal_preview_export_source`. The artifact
verifier requires frame-ready, export-source, and export-saved traces and
rejects a missing or single-color preview export. Add
`--require-preview-raster-export` when verifying artifacts to require the
saved PNG to come directly from the Previewer cache raster instead of a
SceneViewer framebuffer or widget fallback.
`OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=internal-style-editor` performs the viewer
sequence, opens the Style Editor, changes and restores the current palette
style, and requires `main_internal_style_editor_changed` and
`main_internal_style_editor_restored` traces. These modes avoid macOS
synthetic-input permission prompts; only `basic-viewer` proves system keyboard
event delivery through macOS Automation/Accessibility. The artifact verifier
checks backend
metadata, startup logs, screenshot metadata, optional action metadata, nonblank
PNG content, scene metadata, and OpenGL/Metal screenshot differences when both
backend screenshots are present. The smoke script also enables
`OPENTOONZ_GRAPHICS_METAL_FRAME_DIAGNOSTICS=1`; with
`--require-direct-metal-frame`, the verifier requires a scene-viewer log line
or `graphics-smoke-trace.txt` entry showing `direct_content=1` and
`compatibility_snapshot=0`, so the stricter direct-Metal frame check cannot
pass on process lifetime alone. To reduce dependence on the user's saved room
state, the smoke harness copies the bundled profiles into the artifact
directory, writes a known `currentRoom.txt`, disables lazy room loading, and
forces `ViewBBoxToggleAction1 "0"` in the isolated smoke profile before launch.
Set
`OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_STARTUP_TRACE=1` to make the smoke fail
unless the app writes the `main_after_main_window` trace within the smoke
timeout. Set `OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_METAL_FRAME_TRACE=1` for a
Metal-only smoke that waits for a direct Metal frame trace during the launch
window. The rest of the manual matrix or a future scene-driving harness is still
required for full parity.

The default app-smoke screenshot comparison tolerances are intentionally loose
because `screencapture` captures the whole window and can include compositor
noise outside the rendered scene. Tighten these variables for controlled
captures:

```sh
OPENTOONZ_GRAPHICS_SMOKE_MAX_MEAN_DELTA=8.0
OPENTOONZ_GRAPHICS_SMOKE_MAX_CHANNEL_DELTA=255
OPENTOONZ_GRAPHICS_SMOKE_MAX_DIFFERING_RATIO=0.95
OPENTOONZ_GRAPHICS_SMOKE_MAX_SHIFT=16
OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT_RETRIES=3
```

The app-smoke screenshot gate compares whole-window captures, so the defaults
allow small compositor/color-management differences and bounded pixel shifts.
The smoke harness retries screenshots that decode as blank before accepting the
artifact. When `OPENTOONZ_GRAPHICS_SMOKE_INTERNAL_SCREENSHOT` is set by the
smoke harness, OpenToonz first tries to save an in-process SceneViewer PNG. It
uses framebuffer readback first, falls back to grabbing the visible viewer
widget when framebuffer readback is unavailable or blank, and writes the
temporary file with an explicit PNG format before atomically renaming it. The
shell harness prefers that artifact over `screencapture`; this avoids desktop
capture failures for viewer-scene parity smokes. Use the probe and export
verifiers for exact pixel parity checks.

To smoke every committed or generated `.tnz` scene listed in the golden-scene
manifest:

```sh
OPENTOONZ_GRAPHICS_FIXTURE_DIR=/private/tmp/opentoonz-graphics-fixtures \
OPENTOONZ_SHADERFX_COMPARE_DIR=/private/tmp/opentoonz-shaderfx-compare \
OPENTOONZ_GRAPHICS_SMOKE_BACKENDS="opengl metal" \
OPENTOONZ_GRAPHICS_SMOKE_SECONDS=5 \
OPENTOONZ_GRAPHICS_SMOKE_MANIFEST_SCENE_TIMEOUT_SECONDS=90 \
OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=1 \
bash scripts/graphics_app_smoke_manifest.sh \
  doc/macos_graphics_golden_scenes.tsv \
  /private/tmp/opentoonz-graphics-app-smoke-manifest
```

The macOS Metal CI leg runs this manifest smoke after packaging, using
`$RUNNER_TEMP/opentoonz-graphics-fixtures` for generated scene fixtures and
`$RUNNER_TEMP/opentoonz-shaderfx-compare` for generated shader-effect scene
fixtures, then uploads the fixture and smoke artifact directories with the Metal
graphics artifacts. When `OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT` is enabled, the
manifest wrapper verifies each scene with `--require-screenshot`, so missing or
disabled screenshot evidence fails the manifest smoke. The wrapper also passes
the manifest `frame` column as `OPENTOONZ_GRAPHICS_SMOKE_FRAME`; the artifact
verifier requires a matching `main_smoke_frame_set` trace when a row requests a
specific frame. The vector row uses `doc/sample_data/dwanko_run.tnz`, which
contains committed PLI vector levels, so vector scene loading is exercised by
the app-smoke manifest instead of being skipped as a standalone `.pli` asset. A
per-scene timeout, controlled by
`OPENTOONZ_GRAPHICS_SMOKE_MANIFEST_SCENE_TIMEOUT_SECONDS`, bounds each manifest
row so a launch hang or unexpected crash reports the active scene and artifact
directory instead of consuming the whole macOS CI job timeout. The CI workflow
also applies a step-level timeout to the manifest smoke. A local 13-row
manifest run with internal screenshots enabled produced nonblank
OpenGL and Metal screenshots for every current row and exact OpenGL/Metal
equality for each accepted internal capture.

To specifically check whether a sample scene can launch through the direct
Metal layer path instead of the OpenGL compatibility snapshot, run a Metal-only
smoke with screenshot capture disabled:

```sh
OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/tga_paint.tnz \
OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=internal-editing-context \
OPENTOONZ_GRAPHICS_SMOKE_BACKENDS=metal \
OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=1 \
OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_STARTUP_TRACE=1 \
OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_METAL_FRAME_TRACE=1 \
OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 \
bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-direct-metal
bash scripts/verify_graphics_app_smoke_artifacts.sh \
  /private/tmp/opentoonz-graphics-app-smoke-direct-metal \
  --require-direct-metal-frame
```

If this passes, it proves the packaged app reached the scene viewer and emitted
at least one direct Metal frame without the OpenGL compatibility snapshot for
the selected scene and smoke profile. `tga_paint.tnz` is used for this narrow
gate because it is a simple committed raster scene whose current smoke profile
can produce `direct_content=1` and `compatibility_snapshot=0`; broader camera,
FX, vector, onion-skin, and export coverage stays in the manifest smoke and
probe checks. It does not replace the screenshot comparison smoke. If the log
contains duplicate Qt runtime markers such as
`You might be loading two sets of
Qt binaries` or Cocoa platform plugin initialization failure, treat that as a
packaging/runtime issue rather than a Metal renderer mismatch.
In the current local environment, direct-Metal screenshot capture can also fail
with `screencapture` reporting `could not create image from display`; that is a
screen-capture environment failure. Keep the direct-Metal smoke at
`OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0` until a capture-capable runner or manual
session proves the direct-layer screenshot path.
Use `--require-screenshot` with the artifact verifier for smoke runs that are
intended to provide image evidence; the direct-Metal CI smoke intentionally does
not set that option while this local screen-capture limitation remains.

Before trusting packaged app smoke results, verify the app bundle is not mixing
bundled Qt dylibs and Nix-store Qt references, and that GNU `libiconv` imports
from bundled dependencies resolve to the bundled GNU iconv library instead of
Darwin `libiconv`:

```sh
bash scripts/macos/verify-bundled-qt-runtime.sh toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app
```

`scripts/macos/graphics-app-smoke.sh` runs this verifier automatically before
launching the packaged app when the verifier script is present, so stale bundles
fail before producing misleading Qt/Cocoa or dyld startup crash logs. The smoke
writes the result to `preflight.txt` under the artifact directory, and
`scripts/verify_graphics_app_smoke_artifacts.sh` requires that metadata to show
`verify-bundled-qt-runtime: ok`.

To verify and record Metal shader packaging state:

```sh
OPENTOONZ_METAL_RESOURCE_SUMMARY=/tmp/opentoonz-metal-resources-summary.txt \
  bash scripts/macos/verify-metal-resources.sh toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app
```

The summary records repository and bundled source presence, file sizes,
SHA-256 hashes, `.metallib` presence, detected `metal`/`metallib` tools, and a
status such as `source-and-metallib` or `source-only-toolchain-unavailable`.
The verifier fails if the bundled `.metal` file differs from the repository
source. If both command-line Metal tools are available, it also fails unless the
compiled `.metallib` is packaged.

Release-grade Metal package validation must require the compiled shader
library explicitly:

```sh
OPENTOONZ_REQUIRE_METALLIB=1 \
OPENTOONZ_METAL_RESOURCE_SUMMARY=/tmp/opentoonz-metal-resources-summary.txt \
  bash scripts/macos/verify-metal-resources.sh toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app
```

The macOS Metal CI leg runs the non-strict verifier and uploads the summary.
This proves bundled source parity on GitHub-hosted runners even when Apple's
command-line Metal tools are unavailable. Release-grade Metal package
validation still requires running the strict form above on a runner or machine
where `xcrun --find metal` and `xcrun --find metallib` succeed.

The macOS workflow also exposes a dispatch-time strict resource gate. Run the
workflow with `strict_metallib=true` to configure the Metal matrix leg with
`-DWITH_GRAPHICS_METAL_REQUIRE_METALLIB=ON` and verify the packaged bundle with
`OPENTOONZ_REQUIRE_METALLIB=1`:

```sh
gh workflow run "MacOS Build" \
  --ref <branch-or-sha> \
  -f strict_metallib=true \
  -f system_gui_smoke=false
```

This dispatch run is expected to fail on runners that cannot provide both
`xcrun --find metal` and `xcrun --find metallib`; that failure is the intended
release-readiness signal, not a normal push-CI regression.

Before a release/default-readiness run, use the preflight script to check the
local or runner prerequisites and print the exact dispatch commands for the
strict `.metallib` and system GUI smoke gates:

```sh
bash scripts/verify_macos_release_readiness_prereqs.sh <branch-or-sha>
```

The preflight requires macOS, `gh`, `xcrun`, `codesign`, `security`,
`osascript`, `metal`, `metallib`, `notarytool`, `stapler`, an authenticated
GitHub CLI session, a Developer ID signing identity, notary credentials, and
System Events reachability. Accessibility/Automation approval for System Events
is still an interactive macOS permission; if that approval is missing, the
dispatch `system_gui_smoke=true` run is expected to fail with System Events
metadata in the smoke artifacts.

Use `doc/macos_graphics_manual_walkthrough_checklist.md` for the final
human-driven release/default-readiness pass. The checklist mirrors the
golden-scene manifest categories and records OpenGL result, Metal result,
evidence path, and reviewer notes for each workflow. Keep it verified with:

```sh
bash scripts/verify_macos_manual_walkthrough_checklist.sh
```

To verify downloaded Apple-hosted macOS CI artifacts after a workflow run:

```sh
gh run download <run-id> --dir /tmp/opentoonz-macos-ci-artifacts
bash scripts/verify_macos_ci_artifacts.sh /tmp/opentoonz-macos-ci-artifacts
```

The CI artifact verifier checks both matrix build summaries, elapsed build
time, warning-count fields, ccache summaries, Metal resource summary status,
packaged app preflight metadata, direct Metal frame traces, preview-export
traces, Style Editor traces, viewer-input traces, packaged `tcomposer`
nonblack statistics, and probe summary evidence. Use this verifier when
refreshing the Apple-hosted CI evidence required before any default-backend
change.

For user-facing backend selection and troubleshooting commands, see
`doc/how_to_build_macosx.md`.

## Manual Smoke Matrix

Run this matrix for both OpenGL fallback and Metal when the Metal backend exists:

- launch OpenToonz
- open a raster fixture scene
- open a vector fixture scene
- pan and zoom the scene viewer
- scrub and play the timeline
- toggle camera view
- toggle onion skin
- draw or select a simple stroke
- transform a selected drawing
- use the style editor
- preview or export one representative frame

Record pass/fail results and any visible differences in the milestone handoff.

## Required Validation Commands

Run these after each milestone unless the handoff explains why they cannot run
in the current environment:

```sh
bash scripts/graphics_inventory.sh
bash scripts/graphics_modernization_lint.sh
bash scripts/verify_golden_scene_manifest.sh --require-complete
git diff --check
nix develop path:. --command bash -lc 'bash scripts/nix/prepare-tiff.sh && cmake -S toonz/sources --preset nix-relwithdebinfo'
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --parallel 3
```

For packaging or backend-resource changes on macOS:

```sh
nix develop path:. --command bash -lc 'scripts/macos/package-nix-app.sh'
nix develop path:. --command bash -lc 'scripts/macos/assert-arm64-bundle.sh'
```

## Milestone Handoff Checklist

Every graphics milestone handoff should include:

- files changed
- build commands run
- smoke commands run
- graphics inventory before and after
- warning count before and after when relevant
- screenshot or image-diff evidence when rendering changed
- known visual or behavioral differences
- next milestone recommendation
