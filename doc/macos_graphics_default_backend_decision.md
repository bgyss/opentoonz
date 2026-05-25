# macOS Graphics Default Backend Decision

Status: keep OpenGL as the default macOS graphics backend.

Decision date: 2026-05-24

## Decision

OpenGL remains the default backend for normal macOS OpenToonz launches. Metal
remains opt-in through `OPENTOONZ_GRAPHICS_BACKEND=metal` and Metal-enabled
builds remain explicit through `WITH_GRAPHICS_METAL=ON`.

## Evidence

- The source default still leaves `OPENTOONZ_GRAPHICS_BACKEND` unset for normal
  launches and `tgraphics` only selects Metal when that environment variable is
  set to `metal`.
- `WITH_GRAPHICS_METAL` defaults to `OFF` in CMake and the macOS CI matrix
  builds both `opengl-fallback` and `metal` legs.
- The Metal leg now has local and CI-wired evidence for direct simple raster
  scene-viewer frames, manifest screenshot smoke, style/offscreen probes,
  shader-effect probes, packaged `tcomposer` scene export, internal viewer
  input, drawing gestures, Style Editor palette updates, and app preview/export
  validation. The generated color-card fixture and committed `dwanko_run.tnz`
  FX/vector sample exact-match OpenGL/Metal preview-export PNGs; the committed
  `tga_paint.tnz` TLV sample validates traced nonblank exports for both
  backends without exact dimensions because it can use a viewer-framebuffer
  fallback.
- Apple-hosted macOS CI run `26379595473` on
  `db46c36b83176a9c45933201ff81f0b6b77d99a2` passed the OpenGL-fallback and
  Metal matrix legs. The Metal leg passed build, package, arm64 validation,
  Metal resource verification, packaged `tcomposer` export, preview export,
  Style Editor, viewer input, drawing gesture, manifest graphics, and direct
  Metal scene smokes. The run also verifies that the manifest screenshot
  comparison tolerates small backend-specific viewport extent drift while still
  checking nonblank output and bounded pixel differences.
- `scripts/macos/ci-build-summary.sh` records elapsed build seconds, warning
  counts, `WITH_GRAPHICS_METAL`, and ccache summaries for each macOS matrix
  leg.
- `scripts/verify_macos_ci_artifacts.sh` defines the post-download audit for
  Apple-hosted macOS CI evidence, including both matrix build summaries,
  Metal resource summary status, direct Metal frame traces, app smoke traces,
  packaged `tcomposer` output statistics, and probe summaries.

## Remaining Gaps Before Switching Default

- System-level keyboard/mouse routing still has less coverage than the internal
  Qt-event smokes. The CI gates now cover internal viewer input and drawing
  gestures, but broader user-driven GUI workflows should still be manually
  exercised before changing the default.
- Broader user-driven preview/export workflow parity is still less direct than
  the internal app-action and packaged helper gates, even though the current
  CI now covers generated, TLV, and FX/vector sample data.
- Strict compiled `.metallib` packaging still needs evidence from a runner or
  machine with Apple's command-line `metal` and `metallib` tools. The current
  GitHub-hosted runner can still prove bundled Metal source parity and records
  toolchain availability in the resource summary.
- Release signing and notarization are skipped in the public CI run because the
  signing secrets are absent; run the same workflow with release credentials
  before shipping a Metal-default build.

## Switch Criteria

Do not switch the macOS default backend to Metal until all of these are true:

- Normal viewer, editing, preview, and render workflows pass the Metal gates
  for the golden-scene set.
- OpenGL fallback remains available or a separate retirement plan has been
  approved.
- Apple-hosted macOS arm64 CI proves repeatable Metal build, package, arm64
  validation, shader-resource packaging, and app smoke results.
- Warning-count and build-time summaries are recorded for the default-backend
  change.
- User-facing backend selection and troubleshooting docs are current.
