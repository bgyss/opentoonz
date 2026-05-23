# macOS Graphics Modernization Current Handoff

Status: refreshed local evidence from the Codex worktree on 2026-05-23.

This handoff summarizes the current state against
`doc/macos_graphics_modernization_goal_prompt.md`. The repository already
contains the inventory harness, `tgraphics` abstraction, opt-in Metal backend,
Metal probe targets, shader-effect probes, macOS CI matrix wiring, and
milestone reports through the CI checkpoint.

## Current State

- OpenGL remains the default backend.
- Metal is opt-in with `OPENTOONZ_GRAPHICS_BACKEND=metal`.
- `WITH_GRAPHICS_METAL=ON` builds the Metal implementation and probe targets on
  macOS.
- `QGL*` usage is gone from source-like inventory.
- `glDrawPixels` usage is gone from source-like inventory.
- Remaining OpenGL selection usage is isolated to the legacy SceneViewer picking
  path and Skeleton Tool 3D fallback markers.
- Metal shader source is copied into the app bundle. A compiled `.metallib` is
  packaged only when the local Metal toolchain provides `metal` and `metallib`.
- `scripts/macos/graphics-app-smoke.sh` provides a bounded app-bundle launch
  smoke for `OPENTOONZ_GRAPHICS_BACKEND=opengl` and `metal`, with logs and
  optional screenshots saved outside the repository.

## Fresh Validation

Commands run from the repository root:

```sh
bash scripts/graphics_inventory.sh
bash -n scripts/graphics_inventory.sh scripts/graphics_shader_inventory.sh scripts/graphics_shaderfx_compare.sh scripts/macos/ci-build-summary.sh scripts/macos/verify-metal-resources.sh
git diff --check
nix develop path:. --command bash -lc 'bash scripts/nix/prepare-tiff.sh && cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=ON'
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tgraphics_metal_probe OpenToonz --parallel 3
nix develop path:. --command toonz/build/nix-relwithdebinfo/tnzcore/tgraphics_metal_probe
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target shaderfx_metal_probe --parallel 3
nix develop path:. --command bash scripts/graphics_shaderfx_compare.sh /private/tmp/opentoonz-shaderfx-compare-4146
bash scripts/macos/verify-metal-resources.sh toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app
bash -n scripts/macos/graphics-app-smoke.sh
```

Observed results:

```text
tgraphics_metal_probe: ok on Apple M1 Max
graphics_shaderfx_compare: ok
Metal shader source resource present; metallib build skipped because the Metal toolchain is unavailable
```

The fresh Metal-enabled build linked:

```text
toonz/OpenToonz.app/Contents/MacOS/OpenToonz
tnzcore/tgraphics_metal_probe
stdfx/shaderfx_metal_probe
```

## Fresh Graphics Inventory

```text
all graphics markers               files=  106 matches=  2184
Qt legacy QGL                      files=    0 matches=     0
Qt QOpenGL                         files=   30 matches=   211
GLU                                files=    4 matches=    54
GLEW or GLUT                       files=   10 matches=    30
fixed-function drawing             files=   63 matches=  1411
fixed-function matrix              files=   55 matches=   454
glDrawPixels                       files=    0 matches=     0
OpenGL selection                   files=    3 matches=    24
```

## Remaining Acceptance Gaps

- Metal is not ready to become the default macOS backend.
- Full GUI smoke still needs manual or scripted evidence for viewer navigation,
  drawing/editing tools, style editor, preview/export, and representative scene
  files under `OPENTOONZ_GRAPHICS_BACKEND=metal`.
- The bounded app launch smoke harness exists, but it still needs to be run and
  reviewed on a local interactive macOS desktop for screenshot evidence.
- Golden-scene image comparison is still incomplete for full application
  workflows, even though command-line Metal/OpenGL probes pass.
- The legacy SceneViewer `GL_SELECT` path and Skeleton Tool 3D selection markers
  remain compatibility code.
- Apple-hosted CI evidence should be refreshed after any further parity changes.
- `.metallib` packaging was not proven in this local environment because the
  installed Xcode lacks the Metal command-line toolchain.

## Next Recommendation

Continue with the smallest user-visible parity gap: replace the remaining
SceneViewer/Skeleton Tool OpenGL selection fallback with CPU or ID-buffer hit
testing, then extend `scripts/macos/graphics-app-smoke.sh` into a scene-driving
smoke that opens baseline scenes under both `OPENTOONZ_GRAPHICS_BACKEND=opengl`
and `OPENTOONZ_GRAPHICS_BACKEND=metal` and stores comparable screenshots.
