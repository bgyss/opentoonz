# Codex Goal Prompt: Modernize OpenToonz macOS Graphics With Metal

Use this prompt to start a long-running Codex implementation effort for the
macOS graphics modernization described in
`doc/macos_graphics_modernization_plan.md`.

## Goal

Modernize OpenToonz on macOS by moving normal viewer, editing, preview, and
offscreen render workflows away from deprecated OpenGL and onto a validated
Metal backend, while keeping the existing OpenGL backend available as a
compatibility path until Metal reaches parity.

Do not attempt a one-shot OpenGL-to-Metal rewrite. The codebase has broad
fixed-function OpenGL, GLU, Qt 5 OpenGL, offscreen OpenGL, and GLSL shader
dependencies. Work milestone by milestone, preserve existing behavior, and
leave each milestone buildable and reviewable.

## Repository Context

OpenToonz is a large C++17 / Qt 5.15+ application. The primary CMake entry
point is `toonz/sources`. The preferred reproducible workflow in this checkout
is:

```sh
mise run doctor
mise run configure
mise run build
```

When using the Nix path directly:

```sh
nix develop path:. --command bash -lc 'bash scripts/nix/prepare-tiff.sh && cmake -S toonz/sources --preset nix-relwithdebinfo'
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --parallel 3
```

Keep changes scoped. Avoid formatting sweeps. Do not touch vendored or binary
third-party assets unless a milestone explicitly requires it.

## Strategic Direction

Implement a Metal-first macOS modernization through a backend-neutral rendering
layer:

1. Keep OpenGL working as the compatibility backend.
2. Remove deprecated Qt `QGL*` and GLU-era dependencies where possible.
3. Introduce a small renderer abstraction backed first by OpenGL.
4. Add a macOS-only Metal backend behind the same abstraction.
5. Validate Metal with golden scenes, image diffs, smoke tests, packaging, and
   CI timing.
6. Expand Metal from read-only scene viewing to editing, picking, style editor,
   offscreen rendering, and shader effects.
7. Consider Vulkan/MoltenVK only after the abstraction exists and only if the
   project needs a cross-platform modern backend.

## Current Hotspots

Prioritize these areas:

- `toonz/sources/toonz/sceneviewer.cpp`
  - `QOpenGLFramebufferObject`, matrix stack usage, `gluOrtho2D`,
    `gluProject`, `gluUnProject`, immediate-mode drawing, `glDrawPixels`, and
    `GL_SELECT` picking.
- `toonz/sources/common/tvrender/qtofflinegl.cpp`
  and `toonz/sources/include/qtofflinegl.h`
  - mixed `QOpenGLContext` / FBO code plus legacy `QGLFormat`, `QGLContext`,
    and `QGLPixelBuffer`.
- `toonz/sources/common/tvrender/ttessellator.cpp`
  - GLU tessellation callbacks wired to immediate-mode OpenGL.
- `toonz/sources/toonzqt/styleeditor.cpp`
  - `QOpenGLFramebufferObject` plus immediate-mode OpenGL.
- `toonz/sources/toonz/main.cpp`, `toonz/sources/toonz/mainwindow.cpp`,
  `toonz/sources/common/tgl/tgl.cpp`, and selected `tnztools` files
  - `QGLFormat`, `QGLPixelBuffer`, `QGLContext`, and
    `QGLWidget::convertToGLFormat`.
- `toonz/sources/include/stdfx/shadingcontext.h`,
  `toonz/sources/include/stdfx/shaderinterface.h`, and related `stdfx` code
  - `QOpenGLShaderProgram` and GLSL shader management.

## Non-Negotiable Constraints

- OpenGL fallback must continue to build and run until the Metal backend is
  validated for the same workflow.
- Metal work must be opt-in until parity criteria are met.
- Every milestone must leave the project in a buildable state.
- Every behavioral migration must have either automated evidence, image
  comparison evidence, or a documented manual smoke test.
- Do not use Qt 6 or QRhi as a prerequisite for the first Metal backend. Qt 6
  can be evaluated later, but the initial path must work with the current Qt 5
  architecture.
- Do not introduce Vulkan/MoltenVK in early milestones. Add it only if a later
  milestone explicitly proves cross-platform value.
- Do not remove `GL_SILENCE_DEPRECATION` until macOS application targets no
  longer include OpenGL.

## Milestone 0: Baseline Inventory and Verification Harness

Objective: make current graphics behavior measurable before refactoring.

Tasks:

- Add `scripts/graphics_inventory.sh`.
- Count direct usage of `QGL*`, `QOpenGL*`, GLU, GLEW, GLUT, fixed-function
  OpenGL, `glDrawPixels`, and `GL_SELECT`.
- Add a documented baseline warning-count command for macOS builds.
- Identify or create a minimal golden-scene set covering:
  - raster levels
  - vector levels
  - palette/style changes
  - mesh deformation
  - camera transforms
  - onion skin and overlays
  - common shader effects
  - offscreen render/export
- Add a graphics verification README or doc section with exact commands.
- Add screenshot or image-diff scripts if practical in the current environment.

Validation:

```sh
bash scripts/graphics_inventory.sh
git diff --check
nix develop path:. --command bash -lc 'bash scripts/nix/prepare-tiff.sh && cmake -S toonz/sources --preset nix-relwithdebinfo'
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --parallel 3
```

Completion criteria:

- The inventory script runs and reports stable counts.
- The baseline build succeeds.
- The verification document explains how to compare OpenGL and future Metal
  output.
- Golden scenes or fixture requirements are documented.

## Milestone 1: Remove Qt `QGL*` and Isolate GLU Dependencies

Objective: reduce deprecated Qt OpenGL usage without changing the rendering
backend.

Tasks:

- Replace `QGLFormat` setup with `QSurfaceFormat`.
- Replace `QGLContext` uses with `QOpenGLContext` or a local compatibility
  wrapper.
- Replace `QGLPixelBuffer` paths with `QOpenGLFramebufferObject` or
  `QOffscreenSurface` plus `QOpenGLContext`.
- Replace `QGLWidget::convertToGLFormat` with explicit `QImage` conversion and
  texture upload helpers.
- Introduce local projection/unprojection helpers to replace `gluProject`,
  `gluUnProject`, `gluOrtho2D`, and `gluPickMatrix`.
- Isolate remaining GLU tessellation behind a local adapter so future work can
  swap it for CPU tessellation.

Validation:

```sh
rg -n "QGLFormat|QGLContext|QGLPixelBuffer|QGLWidget::convertToGLFormat" toonz/sources
bash scripts/graphics_inventory.sh
git diff --check
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --parallel 3
```

Manual smoke:

- Launch OpenToonz.
- Open a raster scene and vector scene.
- Pan and zoom the scene viewer.
- Toggle camera view and onion skin.
- Render or preview one simple frame.

Completion criteria:

- No direct `QGL*` use remains in OpenToonz application code, or each remaining
  use is documented as a deliberate blocker.
- OpenGL output remains visually equivalent for the baseline scenes.
- macOS warnings from deprecated Qt OpenGL classes are gone or materially
  reduced.

## Milestone 2: Introduce `tgraphics` With OpenGL Backend

Objective: move high-value call sites away from raw OpenGL while preserving the
current backend.

Tasks:

- Add a backend-neutral renderer module, tentatively named `tgraphics`.
- Define interfaces for:
  - `Device`
  - `RenderTarget`
  - `Texture`
  - `Buffer`
  - `Pipeline`
  - `CommandEncoder`
  - `DrawList2D`
  - `HitTest`
  - `ShaderLibrary`
- Implement an `OpenGLBackend` that wraps current behavior.
- Convert one contained viewer or style-editor path to emit `DrawList2D`
  commands.
- Add debug labels and optional command capture for representative frames.
- Keep raw OpenGL call sites working outside the converted path.

Validation:

```sh
bash scripts/graphics_inventory.sh
git diff --check
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --parallel 3
```

If command capture is added:

```sh
nix develop path:. --command <capture-or-replay-command>
```

Completion criteria:

- The converted path renders through `tgraphics` using the OpenGL backend.
- OpenGL fallback remains the only production backend.
- The abstraction is small and concrete; avoid speculative APIs that no call
  site uses.

## Milestone 3: Experimental Metal Scene Viewer Backend

Objective: prove Metal on a narrow read-only viewer path.

Scope:

- Scene viewer playback and still-frame rendering.
- Pan, zoom, camera transform, checker background, raster/vector compositing,
  and simple overlays that already flow through `DrawList2D`.
- No full editing workflow yet.

Tasks:

- Add `WITH_GRAPHICS_METAL` CMake option enabled only on macOS.
- Add an experimental runtime selector, for example:

```sh
OPENTOONZ_GRAPHICS_BACKEND=metal
OPENTOONZ_GRAPHICS_BACKEND=opengl
```

- Add a macOS-only Metal backend using Objective-C++.
- Integrate Metal with the Qt widget hierarchy through a native view or layer.
- Implement:
  - device and command queue creation
  - drawable/render-target lifecycle
  - texture upload
  - basic 2D textured rendering
  - alpha blending
  - clear/load/store behavior
  - readback for screenshots or tests
  - debug labels
- Add minimal `.metal` shader sources and CMake build integration.
- Keep OpenGL as the default backend.

Validation:

```sh
git diff --check
nix develop path:. --command bash -lc 'bash scripts/nix/prepare-tiff.sh && cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=ON'
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --parallel 3
```

Metal smoke:

```sh
OPENTOONZ_GRAPHICS_BACKEND=metal <path-to-built-OpenToonz-app-or-binary>
```

OpenGL fallback smoke:

```sh
OPENTOONZ_GRAPHICS_BACKEND=opengl <path-to-built-OpenToonz-app-or-binary>
```

Completion criteria:

- Metal backend builds on macOS arm64.
- OpenGL remains default and still works.
- Metal can display at least one baseline scene viewer frame.
- Metal and OpenGL screenshots for that frame match within a documented
  tolerance, or every difference is recorded as a follow-up issue.

## Milestone 4: Metal Viewer Interaction Parity

Objective: make the Metal scene viewer usable for normal navigation and basic
editing context.

Tasks:

- Port tool overlays to `DrawList2D`.
- Replace `GL_SELECT` with CPU hit testing or an ID-buffer pass.
- Validate high-DPI coordinate transforms.
- Validate tablet/stylus event paths do not regress.
- Port camera guide, pegbar, onion skin controls, selection outlines, skeleton
  overlays, vector control points, and mesh editing overlays as needed.
- Add visual comparison cases for the migrated overlays.

Validation:

```sh
bash scripts/graphics_inventory.sh
git diff --check
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --parallel 3
```

Manual smoke:

- Launch with `OPENTOONZ_GRAPHICS_BACKEND=metal`.
- Open raster and vector test scenes.
- Pan, zoom, scrub, and play.
- Toggle camera view.
- Select and transform drawings.
- Exercise common drawing and selection tools.
- Compare screenshots against `OPENTOONZ_GRAPHICS_BACKEND=opengl`.

Completion criteria:

- Common viewer interaction works under Metal.
- Picking no longer depends on OpenGL selection mode in migrated paths.
- User-visible differences from OpenGL are documented and triaged.

## Milestone 5: Metal Offscreen Rendering, Style Editor, and Effects

Objective: remove OpenGL dependence from secondary rendering and preview
surfaces on macOS.

Tasks:

- Port offscreen render targets from `qtofflinegl` to `tgraphics`.
- Port style editor rendering from immediate OpenGL to `DrawList2D` or
  CPU-generated textures.
- Inventory GLSL shaders and classify each as:
  - direct Metal Shading Language rewrite
  - CPU operation
  - shared shader-generation candidate
  - blocked by OpenGL-specific behavior
- Port the smallest useful shader-effect subset.
- Add shader build, packaging, and cache invalidation for Metal.
- Add image-diff validation for render preview/export.

Validation:

```sh
bash scripts/graphics_inventory.sh
git diff --check
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --parallel 3
nix develop path:. --command bash -lc 'scripts/macos/package-nix-app.sh'
nix develop path:. --command bash -lc 'scripts/macos/assert-arm64-bundle.sh'
```

Manual smoke:

- Launch with Metal.
- Use the style editor.
- Preview/export representative frames.
- Compare Metal output to OpenGL output.

Completion criteria:

- Common preview/export workflows can run through Metal.
- Style editor no longer requires direct OpenGL in the migrated path.
- Metal shaders are packaged into the macOS app bundle correctly.

## Milestone 6: CI Gate and Default-Backend Decision

Objective: decide whether Metal is ready to become the default macOS backend.

Tasks:

- Add macOS arm64 CI coverage for:
  - OpenGL fallback build
  - Metal-enabled build
  - app bundle packaging
  - arm64 Mach-O validation
  - graphics inventory output
  - warning count summary
  - ccache summary
- Add backend smoke jobs if a headless or scripted GUI route exists.
- Record build-time impact compared to the pre-Metal baseline.
- Decide default backend:
  - keep OpenGL default if parity gaps remain
  - switch Metal default only after viewer, editing, preview, and offscreen
    workflows satisfy acceptance criteria

Validation:

```sh
gh workflow run <workflow-name>
gh run watch <run-id>
gh run view <run-id> --log-failed
```

If `gh` authentication is stale:

```sh
gh auth refresh -h github.com -s repo -s workflow
gh auth status
```

Completion criteria:

- CI proves Metal-enabled macOS arm64 builds are repeatable.
- Packaging and arm64 bundle validation pass.
- Build-time and warning-count effects are documented.
- Metal default decision is backed by evidence, not preference.

## Milestone 7: OpenGL Retirement Plan

Objective: remove OpenGL from normal macOS operation after Metal parity.

Tasks:

- Switch macOS default backend to Metal.
- Keep OpenGL fallback for at least one release cycle if feasible.
- Add release notes and troubleshooting docs.
- Stop linking OpenGL on macOS once fallback is removed.
- Remove `GL_SILENCE_DEPRECATION` from macOS app targets only after OpenGL is
  gone.
- Keep Linux/Windows backend behavior explicit and unaffected.

Validation:

```sh
rg -n "GL_SILENCE_DEPRECATION|OpenGL.framework|QOpenGL|QGL|glu[A-Z]|GL_SELECT|glDrawPixels" toonz/sources .github scripts
git diff --check
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --parallel 3
nix develop path:. --command bash -lc 'scripts/macos/package-nix-app.sh'
nix develop path:. --command bash -lc 'scripts/macos/assert-arm64-bundle.sh'
```

Completion criteria:

- Normal macOS builds and packages no longer require OpenGL.
- The app runs normal macOS workflows through Metal.
- Remaining OpenGL usage, if any, is isolated to explicit compatibility code or
  non-macOS paths.

## Final Acceptance Criteria

The goal is complete only when all of the following are true:

- macOS OpenToonz can run normal viewer, editing, preview, and render workflows
  through Metal.
- OpenGL fallback remains available until explicitly retired.
- Golden scene output from Metal matches the OpenGL baseline within documented
  tolerance.
- Metal backend is covered by macOS arm64 CI build and package validation.
- Metal shaders and resources are included in the app bundle.
- macOS warning counts no longer include routine Qt `QGL*` or Apple OpenGL
  deprecation noise in the default backend.
- Build-time impact is measured and documented.
- User-facing backend selection and troubleshooting are documented.

## Required Handoff After Each Milestone

End every milestone with:

- Files changed.
- Build commands run.
- Test and smoke commands run.
- Graphics inventory before/after.
- Warning count before/after when relevant.
- Screenshots or image-diff evidence when rendering changed.
- Known visual or behavioral differences.
- Next milestone recommendation.

If full validation cannot be run locally, state exactly why and provide the
commands that should be run on a macOS arm64 machine.
