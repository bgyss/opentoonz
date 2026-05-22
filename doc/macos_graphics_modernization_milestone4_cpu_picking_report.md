# macOS Graphics Modernization Milestone 4 CPU Picking Report

Status: partial Milestone 4 completed locally on 2026-05-22.

## Objective

This checkpoint starts reducing runtime dependence on OpenGL selection mode by
promoting an existing CPU picker from Metal-only use to normal Edit Tool use.
The central legacy `SceneViewer::pick()` path remains available for tools that
have not yet been migrated.

## Files Changed

- `toonz/sources/tnztools/edittool.cpp`

## Changes

- Removed the Metal-backend gate from Edit Tool "All" axis picking.
- Edit Tool handle and FX-gadget hover/down picking now uses existing CPU hit
  tests on both OpenGL and Metal backends.
- Removed the now-unneeded `tgraphics.h` include from `edittool.cpp`.

## Inventory

Current source-like inventory after this checkpoint:

```text
OpenToonz graphics API inventory
source_root=toonz/sources

all graphics markers               files=  121 matches=  2874
Qt legacy QGL                      files=    0 matches=     0
Qt QOpenGL                         files=   32 matches=   218
GLU                                files=    5 matches=    53
GLEW or GLUT                       files=   10 matches=    30
fixed-function drawing             files=   85 matches=  2020
fixed-function matrix              files=   56 matches=   458
glDrawPixels                       files=    0 matches=     0
OpenGL selection                   files=    5 matches=    95
```

The OpenGL selection inventory count is unchanged because the central
`SceneViewer::pick()` implementation and legacy `glPushName(...)` draw markers
remain for other tools. This checkpoint reduces runtime use of that path for a
high-value Edit Tool workflow instead of deleting shared selection code.

## Validation Run

Commands run:

```sh
git diff --check
bash scripts/graphics_inventory.sh
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tnztools OpenToonz --parallel 3
nix develop path:. --command cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=ON
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tgraphics_metal_probe OpenToonz --parallel 3
nix develop path:. --command toonz/build/nix-relwithdebinfo/tnzcore/tgraphics_metal_probe
nix develop path:. --command cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=OFF
```

Result: passed. The fallback build recompiled `edittool.cpp`, linked
`tnztools`, and linked `OpenToonz.app`. The Metal-enabled build linked
`OpenToonz.app`, copied the Metal shader source to Resources, and
`tgraphics_metal_probe` reported `ok on Apple M1 Max`. The broader fallback and
Metal rebuilds emitted existing unrelated warnings in image/trop/tool code, but
the changed `edittool.cpp` compiled cleanly.

## Manual Smoke

Manual GUI smoke was not run in this checkpoint. These workflows should be
exercised before merging this milestone:

- Edit Tool with Active Axis set to All.
- Hover and drag center, rotation, scale, scale-XY, and shear handles.
- Hover and drag visible FX gadget handles.
- Verify auto-select still works when clicking away from handles.
- Compare the same interactions with `OPENTOONZ_GRAPHICS_BACKEND=metal` and
  `OPENTOONZ_GRAPHICS_BACKEND=opengl`.

## Remaining Work

- Promote or replace Skeleton Tool CPU picking beyond Metal-only use after
  manual smoke confirms parity.
- Continue migrating tools that still call `SceneViewer::pick()`.
- Remove `glPushName(...)` draw markers only after no active picking path needs
  OpenGL selection names.
- Eventually replace or retire `SceneViewer::pick()` itself.
