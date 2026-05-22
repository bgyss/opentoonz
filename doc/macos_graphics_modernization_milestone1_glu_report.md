# macOS Graphics Modernization Milestone 1 GLU Cleanup Report

Status: partial Milestone 1 completed locally on 2026-05-22.

## Objective

This checkpoint removes GLU projection, unprojection, orthographic projection,
pick-matrix, disk, and dead image-scaling usage while preserving the existing
OpenGL backend. It also isolates the `ttessellator` GLU tessellation API behind
`TglTessellator::GLTess` methods so the rendering loops no longer call GLU's
polygon and contour API directly. A later checkpoint hides the GLU tessellator
handle type from the public `ttessellator.h` header, keeping the GLU-specific
types and include in `ttessellator.cpp`.

## Files Changed

- `toonz/sources/toonz/sceneviewer.cpp`
- `toonz/sources/common/tvrender/tofflinegl.cpp`
- `toonz/sources/common/tgl/tgl.cpp`
- `toonz/sources/common/tvectorrenderer.cpp`
- `toonz/sources/toonzqt/planeviewer.cpp`
- `toonz/sources/common/tvrender/ttessellator.cpp`
- `toonz/sources/include/ttessellator.h`
- `toonz/sources/toonzlib/imagebuilders.cpp`
- `toonz/sources/toonzlib/plasticdeformerfx.cpp`
- `toonz/sources/toonzlib/stylemanager.cpp`
- `toonz/sources/toonzlib/toonzscene.cpp`
- `toonz/sources/stdfx/iwa_flowpaintbrushfx.cpp`
- `toonz/sources/stdfx/shadingcontext.cpp`

## Changes

- Added local scene-viewer matrix helpers for projection, unprojection, and
  pick-matrix behavior.
- Replaced scene-viewer `gluProject`, `gluUnProject`, `gluPickMatrix`, and
  `gluOrtho2D` call sites.
- Replaced offscreen/vector/style/effect `gluOrtho2D` calls with equivalent
  `glOrtho(..., -1, 1)` calls.
- Replaced `tglDrawDisk`'s `gluDisk` dependency with a local triangle fan.
- Removed dead `SCALE_BY_GLU` `gluScaleImage` branches from mipmap generation;
  the active path already used `TRop::resample`.
- Added GLU-backed adapter methods on `TglTessellator::GLTess` and moved
  tessellation begin/end/contour/vertex callback calls behind that adapter.
- Replaced the public `GLUtesselator` / `GLUtriangulatorObj` member in
  `TglTessellator::GLTess` with an opaque handle so downstream headers no
  longer need GLU tessellator type definitions.

## Inventory Before and After

Previous source-like inventory from the QGL checkpoint:

```text
GLU                                files=   16 matches=   108
```

Current source-like inventory:

```text
OpenToonz graphics API inventory
source_root=toonz/sources

all graphics markers               files=  120 matches=  2804
Qt legacy QGL                      files=    0 matches=     0
Qt QOpenGL                         files=   32 matches=   218
GLU                                files=    4 matches=    54
GLEW or GLUT                       files=   10 matches=    30
fixed-function drawing             files=   85 matches=  2020
fixed-function matrix              files=   56 matches=   458
glDrawPixels                       files=    0 matches=     0
OpenGL selection                   files=    3 matches=    24
```

Direct verification:

```sh
rg -n "glu(Project|UnProject|Ortho2D|PickMatrix|Disk|ScaleImage)" toonz/sources
```

Result: no matches.

Remaining GLU usage is concentrated in tessellation adapters and the separate
`tcg` triangulation helper:

- `toonz/sources/common/tvrender/ttessellator.cpp`
- `toonz/sources/include/tcg/triangulate.h`
- `toonz/sources/include/tcg/hpp/triangulate.hpp`
- `toonz/sources/tnzext/meshbuilder.cpp`

Direct `ttessellator.h` GLU type exposure is removed; the remaining
`ttessellator` GLU calls are local to `ttessellator.cpp`.

## Validation Run

Commands run:

```sh
bash scripts/graphics_inventory.sh
git diff --check
rg -n "glu(Project|UnProject|Ortho2D|PickMatrix|Disk|ScaleImage)" toonz/sources
rg -n "GLUtesselator|GLUtriangulator|GLU_VERSION|glu[A-Za-z]|GLU_" toonz/sources/include/ttessellator.h toonz/sources/common/tvrender/ttessellator.cpp
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tnzcore OpenToonz --parallel 3
nix develop path:. --command cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=ON
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tgraphics_metal_probe OpenToonz --parallel 3
nix develop path:. --command toonz/build/nix-relwithdebinfo/tnzcore/tgraphics_metal_probe
nix develop path:. --command cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=OFF
```

Result: passed.

The latest fallback build recompiled `ttessellator.cpp`, linked `tnzcore`, and
linked `OpenToonz.app`. The Metal-enabled build linked `OpenToonz.app`, copied
the Metal shader source to Resources, and `tgraphics_metal_probe` reported
`ok on Apple M1 Max`. The broader fallback and Metal rebuilds emitted existing
unrelated warnings in image/trop/tool code, but the changed tessellator code
compiled cleanly.

## Manual Smoke

Manual GUI smoke was not run in this checkpoint. These workflows should be
exercised before merging this milestone:

- pan and zoom the scene viewer
- use 3D camera navigation
- use scene-viewer picking/selecting
- preview vector and raster levels
- use style chips and style preview UI
- run an effect preview using the updated offscreen projection paths

## Remaining Milestone 1 Work

- Replace `ttessellator`'s GLU implementation with a CPU tessellator that emits
  indexed geometry.
- Isolate or replace the separate `tcg` GLU triangulation helper.
- Continue reducing the remaining Skeleton Tool 3D `GL_SELECT` fallback.
