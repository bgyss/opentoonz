# macOS Graphics Modernization Milestone 3 Metal Probe Report

Status: initial Milestone 3 build/probe, render-target, textured-draw,
offscreen-readback, replace/blend pipeline, OpenGL baseline comparison, first
native-view Metal presentation slice, first direct Metal viewer-background
command, and first direct Metal camera color-card command completed locally on
2026-05-22. Direct axis-aligned camera outline line commands and direct
checkerboard background commands are now also validated through the
Metal/OpenGL probe. Direct transformed texture-quad commands and the first
direct Metal preview-raster presentation path are now also in place. Eligible
normal scene `TRaster32P` nodes now have a conservative direct Metal emission
path before the compatibility OpenGL compositor runs, including column-opacity
modulation for otherwise eligible nodes.

## Objective

This checkpoint adds the first native macOS Metal implementation behind
`WITH_GRAPHICS_METAL`. It proves that `tnzcore` can compile Objective-C++ Metal
code, link against `Metal.framework` and `QuartzCore.framework`, create a
default `MTLDevice`, create a command queue, configure a CAMetalLayer render
target, compile a minimal Metal shader pipeline, upload raster textures, encode
textured quad draws with replace and OpenGL-compatible alpha blending modes,
read back offscreen Metal targets, run the same draw lists through an offscreen
OpenGL baseline, and run an automated Metal/OpenGL validation probe while
preserving OpenGL as the default renderer. It also adds the first opt-in
`SceneViewer` path that can present a captured viewer framebuffer through a
native `CAMetalLayer` child widget when `OPENTOONZ_GRAPHICS_BACKEND=metal` is
requested, plus a first direct Metal viewer command that clears the Metal layer
to the active viewer background color before the compatibility snapshot is
presented. It now also emits a direct solid-color camera color-card rectangle
and a direct camera outline for the narrow non-3D viewer path, plus a direct
checkerboard background when the viewer Transparency Check is enabled. It now
also supports explicit four-corner texture quads so viewer rasters can be
submitted with camera/view transforms instead of only as axis-aligned
screen-space rectangles. The normal 2D scene `Stage::RasterPainter` can now
append simple full-color raster nodes to a direct Metal draw list before it
falls back to the existing CPU raster composition and OpenGL upload. Those
direct texture quads now also carry a per-quad color scale so the Metal path can
match OpenGL-style texture modulation and represent column opacity.

This is not yet a full native Metal scene renderer. Scene composition still
comes from the existing OpenGL viewer path, then the captured viewer framebuffer
is uploaded to Metal and presented through `DrawList2D`. The direct Metal
background/checkerboard/color-card/outline/preview-raster/simple-scene-raster
work is intentionally narrow and is immediately followed by that compatibility
snapshot. This is a deliberate transitional slice to validate Qt/native-view
ownership, drawable lifecycle, direct command encoding, and Metal presentation
before porting scene internals.

## Files Changed

- `toonz/sources/include/tgraphics.h`
- `toonz/sources/common/tgraphics/tgraphics.cpp`
- `toonz/sources/common/tgraphics/tgraphics_metal.mm`
- `toonz/sources/common/tgraphics/tgraphics_metal_probe.cpp`
- `toonz/sources/common/tgraphics/tgraphics_metal_shaders.metal`
- `toonz/sources/tnzcore/CMakeLists.txt`
- `nix/opentoonz-env.nix`
- `toonz/sources/include/toonz/stagevisitor.h`
- `toonz/sources/toonzlib/stagevisitor.cpp`
- `toonz/sources/toonz/sceneviewer.cpp`
- `toonz/sources/toonz/sceneviewer.h`

## Changes

- Added public `TGraphics::isMetalDeviceAvailable()` and
  `TGraphics::metalDeviceName()` probes.
- Added public `TGraphics::metalDevice()` access to the experimental Metal
  device while keeping `TGraphics::activeDevice()` on OpenGL.
- Added `TGraphics::createMetalLayerRenderTarget(...)` and
  `TGraphics::isMetalLayerRenderTarget(...)` so future viewer integration can
  wrap a CAMetalLayer without exposing Objective-C types in the C++ header.
- Added `TGraphics::createMetalLayerForNativeView(...)` to attach a
  `CAMetalLayer` to the native macOS view backing a Qt widget.
- Added `TGraphics::createMetalImageRenderTarget(...)` and
  `TGraphics::readMetalRenderTarget(...)` so future validation can render a
  `DrawList2D` into an offscreen Metal texture and compare it with OpenGL output.
- Added `TGraphics::createOpenGLImageRenderTarget(...)` and
  `TGraphics::readOpenGLRenderTarget(...)` for a narrow Qt/FBO-backed OpenGL
  baseline path used by the probe.
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
- Linked `AppKit.framework` only when `WITH_GRAPHICS_METAL=ON`, because the
  native-view helper uses `NSView`/`NSScreen`.
- Added `MetalCommandEncoder` support for:
  - acquiring a CAMetalLayer drawable
  - clear/store render pass setup
  - runtime-compiled textured-quad pipeline states for replace and alpha blend
  - linear clamp sampler state
  - TRaster32P texture upload to `MTLPixelFormatBGRA8Unorm`
  - triangle draws for `DrawList2D` texture quads
  - explicit four-corner texture quad draws for transformed viewer rasters
  - per-quad `TextureQuad::m_blending` handling
  - solid-color rectangle draws
  - drawable presentation
- Added `DrawList2D::addColorRect(...)` and `ColorRect` so viewer components
  such as camera background/color-card fills can move to Metal without first
  rasterizing synthetic textures.
- Added `DrawList2D::addCheckerboard(...)`, currently implemented by expanding
  clipped checker cells into `ColorRect` commands so both the Metal and OpenGL
  probe paths can share the existing solid-rectangle encoder.
- Added `DrawList2D::addColorLine(...)` and `ColorLine` for simple overlay
  strokes. Axis-aligned lines are rendered as deterministic one-pixel
  rectangles in both backends to avoid backend-specific line endpoint
  rasterization differences.
- Added `DrawList2D::addTextureQuad(...)` for explicit four-corner raster
  texture draws. The axis-aligned `addTexture(...)` path remains available and
  still uses the existing OpenGL helper in the compatibility backend.
- Added `TextureQuad::m_colorScale` and a `DrawList2D::addTextureQuad(...)`
  overload that accepts a `TPixel32` modulation color. The default remains
  white, preserving existing unmodulated texture behavior.
- Added `DrawList2D::setClearColor(...)`, `hasClearColor()`, and
  `clearColor()` so small draw lists can represent a direct render-target clear
  without requiring a synthetic full-frame texture.
- Updated the Metal render pass clear color to use `DrawList2D`'s clear color,
  while preserving transparent black as the default when no clear color is set.
- Updated the OpenGL baseline command encoder to honor the same `DrawList2D`
  clear color before drawing texture quads.
- Updated the OpenGL baseline command encoder to draw `ColorRect` through the
  existing `tglFillRect` path, keeping the compatibility backend aligned with
  existing OpenGL behavior.
- Updated the OpenGL and Metal command encoders to draw `ColorLine`, with
  Metal/OpenGL parity covered by the probe for axis-aligned lines.
- Updated the OpenGL and Metal command encoders to draw explicit texture quads,
  with Metal/OpenGL parity covered by the probe for a camera-transform-like
  scaled and translated raster quad.
- Updated the OpenGL and Metal explicit texture-quad encoders to apply
  per-quad color-scale modulation. OpenGL uses `GL_MODULATE` on the explicit
  quad fallback path; Metal multiplies sampled BGRA texture output by the same
  normalized color scale in the fragment shader.
- Updated Metal layer render passes without an explicit clear color to load the
  existing drawable contents. This lets direct scene-content draw lists layer on
  top of the direct background command before the final compatibility snapshot.
- Matched Metal alpha blending to the existing `tglDraw` OpenGL baseline:
  `GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA` for both color and alpha channels.
- Added `MetalTextureRenderTarget` for offscreen render/readback validation.
- Added the `tgraphics_metal_probe` executable when `WITH_GRAPHICS_METAL=ON` on
  macOS. It renders an inset opaque gradient `DrawList2D` texture through the
  Metal offscreen target, verifies that untouched pixels remain transparent,
  reads the target back, and fails on any pixel mismatch. It also renders a
  second alpha case that replaces a solid base, replaces an opaque gradient
  region, and then blends a semi-transparent overlay across both regions using
  the same alpha behavior as the OpenGL baseline.
- The probe now renders both cases through Metal and OpenGL and fails on any
  pixel mismatch outside a one-channel tolerance.
- The probe now includes a modulated texture-quad case that draws a half-alpha
  explicit texture quad over a solid base and validates Metal/OpenGL readback
  parity.
- Added `tgraphics_metal_shaders.metal` to keep the minimal vertex/fragment
  shader source visible in the build tree.
- Added `tgraphicsColorFragment` to the runtime Metal shader source and the
  checked-in shader source.
- Exported `QT_PLUGIN_PATH` from the Nix dev shell using the existing
  `OPENTOONZ_QT_PLUGIN_DIRS` value so Qt-based command-line probes can find the
  Cocoa platform plugin.
- Added a `SceneViewer` native child widget for the opt-in Metal path. It is
  transparent to mouse events, owns the native view used for the `CAMetalLayer`,
  tracks viewer geometry, and recreates the Metal layer target when the captured
  viewer framebuffer size changes.
- When `OPENTOONZ_GRAPHICS_BACKEND=metal` is requested and Metal is available,
  `SceneViewer::paintGL()` captures the current OpenGL viewer framebuffer and
  presents it through the Metal command encoder. The existing frozen-frame path
  can also present `m_viewGrabImage` through Metal.
- `SceneViewer::paintGL()` now also emits a direct Metal clear command for the
  active viewer background color before presenting the compatibility OpenGL
  framebuffer snapshot. This is the first direct viewer-side Metal command, not
  the final direct scene rendering path.
- The same direct Metal draw list now adds a camera color-card `ColorRect` for
  the narrow non-3D, non-editing, non-blank-frame viewer path when the camera BG
  color toggle is enabled.
- That draw list now also adds four direct Metal `ColorLine` commands for the
  camera outline in the same narrow path.
- The direct Metal viewer background path now adds a checkerboard using
  `Preferences::getChessboardColors(...)` when `ToonzCheck::eTransparency` is
  active.
- `SceneViewer::drawPreview()` now emits the preview raster through the direct
  Metal transformed texture-quad path when the preview raster is `TRaster32P`
  and `OPENTOONZ_GRAPHICS_BACKEND=metal` is active. The legacy OpenGL preview
  draw still runs afterward for fallback behavior and for the compatibility
  framebuffer snapshot.
- Added `Stage::RasterPainter::appendDirectRasterTextureQuads(...)`, a
  conservative bridge that emits eligible scene raster nodes as direct Metal
  texture quads without clearing the existing raster-node list.
- `SceneViewer::drawScene()` now asks `RasterPainter` for those direct raster
  texture quads before calling the existing `flushRasterImages()` OpenGL path.
  The bridge only emits straightforward `TRaster32P` nodes: no active visual
  checks, channel masks, onion skin coloring, filter colors,
  premultiply/white-transparent conversion, ignored alpha, or darken-blended
  raster view mode. Column opacity is now represented as alpha in the per-quad
  texture color scale for otherwise eligible `TRaster32P` nodes.
- Linked `tnzcore` against `Metal.framework` only when
  `WITH_GRAPHICS_METAL=ON`.
- Linked `tnzcore` against `QuartzCore.framework` only when
  `WITH_GRAPHICS_METAL=ON`.
- `TGraphics::isMetalBackendAvailable()` now reports true when the build has
  Metal support and a Metal device/command queue is available.
- `TGraphics::activeDevice()` can return the Metal device when explicitly
  requested and available; call sites that need Metal presentation must still
  provide a Metal render target.

## Inventory After

The OpenGL baseline target intentionally adds a small number of Qt/OpenGL
references to `tgraphics.cpp` so the Metal probe can compare against the current
OpenGL `DrawList2D` behavior. The transformed texture-quad checkpoint adds a
few more fixed-function OpenGL references to that compatibility/probe encoder:

```text
OpenToonz graphics API inventory
source_root=toonz/sources

all graphics markers               files=  121 matches=  2903
Qt legacy QGL                      files=    0 matches=     0
Qt QOpenGL                         files=   32 matches=   216
GLU                                files=    5 matches=    53
GLEW or GLUT                       files=   10 matches=    30
fixed-function drawing             files=   86 matches=  2039
fixed-function matrix              files=   57 matches=   460
glDrawPixels                       files=    4 matches=    10
OpenGL selection                   files=    5 matches=    95
```

## Validation Run

Commands run:

```sh
bash scripts/graphics_inventory.sh
git diff --check
nix develop path:. --command bash -lc 'cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=ON'
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target OpenToonz tgraphics_metal_probe --parallel 3
nix develop path:. --command toonz/build/nix-relwithdebinfo/tnzcore/tgraphics_metal_probe
nix develop path:. --command bash -lc 'OPENTOONZ_GRAPHICS_BACKEND=metal toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app/Contents/MacOS/OpenToonz >/tmp/opentoonz-metal-smoke.log 2>&1 & pid=$!; sleep 8; ...'
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --parallel 3
nix develop path:. --command bash -lc 'cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=OFF'
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target OpenToonz --parallel 3
```

Result: passed.

The default OpenGL build does not compile `tgraphics_metal.mm`. The
Metal-enabled build compiles `tgraphics_metal.mm`, includes the shader source in
the CMake target metadata, links `tnzcore` against AppKit, Metal, and
QuartzCore, builds `tgraphics_metal_probe`, and links `OpenToonz.app`.

Probe output after validating direct solid clear/background pixels, transparent
clear pixels, solid-color rectangle drawing, solid-color rectangle alpha
blending, checkerboard background drawing, deterministic axis-aligned color
line drawing, opaque textured replace drawing, transformed texture-quad
drawing, modulated half-alpha texture-quad drawing, OpenGL-compatible texture
alpha blending over both solid and gradient destinations, and Metal/OpenGL
readback parity:

```text
tgraphics_metal_probe: ok on Apple M1 Max
```

## Manual Smoke

A bounded GUI launch smoke with `OPENTOONZ_GRAPHICS_BACKEND=metal` reached
normal application startup and was then externally terminated. The resulting
crash reporter log shows SIGTERM while startup was in image I/O / ffmpeg
initialization, not a Metal-layer backtrace. A manual visual smoke is still
needed to confirm the CAMetalLayer child presents the viewer snapshot correctly
inside the full UI.

## Known Limitations

- Qt native-view integration exists only for presenting a captured viewer
  framebuffer through Metal.
- The direct Metal viewer background clear, checkerboard, camera color-card
  rectangle, camera outline lines, preview raster, and eligible normal scene
  raster nodes are currently superseded by the compatibility OpenGL framebuffer
  snapshot in the same paint pass.
- The direct preview-raster path only handles `TRaster32P` preview rasters for
  now. Other raster formats still rely on the existing OpenGL path and final
  compatibility snapshot.
- The direct normal-scene raster path intentionally skips complex raster-node
  cases that still need the existing CPU compositor: Toonz raster/palette
  conversion, onion skins, visual check modes, filter colors,
  premultiply/white-transparent behavior, ignored-alpha column behavior, and
  raster darken-blended view mode. It now handles column opacity only for
  otherwise eligible `TRaster32P` nodes through texture color-scale alpha.
- The checkerboard helper expands into many solid rectangles. This is adequate
  for the current 50-device-pixel viewer checker cells and probe coverage, but
  a backend-native tiled/pattern path would be better before broad use.
- Direct camera outline lines are limited to deterministic axis-aligned
  one-pixel strokes; arbitrary anti-aliased or stippled overlay lines still need
  a richer stroke pipeline.
- Scene drawing, picking, overlays, and interaction still originate from the
  existing OpenGL viewer path.
- Metal shader source is present in the build tree, but the experimental
  backend still compiles the same small shader source at runtime; app-bundle
  shader packaging is a later Milestone 5/6 concern.
- The OpenGL baseline target is intentionally narrow and exists for
  `DrawList2D` probe parity; it is not a replacement for `qtofflinegl`.
- `OPENTOONZ_GRAPHICS_BACKEND=metal` still falls back to OpenGL.

## Next Milestone 3 Work

- Replace the compatibility OpenGL framebuffer snapshot with direct Metal
  drawing for more scene components: broader normal scene raster image cases,
  vector image textures, and additional overlays.
- Expand the offscreen probe from synthetic quads into baseline scene fixtures.
- Route only a narrow scene-viewer path to the Metal command encoder once
  drawable lifecycle and fallback behavior are stable.
