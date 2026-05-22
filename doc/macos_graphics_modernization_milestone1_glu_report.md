# macOS Graphics Modernization Milestone 1 GLU Cleanup Report

Status: partial Milestone 1 completed locally on 2026-05-22.

## Objective

This checkpoint removes GLU projection, unprojection, orthographic projection,
pick-matrix, disk, and dead image-scaling usage while preserving the existing
OpenGL backend. It also isolates the `ttessellator` GLU tessellation API behind
`TglTessellator::GLTess` methods so the rendering loops no longer call GLU's
polygon and contour API directly.

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

## Inventory Before and After

Previous source-like inventory from the QGL checkpoint:

```text
GLU                                files=   16 matches=   108
```

Current source-like inventory:

```text
OpenToonz graphics API inventory
source_root=toonz/sources

all graphics markers               files=  120 matches=  2883
Qt legacy QGL                      files=    0 matches=     0
Qt QOpenGL                         files=   31 matches=   206
GLU                                files=    5 matches=    53
GLEW or GLUT                       files=   10 matches=    30
fixed-function drawing             files=   85 matches=  2006
fixed-function matrix              files=   56 matches=   449
glDrawPixels                       files=    8 matches=    17
OpenGL selection                   files=    5 matches=    95
```

Direct verification:

```sh
rg -n "glu(Project|UnProject|Ortho2D|PickMatrix|Disk|ScaleImage)" toonz/sources
```

Result: no matches.

Remaining GLU usage is concentrated in tessellation adapters and the separate
`tcg` triangulation helper:

- `toonz/sources/common/tvrender/ttessellator.cpp`
- `toonz/sources/include/ttessellator.h`
- `toonz/sources/include/tcg/triangulate.h`
- `toonz/sources/include/tcg/hpp/triangulate.hpp`
- `toonz/sources/tnzext/meshbuilder.cpp`

## Validation Run

Commands run:

```sh
bash scripts/graphics_inventory.sh
git diff --check
rg -n "glu(Project|UnProject|Ortho2D|PickMatrix|Disk|ScaleImage)" toonz/sources
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --parallel 3
```

Result: passed.

The final build recompiled the affected GL utility, vector render, offscreen
render, scene viewer, stdfx, toonzlib, and toonzqt targets and linked
`OpenToonz.app`.

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

- Replace or isolate GLU tessellation in `ttessellator` and `tcg`.
- Replace `glDrawPixels` paths with texture upload and draw commands.
- Start reducing `GL_SELECT` picking usage.
