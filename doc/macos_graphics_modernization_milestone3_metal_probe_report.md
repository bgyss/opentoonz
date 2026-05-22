# macOS Graphics Modernization Milestone 3 Metal Probe Report

Status: initial Milestone 3 build/probe slice completed locally on 2026-05-22.

## Objective

This checkpoint adds the first native macOS Metal implementation behind
`WITH_GRAPHICS_METAL`. It proves that `tnzcore` can compile Objective-C++ Metal
code, link against `Metal.framework`, create a default `MTLDevice`, and create a
command queue while preserving OpenGL as the active renderer.

This is not yet a visible Metal scene viewer. The active backend intentionally
continues to fall back to OpenGL until a Metal render target is wired into the
Qt viewer hierarchy.

## Files Changed

- `toonz/sources/include/tgraphics.h`
- `toonz/sources/common/tgraphics/tgraphics.cpp`
- `toonz/sources/common/tgraphics/tgraphics_metal.mm`
- `toonz/sources/tnzcore/CMakeLists.txt`

## Changes

- Added public `TGraphics::isMetalDeviceAvailable()` and
  `TGraphics::metalDeviceName()` probes.
- Added `tgraphics_metal.mm`, compiled only on macOS when
  `WITH_GRAPHICS_METAL=ON`.
- Created a native Metal state object with:
  - `MTLCreateSystemDefaultDevice()`
  - `newCommandQueue`
  - cached Metal device name
- Linked `tnzcore` against `Metal.framework` only when
  `WITH_GRAPHICS_METAL=ON`.
- Kept `TGraphics::isMetalBackendAvailable()` false because CAMetalLayer/
  render-target presentation is not implemented yet.
- Kept `TGraphics::activeDevice()` returning the OpenGL device so the converted
  scene-viewer path remains functional.

## Inventory Before and After

The graphics inventory is unchanged by this native Metal probe:

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

## Validation Run

Commands run:

```sh
bash scripts/graphics_inventory.sh
git diff --check
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --parallel 3
nix develop path:. --command bash -lc 'cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=ON'
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --parallel 3
nix develop path:. --command bash -lc 'cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=OFF'
```

Result: passed.

The default OpenGL build does not compile `tgraphics_metal.mm`. The
Metal-enabled build compiles `tgraphics_metal.mm`, links `tnzcore`, and links
`OpenToonz.app`.

## Manual Smoke

Manual GUI smoke was not run in this checkpoint. User-visible rendering is still
OpenGL even if `OPENTOONZ_GRAPHICS_BACKEND=metal` is requested.

## Known Limitations

- No CAMetalLayer or Qt native-view integration yet.
- No Metal `RenderTarget` implementation yet.
- No Metal texture upload, shader, draw, or readback path yet.
- `OPENTOONZ_GRAPHICS_BACKEND=metal` still falls back to OpenGL.

## Next Milestone 3 Work

- Add a Metal render target around a CAMetalLayer or compatible Qt native view.
- Add minimal Metal shaders and pipeline state for textured 2D quads.
- Add texture upload/readback support for `DrawList2D` validation.
- Route only a narrow scene-viewer path to the Metal command encoder once
  drawable lifecycle and fallback behavior are stable.
