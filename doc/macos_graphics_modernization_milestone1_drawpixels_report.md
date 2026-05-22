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
- `toonz/sources/toonz/sceneviewer.cpp`

## Changes

- Replaced tool balloon and hook overlay `glDrawPixels` calls with temporary
  RGBA texture uploads and screen-sized textured quads.
- Replaced skeleton tool overlay `glDrawPixels` calls with the same texture
  upload approach.
- Replaced the `TOfflineGL` raster constructor's initial pixel draw with the
  existing `tglDraw(TRectD, TRaster32P, false)` texture helper.
- Let `tglDraw(...)` own raster locking in the `TOfflineGL` raster constructor
  to avoid nested locks.
- Replaced `PlaneViewer::flushRasterBuffer()` with `tglDraw(...)`.
- Replaced the frozen scene viewer grab-image draw with `tglDraw(...)`.
- Follow-up: replaced `ImagePainter::onVectorImage()` checkerboard background
  `glDrawPixels` with the existing `tglDraw(TRectD, TRaster32P, false)`
  texture helper. This covers the 32-bit vector-image checkerboard case while
  leaving high-bit-depth raster presentation paths unchanged.
- Follow-up: replaced the `Stage::RasterPainter::flushRasterImages()` final
  premultiplied buffer upload with `GLRasterPainter::drawRaster(...)`. This
  keeps the existing CPU composition path and preserves
  `GL_ONE, GL_ONE_MINUS_SRC_ALPHA` blending while moving the presentation step
  from direct pixel upload to texture-backed drawing.

## Inventory Before and After

Previous inventory before this checkpoint:

```text
glDrawPixels                       files=    8 matches=    17
```

Current source-like inventory after the initial checkpoint:

```text
OpenToonz graphics API inventory
source_root=toonz/sources

all graphics markers               files=  120 matches=  2869
Qt legacy QGL                      files=    0 matches=     0
Qt QOpenGL                         files=   31 matches=   206
GLU                                files=    5 matches=    53
GLEW or GLUT                       files=   10 matches=    30
fixed-function drawing             files=   85 matches=  2026
fixed-function matrix              files=   56 matches=   449
glDrawPixels                       files=    4 matches=    10
OpenGL selection                   files=    5 matches=    95
```

Current source-like inventory after the vector checkerboard follow-up:

```text
OpenToonz graphics API inventory
source_root=toonz/sources

all graphics markers               files=  121 matches=  2864
Qt legacy QGL                      files=    0 matches=     0
Qt QOpenGL                         files=   32 matches=   218
GLU                                files=    5 matches=    53
GLEW or GLUT                       files=   10 matches=    30
fixed-function drawing             files=   85 matches=  2009
fixed-function matrix              files=   56 matches=   450
glDrawPixels                       files=    4 matches=     9
OpenGL selection                   files=    5 matches=    95
```

Current source-like inventory after the stage raster flush follow-up:

```text
OpenToonz graphics API inventory
source_root=toonz/sources

all graphics markers               files=  121 matches=  2860
Qt legacy QGL                      files=    0 matches=     0
Qt QOpenGL                         files=   32 matches=   218
GLU                                files=    5 matches=    53
GLEW or GLUT                       files=   10 matches=    30
fixed-function drawing             files=   85 matches=  2009
fixed-function matrix              files=   56 matches=   447
glDrawPixels                       files=    3 matches=     8
OpenGL selection                   files=    5 matches=    95
```

Remaining `glDrawPixels` sites:

- `toonz/sources/toonz/sceneviewer.cpp`
- `toonz/sources/toonzlib/imagepainter.cpp`
- `toonz/sources/common/tvectorrenderer.cpp`

These remaining sites should be handled with additional visual validation
because they involve 3D side/top views, channel/bit-depth paths, stage
visitation, and platform-specific vector render backgrounds. The 3D scene
viewer buttons still need a screen-space texture helper because the existing
code positions the raster with `glRasterPos3f`.

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

Vector checkerboard follow-up validation:

```sh
bash scripts/graphics_inventory.sh
git diff --check
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target toonzlib OpenToonz --parallel 3
nix develop path:. --command toonz/build/nix-relwithdebinfo/tnzcore/tgraphics_metal_probe
nix develop path:. --command cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=OFF
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target toonzlib OpenToonz --parallel 3
```

Result: passed. The Metal-enabled build linked `OpenToonz.app` and
`tgraphics_metal_probe` reported `ok on Apple M1 Max`. The fallback build also
linked `OpenToonz.app`. The broader fallback rebuild emitted existing unrelated
warnings in image/trop/tool/viewer code, but the changed `imagepainter.cpp`
compiled cleanly.

Stage raster flush follow-up validation:

```sh
bash scripts/graphics_inventory.sh
git diff --check
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target toonzlib OpenToonz --parallel 3
nix develop path:. --command cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=ON
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tgraphics_metal_probe toonzlib OpenToonz --parallel 3
nix develop path:. --command toonz/build/nix-relwithdebinfo/tnzcore/tgraphics_metal_probe
nix develop path:. --command cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=OFF
```

Result: passed. The fallback build recompiled `stagevisitor.cpp` and linked
`OpenToonz.app`. The Metal-enabled build linked `OpenToonz.app`, and
`tgraphics_metal_probe` reported `ok on Apple M1 Max`. The broader
Metal-enabled rebuild emitted existing unrelated warnings in image/trop code,
but the changed `stagevisitor.cpp` compiled cleanly.

## Manual Smoke

Manual GUI smoke was not run in this checkpoint. These workflows should be
exercised before merging this milestone:

- tool hook overlay drawing
- skeleton drawing-browser overlay
- skeleton main gadget overlay
- plane viewer redraw/flush paths
- offscreen raster initialization paths
- frozen scene viewer display

## Remaining Milestone 1 Work

- Replace or isolate the remaining `glDrawPixels` paths in scene viewer,
  image-painter, stage visitor, and vector renderer code.
- Start reducing `GL_SELECT` picking usage.
