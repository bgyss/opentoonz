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
no direct Qt `QGL*` usage, no `glDrawPixels`, and a Metal guard on the generic
SceneViewer OpenGL selection path. It also checks that the Edit Tool and
Skeleton Tool keep their CPU picking paths for 2D tool interactions, so those
workflows do not silently fall back to `GL_SELECT` when Metal is requested; the
remaining Skeleton Tool 3D OpenGL-selection fallback must also stay behind a
compatibility gate that is disabled for the requested Metal backend.
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
the inventory count. It allows real OpenGL selection API use only in the
explicit compatibility files, `toonz/sceneviewer.cpp` and
`tnztools/skeletontool.cpp`, and also verifies the Metal-requested guards on
both paths.

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
rigidity data.

After generating shader-effect comparison artifacts, verify the generated
shader scene fixtures with:

```sh
nix develop path:. --command bash scripts/graphics_shaderfx_compare.sh /private/tmp/opentoonz-shaderfx-compare
bash scripts/verify_shaderfx_scene_fixtures.sh /private/tmp/opentoonz-shaderfx-compare
```

Before any default-backend decision, run the strict form:

```sh
bash scripts/verify_golden_scene_manifest.sh --require-complete
```

This fails while any `status=required` row remains.

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
offline raster-placement slice. It is still a probe-level check; full
style-editor and preview/export workflow parity requires real application smoke
coverage.

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
the error recorded in `actions.txt`. The artifact verifier checks backend
metadata, startup logs, screenshot metadata, optional action metadata, nonblank
PNG content, scene metadata, and OpenGL/Metal screenshot differences when both
backend screenshots are present. The smoke script also enables
`OPENTOONZ_GRAPHICS_METAL_FRAME_DIAGNOSTICS=1`; with
`--require-direct-metal-frame`, the verifier requires a scene-viewer log line
showing `direct_content=1` and `compatibility_snapshot=0`, so the stricter
direct-Metal frame check cannot pass on process lifetime alone. The rest of the
manual matrix or a future scene-driving harness is still required for full
parity.

The default app-smoke screenshot comparison tolerances are intentionally loose
because `screencapture` captures the whole window and can include compositor
noise outside the rendered scene. Tighten these variables for controlled
captures:

```sh
OPENTOONZ_GRAPHICS_SMOKE_MAX_MEAN_DELTA=1.0
OPENTOONZ_GRAPHICS_SMOKE_MAX_CHANNEL_DELTA=255
OPENTOONZ_GRAPHICS_SMOKE_MAX_DIFFERING_RATIO=0.02
```

To smoke every committed or generated `.tnz` scene listed in the golden-scene
manifest:

```sh
OPENTOONZ_GRAPHICS_FIXTURE_DIR=/private/tmp/opentoonz-graphics-fixtures \
OPENTOONZ_SHADERFX_COMPARE_DIR=/private/tmp/opentoonz-shaderfx-compare \
OPENTOONZ_GRAPHICS_SMOKE_BACKENDS="opengl metal" \
OPENTOONZ_GRAPHICS_SMOKE_SECONDS=5 \
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
disabled screenshot evidence fails the manifest smoke.

To specifically check whether a sample scene can launch through the direct
Metal layer path instead of the OpenGL compatibility snapshot, run a Metal-only
smoke with screenshot capture disabled:

```sh
OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/dwanko_run.tnz \
OPENTOONZ_GRAPHICS_SMOKE_BACKENDS=metal \
OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=1 \
OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 \
bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-direct-metal
bash scripts/verify_graphics_app_smoke_artifacts.sh \
  /private/tmp/opentoonz-graphics-app-smoke-direct-metal \
  --require-direct-metal
```

If this passes, it is launch-plus-scene-load evidence for direct Metal
presentation. It does not replace the screenshot comparison smoke. If the log
contains duplicate Qt runtime markers such as `You might be loading two sets of
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

The summary records source and `.metallib` presence, file sizes, detected
`metal`/`metallib` tools, and a status such as `source-and-metallib` or
`source-only-toolchain-unavailable`. If both command-line Metal tools are
available, the verifier fails unless the compiled `.metallib` is packaged.

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
