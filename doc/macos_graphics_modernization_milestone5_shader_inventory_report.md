# macOS Graphics Modernization Milestone 5 Shader Inventory

Status: GLSL/OpenGL shader inventory and Metal-port classification added
locally on 2026-05-22.

## Objective

Milestone 5 requires the OpenGL shader/effects surface to be inventoried and
classified before porting effects to Metal. This checkpoint adds a repeatable
inventory command and records the first classification of the current packaged
GLSL shaders.

This does not complete the effects migration. The existing `ShaderFx` path
still compiles GLSL through `QOpenGLShaderProgram`, uses OpenGL transform
feedback for bbox and input-port geometry programs, and renders through
`ShadingContext`/OpenGL FBOs.

## Files Changed

- `scripts/graphics_shader_inventory.sh`
- `doc/macos_graphics_modernization_milestone5_shader_inventory_report.md`

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
- `sunflare.frag`
- `wavy.frag`

These are procedural fragment shaders with no input texture sampling. They are
the smallest useful shader-effect subset to port first because they avoid
input-port texture routing and bbox transform feedback.

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
library.

## Next Effects Recommendation

Port one procedural source effect first, preferably `sunflare` or `wavy`,
behind an opt-in Metal shader-effect path. The minimum useful acceptance test
for that port is:

- render the same small effect frame through the current OpenGL `ShaderFx`
  path and the new Metal path
- write both outputs plus a diff image
- document the tolerance and any known premultiplication differences
- keep OpenGL `ShaderFx` as the default until preview/export parity is broader

## Validation Run

```sh
bash scripts/graphics_shader_inventory.sh
```

Full OpenToonz build validation should still be run after the next source-code
change that consumes this inventory.
