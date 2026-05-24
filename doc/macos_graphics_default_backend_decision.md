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
  input, Style Editor palette updates, and app preview/export exact PNG
  comparisons for generated and committed TLV samples.
- `scripts/macos/ci-build-summary.sh` records elapsed build seconds, warning
  counts, `WITH_GRAPHICS_METAL`, and ccache summaries for each macOS matrix
  leg.
- `scripts/verify_macos_ci_artifacts.sh` defines the post-download audit for
  Apple-hosted macOS CI evidence, including both matrix build summaries,
  Metal resource summary status, direct Metal frame traces, app smoke traces,
  packaged `tcomposer` output statistics, and probe summaries.

## Remaining Gaps Before Switching Default

- System-level keyboard/mouse routing now has a focused
  Accessibility-authorized `basic-viewer` smoke for a committed raster sample;
  broader drawing/editing gesture workflows still need manual or scripted
  evidence.
- Broader user-driven preview/export workflow parity is not fully proven for
  vector/FX-heavy scenes.
- Apple-hosted CI run IDs and final logs for the expanded smoke matrix still
  need to be recorded after the current local gates are pushed.
- Strict compiled `.metallib` packaging still needs evidence from a runner or
  machine with Apple's command-line `metal` and `metallib` tools. The current
  GitHub-hosted runner can still prove bundled Metal source parity and records
  toolchain availability in the resource summary.
- The release artifact policy still signs/notarizes the OpenGL-fallback leg.

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
