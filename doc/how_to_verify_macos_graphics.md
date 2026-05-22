# How to Verify macOS Graphics Modernization

This document is the Milestone 0 verification harness for
`doc/macos_graphics_modernization_goal_prompt.md`. Use it before and after each
OpenGL cleanup or Metal backend change so renderer work is backed by comparable
evidence.

## Baseline Inventory

Run the graphics API inventory from the repository root:

```sh
bash scripts/graphics_inventory.sh
```

The script reports file counts and match counts for:

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
