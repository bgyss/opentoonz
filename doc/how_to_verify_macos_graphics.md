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
```

The lint script enforces milestone invariants that should not regress, including
no direct Qt `QGL*` usage, no `glDrawPixels`, and a Metal guard on the generic
SceneViewer OpenGL selection path. It also checks that the Edit Tool and
Skeleton Tool keep their CPU picking paths for 2D tool interactions, so those
workflows do not silently fall back to `GL_SELECT` when Metal is requested. The
inventory script reports file counts and match counts for:

- legacy Qt `QGL*` APIs
- Qt `QOpenGL*` APIs
- GLU symbols
- GLEW and GLUT markers
- fixed-function drawing calls
- fixed-function matrix calls
- `glDrawPixels`
- OpenGL selection-mode APIs

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
bash scripts/verify_golden_scene_manifest.sh
```

Rows with `status=repo` must point at committed fixture files. Rows with
`status=generated` are produced by probe scripts. Rows with `status=required`
are explicit remaining fixture gaps that must be replaced by committed or
generated fixtures before Metal can become the default backend.

Committed sample data lives under `doc/sample_data`. The sample pack includes
`dwanko_run.tnz`, `cleanup.tnz`, `tga_paint.tnz`, raster/TLV/TPL/TGA assets,
and the upstream CC BY-NC 4.0 license. Use these scenes for application-level
OpenGL/Metal smoke coverage where they match the manifest categories. The
sample data verifier checks the licensed pack, representative scene assets, and
that committed scene paths remain relocatable through `$scenefolder` with
resolved in-repository dependencies.

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
`*_diff.png` for each validated case. Treat these as renderer-slice evidence,
not as a substitute for full scene-viewer golden scenes.

To turn the probe image output into a pass/fail artifact check:

```sh
nix develop path:. --command bash scripts/verify_metal_probe_images.sh /private/tmp/opentoonz-metal-probe-images
```

The verifier removes stale probe PNGs from the artifact directory, runs the
probe, checks that each case has non-empty Metal, OpenGL, and diff PNGs, and
writes `summary.txt` with file metadata and SHA-256 hashes when `shasum` is
available.

## Scripted App Launch Smoke

For a bounded backend launch smoke of the actual macOS app bundle, run:

```sh
bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke
```

By default the script launches the built app bundle once with
`OPENTOONZ_GRAPHICS_BACKEND=opengl` and once with
`OPENTOONZ_GRAPHICS_BACKEND=metal`, waits 10 seconds, stores logs under the
artifact directory, captures screenshots with `screencapture` when available,
and then terminates the app. When screenshot capture is enabled, a missing,
failed, or empty screenshot fails the smoke; each backend artifact directory
also gets `screenshot.txt` with basic image metadata. Useful overrides:

```sh
OPENTOONZ_APP=toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app \
OPENTOONZ_GRAPHICS_SMOKE_BACKENDS="opengl metal" \
OPENTOONZ_GRAPHICS_SMOKE_SECONDS=15 \
OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=4 \
OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=1 \
OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/dwanko_run.tnz \
bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke
bash scripts/verify_graphics_app_smoke_artifacts.sh /private/tmp/opentoonz-graphics-app-smoke
```

This smoke proves backend startup and captures review artifacts. It does not
prove viewer, editing, preview, export, or golden-scene parity by itself. When
`OPENTOONZ_GRAPHICS_SMOKE_SCENE` is set, it also proves that the built app can
load one committed fixture scene under each requested backend before capture;
the artifact verifier checks backend metadata, startup logs, screenshot
metadata, nonblank PNG content, and scene metadata. The rest of the manual
matrix or a future scene-driving harness is still required for full parity.

To smoke every committed `.tnz` scene listed in the golden-scene manifest:

```sh
OPENTOONZ_GRAPHICS_SMOKE_BACKENDS="opengl metal" \
OPENTOONZ_GRAPHICS_SMOKE_SECONDS=5 \
OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=1 \
bash scripts/graphics_app_smoke_manifest.sh \
  doc/macos_graphics_golden_scenes.tsv \
  /private/tmp/opentoonz-graphics-app-smoke-manifest
```

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
bash scripts/verify_golden_scene_manifest.sh
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
