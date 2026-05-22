# macOS Graphics Modernization Plan

Status: draft plan, based on source inventory from 2026-05-21.

## Executive Summary

OpenToonz should move the macOS graphics stack away from direct OpenGL, but the
right first step is not a direct one-for-one rewrite of OpenGL calls into Metal
or Vulkan. The current code depends on a broad mix of legacy fixed-function
OpenGL, GLU tessellation and projection helpers, Qt 5 OpenGL widgets, offscreen
OpenGL contexts, and GLSL shader effects. A successful migration needs an
OpenToonz rendering abstraction that can keep the current OpenGL backend alive
while a modern backend is introduced feature by feature.

Recommended direction:

1. Keep OpenGL as the compatibility backend during the migration.
2. Remove deprecated Qt `QGL*` usage and isolate fixed-function OpenGL behavior.
3. Introduce a backend-neutral rendering layer for 2D draw commands, textures,
   render targets, shaders, hit testing, and offscreen rendering.
4. Build a native Metal backend first for macOS scene viewing and playback.
5. Expand Metal coverage to tools, picking, style editor, offscreen rendering,
   and shader effects.
6. Evaluate Vulkan through MoltenVK only after the abstraction exists and only
   if cross-platform reuse justifies the dependency and portability constraints.
7. Revisit Qt 6 / QRhi once Qt 6 blockers are understood, but do not make the
   entire graphics migration depend on a Qt major-version migration.

This approach reduces deprecation risk without forcing a high-risk application
rewrite. It also gives the macOS arm64 build a path toward fewer deprecated
headers, fewer warning-heavy translation units, and a renderer that can be
profiled with Apple's Metal tools.

## Why This Work Is Necessary

Apple's OpenGL documentation marks OpenGL as deprecated in macOS 10.14 and
directs high-performance GPU work toward Metal:
https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/OpenGL-MacProgGuide/opengl_intro/opengl_intro.html

Qt 6 also moved away from treating OpenGL as the foundation of Qt graphics.
Qt's own OpenGL migration notes state that Qt 5's deprecated `QGL*` classes were
removed in Qt 6, while Qt 6 graphics infrastructure supports Direct3D, Metal,
and Vulkan in addition to OpenGL:
https://doc.qt.io/qt-6/opengl-changes-qt6.html

The practical implication for OpenToonz is that macOS builds can silence
OpenGL deprecation warnings in the short term, but the long-term fix is to stop
requiring Apple's deprecated OpenGL framework for core rendering paths.

## Current OpenToonz Graphics Surface

This inventory is approximate and based on text search; it should be turned into
a maintained script in the first phase.

```sh
rg -l "QGL|QOpenGL|GLEW|GLUT|glBegin|glEnd|glMatrixMode|glDrawPixels|glVertex|glColor|glTexCoord|glu[A-Z]|GL_SELECT|GLU" toonz/sources | wc -l
rg -n "QGL|QOpenGL|GLEW|GLUT|glBegin|glEnd|glMatrixMode|glDrawPixels|glVertex|glColor|glTexCoord|glu[A-Z]|GL_SELECT|GLU" toonz/sources | wc -l
```

Current result:

- About 130 files contain Qt/OpenGL or legacy OpenGL markers.
- About 2,500 source matches point to fixed-function OpenGL, GLU, Qt OpenGL, or
  related APIs.

Notable hotspots:

- `toonz/sources/toonz/sceneviewer.cpp`
  - Uses `QOpenGLFramebufferObject`, fixed-function matrix state,
    `gluOrtho2D`, `gluProject`, `gluUnProject`, immediate-mode drawing,
    `glDrawPixels`, and `GL_SELECT` picking.
  - This is the highest-value first target because it is user-visible and
    central to playback, camera transforms, overlays, and interactive editing.
- `toonz/sources/common/tvrender/qtofflinegl.cpp` and
  `toonz/sources/include/qtofflinegl.h`
  - Mix modern `QOpenGLContext` / `QOpenGLFramebufferObject` with legacy
    `QGLFormat`, `QGLContext`, and `QGLPixelBuffer`.
  - This is a good early cleanup target because offscreen rendering can be
    tested with image outputs.
- `toonz/sources/common/tvrender/ttessellator.cpp`
  - Uses GLU tessellation callbacks wired directly to OpenGL calls such as
    `glBegin`, `glEnd`, and `glVertex3dv`.
  - This must be replaced or isolated before the renderer can be backend
    neutral.
- `toonz/sources/toonzqt/styleeditor.cpp`
  - The hexagonal color wheel has been moved off `QOpenGLWidget` and
    `QOpenGLFramebufferObject` onto QWidget/QImage rendering with software LUT
    calibration.
  - Remaining style editor and related palette/style preview surfaces should
    continue moving to `DrawList2D` or CPU-generated textures.
- `toonz/sources/toonz/main.cpp`, `toonz/sources/toonz/mainwindow.cpp`,
  `toonz/sources/common/tgl/tgl.cpp`, and selected `tnztools` files
  - Still reference `QGLFormat`, `QGLPixelBuffer`, `QGLContext`, or
    `QGLWidget::convertToGLFormat`.
  - These are early modernization targets because Qt 6 removes the `QGL*`
    classes entirely.
- `toonz/sources/include/stdfx/shadingcontext.h`,
  `toonz/sources/include/stdfx/shaderinterface.h`, and related `stdfx` code
  - Depend on `QOpenGLShaderProgram` and GLSL shader management.
  - Shader effects need their own migration plan because Metal uses Metal
    Shading Language, Vulkan uses SPIR-V, and Qt QRhi expects shader packages
    generated from SPIR-V.

## Technology Recommendation

### Primary macOS backend: Metal

Metal should be the first modern backend for macOS.

Reasons:

- It is Apple's intended replacement for deprecated OpenGL on macOS.
- It is native on Apple Silicon and Intel Macs that support current macOS
  versions.
- It gives access to Xcode Metal frame capture, shader debugging, GPU counters,
  and Metal HUD instrumentation.
- It avoids adding a translation layer on macOS while OpenToonz is still
  learning its modern renderer shape.

Tradeoffs:

- It is Apple-specific.
- It requires Objective-C++ integration at the Qt/native-view boundary.
- Existing GLSL shaders and fixed-function GL behavior must be ported or
  rewritten.

### Secondary option: Vulkan through MoltenVK

Vulkan should not be the first macOS replacement for OpenGL unless the project
chooses cross-platform Vulkan as a strategic goal. On macOS, Vulkan support is
provided through MoltenVK, which maps Vulkan to Metal rather than using a native
Apple Vulkan driver.

MoltenVK is valuable, but it is still an extra portability layer. Its README
describes it as a Vulkan implementation layered over Apple's Metal framework
and documents that Vulkan compliance is affected by differences between Vulkan
and Metal:
https://github.com/KhronosGroup/MoltenVK

Use Vulkan/MoltenVK when:

- OpenToonz wants one modern backend shared by macOS, Linux, and possibly
  Windows.
- The renderer abstraction is already in place.
- Shader tooling and package/notarization impact are acceptable.
- MoltenVK's portability subset is tested against OpenToonz rendering needs.

Avoid making Vulkan/MoltenVK the first migration milestone because it will not
remove the need to understand Metal-era constraints on macOS. It can also make
debugging harder during the period when OpenToonz is still disentangling legacy
OpenGL behavior.

### Future option: Qt 6 QRhi

Qt 6's QRhi is relevant because it abstracts OpenGL, Direct3D, Metal, and
Vulkan:
https://doc.qt.io/archives/qt-6.9/qrhi.html

However, QRhi is not a drop-in OpenGL replacement for this codebase:

- OpenToonz currently targets Qt 5.15+.
- The codebase still uses Qt 5 modules that are migration blockers, including
  Qt Script.
- QRhi's public documentation warns that the QRhi family has limited source and
  binary compatibility guarantees and requires linking to Qt private GUI APIs.
- QRhi does not automatically port fixed-function OpenGL concepts such as matrix
  stacks, `glDrawPixels`, GLU tessellation, or `GL_SELECT` picking.

Recommendation:

- Track Qt 6 / QRhi as a medium-term route to cross-platform rendering only
  after a Qt 6 feasibility project has retired or replaced Qt 5-only blockers.
- Keep the OpenToonz renderer abstraction independent enough that it can be
  backed by either direct Metal or QRhi later.

## Target Architecture

Introduce a small backend-neutral rendering layer before adding a second GPU
API. The first implementation should wrap the existing OpenGL behavior so that
behavior can be preserved while call sites move away from raw GL.

Proposed module shape:

- `tgraphics::Device`
  - Owns backend initialization, device capability queries, frame lifecycle,
    debug labels, and resource cleanup.
- `tgraphics::RenderTarget`
  - Represents window, offscreen image, thumbnail, and FBO-like targets.
- `tgraphics::Texture`
  - Represents raster uploads, viewer images, brushes, icons, color LUTs, and
    effect intermediates.
- `tgraphics::Buffer`
  - Represents vertex, index, uniform, and staging data.
- `tgraphics::Pipeline`
  - Represents shader program, blend state, depth/stencil state, topology, and
    color formats.
- `tgraphics::CommandEncoder`
  - Records draw, clear, copy, upload, readback, and debug marker commands.
- `tgraphics::DrawList2D`
  - Captures immediate-mode style viewer/tool drawing as retained geometry.
- `tgraphics::HitTest`
  - Replaces `GL_SELECT` with CPU hit testing or an explicit ID-buffer pass.
- `tgraphics::ShaderLibrary`
  - Owns shader source, generated variants, cache keys, and compile diagnostics.

Initial backends:

- `OpenGLBackend`
  - Compatibility backend used to preserve behavior while call sites migrate.
- `MetalBackend`
  - New macOS backend, introduced first for scene viewer playback.

Optional later backend:

- `VulkanBackend`
  - Only after the abstraction has proven useful and after MoltenVK portability
    constraints are tested on macOS.

## Migration Plan

### Phase 0: Baseline and Test Harness

Goal: make graphics behavior measurable before changing it.

Tasks:

- Add a maintained graphics inventory script that counts direct `QGL*`, GLU,
  fixed-function OpenGL, `QOpenGL*`, GLEW, GLUT, and GLSL shader usage.
- Create a small suite of golden OpenToonz scenes that cover:
  - raster levels
  - vector levels
  - palette/style changes
  - mesh deformation
  - camera transforms
  - sub-xsheets
  - onion skin and overlays
  - common shader effects
  - offscreen render/export
- Add screenshot or image-diff checks for scene viewer and offscreen rendering.
- Add manual GUI smoke coverage for pan/zoom, playback, camera view, tool
  overlays, style editor, and render preview.
- Add frame-time and memory telemetry around scene viewer playback.
- Record macOS arm64 CI timing and warning counts before every graphics phase.

Deliverables:

- `scripts/graphics_inventory.sh`
- `doc/macos_graphics_modernization_plan.md` kept current
- golden scene assets or documented fixture locations
- CI job or manual script for macOS graphics smoke checks

Exit criteria:

- Current OpenGL behavior can be compared visually and functionally.
- Warning counts and build timings are tracked.
- The team has a short list of scenes that must remain visually stable.

### Phase 1: Legacy OpenGL Cleanup Without Changing Rendering Backend

Goal: reduce deprecation pressure and remove Qt 6 blockers while OpenGL output
is still the only renderer.

Tasks:

- Replace `QGLFormat` with `QSurfaceFormat`.
- Replace `QGLContext` with `QOpenGLContext`.
- Replace `QGLPixelBuffer` paths with `QOpenGLFramebufferObject` or
  `QOffscreenSurface` plus `QOpenGLContext`.
- Replace `QGLWidget::convertToGLFormat` with explicit `QImage` conversion and
  texture upload logic.
- Isolate `GLU` usage behind local helper APIs.
- Replace `gluProject`, `gluUnProject`, `gluOrtho2D`, and `gluPickMatrix` with
  local matrix math.
- Replace `GL_SELECT` picking with CPU hit testing or an explicit render-ID
  selection pass.
- Replace `glDrawPixels` with texture upload and textured quad rendering.
- Convert obvious `glBegin` / `glEnd` drawing to vertex arrays or local
  `DrawList2D` structures.

Deliverables:

- No remaining `QGL*` usage in OpenToonz application code.
- GLU calls isolated to one compatibility implementation or removed.
- Scene viewer still renders through OpenGL with identical visual behavior.

Exit criteria:

- macOS build is warning-clean for Qt/OpenGL deprecations except for deliberate
  OpenGL framework deprecation suppression.
- The app can still run with the current OpenGL backend.
- Offscreen render output matches the baseline scenes within tolerance.

### Phase 2: Introduce Renderer Abstraction With OpenGL Backend

Goal: move high-value call sites away from raw OpenGL without changing the GPU
API yet.

Tasks:

- Add `tgraphics` interfaces for device, render target, textures, buffers,
  pipelines, command encoding, draw lists, shader library, and hit testing.
- Implement `OpenGLBackend` by wrapping the current OpenGL path.
- Convert scene viewer image compositing to submit `DrawList2D` commands.
- Convert viewer overlays to retained draw commands instead of direct
  fixed-function GL.
- Add command capture/replay tests for representative frames.
- Add debug labels around major render passes.

Deliverables:

- OpenGL-backed `tgraphics` module.
- Scene viewer read-only playback path using `tgraphics`.
- Capture/replay fixture for at least one raster scene and one vector scene.

Exit criteria:

- Scene viewer output is unchanged with the OpenGL backend.
- New Metal backend work can start without touching every viewer call site.

### Phase 3: Metal Scene Viewer Pilot

Goal: prove the new backend on the most important macOS surface with limited
scope.

Scope:

- Read-only scene viewer playback.
- Pan, zoom, camera transform, checker background, raster/vector compositing,
  onion skin if it is already represented in the draw list.
- No editing tools in the first pilot except basic visual overlays.

Tasks:

- Add a macOS-only Metal backend using Objective-C++.
- Integrate a Metal-backed view or layer with the existing Qt widget hierarchy.
- Implement texture upload, render target lifecycle, command buffers, basic
  blending, simple 2D pipelines, and readback.
- Add shader build rules for `.metal` sources.
- Add runtime backend selection:
  - default: OpenGL
  - opt-in: Metal through preference, environment variable, or developer flag
- Add Xcode Metal frame capture notes for local debugging.

Deliverables:

- Experimental Metal scene viewer backend.
- OpenGL fallback available at runtime.
- CI build coverage for the Metal backend on macOS arm64.

Exit criteria:

- Golden scene viewer captures match OpenGL within defined tolerance.
- Playback performance is no worse than OpenGL on Apple Silicon for test scenes.
- The app can switch back to OpenGL immediately if the Metal path fails.

### Phase 4: Editing, Overlays, and Picking

Goal: make the Metal viewer usable for normal animation work, not just playback.

Tasks:

- Port tool overlays to `DrawList2D`.
- Replace `GL_SELECT` behavior with the selected hit-test strategy.
- Port camera guide, pegbar, onion skin controls, selection outlines, skeleton
  overlays, vector control points, and mesh editing overlays.
- Validate tablet/stylus input paths and high-DPI coordinate transforms.
- Add visual and interaction tests for common tools.

Deliverables:

- Metal scene viewer can be used for normal drawing and editing workflows.
- Hit testing no longer depends on OpenGL selection mode.

Exit criteria:

- Artists can perform representative drawing, selection, transform, and camera
  workflows with the Metal backend.
- Known differences are documented and tracked as bugs, not architectural gaps.

### Phase 5: Offscreen Rendering, Style Editor, and Shader Effects

Goal: remove OpenGL from secondary rendering surfaces and effect previews.

Tasks:

- Port offscreen render targets from `qtofflinegl` to `tgraphics`.
- Port style editor rendering from immediate OpenGL to `DrawList2D` or
  CPU-generated textures.
- Inventory all GLSL shaders and classify them:
  - simple enough to rewrite directly in Metal Shading Language
  - better represented as CPU image operations
  - candidates for shared shader source generation
  - blocked by OpenGL-specific behavior
- Introduce shader packaging and cache invalidation for Metal.
- Add render-preview image comparisons for effects.

Deliverables:

- Metal-backed offscreen render path.
- Style editor no longer requires direct OpenGL.
- First shader-effect subset running through Metal.

Exit criteria:

- Common export/render-preview workflows work without OpenGL on macOS.
- Shader diagnostics are understandable to developers and packagers.

### Phase 6: Qt 6 / QRhi Decision Point

Goal: decide whether direct Metal remains the long-term macOS backend or whether
OpenToonz should adopt QRhi after Qt 6 migration work.

Tasks:

- Complete a Qt 6 feasibility branch focused on:
  - Qt Script replacement
  - Qt OpenGL module changes
  - `QOpenGLWidget` module/linking changes
  - removed or changed Qt APIs
  - packaging changes
- Build a small QRhi prototype that renders one captured `DrawList2D` frame.
- Compare direct Metal and QRhi on:
  - code complexity
  - shader tooling
  - performance
  - debug tooling
  - compatibility guarantees
  - long-term maintenance

Decision:

- Keep direct Metal if macOS-specific quality and tooling matter most.
- Move to QRhi if cross-platform backend reuse outweighs QRhi's private API and
  Qt 6 coupling costs.

### Phase 7: Optional Vulkan/MoltenVK Backend

Goal: add Vulkan only if it gives OpenToonz cross-platform leverage beyond what
Metal alone provides.

Tasks:

- Add Vulkan backend behind the same `tgraphics` abstraction.
- On macOS, package and test through MoltenVK.
- Enable validation layers in developer builds.
- Test MoltenVK portability behavior against OpenToonz needs:
  - render target formats
  - blending
  - texture upload and readback
  - shader conversion
  - offscreen rendering
  - synchronization
  - Intel and Apple Silicon Macs
- Compare Vulkan/MoltenVK against direct Metal with golden scenes and playback
  traces.

Deliverables:

- Experimental Vulkan backend.
- macOS MoltenVK package integration notes.
- Performance and parity report.

Exit criteria:

- Vulkan provides measurable cross-platform value, or the project explicitly
  decides not to carry the backend.

### Phase 8: Default Switch and OpenGL Retirement

Goal: make the modern backend the default on macOS and remove OpenGL dependency
from normal macOS operation.

Tasks:

- Switch macOS default backend to Metal after viewer, tools, offscreen render,
  style editor, and common effects meet parity criteria.
- Keep OpenGL fallback for at least one release cycle if possible.
- Stop linking OpenGL on macOS when the fallback is removed.
- Remove `GL_SILENCE_DEPRECATION` when OpenGL is no longer included by macOS
  application targets.
- Update build docs, CI, packaging, and troubleshooting docs.

Exit criteria:

- Normal macOS operation does not require OpenGL.
- macOS arm64 CI no longer compiles the old OpenGL-heavy code paths by default.
- Users have a documented fallback or migration note for affected hardware.

## Build and CI Strategy

Short-term CI optimization:

- Keep `GL_SILENCE_DEPRECATION` while OpenGL is still used. This reduces noisy
  Apple framework warnings but should be treated as temporary.
- Keep ccache enabled for macOS arm64 and inspect cache hit rates after each
  workflow run.
- Avoid adding Metal/Vulkan dependencies to non-macOS jobs unless a cross-
  platform backend is actually enabled.

During migration:

- Add build flags:
  - `WITH_GRAPHICS_OPENGL=ON`
  - `WITH_GRAPHICS_METAL=ON` on macOS
  - `WITH_GRAPHICS_VULKAN=OFF` by default until Phase 7
- Add runtime selection:
  - `OPENTOONZ_GRAPHICS_BACKEND=opengl`
  - `OPENTOONZ_GRAPHICS_BACKEND=metal`
  - `OPENTOONZ_GRAPHICS_BACKEND=vulkan` only when available
- Add CI matrix coverage:
  - macOS arm64 OpenGL fallback build
  - macOS arm64 Metal build
  - Linux OpenGL build
  - optional Vulkan build only after Phase 7
- Track:
  - total build time
  - warning count
  - ccache hit rate
  - package size
  - scene viewer smoke results
  - golden image diff results

Expected build-time effect:

- Silencing OpenGL deprecation warnings reduces log volume but does not remove
  OpenGL compile cost.
- Removing `QGL*`, GLU, and fixed-function call sites reduces warning churn and
  Qt 6 blockers.
- Keeping the backend modular prevents every graphics experiment from forcing a
  full application-wide rewrite.
- A Metal backend may add shader compilation and Objective-C++ build work, so CI
  should measure the cost instead of assuming it is free.

## Risk Register

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Fixed-function GL behavior is spread across viewer, tools, and utility code | A direct Metal/Vulkan rewrite becomes unbounded | First wrap behavior in `DrawList2D` and matrix/hit-test helpers |
| `GL_SELECT` picking has no modern equivalent | Tool selection behavior regresses | Replace with CPU hit testing or explicit ID-buffer render pass |
| GLU tessellation is coupled to immediate-mode drawing | Vector fill behavior changes | Replace with CPU tessellation that outputs indexed geometry |
| GLSL shader effects do not translate automatically to Metal | Effects regress or disappear | Inventory shaders, port in batches, add golden render tests |
| Qt 6 migration is larger than graphics migration | Renderer work stalls behind unrelated Qt API changes | Keep direct Metal path possible under Qt 5 while designing for QRhi later |
| MoltenVK portability subset differs from native Vulkan | Vulkan backend behaves differently on macOS | Treat Vulkan as optional and test through MoltenVK before committing |
| Native Metal view integration breaks Qt widget assumptions | UI regressions and event issues | Start with read-only viewer pilot and keep OpenGL fallback |
| Metal code complicates packaging/signing | Broken app bundles or notarization failures | Add package checks early and keep dependency footprint explicit |

## Acceptance Criteria

The macOS graphics migration should not be considered complete until:

- OpenToonz can run normal macOS viewer, editing, preview, and render workflows
  without OpenGL.
- Golden scene captures match the OpenGL baseline within agreed tolerances.
- Common animation workflows have manual smoke coverage on Apple Silicon.
- Shader effects used by default scenes and common workflows are ported or have
  documented fallbacks.
- macOS packaging, signing, and notarization work with the modern backend.
- CI tracks build time, warning count, and backend-specific smoke results.
- OpenGL fallback can be removed or clearly scoped to legacy support.

## Near-Term Implementation Backlog

Suggested first pull requests:

1. Add `scripts/graphics_inventory.sh` and CI/manual docs for warning and API
   usage counts.
2. Replace `QGLFormat` setup in `toonz/sources/toonz/main.cpp` with
   `QSurfaceFormat`.
3. Replace `QGLPixelBuffer` checks and pbuffer paths with
   `QOpenGLFramebufferObject` / `QOffscreenSurface`.
4. Replace `QGLWidget::convertToGLFormat` in `tnztools` with explicit `QImage`
   conversion helpers.
5. Add local matrix helper replacements for GLU projection/unprojection in the
   scene viewer.
6. Replace `glDrawPixels` viewer paths with texture upload and draw commands.
7. Introduce a minimal `DrawList2D` and convert a small overlay or style editor
   drawing path.
8. Add a hidden experimental Metal backend flag and render one captured
   read-only scene viewer frame.

## Recommended Decision

Adopt a Metal-first macOS modernization strategy, but make it backend-driven
instead of macOS-only at the call sites. The work should start by cleaning up
legacy OpenGL assumptions and creating a rendering abstraction with an OpenGL
backend. Once that layer exists, add a Metal scene viewer pilot and expand it
based on visual parity and interaction tests. Vulkan/MoltenVK should remain a
deliberate second backend choice, not the initial OpenGL replacement.
