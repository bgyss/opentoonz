# Codex Goal Prompt: Begin The OpenToonz Rust Migration Safely

Prepared: July 26, 2026

Survey baseline: `6f87dd4535de01cfd4d8fa84cd4ceedb5c7492bd`

## How To Use This Prompt

Use this prompt for the first implementation phase after the Qt 6 and
Metal/Vulkan predecessor gates are complete. It is deliberately narrower than
“rewrite OpenToonz in Rust.” Its job is to establish a trustworthy mixed
C++/Rust build, oracle, bridge, and framework evidence before production
behavior moves.

If the predecessor gates are not complete, limit the session to read-only
refresh, fixtures, documentation, and isolated non-shipping experiments.
Do not change default product behavior.

After this bootstrap goal is accepted, create a new bounded goal for one
profiled production slice using `doc/rust_porting_workflow.md`. Do not keep
expanding this prompt until it means the whole application.

## Goal

Establish the first supportable Rust migration lane in OpenToonz while keeping
the C++/Qt 6 application authoritative and behaviorally unchanged.

Deliver:

1. a pinned, reproducible Rust workspace integrated into Nix, mise, CMake, and
   supported packages;
2. a versioned C++/Rust oracle and comparison-report foundation;
3. one non-Qt CXX bridge and one CXX-Qt QObject/model bridge that prove
   lifetime, thread, error, cancellation, shutdown, and package behavior;
4. an isolated evaluation of official Qt Bridge for Rust against OpenToonz's
   Qt Quick/QML and platform needs;
5. an isolated offscreen `wgpu` backend probe on Metal, Vulkan, and the Windows
   release backend;
6. a dated evidence record and a recommendation for the first production Rust
   slice.

This goal does not port scene mutation, tools, FX, file writers, or the shipping
viewer renderer. It builds the proof system needed to port them safely.

## Read These First

1. `AGENTS.md`
2. `doc/rust_migration_study.md`
3. `doc/rust_porting_workflow.md`
4. `doc/qt6_migration_goal_prompt.md`
5. `doc/qt6_remaining_work_and_manual_verification.md`
6. the latest record in `doc/qt6_port_progress/`
7. the completed Metal/Vulkan migration contract and latest evidence record
8. `doc/how_to_build_nix_mise.md`
9. `toonz/sources/CMakeLists.txt`
10. `toonz/sources/CMakePresets.json`
11. `toonz/sources/tnzcore/CMakeLists.txt`
12. `toonz/sources/toonzlib/CMakeLists.txt`
13. `toonz/sources/toonzqt/CMakeLists.txt`
14. `toonz/sources/toonz/CMakeLists.txt`
15. `nix/opentoonz-env.nix`
16. `mise.toml`
17. the platform packaging workflows

Also inspect:

- `toonz/sources/include/tsmartpointer.h`
- `toonz/sources/include/tpersist.h`
- `toonz/sources/include/toonz/toonzscene.h`
- `toonz/sources/include/toonz/txsheet.h`
- `toonz/sources/include/trasterfx.h`
- `toonz/sources/include/trenderer.h`
- the existing plugin headers and samples used by the build

Refresh current external framework documentation before pinning dependencies.
The study's links are starting points, not a license to inherit stale versions.

## Predecessor Gates

Record each gate as passed, failed, unsupported, or pending. Pending is not
passed.

### `RUST-PRQ-01`: Qt 6 release completion

Require:

- all P0/P1 Qt 6 requirements accepted or explicitly waived;
- same-commit supported packages;
- real workflow, input, multimedia, translation, and clean-package evidence;
- stable Qt minimum/release/forward policy;
- a retained C++/Qt 6 package baseline.

### `RUST-PRQ-02`: graphics migration completion

Require:

- OpenGL-to-Metal/Vulkan work accepted on supported platforms;
- backend-neutral render target/resource/command contract;
- named render corpus with expected output;
- device-loss, resize, DPI, color, alpha, and shader failure behavior;
- performance and memory baselines;
- exact backend, GPU, driver, shader, and package evidence;
- no unresolved requirement that new Rust renderer code call legacy OpenGL.

### `RUST-PRQ-03`: oracle baseline

Require:

- exact source commit;
- exact package artifacts and hashes;
- fixture/corpus revision;
- supported platform/hardware matrix;
- list of accepted incompatibilities/waivers;
- artifact retention location.

### `RUST-PRQ-04`: repository state

Require:

- current branch/worktree and dirty state recorded;
- user changes preserved;
- live relevant branches and active renderer work identified;
- no production Rust implementation already exists under another contract.

If a predecessor gate fails, update the evidence record and stop before
production integration. Isolated experiments may continue only if they do not
change default builds or packages.

## Non-Negotiable Architecture

- No big-bang rewrite.
- Qt 6 remains the GUI framework.
- Existing Qt Widgets remain C++ during the bootstrap.
- Official Qt Bridge for Rust is evaluated for new Qt Quick/QML surfaces, not
  misrepresented as a QWidget binding.
- CXX is the default non-Qt C++/Rust bridge.
- CXX-Qt is the transition bridge for Qt QObject/model integration.
- A versioned C ABI is reserved for plugins/process boundaries.
- `wgpu` is the default Rust cross-platform graphics abstraction.
- Rust core/domain crates do not depend on Qt, QRhi, QWidget, native window
  handles, or CXX-Qt.
- QRhi private APIs do not become the Rust renderer foundation.
- Direct `ash` or `objc2-metal` code requires a documented `wgpu` gap and stays
  behind a backend-neutral trait.
- CMake remains the top-level product/package build during the transition;
  Cargo owns the Rust workspace.
- All dependencies and the Rust toolchain are exactly pinned.
- The C++ application remains the correctness oracle.
- Passed, failed, unsupported, skipped, and pending are distinct.
- No release claim may rely only on compilation or a synthetic smoke.

## Required Outcome 0: Refresh And Freeze Evidence

Create:

```text
doc/rust_port_progress/
  README.md
  YYYY-MM-DD-bootstrap-baseline.md
```

The README defines document roles and points to the latest dated record. The
baseline record uses the evidence template from
`doc/rust_porting_workflow.md` and includes all predecessor gate results.

Do not copy the entire Qt 6 history. Link to authoritative records and capture
only the exact state on which Rust bootstrap work depends.

Exit gate:

- exact source and package baseline recorded;
- every predecessor gate classified;
- external framework observations timestamped;
- allowed implementation scope is explicit.

## Required Outcome 1: Add The Rust Build Lane

Create a workspace under `rust/` with the smallest useful crates:

```text
rust/
  Cargo.toml
  Cargo.lock
  crates/
    otz-core/
    otz-oracle/
    otz-bridge/
    otz-bridge-probe/
    otz-gpu-probe/
```

Responsibilities:

- `otz-core`: version types, stable IDs, small geometry/value DTOs, structured
  errors, diagnostics, no Qt;
- `otz-oracle`: versioned snapshot/report schema and canonicalization;
- `otz-bridge`: CXX and CXX-Qt bridge declarations/adapters only;
- `otz-bridge-probe`: non-shipping executable/test surface for bridge lifecycle
  and Qt integration;
- `otz-gpu-probe`: non-shipping offscreen `wgpu` render/readback probe.

Names may change if current crate conventions provide a better fit, but keep
responsibilities separate.

Add:

- `rust-toolchain.toml`;
- appropriate Cargo config for supported linkers/targets;
- Nix dependencies and shell exposure;
- mise tasks;
- CMake import through a pinned CXX-Qt/Corrosion integration or an equivalently
  documented target integration;
- formatting, Clippy, tests, dependency/license policy, and offline/reproducible
  build behavior;
- packaging rules only for artifacts linked into a product/probe target.

Do not fetch build dependencies dynamically from an unpinned branch during
ordinary configure. Follow the repository's vendoring/mirroring policy.

Desired task interface:

```sh
mise run rust-doctor
mise run rust-check
mise run rust-test
mise run rust-ffi-check
mise run rust-oracle
mise run rust-gpu-offscreen
```

Exit gate:

- workspace builds in the Nix/mise environment;
- supported platform CI builds it;
- default C++/Qt application behavior is unchanged;
- package/linker/runtime behavior is documented;
- no Qt dependency appears in `otz-core` or `otz-oracle`.

## Required Outcome 2: Versioned Oracle And Comparison Foundation

Define a versioned protocol for:

- run metadata;
- implementation identity;
- platform/toolchain/backend identity;
- fixture identity and hashes;
- canonical structured output;
- image artifact metadata;
- timing and memory;
- passed/failed/unsupported/skipped;
- mismatch details;
- artifact hashes.

Add a tiny, redistributable fixture set that does not depend on large LFS
assets. It should cover at least:

- core IDs/geometry/value serialization;
- canonical ordering and path normalization;
- one generated raster image and exact pixel statistics;
- malformed or unsupported input classification.

Add a minimal C++ oracle target or adapter that produces the same protocol for
the chosen tiny surface. Do not fake unimplemented capabilities. Emit
`unsupported` with a stable reason.

One command must produce:

```text
comparison/reports/<run-id>/
  report.json
  report.md
  artifacts/
```

Exit gate:

- deterministic repeat runs match;
- expected mismatch tests fail nonzero;
- unsupported/skipped do not masquerade as passes;
- paths are machine-neutral;
- report schema/version tests pass;
- C++ and Rust identities are retained.

## Required Outcome 3: Prove CXX And CXX-Qt Contracts

### Non-Qt CXX probe

Implement a small batch-oriented service using:

- opaque Rust ownership;
- fixed-width shared values;
- a success result and structured failure;
- deliberate invalid input;
- explicit create/use/destroy;
- panic containment test;
- repeated lifecycle and shutdown test.

Do not bind an arbitrary existing C++ class graph.

### CXX-Qt probe

Implement a Rust-backed QObject or model consumed by a small test-only Qt
surface in the existing build. It must exercise:

- properties, signals, slots, and model updates;
- GUI-thread delivery from Rust worker completion;
- progress and cancellation;
- object destruction while work is pending;
- application shutdown;
- ordered events;
- structured error projection;
- repeated create/destroy;
- Qt Test or equivalent focused verification.

Do not rewrite an existing OpenToonz panel in this outcome.

### Contract documentation

Add a checked-in bridge contract covering:

- ownership and allocation;
- opaque/shared values;
- error and panic/exception boundaries;
- thread affinity;
- cancellation;
- event ordering;
- shutdown;
- versioning;
- batch/performance expectations.

Exit gate:

- debug and release builds pass;
- sanitizer/diagnostic lane is run where supported;
- supported packages include and launch the probe as intended, or the probe is
  test-only with a proved linked equivalent;
- no leak, deadlock, cross-thread Qt access, or boundary unwind is observed;
- C++ default product behavior remains unchanged.

## Required Outcome 4: Evaluate Official Qt Bridge For Rust

Pin an exact `qtbridge` version/source in an isolated experimental crate or
sample. Do not add it to the production application target.

Exercise:

- Rust-backed QML object;
- editable list and table models;
- insert/remove/reset and selection;
- async load, progress, cancellation, and shutdown;
- translation/resource loading;
- deliberate re-entrant property/signal patterns;
- large model behavior;
- repeated QML component create/destroy;
- Qt Quick focus and shortcuts;
- packaging on Linux, Windows, and macOS arm64.

Record:

- upstream maturity and date;
- exact Qt/Rust/platform requirements;
- macOS experimental result;
- `Rc<RefCell<_>>` borrow/re-entrancy behavior;
- QML IDE/tooling limitations;
- CXX-Qt interoperability status;
- license/pre-release terms;
- packaging/signing/notarization;
- upgrade and fallback feasibility.

Decision states:

- `adopt-for-new-ui`;
- `continue-experiment`;
- `defer`;
- `reject-for-current-contract`.

Do not state that Qt Bridge can replace the existing QWidget UI unless upstream
scope and a project prototype prove that claim.

Exit gate:

- all supported platform results recorded;
- decision and rationale recorded;
- production domain crates remain bridge-independent;
- no production dependency was introduced without explicit approval.

## Required Outcome 5: Prove The `wgpu` Baseline

Create an offscreen, non-shipping probe that:

- selects and records the backend/adapter/device;
- renders a deterministic WGSL pattern into an owned texture;
- reads it back with explicit row alignment;
- writes an image and pixel-statistics record;
- validates orientation, channel order, alpha, and color convention;
- supports an expected mismatch test;
- handles no-adapter/unsupported capabilities explicitly;
- exercises device teardown and repeated initialization;
- reports timing and GPU limits/features.

Run:

- Metal on supported macOS;
- Vulkan on supported Linux;
- the selected Windows release backend, normally Direct3D 12;
- Vulkan on Windows as an additional lane if it is part of project policy.

Use `wgpu` and Naga as pinned dependencies. Do not integrate with the shipping
viewer, QRhi, or native window handles in this outcome. Do not add direct
`ash`/`objc2-metal` code.

Exit gate:

- image and metadata artifacts retained on all supported platforms;
- shader validation passes;
- backend failures are explicit;
- debug GPU validation is run where supported;
- toolchain and dependency upgrade policy recorded.

## Required Outcome 6: Select The First Production Slice

Profile and compare at least three candidate slices from
`doc/rust_migration_study.md`. Include:

- current call graph/boundary;
- Qt/platform/GPU/persistence coupling;
- fixture readiness;
- characterization effort;
- bridge frequency and data volume;
- user value and failure consequence;
- fallback feasibility;
- expected performance opportunity.

Select one deterministic, bounded slice that does not own Qt objects or scene
mutation. Good categories include:

- geometry/value logic;
- one scalar raster kernel family;
- hashing/cache-key logic;
- farm protocol/process logic.

Write the next copy-ready goal prompt in the dated progress record or a
dedicated stable prompt only after maintainer review. It must use the standard
slice workflow and name exact acceptance thresholds.

Exit gate:

- one slice selected from evidence;
- alternatives and rejection reasons recorded;
- required fixtures exist or have a bounded creation plan;
- no production code for the selected slice is implemented as part of this
  bootstrap goal.

## Validation

Run repository-native tasks introduced by the implementation. At minimum:

```sh
mise run doctor
mise run doctor-qt6
mise run rust-doctor
mise run rust-check
mise run rust-test
mise run rust-ffi-check
mise run rust-oracle
mise run rust-gpu-offscreen
```

Also run:

- the smallest Qt 6 configure/build target that links the bridge;
- the Qt 5 lane only if it still exists under the accepted predecessor policy;
- strict Qt 6/deprecation guards affected by build changes;
- supported platform package jobs;
- Markdown/path/privacy checks for authored docs;
- exact direct Cargo/CMake commands needed to diagnose any task failure.

Do not claim an unavailable platform passed. Record it as pending and keep the
goal incomplete unless an approved waiver changes the contract.

## Bootstrap Completion Criteria

This goal is complete only when:

1. every predecessor gate is passed or explicitly waived;
2. the Rust workspace/toolchain/dependencies are pinned;
3. Nix, mise, CMake, Cargo, CI, and packages agree on the build;
4. `otz-core` and oracle/domain code are Qt-free;
5. the versioned C++/Rust oracle produces deterministic JSON and Markdown
   reports;
6. passed/failed/unsupported/skipped are all tested;
7. CXX lifetime/error/panic contracts pass;
8. CXX-Qt queue/cancel/shutdown/model contracts pass;
9. official Qt Bridge for Rust has a same-date, cross-platform decision record;
10. offscreen `wgpu` evidence exists for every supported release backend;
11. no default application behavior moved to Rust;
12. the first production slice is selected from profiling and fixture evidence;
13. docs, commands, package results, artifacts, and blockers are complete;
14. no required rerun or artifact is still pending.

## Anti-Goals

- Do not translate `tnzcore`, `toonzlib`, the scene graph, or the GUI wholesale.
- Do not port a production subsystem in this bootstrap.
- Do not replace Qt.
- Do not rewrite Widgets as QML merely to use Qt Bridge.
- Do not make Qt Bridge, CXX-Qt, QRhi, or `wgpu` types part of core domain APIs.
- Do not share a mutable scene object across the bridge.
- Do not call FFI per pixel or per cell.
- Do not introduce two independently authoritative renderers without
  differential execution and a removal gate.
- Do not treat a successful build, triangle, or synthetic model test as product
  parity.
- Do not use unpinned dependency branches or wildcard crate versions.
- Do not weaken Qt 6 or renderer migration gates to start Rust sooner.

## Handoff

End the implementation turn with:

- files changed;
- exact commands and results;
- source, package, dependency, and toolchain versions;
- artifacts and hashes;
- predecessor and bootstrap requirement status;
- failed/unsupported/skipped/pending evidence;
- Qt Bridge adoption decision;
- `wgpu` backend result;
- selected first production slice;
- retrospective and the smallest next goal.
