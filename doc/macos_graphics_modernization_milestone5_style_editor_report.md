# macOS Graphics Modernization Milestone 5 Style Editor Checkpoint

Status: first contained style-editor rendering migration completed locally on
2026-05-22.

## Objective

This checkpoint starts Milestone 5 by removing immediate-mode OpenGL drawing
from the Style Editor's `HexagonalColorWheel`. The wheel is still hosted in the
existing `GLWidgetForHighDpi` widget so color-calibration and high-DPI behavior
remain compatible with the surrounding Qt 5 UI, but the normal wheel content is
now generated as a CPU `QImage` and painted with `QPainter` instead of emitting
fixed-function `glBegin`, matrix-stack, viewport, and clear commands.

This is not the full Milestone 5 completion. Other style-editor, offscreen
rendering, preview/export, and shader-effect paths still use OpenGL or
`QOpenGLFramebufferObject` directly and remain follow-up work.

## Files Changed

- `toonz/sources/include/toonzqt/styleeditor.h`
- `toonz/sources/toonzqt/styleeditor.cpp`

## Changes

- Replaced the hexagonal color wheel's direct fixed-function OpenGL draw path
  with a CPU raster generator:
  - wheel pixels are computed from the same hue/saturation geometry used by
    the existing mouse-hit logic
  - triangle pixels are computed from the same saturation/value geometry used by
    the existing mouse-hit logic
  - current-color markers are drawn with `QPainter`
- Kept the existing `QOpenGLFramebufferObject` route available for LUT color
  calibration, but draw the CPU-generated wheel into the FBO with
  `QOpenGLPaintDevice` before handing it to `LutCalibrator`.
- Removed direct style-editor calls to:
  - `glClearColor`
  - `glClear`
  - `glViewport`
  - `glMatrixMode`
  - `glLoadIdentity`
  - `glOrtho`
  - `glPushMatrix` / `glPopMatrix`
  - `glTranslatef` / `glRotatef`
  - `glBegin` / `glEnd`
  - `glColor3f`
  - `glVertex2f`

## Inventory Impact

Before this checkpoint, after the previous Metal picking checkpoint:

```text
all graphics markers               files=  121 matches=  2913
fixed-function drawing             files=   86 matches=  2049
fixed-function matrix              files=   57 matches=   460
```

After this checkpoint:

```text
all graphics markers               files=  121 matches=  2865
fixed-function drawing             files=   85 matches=  2009
fixed-function matrix              files=   56 matches=   450
```

`styleeditor.cpp` no longer appears in the top graphics-marker files and no
longer contains direct fixed-function OpenGL drawing calls. `QOpenGL*` counts
increase slightly because the LUT calibration path now uses
`QOpenGLPaintDevice` to bridge the CPU image into the existing calibration FBO.

## Validation Run

```sh
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target OpenToonz --parallel 3
nix develop path:. --command bash -lc 'cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=ON'
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tgraphics_metal_probe OpenToonz --parallel 3
nix develop path:. --command toonz/build/nix-relwithdebinfo/tnzcore/tgraphics_metal_probe
nix develop path:. --command bash -lc 'cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=OFF'
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target OpenToonz --parallel 3
bash scripts/graphics_inventory.sh
git diff --check
```

Metal probe output:

```text
tgraphics_metal_probe: ok on Apple M1 Max
```

## Known Gaps

- The Style Editor still inherits from `GLWidgetForHighDpi`; this checkpoint
  removes immediate-mode drawing from the color wheel but does not yet convert
  the widget to a fully non-OpenGL Qt widget.
- LUT color calibration still depends on `LutCalibrator`, GLSL, and OpenGL FBO
  plumbing.
- Manual visual smoke is still needed for the Style Editor color wheel under
  normal and LUT-calibrated configurations.
- Preview/export, shader effects, and broader offscreen render targets remain
  Milestone 5 work.

## Next Recommendation

Continue Milestone 5 by moving a second isolated secondary surface away from
direct OpenGL, or by introducing a Metal/CPU-backed offscreen render target
adapter for one `qtofflinegl` call site with image-diff validation.
