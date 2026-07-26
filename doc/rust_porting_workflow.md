# OpenToonz Rust Porting Workflow

Prepared: July 26, 2026

## Purpose

This is the operating procedure for incremental C++-to-Rust migration work in
OpenToonz. It turns the architecture in `doc/rust_migration_study.md` into
repeatable, reviewable slices.

Use it only after the prerequisites in
`doc/rust_port_codex_goal_prompt.md` are met, except for explicitly isolated
toolchain and bridge experiments. It does not authorize work on the current Qt
6 or renderer migrations to be skipped or declared complete.

## Document Ownership

Keep migration information in four distinct layers:

| Document | Owns |
|---|---|
| `doc/rust_migration_study.md` | Stable architecture, framework choices, risks, and long-term sequence |
| `doc/rust_port_codex_goal_prompt.md` | Ordered implementation contract and acceptance gates |
| This document | Repeatable per-slice workflow, validation, and evidence format |
| Future `doc/rust_port_progress/YYYY-MM-DD-*.md` | Dated facts about exact commits, builds, packages, and remaining blockers |

Do not copy current status into the stable study. Do not turn an old progress
record into current evidence.

## Entry Gates

### Production substitution gate

Production Rust substitution may begin only when:

- the Qt 6 migration has a release-quality completion record;
- the Metal/Vulkan migration has a stable backend-neutral renderer contract;
- same-commit packages exist for all supported platforms;
- the C++ oracle commit and package artifacts are retained;
- a named scene, format, render, plugin, input, and hardware corpus exists;
- fallback and rollback policy is approved;
- the Rust architecture/bridge/toolchain spike has passed without changing
  default product behavior.

If one of these is absent, the allowed work is limited to documentation,
characterization, fixture creation, build-lane setup, and non-production
experiments.

### Per-slice gate

A candidate slice needs:

- a named owner;
- one primary subsystem and a bounded file/target surface;
- current profiling or risk evidence for why it is next;
- fixtures that exercise normal, boundary, malformed, cancellation, and
  platform-relevant cases;
- a C++ behavior oracle;
- a proposed cross-language contract;
- an explicit feature switch and rollback path;
- acceptance thresholds;
- no requirement to translate an unrelated subsystem first.

Reject the slice if its boundary is “all of `tnzcore`”, “the scene graph”, “the
viewer”, or another open-ended area.

## Slice States

Use these states in progress records:

| State | Meaning |
|---|---|
| `characterizing` | Current C++ behavior and cost are being captured |
| `contracted` | Boundary, ownership, threading, errors, and evidence are approved |
| `rust-shadow` | Rust runs in tests or dual-run but cannot control output |
| `rust-opt-in` | Developers/testers may choose Rust; C++ remains default |
| `rust-default` | Rust controls the bounded path; C++ is fallback |
| `fallback-window` | Rust is default and fallback removal evidence is accumulating |
| `complete` | C++ implementation is removed or intentionally retained by policy |
| `blocked` | A named external or predecessor condition prevents useful progress |

Do not use percentages. A large amount of translated code can still be in
`rust-shadow`.

## Standard Slice Procedure

### 1. Refresh the baseline

Record:

- branch and exact commit;
- dirty/untracked files;
- Qt, Rust, bridge, `wgpu`, compiler, SDK, CMake, and Ninja versions;
- supported package matrix;
- relevant recent CI and runtime artifacts;
- predecessor renderer backend, adapter, driver, and shader versions;
- fixture/corpus revisions.

Use a read-only status path that disables Git LFS filters if normal status
cannot inspect the worktree. Do not modify LFS assets during source-only work.

### 2. Draw the current boundary

Identify:

- public C++ types and exported symbols;
- direct callers and callback receivers;
- allocation/destruction ownership;
- intrusive, shared, unique, raw, and Qt-parented pointers;
- thread affinity and locks;
- persistence tags and version branches;
- Qt, OpenGL/Metal/Vulkan, platform, codec, and plugin dependencies;
- caches and global registries;
- user-visible errors and translations;
- shutdown behavior.

Produce a small dependency note in the dated progress record. Avoid an
unbounded header graph dump.

### 3. Characterize behavior

Before writing Rust:

- run existing tests and smokes that reach the slice;
- add the smallest missing C++ characterization hook/test;
- capture canonical input and output;
- capture expected errors and unsupported behavior;
- record cold/warm timing and peak memory;
- test cancellation and shutdown if asynchronous;
- save exact artifacts.

Characterization code is not automatically permanent. Promote it to a durable
test only when it checks a stable product contract.

### 4. Design the bridge contract

Write the contract before implementation:

```text
Operation:
Caller:
Thread:
Input ownership:
Output ownership:
Mutation:
Cancellation:
Progress/events:
Errors:
Panic/exception containment:
Version:
Performance budget:
Fallback:
```

Contract rules:

- prefer one batch call to many fine-grained calls;
- use opaque handles for complex objects;
- use fixed-width value DTOs for small shared data;
- never expose STL, Rust standard collections, Qt containers, or raw GPU
  objects through a C ABI;
- never retain a borrowed pointer across an event-loop or async boundary;
- pass stable IDs rather than object addresses;
- each side destroys its own allocations;
- contain Rust panics and C++ exceptions;
- include shutdown and cancellation;
- include schema/protocol versioning on durable boundaries.

### 5. Choose the correct bridge

| Need | Bridge |
|---|---|
| Non-Qt Rust service called by C++ | CXX |
| Rust QObject, signal/slot/property/model used by existing Qt app | CXX-Qt |
| New Rust-backed Qt Quick/QML surface after maturity gate | official `qtbridge` |
| Dynamic plugin or process-stable API | versioned C ABI |
| Crash isolation, vendor SDK, long-running external work | process protocol |

Do not add another bridge technology for convenience. Any exception belongs in
the stable study with a removal plan.

### 6. Implement a scalar/reference Rust path

- keep domain crates free of Qt;
- keep GPU and platform access behind traits/adapters;
- implement clear scalar behavior before SIMD/GPU optimization;
- use explicit checked conversions at the boundary;
- make unsupported inputs return an explicit result;
- add unit, property, malformed-input, and cancellation tests;
- centralize `unsafe` and document its invariants.

The first Rust path must favor observability and correctness over speed.

### 7. Add shadow and differential execution

Shadow mode:

- C++ remains authoritative;
- Rust receives the same normalized input;
- outputs are compared;
- mismatches record a bounded artifact;
- no mismatch may modify the user's project;
- expensive shadow work is opt-in or fixture-only.

Comparison records must include:

- input and fixture revision;
- C++ and Rust implementation revisions;
- platform/toolchain/backend;
- comparison method and thresholds;
- result class: passed, failed, unsupported, or skipped;
- artifact paths and hashes;
- timing and memory;
- known nondeterminism.

### 8. Integrate through the real Qt path

Prove:

- UI thread remains responsive;
- queued delivery preserves order;
- cancellation closes progress UI and joins work;
- application shutdown does not leak, deadlock, or call destroyed Qt objects;
- translation/message IDs render correctly;
- undo/redo and dirty state are correct;
- file save/reopen behavior is unchanged;
- high-DPI coordinates and input mapping are correct where relevant.

A headless pass is not an integrated pass.

### 9. Validate packages

For Linux, Windows, and macOS packages:

- Rust runtime/static artifacts are present as intended;
- no developer-machine library path is embedded;
- Qt and QML plugins/resources remain complete;
- symbols/crash reporting cover Rust and C++;
- signing/notarization and checksums pass;
- a clean machine launches and exercises the slice;
- license/source obligations for Rust crates are captured;
- debug and release runtime choices are consistent, especially on MSVC.

### 10. Promote and retain fallback

Promotion sequence:

```text
shadow -> opt-in -> CI/package lane -> default -> fallback removal
```

Each promotion needs an exact commit and evidence record. Do not combine default
promotion and C++ deletion in the same change.

The fallback window ends only after:

- the agreed release/test duration;
- no unresolved P0/P1 mismatch;
- performance and memory budgets pass;
- supported packages and representative workflows pass;
- rollback was tested;
- maintainer approval is recorded.

### 11. Remove or classify C++

When removing a fallback:

- delete only the implementation made unreachable by the slice;
- remove stale feature switches, build entries, adapters, tests, and docs;
- keep oracle fixtures and comparison report schemas;
- verify no symbols or plugin contracts disappeared accidentally;
- update the remaining-C++ inventory.

If C++ is intentionally retained, classify it:

- Qt Widgets shell;
- Qt/private/platform adapter;
- third-party/vendor code;
- stable plugin ABI;
- proven performance/compatibility exception;
- temporary fallback with owner and expiry.

### 12. Retrospective

Record:

- what failed or was ambiguous;
- what evidence exposed it;
- whether it was code, contract, fixture, CI, packaging, hardware, or
  environment;
- whether the same issue has happened before;
- the smallest durable improvement if repetition is established.

Use:

- `AGENTS.md` for always-on repository conventions;
- the study for stable architecture decisions;
- this workflow for repeated mechanical process;
- mise/scripts for mechanical checks;
- CI only after the local check is stable.

Do not encode subjective architectural judgment into grep hooks.

## Specialized Workflow: Qt Bridge For Rust

Official Qt Bridge work is a Qt Quick/QML migration, not a drop-in QWidget
binding.

### Spike procedure

1. Pin the Qt release, Rust toolchain, and exact `qtbridge` crate/source.
2. Build a non-shipping Qt Quick surface containing:
   - editable list and table models;
   - selection and keyboard navigation;
   - async load with progress/cancel;
   - error presentation;
   - translation;
   - a large model;
   - repeated create/destroy;
   - deliberate re-entrant signal/property calls.
3. Package it on all supported platforms.
4. Embed it beside or within the Widgets shell if that is the proposed
   transition.
5. Test focus traversal, shortcuts, tablet/mouse input, accessibility, mixed
   DPI, styles, resources, signing, and shutdown.
6. Attempt one controlled dependency upgrade.
7. Compare the same Rust domain service through a CXX-Qt adapter.

### Promotion rule

The domain service may not depend on `qtbridge`. The Qt Bridge adapter is a
presentation crate. If the spike fails, the domain service remains usable
through CXX-Qt.

### Qt Bridge evidence

Record:

- upstream status (beta, Technology Preview, or supported release);
- exact platform status, including macOS;
- Qt minimum and release versions;
- Rust minimum and pinned version;
- QML tooling limitations;
- runtime borrow/re-entrancy failures;
- packaging and licensing result;
- CXX-Qt interoperability status;
- accepted upgrade and fallback policy.

## Specialized Workflow: Rust GPU Slice

### Renderer ownership

One service owns:

- `wgpu::Instance`, adapter, device, and queue;
- surface configuration or offscreen targets;
- pipelines and shader modules;
- staging/upload/readback resources;
- device-loss recovery;
- GPU cache budgets.

Qt sends immutable render snapshots and presentation events. Qt does not
mutate GPU resources directly.

### GPU slice sequence

1. Implement a CPU/scalar reference.
2. Implement offscreen `wgpu` output without Qt.
3. Validate WGSL and capture adapter/limit metadata.
4. Compare Metal, Vulkan, and Windows release backends.
5. Add Qt presentation using copied images.
6. Add a dedicated native surface if interactive performance requires it.
7. Consider shared textures only after profiling proves the copy is the
   bottleneck.
8. Add device-loss, resize, DPI, occlusion, minimize/restore, and shutdown
   tests.
9. Optimize and then set budgets.

### Required GPU evidence

- exact source and shader hashes;
- `wgpu`/Naga versions;
- backend, adapter, driver, limits, and enabled features;
- output image and comparison report;
- CPU/GPU timing and memory;
- validation-layer or Metal-validation logs for debug runs;
- device-loss and fallback result;
- color space, alpha, orientation, and sampling conventions.

### Direct Vulkan or Metal escape hatch

Before adding `ash` or `objc2-metal`, document:

- the missing `wgpu` capability;
- the user-visible need;
- an upstream issue or feasibility result;
- backend-neutral trait boundary;
- portable fallback;
- validation plan;
- removal/upstreaming owner.

## Specialized Workflow: Persistence And Formats

For each format or scene component:

1. collect legal, representative fixtures across versions and platforms;
2. record the current parser/writer capability and errors;
3. normalize semantic output without discarding compatibility-relevant data;
4. implement Rust read-only support;
5. fuzz and test malformed/truncated/oversized inputs;
6. compare resource/path resolution;
7. implement a writer only after reads pass;
8. compare byte output where required;
9. reload both outputs through both implementations;
10. test save interruption and atomic replacement;
11. retain the C++ adapter until production projects pass.

Never overwrite the only copy of a fixture or user project during comparison.

## Specialized Workflow: Scene, Commands, And Undo

Scene mutation must enter Rust as transactions:

```text
request
  -> validate against revision
  -> apply command to Rust domain state
  -> produce new revision + undo record + domain events + invalidations
  -> publish immutable presentation snapshot
  -> update Qt models
```

Test:

- stale revision rejection or rebase policy;
- deterministic command replay;
- undo/redo inverse behavior;
- observer event order;
- selection and dirty-state projection;
- nested xsheets and FX DAG invalidation;
- save/reopen after every command family;
- cancellation before and after commit;
- no Qt callback while a mutable scene guard is held.

Do not expose a general `get_mut_scene()` across FFI.

## CI And Validation Lanes

Introduce lanes in this order:

| Lane | Purpose | Required before |
|---|---|---|
| `rust-check` | Format, Clippy, unit/doc tests, dependency policy | Any Rust PR |
| `rust-ffi` | CXX/CXX-Qt compile and contract tests | Bridge merge |
| `rust-oracle` | Tiny deterministic differential corpus | First slice |
| `rust-package` | Same-commit platform packages | Opt-in promotion |
| `rust-gpu` | Backend image/performance artifacts | Renderer promotion |
| `rust-soak` | Cancellation, shutdown, repeated open/render/close | Default promotion |
| `rust-compat` | Rich production corpus, plugins, formats, hardware | Fallback removal |

Keep unit checks fast. Rich GPU/hardware/studio evidence may be scheduled or
manual, but absence remains a named release gap.

## Planned Local Command Shape

These commands describe the desired task interface. They do not exist until
the bootstrap goal implements them.

```sh
mise run rust-doctor
mise run rust-check
mise run rust-test
mise run rust-ffi-check
mise run rust-oracle
mise run rust-gpu-offscreen
mise run rust-package-check
```

Direct equivalents should remain available for diagnosis:

```sh
cargo fmt --manifest-path rust/Cargo.toml --all -- --check
cargo clippy --manifest-path rust/Cargo.toml --workspace --all-targets --all-features -- -D warnings
cargo test --manifest-path rust/Cargo.toml --workspace --all-targets
cmake --build toonz/build/<preset> --target <bridge-or-oracle-target> --parallel
```

The checked-in mise tasks are the contributor interface; direct Cargo/CMake
commands are evidence and debugging tools.

## Evidence Record Template

Create a dated record under a future `doc/rust_port_progress/` directory:

```markdown
# Rust Port Slice: <name>

Date:
Source commit:
C++ oracle commit/package:
Requirement IDs:
Slice state:
Owner:

## Contract

Operation:
Boundary:
Ownership:
Threads:
Errors:
Cancellation:
Fallback:

## Environment

Platform:
Architecture:
Qt:
Rust:
Bridge:
wgpu/Naga:
Compiler/SDK:
GPU/backend/driver:
Fixture revision:

## Commands And Results

| Command | Result | Artifact |
|---|---|---|

## Comparisons

| Fixture | C++ | Rust | Metric/threshold | Result |
|---|---|---|---|---|

## Package And Manual Evidence

## Performance And Memory

## Unsupported, Skipped, And Waived

## Blockers

## Promotion Decision

## Retrospective
```

Every artifact should have a stable relative path or CI URL and a hash when it
is used as release evidence.

## Review Checklist

### Architecture

- [ ] Slice is bounded and justified by evidence.
- [ ] Core/domain crates remain Qt-free.
- [ ] Bridge choice matches the decision table.
- [ ] Ownership, thread, error, cancellation, and shutdown contracts exist.
- [ ] No new permanent C++/Rust duplicate lacks a fallback-removal gate.

### Safety

- [ ] Panics and exceptions cannot cross ordinary FFI.
- [ ] All allocations are destroyed by their owner.
- [ ] Borrowed data cannot outlive the call.
- [ ] `unsafe` is isolated, documented, and tested.
- [ ] Malformed and oversized inputs are bounded.

### Correctness

- [ ] Current C++ behavior was characterized first.
- [ ] Passed/failed/unsupported/skipped are distinct.
- [ ] Differential artifacts are retained.
- [ ] Undo, cancel, save/reopen, and errors are covered where applicable.
- [ ] Goldens were not silently updated.

### Product

- [ ] Real Qt integration was exercised.
- [ ] Supported packages were checked.
- [ ] Performance and memory budgets passed.
- [ ] Plugin/format/hardware impact is explicit.
- [ ] Promotion and rollback decisions are recorded.

## Definition Of Done For A Slice

A slice is complete only when:

1. Rust is the agreed owner of the bounded behavior;
2. the bridge contract is versioned and tested;
3. the named C++ and Rust corpus passes;
4. supported packages and real workflow evidence pass;
5. performance, memory, cancellation, and shutdown budgets pass;
6. the C++ fallback is removed or intentionally classified;
7. documentation and remaining-C++ inventory are current;
8. no required evidence is merely pending.
