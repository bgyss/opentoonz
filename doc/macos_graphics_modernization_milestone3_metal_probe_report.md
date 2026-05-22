# macOS Graphics Modernization Milestone 3 Metal Probe Report

Status: initial Milestone 3 build/probe, render-target, textured-draw,
offscreen-readback, replace/blend pipeline, and automated probe slices completed
locally on 2026-05-22.

## Objective

This checkpoint adds the first native macOS Metal implementation behind
`WITH_GRAPHICS_METAL`. It proves that `tnzcore` can compile Objective-C++ Metal
code, link against `Metal.framework` and `QuartzCore.framework`, create a
default `MTLDevice`, create a command queue, configure a CAMetalLayer render
target, compile a minimal Metal shader pipeline, upload raster textures, encode
textured quad draws with replace and source-over alpha blending modes, read back
offscreen Metal targets, and run an automated offscreen Metal validation probe
while preserving OpenGL as the active renderer.

This is not yet a visible Metal scene viewer. The active backend intentionally
continues to fall back to OpenGL until a Metal render target is wired into the
Qt viewer hierarchy.

## Files Changed

- `toonz/sources/include/tgraphics.h`
- `toonz/sources/common/tgraphics/tgraphics.cpp`
- `toonz/sources/common/tgraphics/tgraphics_metal.mm`
- `toonz/sources/common/tgraphics/tgraphics_metal_probe.cpp`
- `toonz/sources/common/tgraphics/tgraphics_metal_shaders.metal`
- `toonz/sources/tnzcore/CMakeLists.txt`

## Changes

- Added public `TGraphics::isMetalDeviceAvailable()` and
  `TGraphics::metalDeviceName()` probes.
- Added public `TGraphics::metalDevice()` access to the experimental Metal
  device while keeping `TGraphics::activeDevice()` on OpenGL.
- Added `TGraphics::createMetalLayerRenderTarget(...)` and
  `TGraphics::isMetalLayerRenderTarget(...)` so future viewer integration can
  wrap a CAMetalLayer without exposing Objective-C types in the C++ header.
- Added `TGraphics::createMetalImageRenderTarget(...)` and
  `TGraphics::readMetalRenderTarget(...)` so future validation can render a
  `DrawList2D` into an offscreen Metal texture and compare it with OpenGL output.
- Added `tgraphics_metal.mm`, compiled only on macOS when
  `WITH_GRAPHICS_METAL=ON`.
- Created a native Metal state object with:
  - `MTLCreateSystemDefaultDevice()`
  - `newCommandQueue`
  - cached Metal device name
- Added a `MetalLayerRenderTarget` that configures:
  - `CAMetalLayer.device`
  - `MTLPixelFormatBGRA8Unorm`
  - `framebufferOnly`
  - high-DPI aware `drawableSize`
- Added `MetalCommandEncoder` support for:
  - acquiring a CAMetalLayer drawable
  - clear/store render pass setup
  - runtime-compiled textured-quad pipeline states for replace and alpha blend
  - linear clamp sampler state
  - TRaster32P texture upload to `MTLPixelFormatBGRA8Unorm`
  - triangle draws for `DrawList2D` texture quads
  - per-quad `TextureQuad::m_blending` handling
  - drawable presentation
- Added `MetalTextureRenderTarget` for offscreen render/readback validation.
- Added the `tgraphics_metal_probe` executable when `WITH_GRAPHICS_METAL=ON` on
  macOS. It renders an inset opaque gradient `DrawList2D` texture through the
  Metal offscreen target, verifies that untouched pixels remain transparent,
  reads the target back, and fails on any pixel mismatch. It also renders a
  second alpha case that replaces a solid base, replaces an opaque gradient
  region, and then source-over blends a semi-transparent overlay across both
  regions.
- Added `tgraphics_metal_shaders.metal` to keep the minimal vertex/fragment
  shader source visible in the build tree.
- Linked `tnzcore` against `Metal.framework` only when
  `WITH_GRAPHICS_METAL=ON`.
- Linked `tnzcore` against `QuartzCore.framework` only when
  `WITH_GRAPHICS_METAL=ON`.
- Kept `TGraphics::isMetalBackendAvailable()` false because the Metal drawable
  path is not integrated with a Qt viewer/native view yet.
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
nix develop path:. --command bash -lc 'cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=ON'
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tgraphics_metal_probe --parallel 3
nix develop path:. --command toonz/build/nix-relwithdebinfo/tnzcore/tgraphics_metal_probe
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --parallel 3
nix develop path:. --command bash -lc 'cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=OFF'
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --parallel 3
```

Result: passed.

The default OpenGL build does not compile `tgraphics_metal.mm`. The
Metal-enabled build compiles `tgraphics_metal.mm`, includes the shader source in
the CMake target metadata, links `tnzcore` against Metal and QuartzCore, builds
`tgraphics_metal_probe`, and links `OpenToonz.app`.

Probe output after validating transparent clear pixels, opaque replace drawing,
and source-over alpha blending over both solid and gradient destinations:

```text
tgraphics_metal_probe: ok on Apple M1 Max
```

## Manual Smoke

Manual GUI smoke was not run in this checkpoint. User-visible rendering is still
OpenGL even if `OPENTOONZ_GRAPHICS_BACKEND=metal` is requested.

## Known Limitations

- No Qt native-view integration yet.
- Metal shader source is present in the build tree, but the experimental
  backend still compiles the same small shader source at runtime; app-bundle
  shader packaging is a later Milestone 5/6 concern.
- `OPENTOONZ_GRAPHICS_BACKEND=metal` still falls back to OpenGL.

## Next Milestone 3 Work

- Integrate the CAMetalLayer render target with a narrow Qt viewer/native-view
  path.
- Expand the offscreen probe into an image-diff harness with an OpenGL baseline
  comparison.
- Route only a narrow scene-viewer path to the Metal command encoder once
  drawable lifecycle and fallback behavior are stable.
