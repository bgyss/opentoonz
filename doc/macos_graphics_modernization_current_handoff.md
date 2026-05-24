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
  screenshot capture strict, writes per-backend screenshot metadata, asks the
  app bundle to quit through Apple Events before falling back to process
  signals, and waits between backend launches so app shutdown state does not
  bleed into the next smoke. Set `OPENTOONZ_GRAPHICS_SMOKE_SCENE` to pass a
  committed fixture scene to the app for backend launch-plus-scene-load smoke
  coverage. Set `OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=basic-viewer` to activate
  the app and send a small playback/scrub/zoom event sequence before capture;
  this action mode is bounded and records macOS Automation/Accessibility
  failures in `actions.txt`. Set `OPENTOONZ_GRAPHICS_SMOKE_BUNDLE_ID` only when
  testing a bundle with a nonstandard identifier. The smoke enables
  `OPENTOONZ_GRAPHICS_METAL_FRAME_DIAGNOSTICS=1`, and the artifact verifier's
  stricter `--require-direct-metal-frame` gate requires a scene-viewer log line
  proving `direct_content=1` and `compatibility_snapshot=0` for the Metal
  backend. When
  `scripts/macos/verify-bundled-qt-runtime.sh` is present, the smoke script runs
  it before launching OpenToonz, writes the result to `preflight.txt`, and the
  artifact verifier requires that metadata to show `verify-bundled-qt-runtime:
  ok`. This makes stale bundles fail before producing misleading Qt/Cocoa
  startup crash logs.
- `scripts/verify_metal_probe_images.sh` turns the `tgraphics_metal_probe`
  image output into a pass/fail artifact check for Metal/OpenGL/diff PNG
  triplets. It removes stale probe PNGs before each run, checks triplet counts,
  requires the editing tool-overlay case, the transparent style-icon offscreen
  case, and the legacy offline raster-placement case, and records image hashes
  when `shasum` is available.
- `scripts/verify_macos_offscreen_style_probes.sh` runs the existing
  `tofflinegl_probe` under OpenGL and Metal, then runs the
  `styleeditor_colorwheel_probe` with Qt's offscreen platform. This promotes
  the Milestone 5 offscreen/style-editor probes into the active macOS Metal
  verification gate.
- `scripts/verify_macos_preview_export_probe.sh` runs the `TOfflineGL`
  raster-placement preview/export slice under OpenGL and Metal, writes
  active-backend, legacy-OpenGL, and amplified diff PNG artifacts, rejects blank
  artifacts, and requires the Metal active-backend artifact to exactly match
  the legacy OpenGL output for that reduced fixture.
- `scripts/verify_graphics_app_smoke_artifacts.sh` validates packaged app smoke
  artifacts for backend metadata, startup failure markers, screenshot metadata,
  optional action metadata, nonblank PNG screenshot content, OpenGL/Metal
  screenshot differences when both backend screenshots are present, consistent
  scene metadata across backends, optional required screenshot evidence, and
  optional required direct-Metal metadata.
- `scripts/graphics_app_smoke_manifest.sh` runs the packaged app smoke against
  each committed `.tnz` scene row in the golden-scene manifest and verifies the
  artifacts for each scene/backend pair. When screenshot capture is enabled, it
  now passes `--require-screenshot` to the artifact verifier so missing or
  disabled screenshot evidence fails the manifest smoke.
- `scripts/verify_png_nonblank.py` is a small standard-library PNG decoder used
  by the app-smoke artifact verifier to reject single-color screenshots.
- `scripts/verify_png_match.py` compares two non-interlaced 8-bit PNGs and
  reports differing-pixel ratio, maximum channel delta, and mean absolute
  channel delta. The app-smoke artifact verifier uses it for OpenGL/Metal
  screenshots with configurable tolerances.
- `SceneViewer::pick()` now refuses the legacy OpenGL selection path when
  `OPENTOONZ_GRAPHICS_BACKEND=metal` is requested. The remaining `GL_SELECT`
  implementation is still present for OpenGL compatibility paths.
- Skeleton Tool 2D interactions use CPU picking, and its remaining 3D
  OpenGL-selection fallback is now gated behind an explicit compatibility check
  that is disabled when `OPENTOONZ_GRAPHICS_BACKEND=metal` is requested.
- `scripts/verify_opengl_selection_compatibility.sh` is the strict companion to
  the inventory count. It allows real OpenGL selection API use only in
  `toonz/sceneviewer.cpp` and `tnztools/skeletontool.cpp`, and verifies that
  both paths keep their Metal-requested guards.
- `scripts/graphics_modernization_lint.sh` and
  `scripts/verify_golden_scene_manifest.sh` enforce the current graphics
  modernization invariants and golden-scene coverage manifest in the macOS CI
  workflow. The graphics lint also runs the sample data verifier when the
  committed sample pack is present, and now enforces that Edit Tool and
  Skeleton Tool 2D picking stay on their CPU picking paths instead of regressing
  to the generic OpenGL selection path. It also enforces that PlaneViewer
  background/raster presentation stays on `tgraphics` draw lists, the Style
  Editor color wheel stays on its QWidget/QPainter implementation without
  direct OpenGL drawing, and camera-mask/color-card overlays remain
  `DrawList2D` surfaces. It also enforces that macOS CI keeps the Metal probe
  image verifier, offscreen/style probe verifier, OpenGL selection
  compatibility verifier, direct-Metal artifact verification, and shader-effect
  scene-fixture verifier wired into the graphics gates. It now also enforces
  that the Metal probe verifier keeps the editing tool-overlay artifact gate.
  It also enforces that the manifest smoke wrapper keeps the
  `--require-screenshot` gate for screenshot-enabled runs.
- `scripts/verify_sample_data.sh` validates the committed `doc/sample_data`
  pack used by the golden scene manifest: license, key scene files,
  representative raster/vector/material assets, and `$scenefolder`
  relocatability with resolved in-repository scene dependencies.
- `scripts/generate_graphics_fixture_scenes.sh` and
  `scripts/verify_graphics_fixture_scenes.sh` materialize and validate
  deterministic generated scene fixtures that should not be maintained as large
  checked-in XML. The generated app-behavior fixtures are
  `sub_xsheet_basic.tnz`, a nested child-level scene backed by the committed
  sample TLV data, and `mesh_skeleton_basic.tnz`, a mesh-column scene backed by
  a generated `.mesh` frame with triangular faces and rigidity data.
- The macOS Metal CI leg runs `scripts/verify_metal_probe_images.sh` and uploads
  the generated Metal/OpenGL/diff PNGs plus shader-effect comparison artifacts.
- `scripts/macos/verify-metal-resources.sh` can write
  `OPENTOONZ_METAL_RESOURCE_SUMMARY`, a machine-readable record of packaged
  Metal source and `.metallib` presence, file sizes, detected command-line Metal
  tools, and verifier status. The macOS Metal CI leg uploads that summary.
- The macOS Metal CI leg now also runs the manifest-driven packaged app smoke
  with generated graphics fixtures, screenshot capture enabled, and
  comparison-aware artifact verification for every available manifest `.tnz`
  scene, including shader-effect scenes generated under the shader comparison
  artifact directory.
- The macOS Metal CI leg also runs and uploads the focused preview/export probe
  artifacts from `scripts/verify_macos_preview_export_probe.sh`.
- `scripts/macos/verify-bundled-qt-runtime.sh` verifies packaged app bundles do
  not mix bundled Qt dylibs with Nix-store Qt references. This catches the
  duplicate-Qt runtime condition that produced misleading Cocoa plugin startup
  failures during direct-Metal smoke attempts. It also checks that bundled
  dependencies requiring GNU `libiconv` resolve `_libiconv` imports to
  `libgnuiconv.2.dylib` instead of Darwin `libiconv.2.dylib`, and that
  `libidn2.0.dylib` is linked to the bundled GNU iconv library. This catches
  the dyld launch abort where `libidn2.0.dylib` references `_libiconv` but the
  loaded `libiconv.2.dylib` does not export it.
- Packaged helper binaries such as `tcomposer` now resolve macOS portable
  `portablestuff` from `QCoreApplication::applicationDirPath()` when running
  inside `OpenToonz.app/Contents/MacOS`; non-Qt helpers fall back to the
  executable path without asking Qt for an application directory before a
  `QCoreApplication` exists. `TEnv` also uses the platform path separator when
  checking portable paths and expanding `-TOONZROOT`, and no longer strips
  non-`.app` helper executable paths through the old `std::string::find()`
  truthiness bug. This moves preview/export validation past the earlier
  `Undefined: ""` / missing `TOONZROOT` startup failure.
- The macOS Metal CI leg now also runs a packaged direct-Metal smoke for
  `doc/sample_data/dwanko_run.tnz` with
  `OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=1` and screenshot capture disabled.
  This proves launch-plus-scene-load through the direct Metal layer path instead
  of the OpenGL compatibility snapshot; screenshot comparison remains covered by
  the normal manifest smoke.
- `scripts/verify_shaderfx_scene_fixtures.sh` checks that the generated
  shader-effect scene fixtures and saved-scene render outputs exist and are
  non-empty; the macOS Metal CI leg runs it after shader-effect comparison.
- `doc/how_to_build_macosx.md` now documents user-facing backend selection and
  troubleshooting for OpenGL, Metal, direct-Metal smoke mode, packaging-related
  launch failures, shader resource fallback, and Metal-to-OpenGL fallback.
- `doc/macos_graphics_golden_scenes.tsv` is a checked golden-scene coverage
  manifest. It records committed sample-scene coverage plus generated
  shader-effect, sub-xsheet, and mesh-column scene coverage.
  `scripts/verify_golden_scene_manifest.sh --require-complete` is the strict
  fixture gate for any future Metal-default decision.
- `doc/sample_data` has been added as committed sample application data under
  the upstream CC BY-NC 4.0 license. The golden-scene manifest now uses
  `dwanko_run.tnz`, `cleanup.tnz`, `tga_paint.tnz`, and sample vector material
  for real application-behavior coverage where applicable. Onion-skin coverage
  uses the multi-frame `tga_paint.tnz` sample with an explicit toggle-on smoke
  because onion-skin masks are runtime viewer state, not a normal `.tnz`
  scene-level property. Sub-xsheet coverage now uses the generated
  `sub_xsheet_basic.tnz` fixture. Mesh-column coverage now uses the generated
  `mesh_skeleton_basic.tnz` fixture; full animated plastic deformation parity
  still requires manual or scripted tool smoke beyond this fixture gate.

## Fresh Validation

Commands run from the repository root:

```sh
bash scripts/graphics_inventory.sh
bash scripts/verify_sample_data.sh
bash scripts/verify_graphics_fixture_scenes.sh /private/tmp/opentoonz-graphics-fixtures-4146
bash scripts/verify_opengl_selection_compatibility.sh
bash scripts/graphics_modernization_lint.sh
bash scripts/verify_golden_scene_manifest.sh
bash scripts/verify_golden_scene_manifest.sh --require-complete
bash scripts/verify_shaderfx_scene_fixtures.sh /private/tmp/opentoonz-shaderfx-compare-4146
bash -n scripts/graphics_inventory.sh scripts/graphics_modernization_lint.sh scripts/graphics_shader_inventory.sh scripts/graphics_shaderfx_compare.sh scripts/verify_golden_scene_manifest.sh scripts/verify_macos_offscreen_style_probes.sh scripts/verify_metal_probe_images.sh scripts/verify_sample_data.sh scripts/verify_shaderfx_scene_fixtures.sh scripts/macos/ci-build-summary.sh scripts/macos/verify-metal-resources.sh
! sed -n '203,267p' doc/how_to_build_macosx.md | rg -n "/Users/|/home/|~|\\.codex|briangyss|/Applications|/private/tmp"
git diff --check
nix develop path:. --command bash -lc 'bash scripts/nix/prepare-tiff.sh && cmake -S toonz/sources --preset nix-relwithdebinfo -DWITH_GRAPHICS_METAL=ON'
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tgraphics_metal_probe OpenToonz --parallel 3
nix develop path:. --command toonz/build/nix-relwithdebinfo/tnzcore/tgraphics_metal_probe
nix develop path:. --command bash scripts/verify_metal_probe_images.sh /private/tmp/opentoonz-metal-probe-images-4146-verified
nix develop path:. --command bash scripts/verify_metal_probe_images.sh /private/tmp/opentoonz-metal-probe-images-4146-hardened
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tgraphics_metal_probe --parallel 3
nix develop path:. --command bash scripts/verify_metal_probe_images.sh /private/tmp/opentoonz-metal-probe-images-4146-offscreen-placement
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tofflinegl_probe styleeditor_colorwheel_probe --parallel 3
nix develop path:. --command bash scripts/verify_macos_offscreen_style_probes.sh
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tofflinegl_probe --parallel 3
nix develop path:. --command bash scripts/verify_macos_preview_export_probe.sh /private/tmp/opentoonz-preview-export-probe-4146
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target shaderfx_metal_probe --parallel 3
nix develop path:. --command bash scripts/graphics_shaderfx_compare.sh /private/tmp/opentoonz-shaderfx-compare-4146
bash scripts/macos/verify-metal-resources.sh toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app
OPENTOONZ_METAL_RESOURCE_SUMMARY=/private/tmp/opentoonz-metal-resources-4146-summary.txt bash scripts/macos/verify-metal-resources.sh toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app
bash -n scripts/macos/graphics-app-smoke.sh
bash -n scripts/macos/graphics-app-smoke.sh scripts/graphics_app_smoke_manifest.sh scripts/verify_graphics_app_smoke_artifacts.sh scripts/verify_golden_scene_manifest.sh scripts/verify_sample_data.sh scripts/verify_graphics_fixture_scenes.sh scripts/generate_graphics_fixture_scenes.sh scripts/graphics_modernization_lint.sh
python3 -m py_compile scripts/verify_png_match.py scripts/verify_png_nonblank.py
OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/dwanko_run.tnz OPENTOONZ_GRAPHICS_SMOKE_BACKENDS=opengl OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 OPENTOONZ_GRAPHICS_SMOKE_SECONDS=0 bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-argcheck
nix develop path:. --command bash -lc 'OPENTOONZ_ADHOC_SIGN=0 scripts/macos/package-nix-app.sh'
bash scripts/macos/assert-arm64-bundle.sh toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app
OPENTOONZ_GRAPHICS_SMOKE_SECONDS=5 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=4 OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-4146-combined
OPENTOONZ_GRAPHICS_SMOKE_SECONDS=5 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=4 OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=1 bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-4146-screenshots
OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/dwanko_run.tnz OPENTOONZ_GRAPHICS_SMOKE_BACKENDS="opengl metal" OPENTOONZ_GRAPHICS_SMOKE_SECONDS=5 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=2 OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-sample-scene-4146-bundled
OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/dwanko_run.tnz OPENTOONZ_GRAPHICS_SMOKE_BACKENDS="opengl metal" OPENTOONZ_GRAPHICS_SMOKE_SECONDS=5 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=2 OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=1 bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-sample-scene-4146-screenshots
scripts/verify_png_nonblank.py /private/tmp/opentoonz-graphics-app-smoke-sample-scene-4146-screenshots/opengl/screenshot.png /private/tmp/opentoonz-graphics-app-smoke-sample-scene-4146-screenshots/metal/screenshot.png
bash scripts/verify_graphics_app_smoke_artifacts.sh /private/tmp/opentoonz-graphics-app-smoke-sample-scene-4146-screenshots
scripts/verify_png_match.py --max-mean-delta 255 --max-channel-delta 255 --max-differing-ratio 1 /private/tmp/opentoonz-graphics-app-smoke-sample-scene-4146-screenshots/metal/screenshot.png /private/tmp/opentoonz-graphics-app-smoke-sample-scene-4146-screenshots/opengl/screenshot.png
OPENTOONZ_GRAPHICS_FIXTURE_DIR=/private/tmp/opentoonz-graphics-fixtures-4146 OPENTOONZ_SHADERFX_COMPARE_DIR=/private/tmp/opentoonz-shaderfx-compare-4146 OPENTOONZ_GRAPHICS_SMOKE_BACKENDS="opengl metal" OPENTOONZ_GRAPHICS_SMOKE_SECONDS=1 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=1 OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 bash scripts/graphics_app_smoke_manifest.sh doc/macos_graphics_golden_scenes.tsv /private/tmp/opentoonz-graphics-app-smoke-manifest-4146-fixtures
OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/dwanko_run.tnz OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=basic-viewer OPENTOONZ_GRAPHICS_SMOKE_BACKENDS="opengl" OPENTOONZ_GRAPHICS_SMOKE_SECONDS=1 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=1 OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-basic-viewer-4146-bounded
OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/dwanko_run.tnz OPENTOONZ_GRAPHICS_SMOKE_BACKENDS=metal OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=1 OPENTOONZ_GRAPHICS_SMOKE_SECONDS=2 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=1 OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-direct-metal-fixed-4146
bash scripts/verify_graphics_app_smoke_artifacts.sh /private/tmp/opentoonz-graphics-app-smoke-direct-metal-fixed-4146 --require-direct-metal
OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/dwanko_run.tnz OPENTOONZ_GRAPHICS_SMOKE_BACKENDS=metal OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=1 OPENTOONZ_GRAPHICS_SMOKE_SECONDS=1 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=1 OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-direct-metal-preflight-artifact-4146
bash scripts/verify_graphics_app_smoke_artifacts.sh /private/tmp/opentoonz-graphics-app-smoke-direct-metal-preflight-artifact-4146 --require-direct-metal
OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/dwanko_run.tnz OPENTOONZ_GRAPHICS_SMOKE_BACKENDS=metal OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=1 OPENTOONZ_GRAPHICS_SMOKE_SECONDS=1 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=1 OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-direct-metal-iconv-4146
bash scripts/verify_graphics_app_smoke_artifacts.sh /private/tmp/opentoonz-graphics-app-smoke-direct-metal-iconv-4146 --require-direct-metal
OPENTOONZ_GRAPHICS_FIXTURE_DIR=/private/tmp/opentoonz-graphics-fixtures-4146 OPENTOONZ_SHADERFX_COMPARE_DIR=/private/tmp/opentoonz-shaderfx-compare-4146 OPENTOONZ_GRAPHICS_SMOKE_BACKENDS=metal OPENTOONZ_GRAPHICS_SMOKE_SECONDS=1 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=1 OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 bash scripts/graphics_app_smoke_manifest.sh doc/macos_graphics_golden_scenes.tsv /private/tmp/opentoonz-graphics-app-smoke-manifest-4146-no-screenshot-gate
bash scripts/verify_graphics_app_smoke_artifacts.sh /private/tmp/opentoonz-graphics-app-smoke-sample-scene-4146-screenshots --require-screenshot
OPENTOONZ_CI_BUILD_LABEL=macos-arm64-4146-current OPENTOONZ_CMAKE_EXTRA_ARGS=-DWITH_GRAPHICS_METAL=ON OPENTOONZ_BUILD_PARALLEL=3 scripts/macos/ci-build-summary.sh
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target OpenToonz --parallel 3
nix develop path:. --command bash -lc 'OPENTOONZ_ADHOC_SIGN=0 scripts/macos/package-nix-app.sh'
bash scripts/macos/verify-bundled-qt-runtime.sh toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app
```

Observed results:

```text
tgraphics_metal_probe: ok on Apple M1 Max
verify-metal-probe-images: cases=21 artifacts=/private/tmp/opentoonz-metal-probe-images-4146-editing-overlay
probe image counts: total_png=63 metal=21 opengl=21 diff=21; summary.txt includes SHA-256 hashes, editing_tool_overlay_* artifacts, transparent_style_icon_* artifacts, and legacy_offline_raster_placement_* artifacts.
tofflinegl_probe: ok backend=opengl
tofflinegl_probe: ok backend=metal
styleeditor_colorwheel_probe: ok
verify-macos-offscreen-style-probes: ok
verify-macos-preview-export-probe: ok artifacts=/private/tmp/opentoonz-preview-export-probe-4146
preview/export probe artifacts: OpenGL, Metal, legacy OpenGL, and diff PNGs are nonblank 16 x 12 RGBA images; Metal active-backend output matched legacy OpenGL exactly with differing_pixels=0.
graphics-modernization-lint: ok
graphics-modernization-lint regression guards: PlaneViewer draw-list
background/raster presentation, Style Editor non-OpenGL color wheel, and
ViewerDraw camera-mask/color-card draw-list overlays are now enforced.
Skeleton Tool selection fallback: 2D CPU picking remains enforced, and the
legacy 3D `pick(e.m_pos)` fallback is now skipped when Metal is requested.
verify-opengl-selection-compatibility: ok files=2 matches=22
graphics-modernization-lint smoke evidence guards: direct-Metal workflow smoke
must verify artifacts with --require-direct-metal, and the manifest wrapper must
keep --require-screenshot for screenshot-enabled runs.
verify-sample-data: ok
verify-graphics-fixture-scenes: ok artifacts=/private/tmp/opentoonz-graphics-fixtures-4146
verify-golden-scene-manifest: ok
strict golden-scene manifest check: ok
sample data: 40 files, 45M under doc/sample_data; committed scene dependencies resolve through $scenefolder.
verify-shaderfx-scene-fixtures: scenes=4 pams=4 artifacts=/private/tmp/opentoonz-shaderfx-compare-4146
privacy scan: no personal/transient paths in the new backend-selection doc section.
graphics_shaderfx_compare: ok
macOS workflow now runs verify_metal_probe_images.sh and uploads Metal graphics probe artifacts.
macOS workflow now runs verify_golden_scene_manifest.sh --require-complete in the graphics invariant step.
macOS workflow now runs verify_opengl_selection_compatibility.sh explicitly in the graphics invariant step.
macOS workflow now runs verify_graphics_fixture_scenes.sh, the focused preview/export probe, and the manifest-driven packaged app smoke with generated fixtures and screenshot comparison artifacts.
macOS workflow now verifies the packaged Qt runtime does not mix bundled and Nix-store Qt dylibs.
macOS workflow now runs a packaged direct-Metal scene smoke with OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=1 and uploads its artifacts.
Metal shader source resource present; metallib build skipped because the Metal toolchain is unavailable
Metal resource summary: status=source-only-toolchain-unavailable source_present=1 source_bytes=20675 library_present=0 library_bytes=0 metallib_tool=.
Checked 281 Mach-O files for arm64.
graphics-app-smoke: backend=opengl passed
graphics-app-smoke: backend=metal passed
graphics-app-smoke scene argument check: backend=opengl passed with OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/dwanko_run.tnz and screenshot capture disabled.
graphics-app-smoke sample scene: packaged app loaded doc/sample_data/dwanko_run.tnz under opengl and metal with screenshot capture disabled.
graphics-app-smoke sample scene screenshots: packaged app loaded doc/sample_data/dwanko_run.tnz under opengl and metal with 3456 x 2234 PNG screenshots.
verify-png-nonblank: ok for opengl and metal sample-scene screenshots.
verify-png-match sample-scene screenshots: differing_pixels=3490 differing_ratio=0.00045203 max_channel_delta=227 mean_abs_channel_delta=0.05153296
verify-graphics-app-smoke-artifacts: ok backends=opengl metal artifacts=/private/tmp/opentoonz-graphics-app-smoke-sample-scene-4146-screenshots
graphics-app-smoke-manifest: ok scenes=8 artifacts=/private/tmp/opentoonz-graphics-app-smoke-manifest-4146-fixtures
manifest smoke covered committed raster/style/onion sample scene, generated mesh-column fixture, committed camera/FX/export sample scene, generated sub-xsheet fixture, and four generated shader-effect scene fixtures under both OpenGL and Metal with screenshots disabled.
manifest smoke screenshot gate: when OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT is enabled, graphics_app_smoke_manifest.sh now requires screenshot evidence for every scene/backend artifact.
manifest smoke no-screenshot compatibility: the same wrapper still passes all 8 manifest scenes when OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0, proving the stricter gate only applies to screenshot-enabled smokes.
verify-graphics-app-smoke-artifacts --require-screenshot: existing OpenGL/Metal sample-scene screenshot artifacts pass the stricter screenshot evidence gate.
graphics-app-smoke basic-viewer actions: action mode is implemented and bounded, but the local sandboxed run was denied by macOS System Events with error -10827. The failed run left no smoke processes after cleanup. It should be rerun from an Automation/Accessibility-authorized terminal before treating viewer event delivery as proven.
bundled Qt runtime verifier: ok after rerunning package-nix-app; the previous stale bundle mixed Nix-store Qt references with bundled Qt dylibs.
bundled GNU iconv verifier: ok; `libidn2.0.dylib` imports `_libiconv` from bundled `libgnuiconv.2.dylib`, preventing the observed dyld "Symbol not found: _libiconv" launch crash.
packaged helper runtime paths: tcomposer no longer aborts at startup with missing TOONZROOT after the TEnv portable path fix; it initializes plugins and loads sample scenes. Full tcomposer frame export remains incomplete because the attempted sample renders did not finish before manual termination in this local run.
packaged helper runtime paths: tconverter was also checked as a smaller export path; it no longer needs the macOS `.app` path stripping bug, but the sample fixture filenames are rejected by its level-existence rules, so it is not yet a usable golden export verifier.
packaged app verifier after helper rebuild: package-nix-app restored bundled Qt linkage and verify-bundled-qt-runtime passed.
graphics-app-smoke direct Metal GNU iconv preflight: packaged app loaded doc/sample_data/dwanko_run.tnz with OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=1, and artifact verification passed with --require-direct-metal after the hardened bundle verifier.
graphics-app-smoke direct Metal sample scene: packaged app loaded doc/sample_data/dwanko_run.tnz with OPENTOONZ_GRAPHICS_BACKEND=metal and OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=1; screenshot capture was disabled.
verify-graphics-app-smoke-artifacts direct Metal sample scene: ok backends=metal artifacts=/private/tmp/opentoonz-graphics-app-smoke-direct-metal-fixed-4146 with --require-direct-metal.
graphics-app-smoke Qt runtime preflight: direct-Metal smoke now writes preflight.txt with verify-bundled-qt-runtime: ok before launching OpenToonz, and the direct-Metal artifact verifier requires that metadata and passes with --require-direct-metal.
strict direct-Metal frame diagnostic: `--require-direct-metal-frame` is now available and fails the current local direct-Metal scene smoke because the app log does not yet contain `direct_content=1 compatibility_snapshot=0`; this exposes that the previous direct-Metal smoke proved launch-plus-scene-load metadata, not a painted direct Metal scene-viewer frame.
direct Metal screenshot smoke: after fixing the duplicate-Qt runtime issue, the screenshot-enabled direct-Metal smoke reached screencapture and failed with `could not create image from display`; keep screenshot capture disabled for the direct-Metal smoke until a capture-capable manual session or runner is available.
graphics-app-smoke shutdown hardening: bounded Apple Event quit and ps-denial fallback were validated by the manifest smoke after two earlier hung smoke attempts exposed those edge cases.
graphics-app-smoke: artifacts: /private/tmp/opentoonz-graphics-app-smoke-4146-combined
graphics-app-smoke: artifacts: /private/tmp/opentoonz-graphics-app-smoke-4146-screenshots
graphics-app-smoke: artifacts: /private/tmp/opentoonz-graphics-app-smoke-sample-scene-4146-bundled
opengl screenshot.png: PNG image data, 3456 x 2234, 8-bit/color RGBA, non-interlaced
metal screenshot.png: PNG image data, 3456 x 2234, 8-bit/color RGBA, non-interlaced
macos-arm64-4146-current build summary: status=0 elapsed_seconds=16 WITH_GRAPHICS_METAL=ON total_warnings=0 apple_opengl_deprecation_warnings=0 qt_qgl_warning_lines=0 qt_qopengl_deprecation_warning_lines=0
ccache: hits=30542/36876 (82.82%)
SceneViewer Metal picking guard build: OpenToonz target linked successfully.
graphics-app-smoke shutdown hardening: script syntax check passed after adding
process-state checks that avoid escalating an already-exited child process.
Latest OpenToonz build check: ninja reported no work to do.
Skeleton Tool Metal selection gate build: tnztools rebuilt and OpenToonz linked
successfully.
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
- Full GUI smoke still needs successful manual or scripted evidence for viewer
  navigation, drawing/editing tools, style editor, preview/export, and broader
  representative scene files under `OPENTOONZ_GRAPHICS_BACKEND=metal`. A
  bounded `basic-viewer` action mode now exists for playback/scrub/zoom event
  delivery, but this local run was blocked by macOS System Events permissions.
- Packaged `tcomposer` helper startup now finds portable app resources, but
  full preview/export frame evidence remains incomplete: local sample-scene
  render attempts initialized plugins and loaded the scene, then failed to
  produce a frame before they were terminated.
- Focused preview/export probe evidence now exists for the reduced
  `TOfflineGL` raster-placement path and exact Metal/OpenGL parity, but full
  scene-level preview/export through `tcomposer` or the GUI remains incomplete.
- The bounded app launch smoke now passes locally for OpenGL and Metal after
  packaging with screenshot artifacts captured for both backends.
- Golden-scene image comparison is still incomplete for full application
  workflows, even though command-line Metal/OpenGL probes pass. The manifest now
  uses committed sample scenes where available and lists each remaining missing
  committed fixture category explicitly.
- The legacy SceneViewer `GL_SELECT` implementation and Skeleton Tool 3D
  selection markers remain compatibility code, but `SceneViewer::pick()` and the
  Skeleton Tool fallback no longer enter that path when the Metal backend is
  requested.
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
testing, then extend the basic app-action smoke into targeted drawing/editing,
style-editor, preview, and export flows with comparable screenshots.
