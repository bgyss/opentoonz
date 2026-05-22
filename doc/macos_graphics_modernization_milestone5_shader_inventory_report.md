# macOS Graphics Modernization Milestone 5 Shader Inventory

Status: GLSL/OpenGL shader inventory, Metal-port classification, and first
validated procedural Metal shader helper added locally on 2026-05-22.

## Objective

Milestone 5 requires the OpenGL shader/effects surface to be inventoried and
classified before porting effects to Metal. This checkpoint adds a repeatable
inventory command and records the first classification of the current packaged
GLSL shaders.

This does not complete the effects migration. The existing `ShaderFx` path
still compiles GLSL through `QOpenGLShaderProgram`, uses OpenGL transform
feedback for bbox and input-port geometry programs, and renders through
`ShadingContext`/OpenGL FBOs.

The first implementation checkpoint ports the procedural `sunflare` fragment
logic into the `tgraphics` Metal shader source and exposes a Metal-only
offscreen render helper. The helper is validated by `tgraphics_metal_probe`
against a CPU reference for the same formula.

The follow-up checkpoint wires `SHADER_sunflare` into the production
`ShaderFx::doCompute(...)` path when the active backend is Metal, the effect has
no input ports, and the output tile is 32-bit RGBA. All other cases fall through
to the existing OpenGL `ShaderFx` implementation.

This checkpoint also adds `shaderfx_metal_probe`, a validation target that loads
the packaged shader interfaces and renders the migrated procedural shaders
through `ShaderFx::doCompute(...)`. In Metal mode it compares the resulting tile
to the lower-level Metal helper for the selected shader. It can also write
OpenGL and Metal `ShaderFx` outputs as PAM images and compare them with a
documented tolerance through `scripts/graphics_shaderfx_compare.sh`. The Metal
branch now runs before `ShadingContextManager` is instantiated, so migrated
no-input procedural shaders no longer create the OpenGL shader context before
returning through Metal.

The input-texture checkpoint adds a `tgraphics` Metal HSL blend helper with two
sampled `TRaster32P` inputs, per-input output-to-texture affines, shared Metal
sampler/texture upload plumbing, and CPU-reference probe cases including a 1x1
subtile-sized target. It also routes the supported direct
`SHADER_HSLBlendGPU` `ShaderFx::doCompute(...)` path through Metal when the
active backend is Metal, both input ports are connected, and the output tile is
32-bit RGBA.

The offscreen checkpoint adds `tofflinegl_probe`, a small macOS validation
target for the current `TOfflineGL`/`QtOfflineGL` preview-export baseline and
the first matching `tgraphics` offscreen target. It constructs an offscreen
target, clears it through the existing OpenGL path, verifies readback pixels,
then renders the same clear/readback through the active `tgraphics` backend. It
also exercises the legacy `TOfflineGL::draw(TRasterImageP, TAffine)` raster
draw path and compares the observed offscreen placement against the reusable
`TGraphics::renderLegacyOfflineRasterPlacementWithActiveBackend(...)` helper.
With `OPENTOONZ_GRAPHICS_BACKEND=metal`, the probe proves the Metal image
render target matches the legacy OpenGL baseline for these narrow offscreen
cases. This helper is a narrow legacy-compatible placement bridge; it does not
remove the OpenGL dependency from mixed vector/stage rendering callers yet, but
it creates a focused regression target for replacing those paths with
`tgraphics` and Metal.

The style-editor checkpoint removes the `HexagonalColorWheel` dependency on
`QOpenGLWidget`, `QOpenGLFramebufferObject`, and `QOpenGLPaintDevice`. The
widget now paints the same CPU-generated `QImage` through a normal `QWidget`
paint event and applies color-calibration LUTs through the existing
`LutManager` software conversion path. This is not the full style-editor
surface migration, but it removes one direct OpenGL/FBO style-editor preview
path while preserving the OpenGL fallback elsewhere. The follow-up probe target
renders the migrated widget into a `QImage` and fails if the result is blank or
missing saturated color-wheel pixels.

The preview-swatch checkpoint moves `PlaneViewer::drawBackground()`, shared by
export, vectorizer, and adjustment preview swatches, from hand-authored
fixed-function OpenGL checkerboard quads to
`TGraphics::makeCheckerboardBackgroundDrawList(...)`. The follow-up raster
presentation checkpoint also moves `PlaneViewer::flushRasterBuffer()` from a
direct `tglDraw(...)` call to
`TGraphics::makeRasterPresentationDrawList(...)`. The current widget path still
presents through the OpenGL compatibility backend, but both draw-list helpers
are now validated by `tgraphics_metal_probe` against OpenGL and Metal offscreen
targets. The raster presentation probe intentionally covers full-size raster
buffers, matching `PlaneViewer`'s CPU render-buffer contract; texture resampling
parity remains covered separately by the existing texture cases.

The scene-viewer overlay checkpoint moves the contained
`drawProjectedRasterOverlay(...)` helper from a direct `tglDraw(...)` call to
`TGraphics::makeRasterRectDrawList(...)`. This keeps the current OpenGL widget
presentation path and existing projection setup, but routes the projected 3D
corner raster labels through the same backend-neutral raster-rect command that
is validated by `tgraphics_metal_probe`.

The scene-viewer background checkpoint routes the OpenGL compatibility
framebuffer clear in `SceneViewer::drawBackground()` through
`TGraphics::DrawList2D::setClearColor(...)` and `drawWithOpenGLBackend(...)`.
The Metal presenter already emits a matching clear command, so this narrows the
remaining raw OpenGL in the viewer background path to framebuffer status/error
handling and downstream legacy drawing.

The preview-frame checkpoint moves the `SceneViewer::drawPreview()` blank-color
camera-frame fill from direct `tglFillRect(...)` to a `DrawList2D` color-rect
command on the OpenGL compatibility path. The existing Metal presenter already
emits an equivalent color quad for this overlay; the frame-not-ready red
hairline rectangles now also emit `DrawList2D` color-line commands under the
existing camera transform.

The viewer-mask checkpoint moves `ViewerDraw::drawCameraMask(...)` and
`ViewerDraw::drawColorcard(...)` filled rectangles from direct `tglFillRect(...)`
calls to `DrawList2D` color-rect commands on the OpenGL compatibility path.
These functions feed `SceneViewer` camera-mask and color-card overlays; line and
guide drawing in `ViewerDraw` remains on legacy OpenGL until line primitives
can match OpenGL hairline behavior.

The image-viewer preview-remake checkpoint moves the screen-space red double
border used by `ImageViewer` while an FX preview is remaking from direct
`GL_LINE_LOOP` calls to `DrawList2D` color-line commands. This is limited to an
identity-projection, axis-aligned overlay, so it avoids the transformed and
stippled guide-line cases that still need a stronger `tgraphics` line contract.
The follow-up image-viewer drag-overlay checkpoint moves the zoom-selection and
rectangular RGB-pick overlays from direct `GL_LINE_STRIP` drawing to
`DrawList2D` color-line commands. The RGB-pick overlay keeps the cursor gap and
uses explicit dash segmentation instead of deprecated `glLineStipple`.
The safe-area checkpoint moves `ImageViewer` safe-area rectangles from
`glLineStipple(...)` plus `tglDrawRect(...)` to explicit dashed `DrawList2D`
color-line segments while preserving the identity screen-space transform.

The cleanup-preview camera-test checkpoint moves the cleanup camera and closest
field camera outline/cross primitives from direct immediate-mode line strips and
segments to `DrawList2D` color-quad commands sized by the existing pixel-size
argument. Text labels and handle drawing remain on the legacy tool drawing path,
but the preview camera frame geometry now has an OpenGL-compatible draw-list
shape that can be mirrored by Metal.

The vectorizer-swatch checkpoint moves the in-progress red swatch border from a
direct `GL_LINE_STRIP` with widened line state to four `DrawList2D` color-rect
commands in window coordinates. Vector stroke centerline preview drawing remains
on the legacy path, but the simple preview-progress frame no longer depends on
immediate-mode line drawing.

The scan-crop checkpoint moves the scanner crop rectangle overlay from
`tglDrawRect(...)` plus OpenGL line stipple state to four one-pixel
`DrawList2D` color-rect commands using the tool pixel size. Crop handles remain
on the existing `ToolUtils::drawSquare(...)` path, but the editable crop border
now has a backend-neutral draw-list representation.

The save-box tool checkpoint moves the eight grey save-box resize handles from
direct `tglDrawRect(...)` calls to `DrawList2D` color-line rectangles. The main
dashed save-box outline remains on `ToolUtils::drawRect(...)`, but the repeated
handle geometry now has a backend-neutral draw-list representation.

The tracker tool checkpoint moves tracker-region rectangle outlines from direct
`tglDrawRect(...)` calls to `DrawList2D` color-line commands. Hook handles,
labels, and balloon drawing remain on the existing tool drawing path.

The hook tool checkpoint moves the snapped-hook guide from OpenGL line stipple,
`tglDrawRect(...)`, and immediate-mode crosshair lines to explicit dashed and
solid `DrawList2D` color-line commands. Hook balloons and ordinary hook drawing
remain on the existing tool drawing path.

The edit-tool checkpoint moves visible scale-handle rectangle outlines and
non-active camera frame guides from direct `tglDrawRect(...)` plus OpenGL line
stipple state to `DrawList2D` color-line commands. Picking fills and the denser
axis/center/shear primitives remain on the existing OpenGL path.

The viewer safe-area checkpoint moves `ViewerDraw::drawSafeArea()` from OpenGL
line stipple plus direct `tglDrawRect(...)` calls to explicit dashed
`DrawList2D` color-line commands in camera space.
The camera-frame checkpoint moves the 2D camera border, center cross, and
preview-subcamera border in `ViewerDraw::drawCamera(...)` from OpenGL line
stipple plus immediate-mode line strips/segments to `DrawList2D` color-line
commands. The 3D camera cage path remains on legacy OpenGL.

The selection-tool checkpoint moves the polyline selection preview from a direct
`GL_LINE_STRIP` to `DrawList2D` color-line commands. The start-point circle and
contrast-blended rectangular selection frame remain on the existing drawing path
until `tgraphics` has a contrast-blend line mode.

The view-tools checkpoint moves the zoom tool drag cross from immediate-mode
`GL_LINES` to two `DrawList2D` color-line commands in world coordinates.

The control-point editor checkpoint moves speed-handle and control-point square
fills from repeated `tglFillRect(...)` calls to `DrawList2D` color-rect
commands. The Bezier handle connector segments remain on the existing tool
drawing path.

The skeleton-tool checkpoint moves pinned IK joint square fills, outlines, and
active lock square fills from `glRectd(...)`, `tglDrawRect(...)`, and
`tglFillRect(...)` to `DrawList2D` color-rect and color-line commands. Circular
free-joint drawing remains on the existing tool drawing path.

The follow-up skeleton change-parent checkpoint moves the visible change-parent
square gadget from `glRectd(...)` plus `tglDrawRect(...)` to `DrawList2D`
color-rect and color-line commands. Picking still uses the existing disk/name
path.

The edit-tool axes checkpoint moves the visible object x/y axes and center
cross from direct immediate-mode `GL_LINES` drawing to paired `DrawList2D`
color-line commands under the existing tool transforms. This preserves the
OpenGL compatibility presentation path while giving the Metal backend the same
line-command shape for these basic editing overlays.

The skeleton bone-outline checkpoint moves the dark build-skeleton and inverse
kinematics bone outline segments from immediate-mode `GL_LINE_STRIP`/`GL_LINES`
to `DrawList2D` color-line commands. The translucent filled bone polygons remain
on the existing OpenGL path until the migrated overlay surface has a stronger
triangle/quad contract for these tapered bone bodies.

The viewer grid-guide checkpoint moves `ViewerDraw::drawGridAndGuides(...)`
from direct `GL_LINES`, `glLineStipple(...)`, and per-line OpenGL color state to
`DrawList2D` color-line commands. Grid axes use solid lines, while grid and
ruler guide dashes are emitted as explicit line segments scaled by the current
viewer zoom to better match the former screen-space stipple behavior.

The field-guide checkpoint moves `ViewerDraw::drawFieldGuide()` grid and
diagonal guide lines from direct immediate-mode `GL_LINES` to `DrawList2D`
color-line commands under the existing guide transform. Field-number text labels
remain on the legacy `tglDrawText(...)` path.

The tool-utility rectangle checkpoint moves shared non-contrast
`ToolUtils::drawRect(...)`, `ToolUtils::fillRect(...)`, and
`ToolUtils::drawSquare(...)` drawing to `DrawList2D` color-line/color-rect
commands. Contrast-blended and stippled rectangle variants remain on the legacy
OpenGL path until `tgraphics` has matching blend and stipple semantics.
The follow-up ToolUtils primitive checkpoint moves shared current-color
`ToolUtils::drawPoint(...)`, `ToolUtils::drawCross(...)`, and
`ToolUtils::drawLine(...)` overlays to `DrawList2D` color commands while
preserving the caller's current OpenGL color and blend enable state. Arrowhead,
contrast, stipple, balloon picking, and hook icon geometry remain on legacy
OpenGL until those primitive semantics are represented directly in `tgraphics`.

The edit-tool shear checkpoint moves the visible shear-handle outline in
`EditTool::drawMainHandle()` from direct immediate-mode `GL_LINE_STRIP` drawing
to `DrawList2D` color-line commands. The picking polygon for the same handle
remains on the existing OpenGL selection path.

The edit-tool icon checkpoint moves the visible camera icon and Z-translation
arrow/label line art from direct immediate-mode `GL_LINE_STRIP`/`GL_LINE_LOOP`
to `DrawList2D` color-line commands with explicit caller colors. Picking and 3D
arrow body drawing remain on the existing OpenGL paths.

The scene-viewer FPS graph checkpoint moves the debug FPS graph panel from
direct `glRectd(...)`, `GL_LINE_STRIP`, and `GL_LINES` drawing to `DrawList2D`
color-rect and color-line commands in the existing identity screen transform.

The scene-viewer spline overlay checkpoint moves the visible dashed motion-path
or spline line from OpenGL line stipple plus immediate-mode `GL_LINE_STRIP` to
explicit dashed `DrawList2D` color-line segments under the existing spline
transform. Control-point number labels remain on the legacy text path.

The Canon live-view zoom checkpoint moves the stop-motion live-view zoom-box
border in `SceneViewer::draw()` from direct immediate-mode `GL_LINE_STRIP`
drawing to a `DrawList2D` color-line rectangle under the existing camera
transform.

The plastic angle-limit checkpoint moves the translucent blue angle-limit guide
line in `PlasticTool::drawAngleLimits(...)` from immediate-mode `GL_LINES` to a
`DrawList2D` color-line command. Thicker plastic skeleton and mesh edit edge
overlays remain on legacy OpenGL until `tgraphics` has matching line-width and
stipple semantics.
The plastic mesh-edit checkpoint moves selected vertex square fills,
highlighted vertex square outlines, and one-pixel dashed edge highlights from
direct OpenGL square/line drawing to `DrawList2D` color commands. Width-2
selected mesh edge overlays remain on legacy OpenGL until `tgraphics` has
line-width semantics.
The follow-up line-width checkpoint adds explicit width to `DrawList2D`
`ColorLine` commands, validates wide line rendering against OpenGL and Metal in
`tgraphics_metal_probe`, and moves width-2 selected plastic mesh edges through
that shared command path.

## Files Changed

- `scripts/graphics_shader_inventory.sh`
- `scripts/graphics_shaderfx_compare.sh`
- `doc/macos_graphics_modernization_milestone5_shader_inventory_report.md`
- `toonz/sources/include/tgraphics.h`
- `toonz/sources/common/tgraphics/tgraphics.cpp`
- `toonz/sources/common/tgraphics/tgraphics_metal.mm`
- `toonz/sources/common/tgraphics/tgraphics_metal_shaders.metal`
- `toonz/sources/common/tgraphics/tgraphics_metal_probe.cpp`
- `toonz/sources/common/tvrender/tofflinegl_probe.cpp`
- `toonz/sources/tnzcore/CMakeLists.txt`
- `toonz/sources/tnztools/controlpointeditortool.cpp`
- `toonz/sources/tnztools/edittool.cpp`
- `toonz/sources/tnztools/hooktool.cpp`
- `toonz/sources/tnztools/plastictool.cpp`
- `toonz/sources/tnztools/plastictool_meshedit.cpp`
- `toonz/sources/tnztools/selectiontool.cpp`
- `toonz/sources/tnztools/setsaveboxtool.cpp`
- `toonz/sources/tnztools/skeletontool.cpp`
- `toonz/sources/tnztools/trackertool.cpp`
- `toonz/sources/tnztools/viewtools.cpp`
- `toonz/sources/toonz/CMakeLists.txt`
- `toonz/sources/toonz/cleanuppreview.cpp`
- `toonz/sources/toonz/imageviewer.cpp`
- `toonz/sources/toonz/scanpopup.cpp`
- `toonz/sources/toonz/sceneviewer.cpp`
- `toonz/sources/toonz/vectorizerswatch.cpp`
- `toonz/sources/toonz/viewerdraw.cpp`
- `toonz/sources/toonzqt/planeviewer.cpp`
- `toonz/sources/include/stdfx/shaderfx.h`
- `toonz/sources/stdfx/CMakeLists.txt`
- `toonz/sources/stdfx/shaderfx.cpp`
- `toonz/sources/stdfx/shaderfx_metal_probe.cpp`
- `toonz/sources/include/toonzqt/styleeditor.h`
- `toonz/sources/toonzqt/styleeditor.cpp`
- `toonz/sources/toonzqt/styleeditor_colorwheel_probe.cpp`

## Inventory Command

```sh
bash scripts/graphics_shader_inventory.sh
```

The script reports:

- shader interface XML count
- packaged GLSL source count
- existing `tgraphics` Metal shader source count
- shader interface to program-file mapping
- per-shader source metrics for uniforms, samplers, `texture2D`, `varying`,
  and `gl_FragColor`
- initial Metal-port classification
- OpenGL shader API call-site counts in `toonz/sources`

## Inventory Results

```text
shader interface XML files               9
packaged GLSL shader files              16
tgraphics Metal shader files             1
```

Shader interfaces:

```text
HSLBlendGPU.xml        ports=2 bbox=0 hwt=isotropic programs=programs/HSLBlendGPU.frag,programs/HSLBlendGPU_ports.vert
caustics.xml           ports=0 bbox=0 hwt=any programs=programs/caustics.frag
fireball.xml           ports=0 bbox=0 hwt=any programs=programs/fireball.frag
glitter.xml            ports=1 bbox=1 hwt=Isotropic programs=programs/glitter.frag,programs/glitter_ports.vert,programs/glitter_bbox.vert
radialblurGPU.xml      ports=1 bbox=1 hwt=isotropic programs=programs/radialblurGPU.frag,programs/radialblurGPU_ports.vert,programs/radialblurGPU_bbox.vert
spinblurGPU.xml        ports=1 bbox=1 hwt=isotropic programs=programs/spinblurGPU.frag,programs/spinblurGPU_ports.vert,programs/spinblurGPU_bbox.vert
starsky.xml            ports=0 bbox=0 hwt=any programs=programs/starsky.frag
sunflare.xml           ports=0 bbox=0 hwt=any programs=programs/sunflare.frag
wavy.xml               ports=0 bbox=0 hwt=any programs=programs/wavy.frag
```

OpenGL shader API call-site counts:

```text
QOpenGLShader                       57
QOpenGLShaderProgram                41
glTransformFeedbackVaryings          1
glGetBufferSubData                   1
```

## Classification

Direct Metal Shading Language rewrite candidates:

- `caustics.frag`
- `fireball.frag`
- `starsky.frag`
- `wavy.frag`

These are procedural fragment shaders with no input texture sampling. They are
the smallest useful shader-effect subset to port first because they avoid
input-port texture routing and bbox transform feedback.

Validated Metal procedural helpers:

- `sunflare.frag`
- `caustics.frag`
- `starsky.frag`
- `wavy.frag`
- `fireball.frag`

The Metal implementation uses the same procedural inputs as the GLSL source:
`sunflare` uses `outputToWorld`, `color`, `blades`, `intensity`, `angle`,
`bias`, and `sharpness`; `caustics` uses `outputToWorld`, `color`, and `time`;
`starsky` uses `outputToWorld`, `color`, `time`, and `brightness`; `wavy` uses
`outputToWorld`, `color1`, `color2`, and `time`; `fireball` uses
`outputToWorld`, `color1`, `color2`, `detail`, and `time`. All five render into
a Metal texture target and return `TRaster32P` readback for probe/image-diff
workflows.

Production integration status:

- `OPENTOONZ_GRAPHICS_BACKEND=metal` can route 32-bit, no-input
  `SHADER_sunflare`, `SHADER_caustics`, `SHADER_starsky`, `SHADER_wavy`, and
  `SHADER_fireball` tiles through Metal helpers.
- `OPENTOONZ_GRAPHICS_BACKEND=metal` can route the direct connected
  `SHADER_HSLBlendGPU` `ShaderFx::doCompute(...)` path through the Metal HSL
  helper for 32-bit output. This supported path bypasses the OpenGL transform
  feedback ports shader because `HSLBlendGPU_ports.vert` maps both input rects
  and affines directly from the output rect for the identity case; the Metal
  render and dry-compute paths now express that identity geometry directly in
  CPU code.
- `shaderfx_metal_probe` validates the `ShaderFx::doCompute(...)` Metal branch
  against the lower-level Metal helper for transformed 96x64 tiles.
- `shaderfx_metal_probe --renderer` validates the same migrated Metal shader
  subset through `TRenderer` with precomputing enabled. The migrated Metal
  `ShaderFx` paths intentionally bypass the legacy `TRasterFx::compute(...)`
  cache/resource wrapper while Metal is active, because that wrapper was built
  around the OpenGL `ShadingContext` path and produced transparent renderer
  output for the direct Metal helper routes.
- `scripts/graphics_shaderfx_compare.sh` captures the same transformed
  production `ShaderFx` tiles through OpenGL and Metal, writes OpenGL/Metal/diff
  PAM artifacts for the migrated no-input procedural shaders, writes Metal HSL
  radial blur, spin blur, and glitter artifacts for `SHADER_HSLBlendGPU`,
  `SHADER_radialblurGPU`, `SHADER_spinblurGPU`, and `SHADER_glitter`, writes
  renderer-driven Metal artifacts for the migrated no-input shaders, HSL,
  radial blur, spin blur, and glitter, writes HSL, radial blur, spin blur, and
  glitter Metal scene-render artifacts, writes saved-and-reloaded HSL, radial
  blur, spin blur, and glitter input-texture `.tnz` scene fixtures with
  raster-level inputs, writes
  `ToonzScene`/`buildSceneFx(...)` scene-render OpenGL/Metal/diff artifacts for
  the migrated no-input procedural shaders, writes saved-and-reloaded `.tnz`
  scene fixtures plus OpenGL/Metal/diff artifacts for the same procedural
  subset, and passes on Apple M1 Max.
- OpenGL remains the default backend.
- Non-32-bit tiles and every other `ShaderFx` still use the existing OpenGL
  path.

Remaining shared shader-generation candidates:

- None of the packaged fragment shaders remain in the generic input-texture
  candidate bucket. `HSLBlendGPU.frag`, `radialblurGPU.frag`,
  `spinblurGPU.frag`, and `glitter.frag` all now have explicit hand-routed
  Metal helpers and ShaderFx Metal routes. The GLSL sources remain packaged for
  the OpenGL fallback and are not yet generated into MSL from shared source.

`radialblurGPU.frag` now has a direct hand-routed Metal implementation for the
simple connected 32-bit tile path, detached `TRenderer` execution, a
`ToonzScene`/`buildSceneFx(...)` scene-render fixture with a real raster-level
input column, and saved/reloaded scene-render coverage for that input-texture
fixture. Its Metal path now uses CPU-side bbox/input-rect expansion matching
the legacy radial blur ports/bbox shaders, so the migrated Metal route no
longer compiles the transform-feedback geometry shaders.

`spinblurGPU.frag` now has a direct hand-routed Metal implementation for the
simple connected 32-bit tile path, detached `TRenderer` execution, a
`ToonzScene`/`buildSceneFx(...)` scene-render fixture with a real raster-level
input column, and saved/reloaded scene-render coverage for that input-texture
fixture. Its Metal path uses CPU-side bbox/input-rect expansion for the migrated
route, including dry-compute upstream invalidation, instead of compiling the
legacy transform-feedback bbox/ports shaders.

`glitter.frag` now has a direct hand-routed Metal implementation for the simple
connected 32-bit tile path, detached `TRenderer` execution, a
`ToonzScene`/`buildSceneFx(...)` scene-render fixture with a real raster-level
input column, and saved/reloaded scene-render coverage for that input-texture
fixture. Its Metal path uses CPU-side bbox/input-rect expansion for the migrated
route, including dry-compute upstream invalidation, instead of compiling the
legacy transform-feedback bbox/ports shaders.

Input-texture Metal groundwork:

- `TGraphics::renderHSLBlendWithMetalBackend(...)` renders a two-input HSL
  blend into an offscreen Metal render target.
- The helper accepts foreground/background rasters plus separate
  output-to-texture affines, matching the shape of the GLSL `inputImage[]` and
  `outputToInput[]` bindings used by `ShaderFx`.
- `tgraphics_metal_probe` validates the helper against a CPU reference for the
  same HSL blend formula, including a 1x1 target that matches the renderer cache
  subtile size observed during investigation.
- `shaderfx_metal_probe --shader SHADER_HSLBlendGPU` validates the direct
  connected `ShaderFx::doCompute(...)` Metal route against the lower-level HSL
  helper.
- `shaderfx_metal_probe --shader SHADER_HSLBlendGPU --renderer` validates the
  connected HSL route through `TRenderer` with precomputing enabled, covering the
  renderer status lifecycle used by preview/export jobs.
- `shaderfx_metal_probe --shader SHADER_HSLBlendGPU --scene-render` validates
  HSL through a `ToonzScene` render tree with foreground/background raster level
  columns. The exact pixels are not compared to the detached renderer fixture
  because level-column placement intentionally changes the input coordinate
  contract; the probe still fails if the scene-render output is fully
  transparent.
- `shaderfx_metal_probe --shader SHADER_HSLBlendGPU --scene-render
  --save-load-scene <path>` validates that the HSL input-texture fixture can be
  saved as a minimal `.tnz`, reloaded, hydrated from the saved raster-level
  frame files, rebuilt through `buildSceneFx(...)`, and rendered through the
  Metal path without producing a transparent result.
- `TGraphics::renderRadialBlurWithMetalBackend(...)` renders a single-input
  radial blur into an offscreen Metal render target using the GLSL
  `radialblurGPU.frag` sampling formula and explicit `outputToInput` and
  `worldToOutput` transforms.
- `shaderfx_metal_probe --shader SHADER_radialblurGPU` validates the direct
  connected `ShaderFx::doCompute(...)` Metal route against the lower-level
  radial blur helper for the current simple 32-bit tile path.
- `shaderfx_metal_probe --shader SHADER_radialblurGPU --renderer` validates the
  same route through `TRenderer` with precomputing enabled. The Metal radial
  bbox and port paths now expand rectangles on the CPU instead of compiling the
  legacy `radialblurGPU_bbox.vert` and `radialblurGPU_ports.vert`
  transform-feedback shaders.
- `shaderfx_metal_probe --shader SHADER_radialblurGPU --scene-render` validates
  radial blur through a `ToonzScene` render tree with a real foreground raster
  level column. The scene fixture uses the same visible-pixel validation style
  as HSL because level-column placement changes the input coordinate contract
  relative to the detached renderer fixture.
- `shaderfx_metal_probe --shader SHADER_radialblurGPU --scene-render
  --save-load-scene <path>` validates the same saved/reloaded minimal `.tnz`
  path for the radial-blur input-texture fixture.
- `TGraphics::renderSpinBlurWithMetalBackend(...)` renders a single-input spin
  blur into an offscreen Metal render target using the GLSL
  `spinblurGPU.frag` angular sampling formula and explicit `outputToInput` and
  `worldToOutput` transforms.
- `shaderfx_metal_probe --shader SHADER_spinblurGPU` validates the direct
  connected `ShaderFx::doCompute(...)` Metal route against the lower-level spin
  blur helper for the current simple 32-bit tile path.
- `shaderfx_metal_probe --shader SHADER_spinblurGPU --renderer` validates the
  same route through `TRenderer` with precomputing enabled.
- `shaderfx_metal_probe --shader SHADER_spinblurGPU --scene-render` validates
  spin blur through a `ToonzScene` render tree with a real foreground raster
  level column.
- `shaderfx_metal_probe --shader SHADER_spinblurGPU --scene-render
  --save-load-scene <path>` validates the same saved/reloaded minimal `.tnz`
  path for the spin-blur input-texture fixture.
- `TGraphics::renderGlitterWithMetalBackend(...)` renders a single-input
  glitter effect into an offscreen Metal render target using the GLSL
  `glitter.frag` ray-filter sampling formula and explicit `outputToInput` and
  `worldToOutput` transforms.
- `shaderfx_metal_probe --shader SHADER_glitter` validates the direct connected
  `ShaderFx::doCompute(...)` Metal route against the lower-level glitter helper
  for the current simple 32-bit tile path.
- `shaderfx_metal_probe --shader SHADER_glitter --renderer` validates the same
  route through `TRenderer` with precomputing enabled.
- `shaderfx_metal_probe --shader SHADER_glitter --scene-render` validates
  glitter through a `ToonzScene` render tree with a real foreground raster level
  column.
- `shaderfx_metal_probe --shader SHADER_glitter --scene-render
  --save-load-scene <path>` validates the same saved/reloaded minimal `.tnz`
  path for the glitter input-texture fixture.

Blocked by OpenGL-specific transform feedback:

- None in the currently migrated Metal input-texture `ShaderFx` subset.

The GLSL transform-feedback vertex programs remain packaged for the OpenGL
fallback. Metal routes should continue replacing additional bbox/port geometry
with CPU bbox/port computation or a Metal buffer pass, not direct one-for-one
GLSL translation.

Migrated CPU-side Metal geometry bypasses:

- `HSLBlendGPU_ports.vert` (identity input geometry)
- `radialblurGPU_ports.vert`
- `radialblurGPU_bbox.vert`
- `spinblurGPU_ports.vert`
- `spinblurGPU_bbox.vert`
- `glitter_ports.vert`
- `glitter_bbox.vert`

These GLSL sources remain packaged for the OpenGL fallback. The Metal
`SHADER_HSLBlendGPU`, `SHADER_radialblurGPU`, `SHADER_spinblurGPU`, and
`SHADER_glitter` routes now compute equivalent input and bbox expansion in CPU
code before rendering through their Metal helpers.

Current Metal shader source:

- `toonz/sources/common/tgraphics/tgraphics_metal_shaders.metal`

The current `tgraphics` Metal backend first tries to load
`tgraphics_metal_shaders.metallib` from the main app bundle resources and falls
back to compiling equivalent shader source from an Objective-C++ string in
`tgraphics_metal.mm` when the packaged library is absent or fails to load. The
runtime string and tracked `.metal` source both include the sunflare, caustics,
starsky, wavy, and fireball fragment entry points.

When `WITH_GRAPHICS_METAL=ON`, the macOS app build copies the tracked Metal
shader source into `OpenToonz.app/Contents/Resources/tgraphics_metal_shaders.metal`.
If `xcrun --find metal`, `xcrun --find metallib`, and `xcrun metal -v` are
available, the CMake build also compiles
`tgraphics_metal_shaders.metallib` and copies it into the same app resources
directory. `scripts/macos/verify-metal-resources.sh` verifies the source
resource in every Metal-enabled package and requires the compiled `.metallib`
when the local Xcode Metal toolchain is usable. The runtime still falls back to
the embedded Objective-C++ shader string if the packaged library is absent or
fails to load, which keeps stripped-down local Xcode installations usable.

Current local shader packaging limitation: the local Xcode installation can
locate `metal` at
`/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/metal`,
but invoking it currently fails with `error: cannot execute tool 'metal' due to
missing Metal Toolchain; use: xcodebuild -downloadComponent MetalToolchain`.
`xcrun --find metallib` also fails, so local validation can only prove the
source-resource fallback path until the Metal Toolchain component is installed.

## ShaderFx Image-Diff Command

```sh
nix develop path:. --command bash scripts/graphics_shaderfx_compare.sh /private/tmp/opentoonz-shaderfx-compare
```

Artifacts:

- `/private/tmp/opentoonz-shaderfx-compare/sunflare-opengl.pam`
- `/private/tmp/opentoonz-shaderfx-compare/sunflare-metal.pam`
- `/private/tmp/opentoonz-shaderfx-compare/sunflare-diff.pam`
- `/private/tmp/opentoonz-shaderfx-compare/sunflare-metal-renderer.pam`
- `/private/tmp/opentoonz-shaderfx-compare/sunflare-opengl-scene.pam`
- `/private/tmp/opentoonz-shaderfx-compare/sunflare-metal-scene.pam`
- `/private/tmp/opentoonz-shaderfx-compare/sunflare-scene-diff.pam`
- `/private/tmp/opentoonz-shaderfx-compare/sunflare-opengl.tnz`
- `/private/tmp/opentoonz-shaderfx-compare/sunflare-metal.tnz`
- `/private/tmp/opentoonz-shaderfx-compare/sunflare-opengl-saved-scene.pam`
- `/private/tmp/opentoonz-shaderfx-compare/sunflare-metal-saved-scene.pam`
- `/private/tmp/opentoonz-shaderfx-compare/sunflare-saved-scene-diff.pam`
- `/private/tmp/opentoonz-shaderfx-compare/caustics-opengl.pam`
- `/private/tmp/opentoonz-shaderfx-compare/caustics-metal.pam`
- `/private/tmp/opentoonz-shaderfx-compare/caustics-diff.pam`
- `/private/tmp/opentoonz-shaderfx-compare/caustics-metal-renderer.pam`
- `/private/tmp/opentoonz-shaderfx-compare/caustics-opengl-scene.pam`
- `/private/tmp/opentoonz-shaderfx-compare/caustics-metal-scene.pam`
- `/private/tmp/opentoonz-shaderfx-compare/caustics-scene-diff.pam`
- `/private/tmp/opentoonz-shaderfx-compare/caustics-opengl.tnz`
- `/private/tmp/opentoonz-shaderfx-compare/caustics-metal.tnz`
- `/private/tmp/opentoonz-shaderfx-compare/caustics-opengl-saved-scene.pam`
- `/private/tmp/opentoonz-shaderfx-compare/caustics-metal-saved-scene.pam`
- `/private/tmp/opentoonz-shaderfx-compare/caustics-saved-scene-diff.pam`
- `/private/tmp/opentoonz-shaderfx-compare/starsky-opengl.pam`
- `/private/tmp/opentoonz-shaderfx-compare/starsky-metal.pam`
- `/private/tmp/opentoonz-shaderfx-compare/starsky-diff.pam`
- `/private/tmp/opentoonz-shaderfx-compare/starsky-metal-renderer.pam`
- `/private/tmp/opentoonz-shaderfx-compare/starsky-opengl-scene.pam`
- `/private/tmp/opentoonz-shaderfx-compare/starsky-metal-scene.pam`
- `/private/tmp/opentoonz-shaderfx-compare/starsky-scene-diff.pam`
- `/private/tmp/opentoonz-shaderfx-compare/starsky-opengl.tnz`
- `/private/tmp/opentoonz-shaderfx-compare/starsky-metal.tnz`
- `/private/tmp/opentoonz-shaderfx-compare/starsky-opengl-saved-scene.pam`
- `/private/tmp/opentoonz-shaderfx-compare/starsky-metal-saved-scene.pam`
- `/private/tmp/opentoonz-shaderfx-compare/starsky-saved-scene-diff.pam`
- `/private/tmp/opentoonz-shaderfx-compare/wavy-opengl.pam`
- `/private/tmp/opentoonz-shaderfx-compare/wavy-metal.pam`
- `/private/tmp/opentoonz-shaderfx-compare/wavy-diff.pam`
- `/private/tmp/opentoonz-shaderfx-compare/wavy-metal-renderer.pam`
- `/private/tmp/opentoonz-shaderfx-compare/wavy-opengl-scene.pam`
- `/private/tmp/opentoonz-shaderfx-compare/wavy-metal-scene.pam`
- `/private/tmp/opentoonz-shaderfx-compare/wavy-scene-diff.pam`
- `/private/tmp/opentoonz-shaderfx-compare/wavy-opengl.tnz`
- `/private/tmp/opentoonz-shaderfx-compare/wavy-metal.tnz`
- `/private/tmp/opentoonz-shaderfx-compare/wavy-opengl-saved-scene.pam`
- `/private/tmp/opentoonz-shaderfx-compare/wavy-metal-saved-scene.pam`
- `/private/tmp/opentoonz-shaderfx-compare/wavy-saved-scene-diff.pam`
- `/private/tmp/opentoonz-shaderfx-compare/fireball-opengl.pam`
- `/private/tmp/opentoonz-shaderfx-compare/fireball-metal.pam`
- `/private/tmp/opentoonz-shaderfx-compare/fireball-diff.pam`
- `/private/tmp/opentoonz-shaderfx-compare/fireball-opengl-scene.pam`
- `/private/tmp/opentoonz-shaderfx-compare/fireball-metal-scene.pam`
- `/private/tmp/opentoonz-shaderfx-compare/fireball-scene-diff.pam`
- `/private/tmp/opentoonz-shaderfx-compare/fireball-opengl.tnz`
- `/private/tmp/opentoonz-shaderfx-compare/fireball-metal.tnz`
- `/private/tmp/opentoonz-shaderfx-compare/fireball-opengl-saved-scene.pam`
- `/private/tmp/opentoonz-shaderfx-compare/fireball-metal-saved-scene.pam`
- `/private/tmp/opentoonz-shaderfx-compare/fireball-saved-scene-diff.pam`
- `/private/tmp/opentoonz-shaderfx-compare/fireball-metal-renderer.pam`
- `/private/tmp/opentoonz-shaderfx-compare/HSLBlendGPU-metal.pam`
- `/private/tmp/opentoonz-shaderfx-compare/HSLBlendGPU-metal-renderer.pam`
- `/private/tmp/opentoonz-shaderfx-compare/HSLBlendGPU-metal-scene.pam`
- `/private/tmp/opentoonz-shaderfx-compare/HSLBlendGPU-metal.tnz`
- `/private/tmp/opentoonz-shaderfx-compare/HSLBlendGPU-metal-saved-scene.pam`
- `/private/tmp/opentoonz-shaderfx-compare/radialblurGPU-metal.pam`
- `/private/tmp/opentoonz-shaderfx-compare/radialblurGPU-metal-renderer.pam`
- `/private/tmp/opentoonz-shaderfx-compare/radialblurGPU-metal-scene.pam`
- `/private/tmp/opentoonz-shaderfx-compare/radialblurGPU-metal.tnz`
- `/private/tmp/opentoonz-shaderfx-compare/radialblurGPU-metal-saved-scene.pam`

The default tolerance is 2 channel values. `fireball` uses
`SHADERFX_FIREBALL_COMPARE_TOLERANCE=32` by default because its procedural noise
uses transcendental functions where OpenGL GLSL and Metal Shading Language
rounding can diverge at isolated threshold pixels. This keeps the strict
tolerance for the other migrated shaders while still failing broad color,
alpha, or coordinate mismatches.

## Next Effects Recommendation

The direct no-input procedural shader subset now has direct, renderer-driven,
`ToonzScene`/`buildSceneFx(...)`, and saved-and-reloaded `.tnz` scene fixture
coverage. The first complete direct input-texture route (`HSLBlendGPU`) now has
direct, renderer-driven, `ToonzScene`/`buildSceneFx(...)` scene-render, and
saved-and-reloaded `.tnz` scene-render coverage. `radialblurGPU` now has direct
connected, detached renderer, `ToonzScene`/`buildSceneFx(...)` scene-render,
and saved-and-reloaded `.tnz` scene-render coverage, and its Metal route now
uses CPU-side bbox/input geometry expansion. `spinblurGPU` now has the same
direct connected, detached renderer, `ToonzScene`/`buildSceneFx(...)`
scene-render, and saved-and-reloaded `.tnz` scene-render coverage, and its
Metal route now uses CPU-side bbox/input geometry expansion. `glitter` now has
the same direct connected, detached renderer, `ToonzScene`/`buildSceneFx(...)`
scene-render, saved-and-reloaded `.tnz` scene-render coverage, and CPU-side
bbox/input geometry expansion. The style editor color wheel no longer requires
a direct OpenGL widget/FBO path; it now uses QWidget/QImage rendering with
software LUT application. Preview-swatch checker backgrounds now go through a
shared `tgraphics` draw-list helper with OpenGL/Metal offscreen validation, and
preview-swatch CPU raster-buffer presentation now goes through a matching
`tgraphics` helper. Scene-viewer projected raster overlays now also emit a
`tgraphics` raster-rect command instead of calling `tglDraw(...)` directly, and
scene-viewer OpenGL compatibility background clears now emit the same
`tgraphics` clear command shape used by the Metal presenter. Preview blank-color
camera-frame fills and frame-not-ready red outlines also now use `tgraphics`
color commands in the OpenGL compatibility path, matching the existing Metal
overlay shape. Viewer camera masks and color-card fills now also emit
`tgraphics` color-rect commands on the OpenGL compatibility path. Image-viewer
FX preview-remake double borders now emit `tgraphics` color-line commands for
their screen-space overlay, and
image-viewer zoom/RGB-pick drag overlays now emit `tgraphics` color-line
commands instead of immediate-mode line strips. Cleanup preview camera-test
frame/cross outlines now emit `tgraphics` color-quad commands sized by the
current pixel size. Vectorizer swatch in-progress borders now emit `tgraphics`
color-rect commands in window coordinates instead of widened immediate-mode line
strips. Scanner crop-box borders now emit one-pixel `tgraphics` color-rect
commands instead of direct `tglDrawRect(...)` calls and OpenGL line stipple
state. Flipbook safe-area rectangles now use explicit dashed `tgraphics`
color-line segments instead of OpenGL line stipple state and direct
`tglDrawRect(...)` calls. Save-box resize handles now emit `tgraphics`
color-line rectangles instead of repeated direct `tglDrawRect(...)` calls.
Tracker-region outlines now also emit `tgraphics` color-line rectangles instead
of direct `tglDrawRect(...)` calls. Snapped-hook guides now emit explicit
dashed and solid `tgraphics` color-line commands instead of OpenGL line stipple,
direct `tglDrawRect(...)`, and immediate-mode crosshair lines. Edit-tool
visible scale-handle outlines and non-active camera guides now also emit
`tgraphics` color-line commands instead of direct rectangle/stipple drawing.
Viewer safe-area guides now emit explicit dashed `tgraphics` color-line
commands instead of OpenGL line stipple and direct `tglDrawRect(...)` calls.
Viewer camera-frame and preview-subcamera 2D outlines now emit `tgraphics`
color-line commands instead of OpenGL line stipple and immediate-mode line
strips.
Polyline selection previews now emit `tgraphics` color-line commands instead of
a direct `GL_LINE_STRIP`. Zoom tool drag crosses now emit `tgraphics` color-line
commands instead of immediate-mode `GL_LINES`. Control-point editor square
handles now emit `tgraphics` color-rect commands instead of repeated direct
`tglFillRect(...)` calls. Pinned skeleton IK joint square markers now emit
`tgraphics` color-rect and color-line commands instead of direct rectangle
drawing calls. Skeleton change-parent square gadgets now also emit `tgraphics`
color-rect and color-line commands instead of direct rectangle drawing calls.
Edit-tool object axes and center crosses now emit `tgraphics` color-line
commands instead of direct immediate-mode `GL_LINES`. Skeleton bone and IK-bone
outline segments now also emit `tgraphics` color-line commands instead of direct
immediate-mode line drawing. Viewer grid axes, grid lines, and ruler guides now
emit `tgraphics` color-line commands instead of direct `GL_LINES` and
`glLineStipple(...)` state. Viewer field-guide grid and diagonal lines now also
emit `tgraphics` color-line commands instead of immediate-mode `GL_LINES`.
Shared plain tool rectangles, filled rectangles, and square outlines now also
emit `tgraphics` color commands, and shared current-color tool point, cross,
and line primitives now also emit `tgraphics` color commands. Edit-tool
shear-handle visible outlines now also emit `tgraphics` color-line commands.
Edit-tool camera and Z-translation icons now also emit `tgraphics` color-line
commands. Scene-viewer FPS graph panels now emit `tgraphics` color commands
instead of direct immediate-mode drawing. Scene-viewer spline/motion-path
overlay lines now emit explicit dashed `tgraphics` color-line commands. Canon
live-view zoom-box borders now also emit `tgraphics` color-line commands.
Plastic angle-limit guide lines now emit `tgraphics` color-line commands, while
thicker plastic skeleton and mesh edit edge overlays remain on legacy OpenGL
until width/stipple semantics are represented in `tgraphics`.
Plastic mesh-edit selected vertex fills, highlighted vertex outlines, and
one-pixel dashed edge highlights now also emit `tgraphics` color commands;
`DrawList2D` color lines now carry explicit width semantics validated by
OpenGL/Metal probe coverage, and width-2 selected mesh edges now use that shared
path too.
Continue by broadening input-texture ShaderFx coverage beyond these hand-routed
effects and by moving the remaining preview/export and style-editor surfaces
through `tgraphics`. Keep OpenGL `ShaderFx` as the default until full scene
parity is broader.

## Validation Run

```sh
bash scripts/graphics_shader_inventory.sh
nix develop path:. --command bash -lc 'cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=ON'
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tgraphics_metal_probe --parallel 3
nix develop path:. --command toonz/build/nix-relwithdebinfo/tnzcore/tgraphics_metal_probe
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tgraphics_metal_probe shaderfx_metal_probe OpenToonz --parallel 3
bash scripts/macos/verify-metal-resources.sh toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app
nix develop path:. --command toonz/build/nix-relwithdebinfo/tnzcore/tgraphics_metal_probe
nix develop path:. --command bash -lc 'OPENTOONZ_GRAPHICS_BACKEND=metal toonz/build/nix-relwithdebinfo/stdfx/shaderfx_metal_probe --shader SHADER_fireball'
nix develop path:. --command bash -lc 'OPENTOONZ_GRAPHICS_BACKEND=metal toonz/build/nix-relwithdebinfo/stdfx/shaderfx_metal_probe --shader SHADER_HSLBlendGPU'
nix develop path:. --command bash -lc 'OPENTOONZ_GRAPHICS_BACKEND=metal toonz/build/nix-relwithdebinfo/stdfx/shaderfx_metal_probe --shader SHADER_HSLBlendGPU --renderer'
nix develop path:. --command bash -lc 'OPENTOONZ_GRAPHICS_BACKEND=metal toonz/build/nix-relwithdebinfo/stdfx/shaderfx_metal_probe --shader SHADER_HSLBlendGPU --scene-render'
nix develop path:. --command bash -lc 'OPENTOONZ_GRAPHICS_BACKEND=metal toonz/build/nix-relwithdebinfo/stdfx/shaderfx_metal_probe --shader SHADER_HSLBlendGPU --scene-render --save-load-scene /private/tmp/opentoonz-hsl-saved-scene.tnz --write-pam /private/tmp/opentoonz-hsl-saved-scene.pam'
nix develop path:. --command bash -lc 'OPENTOONZ_GRAPHICS_BACKEND=metal toonz/build/nix-relwithdebinfo/stdfx/shaderfx_metal_probe --shader SHADER_radialblurGPU'
nix develop path:. --command bash -lc 'OPENTOONZ_GRAPHICS_BACKEND=metal toonz/build/nix-relwithdebinfo/stdfx/shaderfx_metal_probe --shader SHADER_radialblurGPU --renderer'
nix develop path:. --command bash -lc 'OPENTOONZ_GRAPHICS_BACKEND=metal toonz/build/nix-relwithdebinfo/stdfx/shaderfx_metal_probe --shader SHADER_radialblurGPU --scene-render'
nix develop path:. --command bash -lc 'OPENTOONZ_GRAPHICS_BACKEND=metal toonz/build/nix-relwithdebinfo/stdfx/shaderfx_metal_probe --shader SHADER_radialblurGPU --scene-render --save-load-scene /private/tmp/opentoonz-radialblur-saved-scene.tnz --write-pam /private/tmp/opentoonz-radialblur-saved-scene.pam'
nix develop path:. --command bash -lc 'OPENTOONZ_GRAPHICS_BACKEND=metal toonz/build/nix-relwithdebinfo/stdfx/shaderfx_metal_probe --shader SHADER_spinblurGPU'
nix develop path:. --command bash -lc 'OPENTOONZ_GRAPHICS_BACKEND=metal toonz/build/nix-relwithdebinfo/stdfx/shaderfx_metal_probe --shader SHADER_spinblurGPU --renderer'
nix develop path:. --command bash -lc 'OPENTOONZ_GRAPHICS_BACKEND=metal toonz/build/nix-relwithdebinfo/stdfx/shaderfx_metal_probe --shader SHADER_spinblurGPU --scene-render'
nix develop path:. --command bash -lc 'OPENTOONZ_GRAPHICS_BACKEND=metal toonz/build/nix-relwithdebinfo/stdfx/shaderfx_metal_probe --shader SHADER_spinblurGPU --scene-render --save-load-scene /private/tmp/opentoonz-spinblur-saved-scene.tnz --write-pam /private/tmp/opentoonz-spinblur-saved-scene.pam'
nix develop path:. --command bash -lc 'OPENTOONZ_GRAPHICS_BACKEND=metal toonz/build/nix-relwithdebinfo/stdfx/shaderfx_metal_probe --shader SHADER_glitter'
nix develop path:. --command bash -lc 'OPENTOONZ_GRAPHICS_BACKEND=metal toonz/build/nix-relwithdebinfo/stdfx/shaderfx_metal_probe --shader SHADER_glitter --renderer'
nix develop path:. --command bash -lc 'OPENTOONZ_GRAPHICS_BACKEND=metal toonz/build/nix-relwithdebinfo/stdfx/shaderfx_metal_probe --shader SHADER_glitter --scene-render'
nix develop path:. --command bash -lc 'OPENTOONZ_GRAPHICS_BACKEND=metal toonz/build/nix-relwithdebinfo/stdfx/shaderfx_metal_probe --shader SHADER_glitter --scene-render --save-load-scene /private/tmp/opentoonz-glitter-saved-scene.tnz --write-pam /private/tmp/opentoonz-glitter-saved-scene.pam'
nix develop path:. --command bash scripts/graphics_shaderfx_compare.sh /private/tmp/opentoonz-shaderfx-compare-glitter
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target toonzqt --parallel 3
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target styleeditor_colorwheel_probe --parallel 3
nix develop path:. --command toonz/build/nix-relwithdebinfo/toonzqt/styleeditor_colorwheel_probe
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tofflinegl_probe --parallel 3
nix develop path:. --command toonz/build/nix-relwithdebinfo/tnzcore/tofflinegl_probe
nix develop path:. --command bash -lc 'cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=ON'
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tofflinegl_probe tgraphics_metal_probe --parallel 3
nix develop path:. --command bash -lc 'OPENTOONZ_GRAPHICS_BACKEND=metal toonz/build/nix-relwithdebinfo/tnzcore/tofflinegl_probe'
nix develop path:. --command toonz/build/nix-relwithdebinfo/tnzcore/tgraphics_metal_probe
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target toonzqt --parallel 3
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tgraphics_metal_probe toonzqt --parallel 3
nix develop path:. --command toonz/build/nix-relwithdebinfo/tnzcore/tgraphics_metal_probe
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target toonzqt --parallel 3
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tgraphics_metal_probe toonzqt --parallel 3
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tgraphics_metal_probe --parallel 3
nix develop path:. --command toonz/build/nix-relwithdebinfo/tnzcore/tgraphics_metal_probe
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target OpenToonz --parallel 3
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tgraphics_metal_probe OpenToonz --parallel 3
nix develop path:. --command toonz/build/nix-relwithdebinfo/tnzcore/tgraphics_metal_probe
nix develop path:. --command bash -lc 'cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=OFF'
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target OpenToonz --parallel 3
nix develop path:. --command bash scripts/macos/assert-arm64-bundle.sh
bash scripts/graphics_inventory.sh
bash scripts/graphics_shader_inventory.sh
git diff --check
rg -n "^WITH_GRAPHICS_METAL:BOOL=" toonz/build/nix-relwithdebinfo/CMakeCache.txt
```

Validation evidence:

```text
tgraphics_metal_probe: ok on Apple M1 Max
resource present: toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app/Contents/Resources/tgraphics_metal_shaders.metal
tgraphics_metal_probe: ok on Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_fireball backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_HSLBlendGPU backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_HSLBlendGPU backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_HSLBlendGPU backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_HSLBlendGPU backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_radialblurGPU backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_radialblurGPU backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_radialblurGPU backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_radialblurGPU backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_spinblurGPU backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_spinblurGPU backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_spinblurGPU backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_spinblurGPU backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_glitter backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_glitter backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_glitter backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_glitter backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_sunflare backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_sunflare backend=opengl
shaderfx_metal_probe: ok shader=SHADER_caustics backend=opengl
shaderfx_metal_probe: ok shader=SHADER_caustics backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_starsky backend=opengl
shaderfx_metal_probe: ok shader=SHADER_starsky backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_wavy backend=opengl
shaderfx_metal_probe: ok shader=SHADER_wavy backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_fireball backend=opengl
shaderfx_metal_probe: ok shader=SHADER_fireball backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_HSLBlendGPU backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_HSLBlendGPU backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_sunflare backend=opengl
shaderfx_metal_probe: ok shader=SHADER_sunflare backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_caustics backend=opengl
shaderfx_metal_probe: ok shader=SHADER_caustics backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_starsky backend=opengl
shaderfx_metal_probe: ok shader=SHADER_starsky backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_wavy backend=opengl
shaderfx_metal_probe: ok shader=SHADER_wavy backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_fireball backend=opengl
shaderfx_metal_probe: ok shader=SHADER_fireball backend=metal device=Apple M1 Max
shaderfx_metal_probe: ok shader=SHADER_HSLBlendGPU backend=metal device=Apple M1 Max
graphics_shaderfx_compare: ok
toonzqt/libtoonzqt.dylib linked after style editor color wheel migration
styleeditor_colorwheel_probe: ok
tofflinegl_probe: ok backend=opengl
tofflinegl_probe: ok backend=metal
tgraphics_metal_probe: ok on Apple M1 Max
tgraphics_metal_probe: ok on Apple M1 Max
tgraphics_metal_probe: ok on Apple M1 Max
tgraphics_metal_probe: ok on Apple M1 Max
Checked 281 Mach-O files for arm64.
WITH_GRAPHICS_METAL:BOOL=OFF
```

The final ShaderFx artifact directory for this checkpoint was:

```text
/private/tmp/opentoonz-shaderfx-compare-glitter
```

Known validation gap: this checkpoint verifies that the production effect graph
can compile and route to the Metal `sunflare`, `caustics`, `starsky`, `wavy`,
`fireball`, and direct connected `HSLBlendGPU` paths, that direct and
renderer-driven `ShaderFx` execution both match the lower-level Metal helpers
for the migrated Metal paths including detached radial blur, spin blur, and
glitter, that the HSL, radial blur, spin blur, and glitter input-texture paths
can render through `ToonzScene`/`buildSceneFx(...)` graphs with real
raster-level inputs, that the HSL, radial blur, spin blur, and glitter
input-texture scene fixtures can be saved, reloaded, hydrated from their saved
raster frame files, rebuilt through `buildSceneFx(...)`, and rendered through
Metal, that the sunflare Metal helper
matches a CPU formula reference, and that the production OpenGL and Metal
`ShaderFx` outputs match
within tolerance for all five no-input migrated shaders directly, when wrapped
through `ToonzScene`/`buildSceneFx(...)`, and after saving and reloading minimal
`.tnz` scene fixtures. It does not yet cover additional non-migrated
input-texture shaders beyond the current hand-routed subset, an actual generated
`.metallib` artifact, or full GUI preview/export scene renders. The style
editor validation now includes the build target plus a rendered color-wheel
pixel probe, but a manual GUI smoke should still open the style editor, drag
inside the hexagonal color wheel, and repeat with color calibration enabled on
a macOS desktop. The `TOfflineGL` offscreen validation now compares the legacy
OpenGL clear/readback baseline to `tgraphics` OpenGL and Metal image-render
targets for the first narrow offscreen case, and it compares the legacy
`TOfflineGL::draw(TRasterImageP, TAffine)` raster placement behavior to a
matching
`TGraphics::renderLegacyOfflineRasterPlacementWithActiveBackend(...)` render
under both OpenGL and Metal. This helper preserves the currently observed
legacy-compatible placement behavior for the probe case; a follow-up must move
mixed vector/stage preview-export drawing off direct
`TOfflineGL::makeCurrent()` raw OpenGL calls and onto `DrawList2D`/Metal before
the broader preview/export surface can be considered migrated.
