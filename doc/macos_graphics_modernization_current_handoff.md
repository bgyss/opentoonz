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
  optional screenshots saved outside the repository. The script treats early
  exits and fatal Qt/dyld startup diagnostics as failures, makes enabled
  screenshot capture strict, writes per-backend screenshot metadata, and waits
  between backend launches so app shutdown state does not bleed into the next
  smoke. Set `OPENTOONZ_GRAPHICS_SMOKE_SCENE` to pass a committed fixture scene
  to the app for backend launch-plus-scene-load smoke coverage.
- `scripts/verify_metal_probe_images.sh` turns the `tgraphics_metal_probe`
  image output into a pass/fail artifact check for Metal/OpenGL/diff PNG
  triplets. It removes stale probe PNGs before each run, checks triplet counts,
  and records image hashes when `shasum` is available.
- `scripts/verify_graphics_app_smoke_artifacts.sh` validates packaged app smoke
  artifacts for backend metadata, startup failure markers, screenshot metadata,
  nonblank PNG screenshot content, and consistent scene metadata across
  backends.
- `scripts/graphics_app_smoke_manifest.sh` runs the packaged app smoke against
  each committed `.tnz` scene row in the golden-scene manifest and verifies the
  artifacts for each scene/backend pair.
- `scripts/verify_png_nonblank.py` is a small standard-library PNG decoder used
  by the app-smoke artifact verifier to reject single-color screenshots.
- `SceneViewer::pick()` now refuses the legacy OpenGL selection path when
  `OPENTOONZ_GRAPHICS_BACKEND=metal` is requested. The remaining `GL_SELECT`
  implementation is still present for OpenGL compatibility paths.
- `scripts/graphics_modernization_lint.sh` and
  `scripts/verify_golden_scene_manifest.sh` enforce the current graphics
  modernization invariants and golden-scene coverage manifest in the macOS CI
  workflow. The graphics lint also runs the sample data verifier when the
  committed sample pack is present, and now enforces that Edit Tool and
  Skeleton Tool 2D picking stay on their CPU picking paths instead of regressing
  to the generic OpenGL selection path.
- `scripts/verify_sample_data.sh` validates the committed `doc/sample_data`
  pack used by the golden scene manifest: license, key scene files,
  representative raster/vector/material assets, and `$scenefolder`
  relocatability with resolved in-repository scene dependencies.
- The macOS Metal CI leg runs `scripts/verify_metal_probe_images.sh` and uploads
  the generated Metal/OpenGL/diff PNGs plus shader-effect comparison artifacts.
- `scripts/verify_shaderfx_scene_fixtures.sh` checks that the generated
  shader-effect scene fixtures and saved-scene render outputs exist and are
  non-empty; the macOS Metal CI leg runs it after shader-effect comparison.
- `doc/how_to_build_macosx.md` now documents user-facing backend selection and
  troubleshooting for OpenGL, Metal, direct-Metal smoke mode, packaging-related
  launch failures, shader resource fallback, and Metal-to-OpenGL fallback.
- `doc/macos_graphics_golden_scenes.tsv` is a checked golden-scene coverage
  manifest. It records the generated shader-effect scene coverage and keeps the
  remaining required scene fixture categories explicit until committed fixtures
  are available. `scripts/verify_golden_scene_manifest.sh --require-complete`
  is the strict gate for any future Metal-default decision.
- `doc/sample_data` has been added as committed sample application data under
  the upstream CC BY-NC 4.0 license. The golden-scene manifest now uses
  `dwanko_run.tnz`, `cleanup.tnz`, `tga_paint.tnz`, and sample vector material
  for real application-behavior coverage where applicable. The sample scenes
  were inspected for the remaining strict fixture gaps; they do not serialize
  mesh/skeleton coverage, onion-skin state, or nested sub-xsheet coverage, so
  those rows remain explicit `status=required` blockers.

## Fresh Validation

Commands run from the repository root:

```sh
bash scripts/graphics_inventory.sh
bash scripts/verify_sample_data.sh
bash scripts/graphics_modernization_lint.sh
bash scripts/verify_golden_scene_manifest.sh
! bash scripts/verify_golden_scene_manifest.sh --require-complete
bash scripts/verify_shaderfx_scene_fixtures.sh /private/tmp/opentoonz-shaderfx-compare-4146
bash -n scripts/graphics_inventory.sh scripts/graphics_modernization_lint.sh scripts/graphics_shader_inventory.sh scripts/graphics_shaderfx_compare.sh scripts/verify_golden_scene_manifest.sh scripts/verify_metal_probe_images.sh scripts/verify_sample_data.sh scripts/verify_shaderfx_scene_fixtures.sh scripts/macos/ci-build-summary.sh scripts/macos/verify-metal-resources.sh
! sed -n '203,267p' doc/how_to_build_macosx.md | rg -n "/Users/|/home/|~|\\.codex|briangyss|/Applications|/private/tmp"
git diff --check
nix develop path:. --command bash -lc 'bash scripts/nix/prepare-tiff.sh && cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=ON'
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tgraphics_metal_probe OpenToonz --parallel 3
nix develop path:. --command toonz/build/nix-relwithdebinfo/tnzcore/tgraphics_metal_probe
nix develop path:. --command bash scripts/verify_metal_probe_images.sh /private/tmp/opentoonz-metal-probe-images-4146-verified
nix develop path:. --command bash scripts/verify_metal_probe_images.sh /private/tmp/opentoonz-metal-probe-images-4146-hardened
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target shaderfx_metal_probe --parallel 3
nix develop path:. --command bash scripts/graphics_shaderfx_compare.sh /private/tmp/opentoonz-shaderfx-compare-4146
bash scripts/macos/verify-metal-resources.sh toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app
bash -n scripts/macos/graphics-app-smoke.sh
OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/dwanko_run.tnz OPENTOONZ_GRAPHICS_SMOKE_BACKENDS=opengl OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 OPENTOONZ_GRAPHICS_SMOKE_SECONDS=0 bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-argcheck
nix develop path:. --command bash -lc 'OPENTOONZ_ADHOC_SIGN=0 scripts/macos/package-nix-app.sh'
bash scripts/macos/assert-arm64-bundle.sh toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app
OPENTOONZ_GRAPHICS_SMOKE_SECONDS=5 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=4 OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-4146-combined
OPENTOONZ_GRAPHICS_SMOKE_SECONDS=5 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=4 OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=1 bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-4146-screenshots
OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/dwanko_run.tnz OPENTOONZ_GRAPHICS_SMOKE_BACKENDS="opengl metal" OPENTOONZ_GRAPHICS_SMOKE_SECONDS=5 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=2 OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-sample-scene-4146-bundled
OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/dwanko_run.tnz OPENTOONZ_GRAPHICS_SMOKE_BACKENDS="opengl metal" OPENTOONZ_GRAPHICS_SMOKE_SECONDS=5 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=2 OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=1 bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-sample-scene-4146-screenshots
scripts/verify_png_nonblank.py /private/tmp/opentoonz-graphics-app-smoke-sample-scene-4146-screenshots/opengl/screenshot.png /private/tmp/opentoonz-graphics-app-smoke-sample-scene-4146-screenshots/metal/screenshot.png
bash scripts/verify_graphics_app_smoke_artifacts.sh /private/tmp/opentoonz-graphics-app-smoke-sample-scene-4146-screenshots
OPENTOONZ_GRAPHICS_SMOKE_BACKENDS="opengl metal" OPENTOONZ_GRAPHICS_SMOKE_SECONDS=5 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=2 OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 bash scripts/graphics_app_smoke_manifest.sh doc/macos_graphics_golden_scenes.tsv /private/tmp/opentoonz-graphics-app-smoke-manifest-4146
OPENTOONZ_CI_BUILD_LABEL=macos-arm64-4146-current OPENTOONZ_CMAKE_EXTRA_ARGS=-DWITH_GRAPHICS_METAL=ON OPENTOONZ_BUILD_PARALLEL=3 scripts/macos/ci-build-summary.sh
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target OpenToonz --parallel 3
```

Observed results:

```text
tgraphics_metal_probe: ok on Apple M1 Max
verify-metal-probe-images: cases=18 artifacts=/private/tmp/opentoonz-metal-probe-images-4146-verified
verify-metal-probe-images: cases=18 artifacts=/private/tmp/opentoonz-metal-probe-images-4146-hardened
probe image counts: total_png=54 metal=18 opengl=18 diff=18; summary.txt includes SHA-256 hashes.
graphics-modernization-lint: ok
verify-sample-data: ok
verify-golden-scene-manifest: ok
strict golden-scene manifest check currently fails as expected with 3 required fixture rows remaining.
sample data: 40 files, 45M under doc/sample_data; committed scene dependencies resolve through $scenefolder.
verify-shaderfx-scene-fixtures: scenes=4 pams=4 artifacts=/private/tmp/opentoonz-shaderfx-compare-4146
privacy scan: no personal/transient paths in the new backend-selection doc section.
graphics_shaderfx_compare: ok
macOS workflow now runs verify_metal_probe_images.sh and uploads Metal graphics probe artifacts.
macOS workflow now runs verify_golden_scene_manifest.sh in the graphics invariant step.
Metal shader source resource present; metallib build skipped because the Metal toolchain is unavailable
Checked 281 Mach-O files for arm64.
graphics-app-smoke: backend=opengl passed
graphics-app-smoke: backend=metal passed
graphics-app-smoke scene argument check: backend=opengl passed with OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/dwanko_run.tnz and screenshot capture disabled.
graphics-app-smoke sample scene: packaged app loaded doc/sample_data/dwanko_run.tnz under opengl and metal with screenshot capture disabled.
graphics-app-smoke sample scene screenshots: packaged app loaded doc/sample_data/dwanko_run.tnz under opengl and metal with 3456 x 2234 PNG screenshots.
verify-png-nonblank: ok for opengl and metal sample-scene screenshots.
verify-graphics-app-smoke-artifacts: ok backends=opengl metal artifacts=/private/tmp/opentoonz-graphics-app-smoke-sample-scene-4146-screenshots
graphics-app-smoke-manifest: ok scenes=2 artifacts=/private/tmp/opentoonz-graphics-app-smoke-manifest-4146
graphics-app-smoke: artifacts: /private/tmp/opentoonz-graphics-app-smoke-4146-combined
graphics-app-smoke: artifacts: /private/tmp/opentoonz-graphics-app-smoke-4146-screenshots
graphics-app-smoke: artifacts: /private/tmp/opentoonz-graphics-app-smoke-sample-scene-4146-bundled
opengl screenshot.png: PNG image data, 3456 x 2234, 8-bit/color RGBA, non-interlaced
metal screenshot.png: PNG image data, 3456 x 2234, 8-bit/color RGBA, non-interlaced
macos-arm64-4146-current build summary: status=0 elapsed_seconds=16 WITH_GRAPHICS_METAL=ON total_warnings=0 apple_opengl_deprecation_warnings=0 qt_qgl_warning_lines=0 qt_qopengl_deprecation_warning_lines=0
ccache: hits=30542/36876 (82.82%)
SceneViewer Metal picking guard build: OpenToonz target linked successfully.
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
- The bounded app launch smoke now passes locally for OpenGL and Metal after
  packaging with screenshot artifacts captured for both backends.
- Golden-scene image comparison is still incomplete for full application
  workflows, even though command-line Metal/OpenGL probes pass. The manifest now
  uses committed sample scenes where available and lists each remaining missing
  committed fixture category explicitly.
- The legacy SceneViewer `GL_SELECT` implementation and Skeleton Tool 3D
  selection markers remain compatibility code, but `SceneViewer::pick()` no
  longer enters that path when the Metal backend is requested.
- Apple-hosted CI evidence should be refreshed after any further parity changes.
- `.metallib` packaging was not proven in this local environment because the
  installed Xcode lacks the Metal command-line toolchain.
- Full packaging succeeded in this run with `OPENTOONZ_ADHOC_SIGN=0`. A normal
  signing-enabled packaging run should still be used before release handoff.
- Backend selection and troubleshooting are now documented, but Metal remains
  explicitly experimental.
- A follow-up attempt to rerun `scripts/macos/package-nix-app.sh` for
  scene-load smoke validation exposed a long-running post-`macdeployqt`
  packaging step. `scripts/macos/package-nix-app.sh` now has a bounded
  dependency-copy pass guard and progress logging. With that guard in place,
  packaging completed with `OPENTOONZ_ADHOC_SIGN=0`, and the committed sample
  scene loaded under both OpenGL and Metal in the bounded app smoke with
  screenshots disabled.

## Next Recommendation

Continue with the smallest user-visible parity gap: replace the remaining
SceneViewer/Skeleton Tool OpenGL selection fallback with CPU or ID-buffer hit
testing, then extend `scripts/macos/graphics-app-smoke.sh` into a scene-driving
smoke that opens baseline scenes under both `OPENTOONZ_GRAPHICS_BACKEND=opengl`
and `OPENTOONZ_GRAPHICS_BACKEND=metal` and stores comparable screenshots.
