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

This checkpoint also adds `shaderfx_metal_probe`, a Metal-only validation target
that loads the packaged shader interface, renders `SHADER_sunflare` through
`ShaderFx::doCompute(...)`, and compares the resulting tile to the lower-level
Metal sunflare helper. The Metal branch now runs before `ShadingContextManager`
is instantiated, so this migrated path no longer creates the OpenGL shader
context before returning through Metal.

## Files Changed

- `scripts/graphics_shader_inventory.sh`
- `doc/macos_graphics_modernization_milestone5_shader_inventory_report.md`
- `toonz/sources/include/tgraphics.h`
- `toonz/sources/common/tgraphics/tgraphics.cpp`
- `toonz/sources/common/tgraphics/tgraphics_metal.mm`
- `toonz/sources/common/tgraphics/tgraphics_metal_shaders.metal`
- `toonz/sources/common/tgraphics/tgraphics_metal_probe.cpp`
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

First validated Metal procedural helper:

- `sunflare.frag`

The Metal implementation uses the same procedural inputs as the GLSL source:
`outputToWorld`, `color`, `blades`, `intensity`, `angle`, `bias`, and
`sharpness`. It renders into a Metal texture target and returns `TRaster32P`
readback for probe/image-diff workflows.

Production integration status:

- `OPENTOONZ_GRAPHICS_BACKEND=metal` can route 32-bit, no-input
  `SHADER_sunflare` tiles through the Metal helper.
- `shaderfx_metal_probe` validates the `ShaderFx::doCompute(...)` Metal branch
  against the lower-level Metal helper for a transformed 96x64 tile.
- OpenGL remains the default backend.
- Non-32-bit sunflare tiles and every other `ShaderFx` still use the existing
  OpenGL path.

Shared shader-generation candidates:

- `HSLBlendGPU.frag`
- `glitter.frag`
- `radialblurGPU.frag`
- `spinblurGPU.frag`

These sample `inputImage` textures through GLSL `sampler2D`/`texture2D` and use
the current OpenGL matrix conventions. They should be ported after a
backend-neutral input texture and coordinate binding path exists in
`tgraphics`.

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

The current `tgraphics` Metal backend still compiles equivalent shader source
from an Objective-C++ string in `tgraphics_metal.mm`; the `.metal` file is
tracked in the target as source evidence, not yet packaged as a runtime
library. The runtime string and tracked `.metal` source both include the
sunflare fragment entry point.

## Next Effects Recommendation

Continue from the opt-in `sunflare` `ShaderFx` path by adding an automated
OpenGL-vs-Metal render comparison for the production effect graph. The next
useful acceptance test is:

- render the same small effect frame through the current OpenGL `ShaderFx`
  path and the new Metal path
- write both outputs plus a diff image
- document the tolerance and any known premultiplication differences
- keep OpenGL `ShaderFx` as the default until preview/export parity is broader

## Validation Run

```sh
bash scripts/graphics_shader_inventory.sh
nix develop path:. --command bash -lc 'cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=ON'
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tnzstdfx tgraphics_metal_probe shaderfx_metal_probe --parallel 3
nix develop path:. --command toonz/build/nix-relwithdebinfo/tnzcore/tgraphics_metal_probe
nix develop path:. --command bash -lc 'OPENTOONZ_GRAPHICS_BACKEND=metal toonz/build/nix-relwithdebinfo/stdfx/shaderfx_metal_probe'
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target OpenToonz --parallel 3
nix develop path:. --command bash -lc 'cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=OFF'
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target OpenToonz --parallel 3
```

Metal probe output:

```text
tgraphics_metal_probe: ok on Apple M1 Max
shaderfx_metal_probe: ok on Apple M1 Max
```

Known validation gap: this checkpoint verifies that the production effect graph
can compile and route to the Metal sunflare path, that `ShaderFx::doCompute(...)`
matches the lower-level Metal helper, and that the Metal helper matches a CPU
formula reference. It does not yet image-diff the production OpenGL `ShaderFx`
output against the production Metal `ShaderFx` output.
