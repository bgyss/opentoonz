# macOS Graphics Modernization Current Handoff

Status: refreshed local and Apple-hosted CI evidence from the Codex worktree on
2026-05-25.

This handoff summarizes the current state against
`doc/macos_graphics_modernization_goal_prompt.md`. The repository already
contains the inventory harness, `tgraphics` abstraction, opt-in Metal backend,
Metal probe targets, shader-effect probes, macOS CI matrix wiring, and
milestone reports through the CI checkpoint.

## Current State

- OpenGL remains the default backend.
- Metal is opt-in with `OPENTOONZ_GRAPHICS_BACKEND=metal`.
- `doc/macos_graphics_default_backend_decision.md` records the current
  default-backend decision: keep OpenGL as the macOS default until the remaining
  Metal switch criteria are satisfied.
- `WITH_GRAPHICS_METAL=ON` builds the Metal implementation and probe targets on
  macOS.
- `QGL*` usage is gone from source-like inventory.
- `glDrawPixels` usage is gone from source-like inventory.
- Remaining OpenGL selection usage is isolated to the legacy SceneViewer picking
  path and Skeleton Tool 3D fallback markers.
- Metal shader source is copied into the app bundle. A compiled `.metallib` is
  packaged when the local Metal toolchain provides both `metal` and `metallib`.
  Release-grade strict validation can require that compiled library with
  `WITH_GRAPHICS_METAL_REQUIRE_METALLIB=ON` at configure time and
  `OPENTOONZ_REQUIRE_METALLIB=1` during package verification. Public CI still
  records source-only evidence when the runner has no `metallib` tool.
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
  failures in `actions.txt`. Set
  `OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=internal-basic-viewer` for a CI-friendly
  in-process viewer action sequence that resets the viewer, zooms in/out,
  scrubs the current frame handle, invalidates the viewer, and requires the
  `main_internal_actions_done` trace without System Events keystrokes. Set
  `OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=internal-editing-context` for the stronger
  CI mode, which also switches through Animate, Selection, Brush, Geometric,
  Skeleton, and Hand tools and verifies each tool trace. Set
  `OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=internal-preview-export` to enable
  SceneViewer full preview, wait for the current preview frame to become ready,
  and write `preview-export.png`. The app first tries the Previewer cache
  raster, records a raster summary, tries an in-app scene render for the same
  frame when that cache raster is blank, and falls back to the visible
  full-preview SceneViewer framebuffer or widget grab only if needed. The
  artifact verifier requires frame-ready/export-source/export-saved traces and
  rejects a missing or single-color preview export. It also supports
  `--require-preview-raster-export` for runs that must prove the saved PNG came
  from the Previewer cache raster rather than the viewer fallback. Set
  `OPENTOONZ_GRAPHICS_SMOKE_BUNDLE_ID` only when
  testing a bundle with a nonstandard identifier. The smoke enables
  `OPENTOONZ_GRAPHICS_METAL_FRAME_DIAGNOSTICS=1`, and the artifact verifier's
  stricter `--require-direct-metal-frame` gate requires a scene-viewer log line
  or `graphics-smoke-trace.txt` entry proving `direct_content=1` and
  `compatibility_snapshot=0` for the Metal backend. The smoke also copies the
  bundled profile into the artifact directory and writes a known
  `currentRoom.txt`, disables lazy room loading in the smoke profile, and can
  be run with `OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_STARTUP_TRACE=1` to fail unless
  the app reaches `main_after_main_window` within the smoke timeout. The
  startup trace also records `mainwindow_fbo_probe_skip` diagnostics so early
  Qt/OpenGL framebuffer capability probes are visible in packaged smoke
  artifacts. When
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
  artifacts, and requires exact zero-difference matches between OpenGL active,
  Metal active, and both legacy OpenGL reference artifacts for that reduced
  fixture.
- `scripts/verify_macos_tcomposer_scene_export.sh` runs the packaged
  `tcomposer` helper against the generated `tcomposer-color-card` row, the
  committed `offscreen-export` (`dwanko_run.tnz`) row, the committed
  `tcomposer-cleanup-scan` row, and the committed `tcomposer-tlv-paint` row in
  `doc/macos_graphics_golden_scenes.tsv` under OpenGL and Metal backend
  selectors. It requires each exported TIFF frame, rejects single-color black
  TIFF output with ImageMagick, and byte-compares paired backend outputs.
  `OPENTOONZ_TCOMPOSER_INCLUDE_REPO_SCENES=1` enables the committed sample
  `.tnz` diagnostics, and `OPENTOONZ_TCOMPOSER_SCENE` and
  `OPENTOONZ_TCOMPOSER_FRAME` still provide a focused single-scene mode.
  `tcomposer` now normalizes relative scene paths before project resolution and
  creates the sandbox project during helper startup, matching the main app's
  standalone-scene setup. The default generated helper fixture is TIFF-backed,
  the committed cleanup sample is TIFF-sequence backed, the committed
  `doc/sample_data/tga_paint.tnz` sample is TLV-backed, and the committed
  `doc/sample_data/dwanko_run.tnz` FX/vector sample all pass the nonblack
  OpenGL/Metal export gate locally. Set
  `OPENTOONZ_TCOMPOSER_DEBUG_LEVELS=1` for decoded helper level-path diagnostics
  and Ino Fore/Back blend bbox diagnostics when investigating helper exports.
- `scripts/verify_graphics_app_smoke_artifacts.sh` validates packaged app smoke
  artifacts for backend metadata, startup failure markers, screenshot metadata,
  optional action metadata, nonblank PNG screenshot content, OpenGL/Metal
  screenshot differences when both backend screenshots are present, consistent
  scene metadata across backends, optional required screenshot evidence, and
  optional required direct-Metal metadata. It also verifies internal
  editing-context tool traces, internal Style Editor palette-change/restore
  traces, and internal preview-export frame/export/source traces when those
  action modes are used. Whole-window screenshot comparison is tolerance-based
  because macOS capture can introduce compositor and color management
  differences; deterministic probe/export checks remain the exact pixel gates.
- `scripts/graphics_app_smoke_manifest.sh` runs the packaged app smoke against
  each committed `.tnz` scene row in the golden-scene manifest and verifies the
  artifacts for each scene/backend pair. When screenshot capture is enabled, it
  now passes `--require-screenshot` to the artifact verifier so missing or
  disabled screenshot evidence fails the manifest smoke. It also passes each
  row's `frame` column as `OPENTOONZ_GRAPHICS_SMOKE_FRAME`, and the artifact
  verifier requires the corresponding app trace when a frame is specified. The
  manifest no longer deduplicates by scene path, so repeated sample scenes still
  run when they cover different categories or frames.
- The app smoke now asks OpenToonz to write an internal SceneViewer framebuffer
  PNG via `OPENTOONZ_GRAPHICS_SMOKE_INTERNAL_SCREENSHOT` and uses that artifact
  before falling back to `screencapture`. The app writes through a temporary
  path and renames atomically after a nonblank retry loop, so the shell verifier
  does not consume partial PNG files.
- `scripts/verify_png_nonblank.py` is a small standard-library PNG decoder used
  by the app-smoke artifact verifier to reject single-color screenshots.
- `scripts/verify_png_match.py` compares two non-interlaced 8-bit PNGs and
  reports differing-pixel ratio, maximum channel delta, and mean absolute
  channel delta. The app-smoke artifact verifier uses it for OpenGL/Metal
  screenshots with configurable tolerances.
- `SceneViewer::pick()` no longer enters OpenGL selection mode. The legacy
  `GL_SELECT` implementation has been removed from SceneViewer, and generic
  viewer picks now return no selection unless a tool supplies its own CPU
  picker.
- Skeleton Tool interactions now use CPU picking in both 2D and 3D views. The
  old `pick(e.m_pos)` OpenGL-selection fallback has been removed.
- `scripts/verify_opengl_selection_compatibility.sh` is the strict companion to
  the inventory count. It requires SceneViewer selection-mode API use to stay
  removed and allows the remaining OpenGL name-stack markers only in Skeleton
  Tool compatibility drawing code.
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
- `scripts/verify_macos_default_backend_decision.sh` keeps the OpenGL-default
  decision record aligned with the actual CMake default, runtime backend
  selector, macOS CI matrix, build-time summary, warning-count summary, and
  ccache summary hooks.
- `scripts/verify_macos_ci_artifacts.sh` verifies downloaded Apple-hosted
  macOS CI artifacts after `gh run download`. It requires successful OpenGL and
  Metal build summaries with elapsed-time, warning-count, and ccache fields,
  Metal resource summary status, bundled-runtime preflight metadata, direct
  Metal frame traces, internal preview-export, Style Editor, viewer-input, and
  drawing-gesture traces, packaged `tcomposer` nonblack statistics, and probe
  summary evidence.
- `scripts/verify_macos_system_viewer_app_smoke.sh` wraps the app smoke's
  `basic-viewer` action mode for Accessibility/Automation-authorized macOS
  runners. It drives a center-window click plus playback/scrub/zoom keyboard
  events through System Events under both OpenGL and Metal, requires screenshot
  evidence, and verifies the action metadata. The macOS workflow exposes this
  as a `workflow_dispatch` input named `system_gui_smoke` so release/default
  readiness can collect system-level input evidence without destabilizing
  ordinary push CI on runners that lack those permissions.
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
  a generated `.mesh` frame with triangular faces and rigidity data. The
  sub-xsheet verifier now requires the TLV level to be declared before the
  childLevel that references it, matching the loader ordering needed to avoid
  `IoCmd::loadScene` failures.
- The macOS Metal CI leg runs `scripts/verify_metal_probe_images.sh` and uploads
  the generated Metal/OpenGL/diff PNGs plus shader-effect comparison artifacts.
- `scripts/macos/verify-metal-resources.sh` can write
  `OPENTOONZ_METAL_RESOURCE_SUMMARY`, a machine-readable record of packaged
  repository and bundled Metal source presence, file sizes, SHA-256 hashes,
  byte-for-byte source parity, `.metallib` presence, detected command-line Metal
  tools, whether strict `.metallib` mode was requested, and verifier status. The
  macOS Metal CI leg uploads that summary. GitHub-hosted runners can pass with
  `status=source-only-toolchain-unavailable`; release-grade strict `.metallib`
  evidence still requires running with `OPENTOONZ_REQUIRE_METALLIB=1` on a
  machine where `metal` and `metallib` are available.
- The macOS workflow exposes a `workflow_dispatch` input named
  `strict_metallib`. When set to `true` for the Metal matrix leg, configure uses
  `-DWITH_GRAPHICS_METAL_REQUIRE_METALLIB=ON` and the package resource verifier
  uses `OPENTOONZ_REQUIRE_METALLIB=1`. This turns missing command-line Metal
  library tooling or a missing packaged `.metallib` into an intentional
  release-readiness failure instead of source-only evidence.
- The macOS Metal CI leg now also runs the manifest-driven packaged app smoke
  with generated graphics fixtures, screenshot capture enabled, and
  comparison-aware artifact verification for every available manifest `.tnz`
  scene, including shader-effect scenes generated under the shader comparison
  artifact directory.
- The macOS Metal CI leg also runs and uploads the focused preview/export probe
  artifacts from `scripts/verify_macos_preview_export_probe.sh`.
- The macOS Metal CI leg also runs and uploads
  `scripts/verify_macos_preview_export_app_smoke.sh`, which verifies a packaged
  OpenGL/Metal `internal-preview-export` run for the generated color-card
  fixture where both saved PNGs come from the Previewer cache raster and
  exact-match. It now also runs the committed `doc/sample_data/tga_paint.tnz`
  TLV sample through app preview/export and exact-compares the OpenGL/Metal PNGs
  while allowing the viewer-framebuffer fallback when the Previewer cache raster
  is blank for that scene. It also runs the committed
  `doc/sample_data/dwanko_run.tnz` FX/vector sample at frame 24, requires
  Previewer-raster export for that sample, and exact-compares the OpenGL/Metal
  PNGs.
- The macOS Metal CI leg also runs and uploads
  `scripts/verify_macos_style_editor_app_smoke.sh`, which verifies a packaged
  OpenGL/Metal `internal-style-editor` run that opens the Style Editor, changes
  the current palette style through `TPaletteHandle`, notifies the palette/style
  listener path, and restores the original style before exit.
- The macOS Metal CI leg also runs and uploads
  `scripts/verify_macos_viewer_input_app_smoke.sh`, which verifies a packaged
  OpenGL/Metal `internal-viewer-input` run that switches to the Hand and
  Selection tools and sends Qt mouse press/move/release events through the
  active SceneViewer event handlers.
- The macOS Metal CI leg also runs and uploads
  `scripts/verify_macos_drawing_gesture_app_smoke.sh`, which verifies a
  packaged OpenGL/Metal `internal-drawing-gesture` run for
  `doc/sample_data/tga_paint.tnz`. The app switches to the Brush tool, sends a
  Qt press/move/move/release gesture through the active SceneViewer, and the
  artifact verifier requires the current Toonz raster summary to change with
  `main_internal_drawing_changed changed=1`. The wrapper also requires the
  Metal run to emit a direct frame trace with `direct_content=1` and
  `compatibility_snapshot=0`.
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
- The macOS Metal CI leg now also runs a packaged direct-Metal frame smoke for
  `doc/sample_data/tga_paint.tnz` with
  `OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=1`,
  `OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=internal-editing-context`,
  `OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_STARTUP_TRACE=1`, and
  `OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_METAL_FRAME_TRACE=1`. Its artifact verifier
  uses `--require-direct-metal-frame`, so the CI step proves the app reached the
  scene viewer, emitted a direct Metal frame with `direct_content=1` and
  `compatibility_snapshot=0`, completed the internal viewer reset/zoom/frame
  scrub action sequence, and switched through common editing tools; screenshot
  comparison remains covered by the normal manifest smoke.
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
  `dwanko_run.tnz`, `cleanup.tnz`, and `tga_paint.tnz` for real
  application-behavior coverage where applicable. Vector coverage now points at
  `dwanko_run.tnz` instead of a standalone `.pli`, because that committed scene
  contains the sample vector PLI levels and is loadable by the app-smoke
  manifest. Onion-skin coverage uses the multi-frame `tga_paint.tnz` sample
  with an explicit toggle-on smoke because onion-skin masks are runtime viewer
  state, not a normal `.tnz` scene-level property. Sub-xsheet coverage now uses
  the generated
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
nix develop path:. --command bash scripts/verify_macos_preview_export_probe.sh /private/tmp/opentoonz-preview-export-probe-4146-hardened
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tcomposer --parallel 3
nix develop path:. --command bash scripts/macos/package-nix-app.sh
bash scripts/verify_macos_tcomposer_scene_export.sh /private/tmp/opentoonz-tcomposer-scene-export-4146-bundled-escalated
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target shaderfx_metal_probe --parallel 3
nix develop path:. --command bash scripts/graphics_shaderfx_compare.sh /private/tmp/opentoonz-shaderfx-compare-4146
bash scripts/macos/verify-metal-resources.sh toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app
OPENTOONZ_METAL_RESOURCE_SUMMARY=/private/tmp/opentoonz-metal-resources-4146-summary.txt bash scripts/macos/verify-metal-resources.sh toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app
bash -n scripts/verify_macos_ci_artifacts.sh
bash -n scripts/macos/graphics-app-smoke.sh
bash -n scripts/macos/graphics-app-smoke.sh scripts/graphics_app_smoke_manifest.sh scripts/verify_graphics_app_smoke_artifacts.sh scripts/verify_golden_scene_manifest.sh scripts/verify_sample_data.sh scripts/verify_graphics_fixture_scenes.sh scripts/generate_graphics_fixture_scenes.sh scripts/graphics_modernization_lint.sh
bash -n scripts/macos/graphics-app-smoke.sh scripts/graphics_app_smoke_manifest.sh scripts/verify_graphics_app_smoke_artifacts.sh scripts/graphics_modernization_lint.sh
bash scripts/graphics_modernization_lint.sh
git diff --check
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target OpenToonz --parallel 3
nix develop path:. --command bash scripts/macos/package-nix-app.sh
bash scripts/verify_graphics_app_smoke_artifacts.sh /private/tmp/opentoonz-frame-artifact-verifier-test-4146 opengl
python3 -m py_compile scripts/verify_png_match.py scripts/verify_png_nonblank.py
OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/dwanko_run.tnz OPENTOONZ_GRAPHICS_SMOKE_BACKENDS=opengl OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 OPENTOONZ_GRAPHICS_SMOKE_SECONDS=0 bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-argcheck
OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/dwanko_run.tnz OPENTOONZ_GRAPHICS_SMOKE_FRAME=24 OPENTOONZ_GRAPHICS_SMOKE_BACKENDS="opengl metal" OPENTOONZ_GRAPHICS_SMOKE_SECONDS=30 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=2 OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=1 OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_STARTUP_TRACE=1 bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-vector-internal-screenshot-4146-pngfmt
bash scripts/verify_graphics_app_smoke_artifacts.sh /private/tmp/opentoonz-graphics-app-smoke-vector-internal-screenshot-4146-pngfmt --require-screenshot
OPENTOONZ_GRAPHICS_FIXTURE_DIR=/private/tmp/opentoonz-graphics-fixtures-4146-internal-screenshot-manifest OPENTOONZ_SHADERFX_COMPARE_DIR=/private/tmp/opentoonz-shaderfx-compare-4146 OPENTOONZ_GRAPHICS_SMOKE_BACKENDS="opengl metal" OPENTOONZ_GRAPHICS_SMOKE_SECONDS=30 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=2 OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=1 OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_STARTUP_TRACE=1 bash scripts/graphics_app_smoke_manifest.sh doc/macos_graphics_golden_scenes.tsv /private/tmp/opentoonz-graphics-app-smoke-manifest-4146-internal-screenshots
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
bash scripts/graphics_inventory.sh
bash -n scripts/graphics_modernization_lint.sh
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target tnztools OpenToonz --parallel 3
nix develop path:. --command bash -lc 'OPENTOONZ_ADHOC_SIGN=0 scripts/macos/package-nix-app.sh'
OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/tga_paint.tnz OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=basic-viewer OPENTOONZ_GRAPHICS_SMOKE_BACKENDS=metal OPENTOONZ_GRAPHICS_SMOKE_SECONDS=8 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=1 OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-metal-basic-viewer-4146
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target OpenToonz --parallel 3
nix develop path:. --command bash -lc 'OPENTOONZ_ADHOC_SIGN=0 scripts/macos/package-nix-app.sh'
OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/tga_paint.tnz OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=internal-basic-viewer OPENTOONZ_GRAPHICS_SMOKE_BACKENDS=metal OPENTOONZ_GRAPHICS_SMOKE_SECONDS=8 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=1 OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-metal-internal-basic-viewer-4146
bash scripts/verify_graphics_app_smoke_artifacts.sh /private/tmp/opentoonz-graphics-app-smoke-metal-internal-basic-viewer-4146 metal
OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/tga_paint.tnz OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=internal-basic-viewer OPENTOONZ_GRAPHICS_SMOKE_BACKENDS=metal OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=1 OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_STARTUP_TRACE=1 OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_METAL_FRAME_TRACE=1 OPENTOONZ_GRAPHICS_SMOKE_SECONDS=20 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=1 OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-metal-direct-internal-basic-viewer-4146
bash scripts/verify_graphics_app_smoke_artifacts.sh /private/tmp/opentoonz-graphics-app-smoke-metal-direct-internal-basic-viewer-4146 --require-direct-metal-frame metal
OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/tga_paint.tnz OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=internal-editing-context OPENTOONZ_GRAPHICS_SMOKE_BACKENDS=metal OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=1 OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_STARTUP_TRACE=1 OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_METAL_FRAME_TRACE=1 OPENTOONZ_GRAPHICS_SMOKE_SECONDS=20 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=1 OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-metal-direct-internal-editing-context-4146
bash scripts/verify_graphics_app_smoke_artifacts.sh /private/tmp/opentoonz-graphics-app-smoke-metal-direct-internal-editing-context-4146 --require-direct-metal-frame metal
OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/tga_paint.tnz OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=internal-editing-context OPENTOONZ_GRAPHICS_SMOKE_BACKENDS=metal OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=1 OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_STARTUP_TRACE=1 OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_METAL_FRAME_TRACE=1 OPENTOONZ_GRAPHICS_SMOKE_SECONDS=20 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=1 OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-no-sceneviewer-glselect-4146
bash scripts/verify_graphics_app_smoke_artifacts.sh /private/tmp/opentoonz-graphics-app-smoke-no-sceneviewer-glselect-4146 --require-direct-metal-frame metal
OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/dwanko_run.tnz OPENTOONZ_GRAPHICS_SMOKE_ACTIONS=internal-preview-export OPENTOONZ_GRAPHICS_SMOKE_BACKENDS=metal OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=1 OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_STARTUP_TRACE=1 OPENTOONZ_GRAPHICS_SMOKE_FRAME=24 OPENTOONZ_GRAPHICS_SMOKE_SECONDS=25 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=1 OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0 bash scripts/macos/graphics-app-smoke.sh /private/tmp/opentoonz-graphics-app-smoke-preview-export-vector-4146
bash scripts/verify_graphics_app_smoke_artifacts.sh /private/tmp/opentoonz-graphics-app-smoke-preview-export-vector-4146 metal
nix develop path:. --command bash scripts/verify_macos_preview_export_probe.sh /private/tmp/opentoonz-preview-export-probe-4146-hardened
OPENTOONZ_CI_BUILD_LABEL=macos-arm64-4146-latest OPENTOONZ_CMAKE_EXTRA_ARGS=-DWITH_GRAPHICS_METAL=ON OPENTOONZ_BUILD_PARALLEL=3 scripts/macos/ci-build-summary.sh
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
verify-macos-preview-export-probe: ok artifacts=/private/tmp/opentoonz-preview-export-probe-4146-hardened
preview/export probe artifacts: OpenGL, Metal, legacy OpenGL, and diff PNGs are nonblank 16 x 12 RGBA images. The hardened verifier now runs four exact zero-difference checks: OpenGL active vs OpenGL legacy, Metal active vs OpenGL legacy, Metal active vs Metal legacy, and OpenGL legacy vs Metal legacy; each reported differing_pixels=0.
tcomposer scene export evidence refreshed: the packaged helper verifier rejects
single-color black exports with ImageMagick and records per-backend color,
maxima, and nonzero-pixel counts before byte-comparing OpenGL and Metal TIFF
outputs. After moving helper render-tree construction to the same
`buildSceneFx()` overload used by newer preview/render paths and bounding Ino
Fore/Back blend bboxes when a Fore input reports OpenToonz's infinite bbox
sentinel, the default gate now includes `doc/sample_data/dwanko_run.tnz` frame
24 and passes for four scenes with exact OpenGL/Metal TIFF equality.
graphics-modernization-lint: ok
graphics-modernization-lint regression guards: PlaneViewer draw-list
background/raster presentation, Style Editor non-OpenGL color wheel, and
ViewerDraw camera-mask/color-card draw-list overlays are now enforced.
Skeleton Tool selection fallback: CPU picking remains enforced for Skeleton
Tool 2D and 3D interactions, and the legacy `pick(e.m_pos)` OpenGL-selection
fallback has been removed. Skeleton Tool name-stack markers remain guarded so
normal drawing does not call `glPushName()` / `glPopName()` outside legacy
compatibility drawing passes.
verify-opengl-selection-compatibility: ok
graphics-modernization-lint smoke evidence guards: direct-Metal workflow smoke
must use doc/sample_data/tga_paint.tnz, require startup and direct-frame traces,
verify artifacts with --require-direct-metal-frame, and the manifest wrapper
must keep --require-screenshot for screenshot-enabled runs.
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
macOS workflow now runs verify_graphics_fixture_scenes.sh, the focused preview/export probe, the packaged preview-export app smoke, and the manifest-driven packaged app smoke with generated fixtures and screenshot comparison artifacts.
macOS workflow now verifies the packaged Qt runtime does not mix bundled and Nix-store Qt dylibs.
macOS workflow now runs a packaged direct-Metal frame smoke with OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=1, startup/direct-frame trace gates, --require-direct-metal-frame artifact verification, and uploads its artifacts.
Metal shader source resource present; metallib build skipped because the Metal toolchain is unavailable
Metal resource summary: status=source-only-toolchain-unavailable repo_source_present=1 source_present=1 repo_source_bytes=20675 source_bytes=20675 repo_source_sha256=74adaa1c3e0c4275f9c21717bf65d6ec22deeef202cca0a55328bef3c477533f source_sha256=74adaa1c3e0c4275f9c21717bf65d6ec22deeef202cca0a55328bef3c477533f library_present=0 library_bytes=0 metallib_tool=.
Checked 281 Mach-O files for arm64.
graphics-app-smoke: backend=opengl passed
graphics-app-smoke: backend=metal passed
graphics-app-smoke scene argument check: backend=opengl passed with OPENTOONZ_GRAPHICS_SMOKE_SCENE=doc/sample_data/dwanko_run.tnz and screenshot capture disabled.
graphics-app-smoke sample scene: packaged app loaded doc/sample_data/dwanko_run.tnz under opengl and metal with screenshot capture disabled.
graphics-app-smoke sample scene screenshots: packaged app loaded doc/sample_data/dwanko_run.tnz under opengl and metal with 3456 x 2234 PNG screenshots.
verify-png-nonblank: ok for opengl and metal sample-scene screenshots.
verify-png-match sample-scene screenshots: differing_pixels=3490 differing_ratio=0.00045203 max_channel_delta=227 mean_abs_channel_delta=0.05153296
verify-graphics-app-smoke-artifacts: ok backends=opengl metal artifacts=/private/tmp/opentoonz-graphics-app-smoke-sample-scene-4146-screenshots
graphics-app-smoke-manifest: ok scenes=13 artifacts=/private/tmp/opentoonz-graphics-app-smoke-manifest-4146-vector-row-metal
manifest smoke covered all 13 current golden rows under Metal with screenshots disabled, including committed raster/style/onion samples, committed vector/camera/FX/export sample rows, the generated mesh-column fixture, the generated sub-xsheet fixture, and four generated shader-effect scene fixtures.
manifest smoke screenshot gate: when OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT is enabled, graphics_app_smoke_manifest.sh now requires screenshot evidence for every scene/backend artifact.
manifest smoke no-screenshot compatibility: the same wrapper still passes when OPENTOONZ_GRAPHICS_SMOKE_SCREENSHOT=0, proving the stricter gate only applies to screenshot-enabled smokes.
verify-graphics-app-smoke-artifacts --require-screenshot: existing OpenGL/Metal sample-scene screenshot artifacts pass the stricter screenshot evidence gate.
graphics-app-smoke basic-viewer system input: after the local environment was
Automation/Accessibility-authorized, `basic-viewer` passed for both OpenGL and
Metal against `doc/sample_data/tga_paint.tnz`. The action now sends a real
System Events center-window mouse click followed by
space/space/right/left/plus/minus keystrokes, and `actions.txt` records
`system_mouse=center-window-click`,
`system_keyboard=space,space,right,left,plus,minus`, and `result=ok` for both
backends. Artifact verification passed at
`/private/tmp/opentoonz-basic-viewer-system-key-mouse-metadata-4146`.
graphics-app-smoke internal drawing gesture: `scripts/verify_macos_drawing_gesture_app_smoke.sh`
passed for both OpenGL and Metal at
`/private/tmp/opentoonz-drawing-gesture-app-smoke-4146e`. The trace shows the
Brush tool gesture delivered press/move/move/release events, changed the
current Toonz CM raster from `non_empty=15087` to `non_empty=15714` under
OpenGL and `non_empty=15689` under Metal, and wrote
`main_internal_drawing_changed changed=1` for both backends. The Metal trace
also includes repeated direct frames with `direct_content=1` and
`compatibility_snapshot=0`.
graphics-app-smoke Metal internal basic-viewer actions: a Metal-only
`internal-basic-viewer` run for `doc/sample_data/tga_paint.tnz` passed without
System Events. The app reached `main_after_load_scene`, emitted repeated Metal
viewer frames with `metal_scene_content nodes=1 texture_quads=1 full_coverage=1
reason=ok` and `metal_frame direct_content=1`, ran the internal reset/zoom/frame
scrub sequence, and wrote `main_internal_actions_done`. The artifact verifier
passed for the Metal backend. Artifacts:
`/private/tmp/opentoonz-graphics-app-smoke-metal-internal-basic-viewer-4146`.
graphics-app-smoke direct Metal internal basic-viewer actions: the stricter
direct-only smoke also passed with startup trace, direct-frame trace, and
internal viewer actions enabled. Artifact verification passed with
`--require-direct-metal-frame`, proving `direct_content=1`,
`compatibility_snapshot=0`, and `main_internal_actions_done` in the same
Metal run. Artifacts:
`/private/tmp/opentoonz-graphics-app-smoke-metal-direct-internal-basic-viewer-4146`.
graphics-app-smoke direct Metal internal editing-context actions: the stronger
direct-only smoke passed with startup trace, direct-frame trace, and internal
tool switching enabled. Artifact verification passed with
`--require-direct-metal-frame`, proving `direct_content=1`,
`compatibility_snapshot=0`, `main_internal_actions_done`, and tool-switch traces
for `T_Edit`, `T_Selection`, `T_Brush`, `T_Geometric`, `T_Skeleton`, and
`T_Hand` in the same Metal run. Artifacts:
`/private/tmp/opentoonz-graphics-app-smoke-metal-direct-internal-editing-context-4146`.
graphics-app-smoke internal preview-export action: the
`internal-preview-export` action now reaches `main_internal_preview_frame_ready`
and writes nonblank `preview-export.png` artifacts for both OpenGL and Metal.
The smoke blank detector now scans the full preview image/raster instead of a
coarse grid, so sparse but valid frame content is no longer mislabeled as
blank. Against the generated TIFF-backed `tcomposer-color-card` scene, both
backends saved `1920 x 1080` PNGs from `source=preview_raster`, and exact PNG
comparison reported `differing_pixels=0`. Artifact verification also passed
with `--require-preview-raster-export`. Artifacts:
`/private/tmp/opentoonz-graphics-app-smoke-preview-export-color-card-fullscan-4146`.
The focused wrapper `scripts/verify_macos_preview_export_app_smoke.sh` was then
validated at `/private/tmp/opentoonz-preview-export-app-smoke-final-4146` and
reported the same exact OpenGL/Metal PNG match.
The committed `doc/sample_data/dwanko_run.tnz` frame 24 preview/export smoke
now exports from `source=preview_raster` for both OpenGL and Metal and exact
PNG comparison reports zero differing pixels. Artifacts:
`/private/tmp/opentoonz-preview-export-dwanko-opengl-metal-4146`.
bundled Qt runtime verifier: ok after rerunning package-nix-app; the previous stale bundle mixed Nix-store Qt references with bundled Qt dylibs.
bundled GNU iconv verifier: ok; `libidn2.0.dylib` imports `_libiconv` from bundled `libgnuiconv.2.dylib`, preventing the observed dyld "Symbol not found: _libiconv" launch crash.
packaged helper runtime paths: tcomposer no longer aborts at startup with missing TOONZROOT after the TEnv portable path fix; it initializes plugins and loads sample scenes. The default generated TIFF-backed tcomposer fixture, committed cleanup TIFF-sequence sample, committed `tga_paint.tnz` TLV sample, and committed `dwanko_run.tnz` FX/vector sample now pass packaged OpenGL/Metal helper export verification with nonblack output and exact byte equality.
packaged helper runtime paths: tconverter was also checked as a smaller export path; it no longer needs the macOS `.app` path stripping bug, but the sample fixture filenames are rejected by its level-existence rules, so it is not yet a usable golden export verifier.
packaged app verifier after helper rebuild: package-nix-app restored bundled Qt linkage and verify-bundled-qt-runtime passed.
tcomposer render-tree diagnostics: `OPENTOONZ_TCOMPOSER_DEBUG_LEVELS=1` now prints the selected frame, `whichLevels`, camera resolution, xsheet bbox, terminal FX bboxes, built render-FX bbox, output FX input tree diagnostics, and Ino Fore/Back blend bbox diagnostics. The patched helper now builds the frame FX through the newer `buildSceneFx()` overload. `doc/sample_data/tga_paint.tnz` frame 1 and `doc/sample_data/dwanko_run.tnz` frame 24 both pass nonblack exact OpenGL/Metal helper export verification; the `dwanko_run.tnz` fix keeps the valid bounded Back branch when the Fore Raylit branch reports OpenToonz's infinite bbox sentinel.
graphics-app-smoke direct Metal GNU iconv preflight: packaged app loaded doc/sample_data/dwanko_run.tnz with OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=1, and artifact verification passed with --require-direct-metal after the hardened bundle verifier. This is historical launch-plus-scene-load evidence; the current CI direct-frame gate below uses doc/sample_data/tga_paint.tnz and --require-direct-metal-frame.
graphics-app-smoke direct Metal sample scene: packaged app loaded doc/sample_data/dwanko_run.tnz with OPENTOONZ_GRAPHICS_BACKEND=metal and OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=1; screenshot capture was disabled. This is historical launch-plus-scene-load evidence.
verify-graphics-app-smoke-artifacts direct Metal sample scene: ok backends=metal artifacts=/private/tmp/opentoonz-graphics-app-smoke-direct-metal-fixed-4146 with --require-direct-metal. This predates the stricter direct-frame gate.
graphics-app-smoke Qt runtime preflight: direct-Metal smoke now writes preflight.txt with verify-bundled-qt-runtime: ok before launching OpenToonz, and the direct-Metal artifact verifier requires that metadata.
strict direct-Metal frame diagnostic: `--require-direct-metal-frame` is now available and fails the current local direct-Metal scene smoke because neither the app log nor `graphics-smoke-trace.txt` contains `direct_content=1 compatibility_snapshot=0`; this exposes that the previous direct-Metal smoke proved launch-plus-scene-load metadata, not a painted direct Metal scene-viewer frame. The latest harness also runs with an isolated copied profile, `currentRoom.txt=Drawing`, and `lazyLoadRooms=false`. A 30-second unattended smoke still produced no `main_*` or `sceneviewer_*` trace entries, so the local harness is not reaching `MainWindow` construction before termination in this environment. `OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_STARTUP_TRACE=1` now turns that condition into a direct smoke failure instead of a post-hoc artifact finding.
startup trace gate validation: `OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_STARTUP_TRACE=1` with a 10-second direct-Metal scene smoke failed with `did not reach main window startup trace`, leaving `environment.txt` and `OpenToonz.log` artifacts under `/private/tmp/opentoonz-graphics-app-smoke-startup-trace-gate-4146`. The log still only contains the macOS pasteboard/HIServices startup diagnostics, confirming the gate catches this pre-`MainWindow` stall.
startup crash root cause: early `main_*` trace points narrowed the sandboxed GUI hang to `QApplication` construction and the escalated GUI crash to `MainWindow::defineActions()`. The crash report at `Crash-20260523-193049.log` showed `SIGSEGV` in `QOpenGLFramebufferObject::hasOpenGLFramebufferObjects()` while building menu actions. `MainWindow` now avoids that legacy Qt/OpenGL FBO probe when the requested backend is Metal; OpenGL keeps the existing capability check. After rebuilding and packaging, the escalated direct-Metal smoke reached `main_after_main_window` and `sceneviewer_constructed`, and `verify_graphics_app_smoke_artifacts.sh /private/tmp/opentoonz-graphics-app-smoke-fbo-fix-4146 --require-direct-metal` passed. The stricter `--require-direct-metal-frame` gate still fails because no painted direct-Metal frame diagnostic is emitted in that unattended run.
direct Metal frame gate follow-up: `OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_METAL_FRAME_TRACE=1` now makes `graphics-app-smoke.sh` wait for a direct Metal frame trace instead of terminating immediately after `main_after_main_window`. With `doc/sample_data/tga_paint.tnz`, the app reaches `main_after_show`, `main_after_load_scene`, and repeated `sceneviewer_paint_gl` entries, but still times out because each frame reports `direct_content=0 compatibility_snapshot=1`. Added `metal_scene_content` diagnostics show the loaded scene reaches `nodes=1 texture_quads=0 full_coverage=0`; attempts to precompose palette, grayscale, generic raster nodes, and allow transparency/color-mask viewer states have not yet produced a direct texture quad in the packaged app. Latest failing artifact: `/private/tmp/opentoonz-graphics-app-smoke-framegate-colormask-4146`.
direct Metal frame gate resolved for simple raster sample: the smoke profile now forces `ViewBBoxToggleAction1 "0"` in its isolated TEnv file, and the direct raster append path emits texture quads even when bbox mode is present but marks coverage partial so compatibility can still supply the overlay. With `doc/sample_data/tga_paint.tnz`, the packaged app smoke now passes with `OPENTOONZ_GRAPHICS_METAL_DIRECT_ONLY=1`, `OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_STARTUP_TRACE=1`, `OPENTOONZ_GRAPHICS_SMOKE_REQUIRE_METAL_FRAME_TRACE=1`, and screenshots disabled. `scripts/verify_graphics_app_smoke_artifacts.sh /private/tmp/opentoonz-graphics-app-smoke-framegate-clean-viewer-4146 --require-direct-metal-frame` passed. The trace includes `metal_scene_content nodes=1 texture_quads=1 full_coverage=1 reason=ok` and `metal_frame direct_content=1 compatibility_snapshot=0`, proving a real direct Metal scene-viewer frame for the committed simple raster sample.
startup FBO probe hardening: `MainWindow::defineActions()` now skips `QOpenGLFramebufferObject::hasOpenGLFramebufferObjects()` both for requested Metal and when no `QOpenGLContext` is current. This fixes the packaged OpenGL startup crash seen while building menu actions and preserves the Metal skip. Final local evidence: `/private/tmp/opentoonz-graphics-app-smoke-final-opengl-fbo-4146` passed artifact verification with `mainwindow_fbo_probe_skip reason=no_current_context`, `main_after_main_window`, `main_smoke_frame_set frame=1 index=0`, and `main_internal_actions_done`; `/private/tmp/opentoonz-graphics-app-smoke-final-metal-fbo-4146` passed `--require-direct-metal-frame` with `mainwindow_fbo_probe_skip backend=metal`, direct Metal frame diagnostics, all internal editing tool traces, requested frame trace, and internal action completion.
sub-xsheet fixture loader fix: the generated `sub_xsheet_basic.tnz` previously declared its childLevel before the TLV level referenced inside the child xsheet, which made `IoCmd::loadScene` throw and caused the manifest smoke to time out waiting for the requested frame trace. The generator now declares the sample TLV level before the childLevel, and `scripts/verify_graphics_fixture_scenes.sh` enforces that ordering. Direct Metal smoke of the repaired fixture passed at `/private/tmp/opentoonz-graphics-app-smoke-subfix-metal`; the full Metal manifest smoke passed all 13 rows at `/private/tmp/opentoonz-graphics-app-smoke-manifest-4146-vector-row-metal`.
direct Metal screenshot smoke: after fixing the duplicate-Qt runtime issue, the screenshot-enabled direct-Metal smoke reached screencapture and failed with `could not create image from display`; keep screenshot capture disabled for the direct-Metal smoke until a capture-capable manual session or runner is available.
internal screenshot smoke: the in-process SceneViewer screenshot path now writes temporary files with an explicit PNG format and falls back from `grabFramebuffer()` to `QWidget::grab()` when framebuffer readback is unavailable or blank. Focused `doc/sample_data/dwanko_run.tnz` frame 24 smoke passed for OpenGL and Metal at `/private/tmp/opentoonz-graphics-app-smoke-vector-internal-screenshot-4146-pngfmt`, and artifact verification with `--require-screenshot` reported exact screenshot equality. Full 13-row manifest smoke with screenshots enabled also passed at `/private/tmp/opentoonz-graphics-app-smoke-manifest-4146-internal-screenshots`; every row produced nonblank OpenGL and Metal screenshots and exact OpenGL/Metal equality for the accepted internal captures.
graphics-app-smoke shutdown hardening: bounded Apple Event quit and ps-denial fallback were validated by the manifest smoke after two earlier hung smoke attempts exposed those edge cases.
graphics-app-smoke: artifacts: /private/tmp/opentoonz-graphics-app-smoke-4146-combined
graphics-app-smoke: artifacts: /private/tmp/opentoonz-graphics-app-smoke-4146-screenshots
graphics-app-smoke: artifacts: /private/tmp/opentoonz-graphics-app-smoke-sample-scene-4146-bundled
opengl screenshot.png: PNG image data, 3456 x 2234, 8-bit/color RGBA, non-interlaced
metal screenshot.png: PNG image data, 3456 x 2234, 8-bit/color RGBA, non-interlaced
macos-arm64-4146-latest build summary: status=0 elapsed_seconds=13 WITH_GRAPHICS_METAL=ON total_warnings=0 apple_opengl_deprecation_warnings=0 qt_qgl_warning_lines=0 qt_qopengl_deprecation_warning_lines=0
ccache: hits=30549/36941 (82.70%)
SceneViewer Metal picking guard build: OpenToonz target linked successfully.
graphics-app-smoke shutdown hardening: script syntax check passed after adding
process-state checks that avoid escalating an already-exited child process.
Latest OpenToonz build check: ninja reported no work to do.
Skeleton Tool Metal selection gate build: tnztools rebuilt and OpenToonz linked
successfully.
Skeleton Tool CPU picking: `canUseCpuSkeletonPicking()` now routes all Skeleton
Tool picks through `pickCpu()` when a viewer is available. The OpenGL
selection fallback has been removed for OpenGL-requested 3D views as well, and
graphics-modernization-lint now rejects both the old
`viewer && !viewer->is3DView()` CPU-picking guard and any `pick(e.m_pos)`
fallback.
Skeleton Tool name-stack guard: `drawIKJoint()`, `drawJoint()`, hook balloons,
and magic-link balloons now call `glPushName()` / `glPopName()` only while
`isPicking()` is true. Drawing-browser and main-gadget pick names were already
inside picking-only branches. The affected `tnztools` library and `OpenToonz`
target rebuilt successfully after the guard.
SceneViewer GL_SELECT removal: `SceneViewer::pick()` no longer enters
OpenGL selection mode, and Skeleton Tool no longer calls the generic
`pick(e.m_pos)` fallback. `scripts/verify_opengl_selection_compatibility.sh`
now requires SceneViewer selection-mode APIs to stay removed and reports the
remaining OpenGL selection markers only in Skeleton Tool compatibility drawing
code. `tnztools` and `OpenToonz` rebuilt successfully, packaging passed bundled
Qt runtime verification, and the direct Metal internal editing-context smoke
passed at `/private/tmp/opentoonz-graphics-app-smoke-no-sceneviewer-glselect-4146`
with `--require-direct-metal-frame`.
```

Additional local validation from the current continuation:

```sh
bash scripts/graphics_inventory.sh
bash scripts/verify_sample_data.sh
bash scripts/verify_golden_scene_manifest.sh --require-complete
bash scripts/verify_graphics_fixture_scenes.sh /private/tmp/opentoonz-graphics-fixtures-4146-continue
bash scripts/verify_opengl_selection_compatibility.sh
bash scripts/graphics_modernization_lint.sh
git diff --check
bash scripts/macos/verify-bundled-qt-runtime.sh toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app
bash scripts/macos/assert-arm64-bundle.sh
OPENTOONZ_METAL_RESOURCE_SUMMARY=/private/tmp/opentoonz-metal-resources-4146-continue-summary.txt bash scripts/macos/verify-metal-resources.sh toonz/build/nix-relwithdebinfo/toonz/OpenToonz.app
nix develop path:. --command cmake --build toonz/build/nix-relwithdebinfo --target OpenToonz --parallel 3
nix develop path:. --command bash scripts/verify_metal_probe_images.sh /private/tmp/opentoonz-metal-probe-images-4146-continue
nix develop path:. --command bash scripts/verify_macos_offscreen_style_probes.sh
nix develop path:. --command bash scripts/verify_macos_preview_export_probe.sh /private/tmp/opentoonz-preview-export-probe-4146-continue
nix develop path:. --command bash scripts/graphics_shaderfx_compare.sh /private/tmp/opentoonz-shaderfx-compare-4146-continue
bash scripts/verify_shaderfx_scene_fixtures.sh /private/tmp/opentoonz-shaderfx-compare-4146-continue
OPENTOONZ_GRAPHICS_SMOKE_SECONDS=25 OPENTOONZ_GRAPHICS_SMOKE_COOLDOWN_SECONDS=1 OPENTOONZ_GRAPHICS_SMOKE_BACKENDS='opengl metal' bash scripts/verify_macos_drawing_gesture_app_smoke.sh /private/tmp/opentoonz-drawing-gesture-app-smoke-4146e
```

All commands above passed. The local Metal resource verifier recorded bundled
shader source parity but skipped compiled `.metallib` validation because the
local command-line Metal toolchain is unavailable; strict `.metallib` evidence
still comes from Apple-hosted macOS CI or another machine with `metal` and
`metallib`.

The fresh Metal-enabled build linked:

```text
toonz/OpenToonz.app/Contents/MacOS/OpenToonz
tnzcore/tgraphics_metal_probe
stdfx/shaderfx_metal_probe
```

## Fresh Graphics Inventory

```text
all graphics markers               files=  106 matches=  2171
Qt legacy QGL                      files=    0 matches=     0
Qt QOpenGL                         files=   30 matches=   212
GLU                                files=    4 matches=    54
GLEW or GLUT                       files=   10 matches=    30
fixed-function drawing             files=   63 matches=  1411
fixed-function matrix              files=   55 matches=   445
glDrawPixels                       files=    0 matches=     0
OpenGL selection                   files=    2 matches=    19
```

## Default Backend Decision

OpenGL remains the default macOS backend. The current evidence supports keeping
Metal opt-in: direct Metal now has packaged viewer/tool-context smoke for a
simple raster sample, focused style/offscreen probes, shader-effect probes, a
hardened preview/export raster-placement probe, and a generated-scene
Previewer-raster export smoke with exact OpenGL/Metal PNG equality. The
packaged `tcomposer` default scene-export check now rejects blank exports and
passes for the generated color-card fixture, the committed cleanup sample, the
committed `tga_paint.tnz` TLV sample, and the committed `dwanko_run.tnz`
FX/vector sample with nonblack exact OpenGL/Metal output.
Full manual workflow parity, system-level input routing, broader sample
preview/export, and locally produced release `.metallib` packaging are not yet
proven.

## Current Completion Audit

Fresh Apple-hosted macOS CI run `26379595473` on
`db46c36b83176a9c45933201ff81f0b6b77d99a2` passed both matrix legs. The Metal
job passed build, package, arm64 bundle validation, Metal resource validation,
packaged `tcomposer` scene export, packaged preview-export app smoke, packaged
Style Editor smoke, packaged viewer-input smoke, packaged drawing-gesture
smoke, packaged manifest graphics smoke, packaged direct Metal scene smoke,
DMG creation, CI summary upload, Metal probe artifact upload, and artifact
upload. The OpenGL-fallback job passed build, package, arm64 bundle validation,
DMG creation, and summary/artifact upload.

The downloaded artifacts at
`/private/tmp/opentoonz-ci-artifacts-26379595473` passed:

```sh
bash scripts/verify_macos_ci_artifacts.sh /private/tmp/opentoonz-ci-artifacts-26379595473
```

The CI summaries report:

```text
macos-arm64-opengl-fallback: status=0 elapsed_seconds=119 WITH_GRAPHICS_METAL=OFF total_warnings=144 apple_opengl_deprecation_warnings=0 qt_qgl_warning_lines=0 qt_qopengl_deprecation_warning_lines=0
macos-arm64-metal: status=0 elapsed_seconds=95 WITH_GRAPHICS_METAL=ON total_warnings=144 apple_opengl_deprecation_warnings=0 qt_qgl_warning_lines=0 qt_qopengl_deprecation_warning_lines=0
```

Automated coverage now proves the committed and generated golden-scene set can
exercise Metal build/package/runtime paths for normal viewer loading,
direct-Metal scene frames, internal viewer input, drawing gestures, Style
Editor palette updates, preview/export, shader-effect probes, offscreen/style
probes, and packaged helper rendering while keeping OpenGL fallback available.
The generated color-card and committed `dwanko_run.tnz` preview exports
exact-match OpenGL and Metal PNG output. The committed `tga_paint.tnz` TLV
preview-export smoke validates traced nonblank OpenGL and Metal output without
exact PNG comparison because that case can use a viewer-framebuffer fallback
with slightly different viewport dimensions.
Manifest screenshot comparison now also allows small backend-specific viewport
extent drift while still requiring nonblank screenshots and bounded OpenGL/Metal
pixel differences over the shared extent.

## Remaining Release/Default-Gate Notes

- Metal remains opt-in and OpenGL remains the default macOS backend. This is an
  explicit product decision, not a build failure.
- Strict compiled `.metallib` validation is still conditional on a machine or
  runner with Apple's `metal` and `metallib` tools. Current push CI validates
  bundled `.metal` source parity and accepts `source-only-toolchain-unavailable`
  when those tools are absent; the dispatch `strict_metallib=true` gate now
  forces configure-time and package-time `.metallib` validation for
  release/default readiness.
- Release signing and notarization are skipped in public CI because signing
  secrets are absent. Run the same workflow with release credentials before
  shipping release artifacts.
- Broader human-driven GUI workflows should still be exercised before changing
  the default backend. A dispatch-only system viewer smoke is now available for
  Accessibility/Automation-authorized runners, and the internal Qt-event app
  smokes cover viewer input, drawing, style editing, preview/export, direct
  Metal frames, and the manifest scene set in ordinary CI.

## Final Acceptance Audit

The goal prompt's final acceptance criteria are not yet fully complete, even
though the automated macOS Metal CI gate is green.

| Criterion | Current evidence | Status |
| --- | --- | --- |
| macOS OpenToonz can run normal viewer, editing, preview, and render workflows through Metal | CI covers direct Metal scene frames, internal viewer input, drawing gestures, Style Editor updates, preview/export, packaged `tcomposer`, manifest screenshots, shader-effect probes, and offscreen/style probes. A dispatch-only `system_gui_smoke` gate now exists for Accessibility-authorized system mouse/keyboard evidence, but broader human-driven GUI workflow evidence still remains a release/default gate until that gate is run and reviewed. | Partially proven |
| OpenGL fallback remains available until explicitly retired | OpenGL remains the default backend, `WITH_GRAPHICS_METAL=OFF` builds in CI, and explicit `OPENTOONZ_GRAPHICS_BACKEND=opengl` smoke coverage remains available. | Proven |
| Golden scene output from Metal matches OpenGL baseline within documented tolerance | Generated and committed sample rows cover raster, TLV, FX/vector, cleanup, sub-xsheet, mesh/skeleton, camera/overlay, and shader-effect cases through exact export checks, nonblank checks, and bounded screenshot comparison. | Proven for automated fixture set |
| Metal backend is covered by macOS arm64 CI build and package validation | Apple-hosted macOS CI run `26379595473` passed the Metal and OpenGL-fallback matrix legs, and `scripts/verify_macos_ci_artifacts.sh /private/tmp/opentoonz-ci-artifacts-26379595473` passed on downloaded artifacts. | Proven |
| Metal shaders and resources are included in the app bundle | CI verifies bundled `.metal` source parity and records Metal resource summary status. A dispatch-only `strict_metallib=true` gate now forces configure-time and package-time compiled `.metallib` validation, but strict evidence still requires running that gate on a runner or machine with both `metal` and `metallib`. | Source proven; strict `.metallib` gate added but pending run |
| macOS warning counts no longer include routine Qt `QGL*` or Apple OpenGL deprecation noise in the default backend | CI summaries for run `26379595473` report `apple_opengl_deprecation_warnings=0`, `qt_qgl_warning_lines=0`, and `qt_qopengl_deprecation_warning_lines=0` for both matrix legs. | Proven |
| Build-time impact is measured and documented | CI summaries record elapsed seconds, warning counts, and ccache summaries for both matrix legs. | Proven |
| User-facing backend selection and troubleshooting are documented | `doc/how_to_verify_macos_graphics.md`, `doc/how_to_build_macosx.md`, and `doc/macos_graphics_default_backend_decision.md` document backend selection, direct-Metal smoke mode, verification commands, and the OpenGL-default decision. | Proven |

## Next Recommendation

Keep Metal opt-in for now. The next useful step is a release/default readiness
pass on a signing-capable macOS machine with the Metal command-line tools and
Accessibility/Automation permissions available: run strict `.metallib`
verification with dispatch `strict_metallib=true`, signing/notarization, the
dispatch `system_gui_smoke=true` gate, and a short manual GUI walkthrough over
the same golden-scene set.
