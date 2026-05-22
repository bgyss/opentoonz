# macOS Graphics Modernization Milestone 1 glDrawPixels Report

Status: partial Milestone 1 completed locally on 2026-05-22.

## Objective

This checkpoint replaces several low-risk `glDrawPixels` paths with temporary
texture upload and textured-quad drawing. It preserves the existing OpenGL
backend while moving overlay and buffer flush behavior closer to the draw-command
model needed for a future Metal backend.

## Files Changed

- `toonz/sources/tnztools/toolutils.cpp`
- `toonz/sources/tnztools/skeletontool.cpp`
- `toonz/sources/common/tvrender/tofflinegl.cpp`
- `toonz/sources/toonzqt/planeviewer.cpp`

## Changes

- Replaced tool balloon and hook overlay `glDrawPixels` calls with temporary
  RGBA texture uploads and screen-sized textured quads.
- Replaced skeleton tool overlay `glDrawPixels` calls with the same texture
  upload approach.
- Replaced the `TOfflineGL` raster constructor's initial pixel draw with the
  existing `tglDraw(TRectD, TRaster32P, false)` texture helper.
- Replaced `PlaneViewer::flushRasterBuffer()` with `tglDraw(...)`.

## Inventory Before and After

Previous inventory before this checkpoint:

```text
glDrawPixels                       files=    8 matches=    17
```

Current source-like inventory:

```text
OpenToonz graphics API inventory
source_root=toonz/sources

all graphics markers               files=  120 matches=  2870
Qt legacy QGL                      files=    0 matches=     0
Qt QOpenGL                         files=   31 matches=   206
GLU                                files=    5 matches=    53
GLEW or GLUT                       files=   10 matches=    30
fixed-function drawing             files=   85 matches=  2026
fixed-function matrix              files=   56 matches=   449
glDrawPixels                       files=    4 matches=    11
OpenGL selection                   files=    5 matches=    95
```

Remaining `glDrawPixels` sites:

- `toonz/sources/toonz/sceneviewer.cpp`
- `toonz/sources/toonzlib/stagevisitor.cpp`
- `toonz/sources/toonzlib/imagepainter.cpp`
- `toonz/sources/common/tvectorrenderer.cpp`

These remaining sites should be handled with additional visual validation
because they involve 3D side/top views, view-grab images, channel/bit-depth
paths, stage visitation, and platform-specific vector render backgrounds.

## Validation Run

Commands run:

```sh
bash scripts/graphics_inventory.sh
git diff --check
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --parallel 3
```

Result: passed.

The final build recompiled affected tool, offscreen render, plane viewer, and
OpenToonz application targets and linked `OpenToonz.app`.

## Manual Smoke

Manual GUI smoke was not run in this checkpoint. These workflows should be
exercised before merging this milestone:

- tool hook overlay drawing
- skeleton drawing-browser overlay
- skeleton main gadget overlay
- plane viewer redraw/flush paths
- offscreen raster initialization paths

## Remaining Milestone 1 Work

- Replace or isolate the remaining `glDrawPixels` paths in scene viewer,
  image-painter, stage visitor, and vector renderer code.
- Start reducing `GL_SELECT` picking usage.
