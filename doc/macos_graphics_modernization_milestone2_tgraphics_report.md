# macOS Graphics Modernization Milestone 2 tgraphics Report

Status: initial Milestone 2 slice completed locally on 2026-05-22.

## Objective

This checkpoint introduces the first backend-neutral graphics layer used by an
actual viewer path. It keeps OpenGL as the only production backend while moving
one texture draw from direct helper invocation to a small command-list and
backend encoder shape that can be backed by Metal later.

## Files Changed

- `toonz/sources/include/tgraphics.h`
- `toonz/sources/common/tgraphics/tgraphics.cpp`
- `toonz/sources/tnzcore/CMakeLists.txt`
- `toonz/sources/toonz/sceneviewer.cpp`

## Changes

- Added a new `TGraphics` namespace with concrete versions of the Milestone 2
  concepts:
  - `Device`
  - `RenderTarget`
  - `Texture`
  - `Buffer`
  - `Pipeline`
  - `CommandEncoder`
  - `DrawList2D`
  - `HitTest`
  - `ShaderLibrary`
- Added `RasterTexture` and `TextureQuad` as the first concrete draw command
  payload.
- Added an `OpenGLDevice`/`OpenGLCommandEncoder` implementation that submits
  `DrawList2D` texture quads through the existing `tglDraw(...)` path.
- Converted the frozen scene viewer grab-image path to build a `DrawList2D`
  and submit it through the OpenGL backend.
- Added the new `tgraphics` files to `tnzcore` so downstream app code can use
  the abstraction without adding another library boundary yet.

## Inventory Before and After

Previous source-like inventory before this checkpoint:

```text
glDrawPixels                       files=    4 matches=    10
```

Current source-like inventory is unchanged by this abstraction checkpoint:

```text
glDrawPixels                       files=    4 matches=    10
```

This milestone is about introducing a real backend boundary, not reducing raw
OpenGL counts in this specific checkpoint.

## Validation Run

Commands run:

```sh
bash scripts/graphics_inventory.sh
git diff --check
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --parallel 3
```

Result: passed.

The build re-ran CMake, compiled the new `tgraphics.cpp` source in `tnzcore`,
rebuilt dependent libraries, recompiled `sceneviewer.cpp`, and linked
`OpenToonz.app`.

## Manual Smoke

Manual GUI smoke was not run in this checkpoint. Before merging this milestone,
exercise the frozen viewer path and compare it against the previous OpenGL
baseline:

- launch OpenToonz with the default OpenGL backend
- open a baseline scene
- freeze the viewer
- pan/zoom/scrub around the frozen scene viewer state
- confirm the displayed frozen image remains visually equivalent

## Known Limitations

- The Metal backend is not implemented in this checkpoint.
- `OpenGLDevice` only supports raster texture quad commands.
- `RenderTarget`, `Buffer`, `Pipeline`, `HitTest`, and `ShaderLibrary` are
  intentionally minimal interface placeholders until migrated call sites need
  concrete behavior.
- Most viewer rendering still uses direct OpenGL helpers and fixed-function GL.

## Next Milestone 2 Work

- Convert another contained viewer or style-editor path to `DrawList2D`.
- Add optional command capture or frame debug labels.
- Add the macOS-only `WITH_GRAPHICS_METAL` option after the abstraction has a
  slightly larger draw surface.
- Keep OpenGL as the default and compatibility backend.
