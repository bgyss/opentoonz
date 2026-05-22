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

## Files Changed

- `scripts/graphics_shader_inventory.sh`
- `scripts/graphics_shaderfx_compare.sh`
- `doc/macos_graphics_modernization_milestone5_shader_inventory_report.md`
- `toonz/sources/include/tgraphics.h`
- `toonz/sources/common/tgraphics/tgraphics.cpp`
- `toonz/sources/common/tgraphics/tgraphics_metal.mm`
- `toonz/sources/common/tgraphics/tgraphics_metal_shaders.metal`
- `toonz/sources/common/tgraphics/tgraphics_metal_probe.cpp`
- `toonz/sources/toonz/CMakeLists.txt`
- `toonz/sources/include/stdfx/shaderfx.h`
- `toonz/sources/stdfx/CMakeLists.txt`
- `toonz/sources/stdfx/shaderfx.cpp`
- `toonz/sources/stdfx/shaderfx_metal_probe.cpp`

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
  and affines directly from the output rect for the identity case.
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
  PAM artifacts for the migrated no-input procedural shaders, writes a Metal HSL
  artifact for `SHADER_HSLBlendGPU`, writes renderer-driven Metal artifacts for
  the migrated shaders, and passes on Apple M1 Max.
- OpenGL remains the default backend.
- Non-32-bit tiles and every other `ShaderFx` still use the existing OpenGL
  path.

Remaining shared shader-generation candidates:

- `glitter.frag`
- `radialblurGPU.frag`
- `spinblurGPU.frag`

These sample `inputImage` textures through GLSL `sampler2D`/`texture2D` and use
the current OpenGL matrix conventions. They should be ported after a
backend-neutral input texture and coordinate binding path exists in
`tgraphics`. `HSLBlendGPU.frag` is now the first hand-routed input-texture
ShaderFx case, but it is not yet generated from the GLSL source and does not
cover bbox/ports shaders that need non-identity input geometry.

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
- Full scene-level preview/export coverage still needs a broader validation
  pass with real scene fixtures. The current renderer probe validates the
  migrated `ShaderFx` graph in isolation, not a complete `ToonzScene` render.

Blocked by OpenGL-specific transform feedback:

- `HSLBlendGPU_ports.vert`
- `glitter_ports.vert`
- `glitter_bbox.vert`
- `radialblurGPU_ports.vert`
- `radialblurGPU_bbox.vert`
- `spinblurGPU_ports.vert`
- `spinblurGPU_bbox.vert`

These are vertex programs used by `ShaderFx` to compute input-port rectangles
or output bboxes through transform feedback. A Metal port should replace this
with CPU bbox/port computation or a Metal buffer pass, not a direct one-for-one
GLSL translation.

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
This gives the bundle a concrete Metal shader resource today while preserving
the source-string fallback for local builds and command-line probes.

Known shader packaging gap: the local Xcode installation can locate `metal` at
`/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/metal`,
but invoking it currently fails with `error: cannot execute tool 'metal' due to
missing Metal Toolchain; use: xcodebuild -downloadComponent MetalToolchain`.
`xcrun --find metallib` also fails. Enable an actual CMake `.metal` to
`.metallib` build step after that component is installed, then copy the
generated `tgraphics_metal_shaders.metallib` into app resources so the runtime
uses the packaged library path by default.

## ShaderFx Image-Diff Command

```sh
nix develop path:. --command bash scripts/graphics_shaderfx_compare.sh /private/tmp/opentoonz-shaderfx-compare
```

Artifacts:

- `/private/tmp/opentoonz-shaderfx-compare/sunflare-opengl.pam`
- `/private/tmp/opentoonz-shaderfx-compare/sunflare-metal.pam`
- `/private/tmp/opentoonz-shaderfx-compare/sunflare-diff.pam`
- `/private/tmp/opentoonz-shaderfx-compare/caustics-opengl.pam`
- `/private/tmp/opentoonz-shaderfx-compare/caustics-metal.pam`
- `/private/tmp/opentoonz-shaderfx-compare/caustics-diff.pam`
- `/private/tmp/opentoonz-shaderfx-compare/starsky-opengl.pam`
- `/private/tmp/opentoonz-shaderfx-compare/starsky-metal.pam`
- `/private/tmp/opentoonz-shaderfx-compare/starsky-diff.pam`
- `/private/tmp/opentoonz-shaderfx-compare/wavy-opengl.pam`
- `/private/tmp/opentoonz-shaderfx-compare/wavy-metal.pam`
- `/private/tmp/opentoonz-shaderfx-compare/wavy-diff.pam`
- `/private/tmp/opentoonz-shaderfx-compare/fireball-opengl.pam`
- `/private/tmp/opentoonz-shaderfx-compare/fireball-metal.pam`
- `/private/tmp/opentoonz-shaderfx-compare/fireball-diff.pam`
- `/private/tmp/opentoonz-shaderfx-compare/fireball-metal-renderer.pam`
- `/private/tmp/opentoonz-shaderfx-compare/HSLBlendGPU-metal.pam`
- `/private/tmp/opentoonz-shaderfx-compare/HSLBlendGPU-metal-renderer.pam`

The default tolerance is 2 channel values. `fireball` uses
`SHADERFX_FIREBALL_COMPARE_TOLERANCE=32` by default because its procedural noise
uses transcendental functions where OpenGL GLSL and Metal Shading Language
rounding can diverge at isolated threshold pixels. This keeps the strict
tolerance for the other migrated shaders while still failing broad color,
alpha, or coordinate mismatches.

## Next Effects Recommendation

The direct no-input procedural shader subset and the first direct
input-texture route (`HSLBlendGPU`) now have both direct and renderer-driven
probe coverage. Continue with scene-level preview/export fixtures for the
migrated shader subset, then continue with backend-neutral input texture binding
for the remaining shared shader-generation candidates (`glitter`,
`radialblurGPU`, and `spinblurGPU`) before widening preview/export coverage.
Keep OpenGL `ShaderFx` as the default until full scene parity is broader.

## Validation Run

```sh
bash scripts/graphics_shader_inventory.sh
nix develop path:. --command bash -lc 'cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=ON'
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tgraphics_metal_probe --parallel 3
nix develop path:. --command toonz/build/nix-relwithdebinfo/tnzcore/tgraphics_metal_probe
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tgraphics_metal_probe shaderfx_metal_probe OpenToonz --parallel 3
test -f toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app/Contents/Resources/tgraphics_metal_shaders.metal
nix develop path:. --command toonz/build/nix-relwithdebinfo/tnzcore/tgraphics_metal_probe
nix develop path:. --command bash -lc 'OPENTOONZ_GRAPHICS_BACKEND=metal toonz/build/nix-relwithdebinfo/stdfx/shaderfx_metal_probe --shader SHADER_fireball'
nix develop path:. --command bash -lc 'OPENTOONZ_GRAPHICS_BACKEND=metal toonz/build/nix-relwithdebinfo/stdfx/shaderfx_metal_probe --shader SHADER_HSLBlendGPU'
nix develop path:. --command bash -lc 'OPENTOONZ_GRAPHICS_BACKEND=metal toonz/build/nix-relwithdebinfo/stdfx/shaderfx_metal_probe --shader SHADER_HSLBlendGPU --renderer'
nix develop path:. --command bash scripts/graphics_shaderfx_compare.sh /private/tmp/opentoonz-shaderfx-compare-packaged-source
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
graphics_shaderfx_compare: ok
Checked 281 Mach-O files for arm64.
WITH_GRAPHICS_METAL:BOOL=OFF
```

The final ShaderFx artifact directory for this checkpoint was:

```text
/private/tmp/opentoonz-shaderfx-compare-renderer
```

Known validation gap: this checkpoint verifies that the production effect graph
can compile and route to the Metal `sunflare`, `caustics`, `starsky`, `wavy`,
`fireball`, and direct connected `HSLBlendGPU` paths, that direct and
renderer-driven `ShaderFx` execution both match the lower-level Metal helpers
for the migrated Metal paths, that the sunflare Metal helper matches a CPU
formula reference, and that the production OpenGL and Metal `ShaderFx` outputs
match within tolerance for all five no-input migrated shaders. It does not yet
cover complete scene-level preview/export fixtures, the remaining input-texture
shader effects, transform-feedback bbox/ports shaders beyond the identity HSL
bypass, an actual generated `.metallib` artifact, or full preview/export scene
renders.
