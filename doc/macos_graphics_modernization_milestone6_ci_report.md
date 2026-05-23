# macOS Graphics Modernization Milestone 6 CI Checkpoint

Status: first macOS arm64 CI gate split for OpenGL-fallback and
Metal-enabled builds added locally on 2026-05-22.

## Objective

This checkpoint starts Milestone 6 by making the macOS GitHub Actions workflow
collect the evidence needed for a future Metal default-backend decision. The
workflow now builds both the OpenGL-fallback configuration and the
Metal-enabled configuration on Apple Silicon, records build timing and warning
counts, preserves ccache summaries, runs Metal graphics probes for the
Metal-enabled leg, bundles the app, verifies arm64 Mach-O contents, and checks
that Metal shader resources are present in the app bundle.

This is not the full Milestone 6 completion. The workflow changes still need a
live GitHub Actions run on the fork before the CI gate can be treated as proven,
and the default backend remains OpenGL while viewer, editing, preview/export,
saved-scene input ShaderFx, and broader offscreen parity gaps remain open.

## Files Changed

- `.github/workflows/workflow_macos.yml`
- `scripts/macos/ci-build-summary.sh`
- `doc/macos_graphics_modernization_milestone6_ci_report.md`

## Changes

- Converted the macOS workflow into an Apple Silicon matrix with:
  - `opengl-fallback`, configured with `-DWITH_GRAPHICS_METAL=OFF`
  - `metal`, configured with `-DWITH_GRAPHICS_METAL=ON`
- Added `scripts/macos/ci-build-summary.sh`, a reusable CI wrapper that:
  - prepares bundled libtiff
  - configures the existing Nix `nix-relwithdebinfo` preset with optional
    CMake arguments
  - builds OpenToonz through the Nix shell
  - records elapsed build seconds
  - counts total warning lines
  - counts Apple OpenGL deprecation warning lines
  - counts Qt `QGL*` warning lines
  - counts deprecated `QOpenGL*` warning lines
  - captures `WITH_GRAPHICS_METAL` from `CMakeCache.txt`
  - captures `ccache --show-stats`
  - writes a Markdown summary to `$GITHUB_STEP_SUMMARY` when running in GitHub
    Actions
- Updated macOS ccache keys to include the matrix graphics mode while still
  allowing broad `macos-arm64-` fallback restores.
- Added CI graphics inventory output with `scripts/graphics_inventory.sh`.
- Added Metal CI probes for the Metal-enabled leg:
  - `tgraphics_metal_probe`
  - `scripts/graphics_shaderfx_compare.sh`
- Updated `scripts/graphics_shaderfx_compare.sh` after fork CI exposed
  Apple-Paravirtual-device differences in the `SHADER_caustics` procedural
  noise field. CI still renders and stores OpenGL/Metal caustics artifacts, but
  caustics defaults to Metal smoke validation instead of an OpenGL-vs-Metal
  parity gate. Set `SHADERFX_CAUSTICS_COMPARE=1` to re-enable caustics parity
  comparison when investigating that shader on a specific device. The other
  no-input procedural shaders keep the parity comparison gate.
- Added Metal app-bundle resource checks for:
  - `scripts/macos/verify-metal-resources.sh`, which requires
    `Contents/Resources/tgraphics_metal_shaders.metal` and requires
    `Contents/Resources/tgraphics_metal_shaders.metallib` when the Xcode Metal
    toolchain is usable
  - `tnzcore/tgraphics_metal_probe`
  - `stdfx/shaderfx_metal_probe`
- Added upload of per-leg CI build-summary artifacts.
- Kept release signing and notarization scoped to the `opengl-fallback` leg so
  the release path does not notarize two DMGs until maintainers explicitly
  choose a Metal release artifact policy.

## Milestone 6 Coverage

Covered by this checkpoint:

- OpenGL-fallback macOS arm64 build coverage.
- Metal-enabled macOS arm64 build coverage.
- App bundle packaging coverage for both matrix legs.
- arm64 Mach-O validation for both matrix legs.
- Graphics inventory output.
- Warning count summary.
- ccache summary.
- Metal backend smoke probes for the Metal-enabled leg.
- Metal shader resource presence in the app bundle.

Still open:

- Live GitHub Actions run evidence from the fork for the final smoke-only
  caustics policy.
- Failed-log triage from `gh run view --log-failed` if the current matrix
  exposes additional runner-only issues.
- Build-time comparison against the pre-matrix single-leg workflow.
- A documented default-backend decision after the remaining parity gaps close.
- Headless or scripted GUI smoke for actual app launch, viewer interaction,
  preview/export, and editing workflows.

## Validation Run

Local static validation:

```sh
bash -n scripts/macos/ci-build-summary.sh
git diff --check
```

Local Metal build/package validation:

```sh
OPENTOONZ_CI_BUILD_LABEL=macos-arm64-metal-local \
OPENTOONZ_CMAKE_EXTRA_ARGS=-DWITH_GRAPHICS_METAL=ON \
OPENTOONZ_BUILD_PARALLEL=3 \
scripts/macos/ci-build-summary.sh

nix develop path:. --command toonz/build/nix-relwithdebinfo/tnzcore/tgraphics_metal_probe
nix develop path:. --command bash scripts/graphics_shaderfx_compare.sh /private/tmp/opentoonz-shaderfx-compare-ci
nix develop path:. --command bash scripts/macos/package-nix-app.sh
nix develop path:. --command bash scripts/macos/assert-arm64-bundle.sh
test -f toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app/Contents/Resources/tgraphics_metal_shaders.metal
```

Observed local Metal build summary:

```text
status: 0
elapsed_seconds: 14
WITH_GRAPHICS_METAL: ON
total_warnings: 2
apple_opengl_deprecation_warnings: 0
qt_qgl_warning_lines: 0
qt_qopengl_deprecation_warning_lines: 0
ccache hit rate: 21378 / 24577 (86.98%)
```

Observed local Metal probe/package output:

```text
tgraphics_metal_probe: ok on Apple M1 Max
graphics_shaderfx_compare: ok
Packaged .../toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app
Checked 281 Mach-O files for arm64.
```

Local OpenGL-fallback restore validation:

```sh
nix develop path:. --command bash -lc 'cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=OFF && cmake --build toonz/build/nix-relwithdebinfo --target OpenToonz --parallel 3'
rg -n "^WITH_GRAPHICS_METAL:BOOL=" toonz/build/nix-relwithdebinfo/CMakeCache.txt
```

Observed result:

```text
WITH_GRAPHICS_METAL:BOOL=OFF
OpenToonz target rebuilt successfully.
```

Graphics inventory after this checkpoint:

```text
all graphics markers               files=  121 matches=  2865
Qt legacy QGL                      files=    0 matches=     0
Qt QOpenGL                         files=   32 matches=   218
GLU                                files=    5 matches=    53
GLEW or GLUT                       files=   10 matches=    30
fixed-function drawing             files=   85 matches=  2009
fixed-function matrix              files=   56 matches=   450
glDrawPixels                       files=    4 matches=    10
OpenGL selection                   files=    5 matches=    95
```

GitHub Actions validation:

```sh
gh workflow run workflow_macos.yml
gh run watch <run-id>
gh run view <run-id> --log-failed
```

If `gh` authentication is stale:

```sh
gh auth refresh -h github.com -s repo -s workflow
gh auth status
```

## Known Gaps

- The Metal-enabled CI leg proves the build and command-line probes, not full
  GUI parity.
- `SHADER_caustics` is currently a known visual-parity gap on GitHub-hosted
  Apple Silicon runners. The Metal helper renders non-empty caustics output,
  but its procedural `fract(sin(...))` noise field can diverge sharply from the
  OpenGL baseline on Apple Paravirtual hardware. CI treats it as a smoke
  artifact until the shader is rewritten with a cross-backend-stable noise
  source or a shader-specific acceptance metric.
- Compiled `.metallib` packaging is now wired into CMake when `metal` and
  `metallib` are available, but this local checkout still cannot prove that
  path because the installed Xcode is missing the Metal Toolchain component.
- Saved/reloaded input-texture ShaderFx fixtures for `HSLBlendGPU` and
  `radialblurGPU` are explicitly guarded because the current render-worker path
  is unstable.
- Release signing still follows the OpenGL-fallback artifact. This is
  deliberate until maintainers decide whether release DMGs should be
  Metal-enabled before Metal becomes the default backend.

## Warning Cleanup Follow-up

Additional macOS warning-noise cleanup was added locally on 2026-05-22 after
the first matrix checkpoint. This is separate from the Metal backend work, but
it directly supports the Milestone 6 warning-count gate and the original macOS
arm64 build-time investigation by removing repeated deprecation warnings from
source files that rebuild frequently.

Cleaned warning categories:

- Deprecated `sprintf` calls in `toonz/sources/toonz/crashhandler.cpp` now use
  bounded `snprintf`.
- Deprecated Qt recursive mutex construction in sound, palette, cache-resource,
  and passive-cache code now uses `QRecursiveMutex` directly for the Qt 5.15
  build.
- Deprecated macOS Carbon Trash-folder lookup in
  `toonz/sources/common/tsystem/tsystempd.cpp` now uses the current user's
  `$HOME/.Trash` path, preserving the existing permanent-delete fallback if the
  Trash path cannot be resolved.
- The invalid wide-string plus integer expression in
  `toonz/sources/common/tvrender/tfont_qt.cpp` now formats the `QImage` format
  value explicitly.
- Potentially evaluated `typeid` expressions in palette/style-editor code now
  operate on stored raw pointers.

Local warning-cleanup validation:

```sh
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tnzcore sound toonzlib OpenToonz --parallel 3
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tnzcore tnzbase sound toonzqt OpenToonz --parallel 3
OPENTOONZ_CI_BUILD_LABEL=macos-arm64-warning-cleanup-local \
OPENTOONZ_BUILD_PARALLEL=3 \
scripts/macos/ci-build-summary.sh
git diff --check
bash scripts/graphics_inventory.sh
```

Observed local warning-cleanup summary:

```text
status: 0
elapsed_seconds: 13
WITH_GRAPHICS_METAL: OFF
total_warnings: 0
apple_opengl_deprecation_warnings: 0
qt_qgl_warning_lines: 0
qt_qopengl_deprecation_warning_lines: 0
ccache hit rate: 21522 / 25110 (85.71%)
```

This summary was produced from an incremental local build, so it should be
treated as evidence that the cleaned files are no longer producing warnings in
the current build tree, not as a fresh full-build warning baseline. A broader
rebuild still surfaced unrelated warning families such as non-trivial `memcpy`
pixel copies, abstract-final class declarations, and return-type cleanup in
tool/editor code; those are outside this scoped macOS deprecation cleanup.

## Next Recommendation

Run the new `workflow_macos.yml` matrix on the fork, record the run IDs and
timing/warning summaries, then use any failures to tighten the macOS CI gate.
After CI is repeatable, continue Milestone 5 parity work on preview/export,
saved-scene input ShaderFx, and broader offscreen rendering before revisiting
the default-backend decision.
