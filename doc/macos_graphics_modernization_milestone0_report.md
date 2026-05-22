# macOS Graphics Modernization Milestone 0 Report

Status: completed locally on 2026-05-22.

## Objective

Milestone 0 from `doc/macos_graphics_modernization_goal_prompt.md` creates the
baseline inventory and verification harness needed before OpenGL cleanup or
Metal backend work begins.

## Files Changed

- `scripts/graphics_inventory.sh`
- `doc/how_to_verify_macos_graphics.md`
- `doc/macos_graphics_modernization_goal_prompt.md`

## Graphics Inventory Baseline

Command:

```sh
bash scripts/graphics_inventory.sh
```

Output:

```text
OpenToonz graphics API inventory
source_root=toonz/sources

all graphics markers               files=  135 matches=  2960
Qt legacy QGL                      files=   14 matches=    39
Qt QOpenGL                         files=   29 matches=   197
GLU                                files=   20 matches=   113
GLEW or GLUT                       files=   21 matches=    69
fixed-function drawing             files=   85 matches=  2002
fixed-function matrix              files=   56 matches=   435
glDrawPixels                       files=    8 matches=    17
OpenGL selection                   files=    5 matches=    95
```

Top files by graphics marker matches:

```text
328 toonz/sources/tnztools/edittoolgadgets.cpp
279 toonz/sources/colorfx/strokestyles.cpp
159 toonz/sources/colorfx/regionstyles.cpp
155 toonz/sources/tnztools/edittool.cpp
141 toonz/sources/toonz/sceneviewer.cpp
138 toonz/sources/toonz/viewerdraw.cpp
99 toonz/sources/tnztools/skeletontool.cpp
82 toonz/sources/tnztools/toolutils.cpp
70 toonz/sources/common/tvrender/ttessellator.cpp
70 toonz/sources/common/tgl/tgl.cpp
62 toonz/sources/common/tvrender/tsimplecolorstyles.cpp
55 toonz/sources/toonzlib/stagevisitor.cpp
53 toonz/sources/toonzqt/styleeditor.cpp
53 toonz/sources/toonz/imageviewer.cpp
52 toonz/sources/tnzext/meshutils.cpp
49 toonz/sources/common/tvrender/tglregions.cpp
48 toonz/sources/toonzlib/strokegenerator.cpp
47 toonz/sources/stdfx/shadingcontext.cpp
46 toonz/sources/tnztools/plastictool.cpp
40 toonz/sources/tnzext/OverallDesigner.cpp
```

## Build and Warning Baseline

Configure command:

```sh
nix develop path:. --command bash -lc 'bash scripts/nix/prepare-tiff.sh && cmake -S toonz/sources --preset nix-relwithdebinfo'
```

Result: passed.

Clean build command:

```sh
nix develop path:. --command bash -lc 'cmake --build toonz/build/nix-relwithdebinfo --clean-first --parallel 3 > /private/tmp/opentoonz-milestone0-clean-build.log 2>&1'
```

Result: passed.

Warning counts:

```text
total warnings: 139
Apple OpenGL framework deprecation warnings: 0
QMutex recursive deprecation warnings: 6
```

Top warning categories:

```text
18 abstract class is marked 'final'
12 'HUnlock' is deprecated: first deprecated in macOS 10.8
12 'DisposeHandle' is deprecated: first deprecated in macOS 10.8
8 'NewHandle' is deprecated: first deprecated in macOS 10.8
6 expression with side effects will be evaluated despite being used as an operand to 'typeid'
6 'QMutex' is deprecated: Use QRecursiveMutex instead of a recursive QMutex
5 implicit conversion from 'type' (aka 'unsigned long') to 'double' changes value from 18446744073709551615 to 18446744073709551616
4 result of comparison of constant 100 with expression of type 'Handle' is always true
4 implicit conversion from 'int' to 'Channel' (aka 'unsigned char') changes value from 52428 to 204
3 first argument in call to 'memcpy' is a pointer to non-trivially copyable type 'TPixelRGBM32'
```

## Verification Harness

`doc/how_to_verify_macos_graphics.md` now documents:

- inventory command and expected categories
- clean warning-count command
- golden-scene requirements
- OpenGL baseline capture workflow
- future Metal comparison capture workflow
- manual smoke matrix for OpenGL and Metal
- required validation commands
- milestone handoff checklist

No screenshot or image-diff script was added in this milestone because the repo
does not yet contain a documented golden-scene fixture set or a Metal backend to
compare against. The verification document defines the exact data that a future
script must consume and report.

## Validation Run

Commands run:

```sh
bash scripts/graphics_inventory.sh
bash -n scripts/graphics_inventory.sh
git diff --check
rg -n "[^\\x00-\\x7F]" scripts/graphics_inventory.sh doc/how_to_verify_macos_graphics.md doc/macos_graphics_modernization_goal_prompt.md
nix develop path:. --command bash -lc 'bash scripts/nix/prepare-tiff.sh && cmake -S toonz/sources --preset nix-relwithdebinfo'
nix develop path:. --command bash -lc 'cmake --build toonz/build/nix-relwithdebinfo --parallel 3 > /private/tmp/opentoonz-milestone0-build.log 2>&1'
nix develop path:. --command bash -lc 'cmake --build toonz/build/nix-relwithdebinfo --clean-first --parallel 3 > /private/tmp/opentoonz-milestone0-clean-build.log 2>&1'
```

All commands passed. The non-ASCII scan returned no matches.

## Known Gaps

- Golden scenes still need to be selected or created.
- Screenshot capture and image-diff automation still need fixture paths and a
  stable launch/capture harness.
- No rendering behavior changed in this milestone, so no manual graphics smoke
  matrix was required beyond the successful build.

## Next Milestone Recommendation

Proceed to Milestone 1:

1. Replace `QGLFormat` setup with `QSurfaceFormat`.
2. Replace `QGLContext` and `QGLPixelBuffer` usage with `QOpenGLContext`,
   `QOpenGLFramebufferObject`, or `QOffscreenSurface`.
3. Replace `QGLWidget::convertToGLFormat` in tool code with explicit `QImage`
   conversion helpers.
4. Isolate GLU projection and tessellation dependencies behind local helpers.
