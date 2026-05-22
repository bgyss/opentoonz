# macOS Graphics Modernization Milestone 1 QGL Cleanup Report

Status: partial Milestone 1 completed locally on 2026-05-22.

## Objective

This checkpoint removes active Qt `QGL*` API usage from source-like files while
keeping the existing OpenGL backend and rendering behavior in place.

Milestone 1 still has additional work remaining for GLU isolation,
`glDrawPixels` replacement, and broader fixed-function cleanup.

## Files Changed

- `scripts/graphics_inventory.sh`
- `toonz/sources/toonz/main.cpp`
- `toonz/sources/toonz/mainwindow.cpp`
- `toonz/sources/common/tgl/tgl.cpp`
- `toonz/sources/common/tvrender/qtofflinegl.cpp`
- `toonz/sources/include/qtofflinegl.h`
- `toonz/sources/tnztools/toolutils.cpp`
- `toonz/sources/tnztools/skeletontool.cpp`
- `toonz/sources/toonz/imageviewer.cpp`
- `toonz/sources/toonz/sceneviewer.cpp`
- `toonz/sources/include/stdfx/shaderinterface.h`
- `toonz/sources/include/toonzqt/imageutils.h`
- `toonz/sources/stdfx/shaderfx.cpp`
- `toonz/sources/stdfx/shadingcontext.cpp`

## Changes

- Scoped `scripts/graphics_inventory.sh` to source-like files so counts are not
  polluted by binary/resource payloads.
- Replaced startup `QGLFormat` setup in `toonz/sources/toonz/main.cpp` with
  `QSurfaceFormat`.
- Replaced the `QGLPixelBuffer` rasterize-Pli capability gate in
  `toonz/sources/toonz/mainwindow.cpp` with
  `QOpenGLFramebufferObject::hasOpenGLFramebufferObjects()`.
- Removed the unused `QtOfflineGLPBuffer` implementation and declaration from
  the Qt offscreen GL path.
- Removed stale `QGL*` includes and comments from viewer and shader code.
- Replaced `QGLWidget::convertToGLFormat` in `tnztools` drawing helpers with a
  local `QImage::Format_RGBA8888` conversion plus vertical mirroring for the
  existing `glDrawPixels` path.
- Replaced the non-Windows `tglGetCurrentContext` / `tglMakeCurrent` /
  `tglDoneCurrent` wrapper implementation with `QOpenGLContext`.

## Inventory Before and After

Milestone 0 baseline from `doc/macos_graphics_modernization_milestone0_report.md`:

```text
Qt legacy QGL                      files=   14 matches=    39
```

Current source-like inventory:

```text
OpenToonz graphics API inventory
source_root=toonz/sources

all graphics markers               files=  120 matches=  2888
Qt legacy QGL                      files=    0 matches=     0
Qt QOpenGL                         files=   31 matches=   206
GLU                                files=   16 matches=   108
GLEW or GLUT                       files=   10 matches=    30
fixed-function drawing             files=   85 matches=  2002
fixed-function matrix              files=   56 matches=   435
glDrawPixels                       files=    8 matches=    17
OpenGL selection                   files=    5 matches=    95
```

Direct verification:

```sh
rg --glob '*.c' --glob '*.cc' --glob '*.cpp' --glob '*.cxx' --glob '*.h' --glob '*.hh' --glob '*.hpp' --glob '*.m' --glob '*.mm' --glob '*.frag' --glob '*.glsl' --glob '*.metal' -n "QGL[A-Za-z0-9_]*|QGLWidget::convertToGLFormat|#include <QGL" toonz/sources
```

Result: no matches.

## Validation Run

Commands run:

```sh
bash scripts/graphics_inventory.sh
bash -n scripts/graphics_inventory.sh
git diff --check
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --parallel 3
```

Result: passed.

The final build recompiled the affected core, tool, stdfx, toonzqt, and
OpenToonz application targets and linked `OpenToonz.app`.

## Manual Smoke

Manual GUI smoke was not run in this checkpoint. No renderer backend behavior was
intentionally changed, but the following workflows should be exercised before
merging this milestone:

- launch OpenToonz
- open a raster scene and vector scene
- pan and zoom the scene viewer
- toggle camera view and onion skin
- enable Visualize Vector As Raster
- use skeleton and hook drawing overlays
- render or preview one simple frame

## Remaining Milestone 1 Work

- Replace GLU projection/unprojection helpers in the scene viewer.
- Isolate or replace GLU tessellation in
  `toonz/sources/common/tvrender/ttessellator.cpp`.
- Replace `glDrawPixels` paths with texture upload and draw commands.
- Start reducing `GL_SELECT` picking usage.
