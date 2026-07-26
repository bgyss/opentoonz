# OpenToonz C++ To Rust Migration Study

Prepared: July 26, 2026

Surveyed source commit: `6f87dd4535de01cfd4d8fa84cd4ceedb5c7492bd`

## Executive Recommendation

OpenToonz should move to Rust through a long-lived strangler migration, not a
rewrite. Keep Qt as the product UI, stabilize a language-neutral application
core boundary, and replace bounded C++ subsystems behind that boundary while
the shipping application remains usable.

The recommended target is:

- Rust owns new domain logic, deterministic data models, job scheduling,
  render-graph orchestration, caches, selected codecs, and the new GPU renderer.
- `wgpu` is the default Rust graphics abstraction: Metal on macOS, Vulkan on
  Linux, and the best supported native backend on Windows (normally Direct3D
  12, with Vulkan retained as a diagnostic or supported alternative).
- Qt 6 remains the UI and desktop-integration framework.
- Qt Bridge for Rust (`qtbridge`) is the preferred direction for new Qt
  Quick/QML surfaces after it passes a project-specific maturity gate.
- CXX and CXX-Qt are the transition tools for the existing C++/Qt Widgets
  application. A small C ABI is reserved for stable plugin or process
  boundaries.
- C++ remains the behavioral oracle until every migrated slice proves file,
  render, interaction, performance, and package parity.

Do not begin production Rust substitution until both predecessor programs are
actually complete:

1. the Qt 6 port meets the release contract in
   `doc/qt6_migration_goal_prompt.md`; and
2. the OpenGL-to-Metal/Vulkan migration has a stable renderer contract,
   cross-platform packages, a named comparison corpus, and pixel/performance
   evidence.

Toolchain and bridge experiments may begin earlier in an isolated,
non-shipping lane because they reduce uncertainty without changing the product.
Production ownership must not move early.

The central architectural constraint is important: the current application is
Qt Widgets based, while the official Qt Bridge for Rust public beta is for
Rust-backed Qt Quick/QML applications. Eliminating all C++ while preserving the
current QWidget implementation is therefore not a supported endpoint today.
OpenToonz can either keep a deliberately small C++ QWidget shell indefinitely,
or gradually replace selected UI surfaces with Qt Quick/QML and `qtbridge`.
Both choices stay on Qt.

## Decision Summary

| Decision | Recommendation | Why |
|---|---|---|
| Migration style | Incremental subsystem replacement | Preserves a working oracle and makes rollback practical |
| GUI | Keep Qt 6 | Replacing the GUI and language simultaneously multiplies risk |
| Existing Qt Widgets bridge | CXX plus CXX-Qt | Matches a mixed C++/Rust QObject application |
| New Qt UI | Evaluate and then adopt official Qt Bridge for Rust | Keeps new UI in Qt Quick/QML with idiomatic Rust backends |
| Cross-platform GPU | `wgpu` | One Rust API over Metal, Vulkan, Direct3D 12, and fallback GL |
| Direct graphics APIs | `ash` and `objc2-metal` only behind narrow escape hatches | Avoids maintaining two full renderers |
| Qt RHI | Integration experiment, not the Rust renderer foundation | QRhi has limited source/binary compatibility guarantees |
| Build ownership during transition | CMake top level, Cargo workspace imported as targets | OpenToonz packaging remains CMake-driven while Rust grows |
| Correctness strategy | C++ oracle plus differential tests | A rewrite without a behavioral oracle cannot preserve implicit behavior |
| First production ports | Pure/headless leaf logic and raster kernels | Smaller state surface and easier deterministic proof |
| Last production ports | Scene mutation, undo, tools, Widgets shell, hardware paths | Highest coupling and hardest manual parity requirements |

## Scope And Assumptions

This study answers how to move the codebase from C++ to Rust after the active
Qt 6 and graphics migrations. It does not implement Rust, change the renderer,
or revise the current Qt 6 completion verdict.

The desired product constraints are:

- preserve Qt rather than adopt a different GUI toolkit;
- prefer modern Rust-native Metal/Vulkan-capable graphics technology;
- preserve OpenToonz file and artist-workflow compatibility;
- keep macOS, Windows, and Linux packages supportable;
- avoid a second indefinitely maintained application;
- let proof, not translated line count, determine completion.

“Move to Rust” should mean that Rust becomes the source of truth for product
logic and rendering. It should not require deleting every line of C++ if a
small, well-contained Qt Widgets or platform adapter remains safer. Complete
C++ elimination can be a later policy decision tied to Qt Bridge maturity and
the amount of UI converted from Widgets to Qt Quick.

## Survey Method And Limits

The survey inspected:

- the top-level and subsystem CMake files;
- `tnzcore`, `tnzbase`, `tnzext`, `toonzlib`, `toonzqt`, `tnztools`, `stdfx`,
  `image`, `sound`, `toonz`, `toonzfarm`, command-line tools, plugins, and
  platform code;
- scene, xsheet, persistence, smart-pointer, render, FX, plugin, Qt, threading,
  and OpenGL surfaces;
- the current Qt 6 migration contracts and build lanes;
- current primary documentation for Qt Bridge for Rust, CXX-Qt, CXX,
  Corrosion, Qt graphics integration, `wgpu`, Naga, `ash`, and
  `objc2-metal`.

Static search at the surveyed commit found:

- 2,245 C/C++/Objective-C++ source and header files under `toonz/sources`;
- approximately 895,000 lines in those files;
- 70 Qt Linguist `.ts` files;
- 915 files with a heuristic Qt include, `QObject`, `QWidget`, or `Q_OBJECT`
  match;
- 282 files containing `Q_OBJECT` (666 occurrences);
- 145 files with a heuristic OpenGL/Qt OpenGL match (3,426 occurrences);
- 43 `PERSIST_IDENTIFIER` and 50 `PERSIST_DECLARATION` matches;
- 134 files with an explicit project, Qt, standard, or pthread threading
  primitive match.

These counts are sizing indicators, not architectural truth. The CMake
`tnzcore` target, for example, gathers files from `common` and `include`, so
directory counts do not equal target ownership. Generated files, comments,
conditional platform code, and false-positive symbol matches also affect
search counts.

The largest source concentrations were:

| Subtree | Files | Approximate lines | Migration implication |
|---|---:|---:|---|
| `toonz` | 401 | 223,000 | GUI/application behavior cannot be an early translation target |
| `common` | 224 | 120,000 | Foundational target inputs must be split by capability |
| `include` | 611 | 109,000 | Public headers expose ownership and dependency coupling |
| `toonzlib` | 191 | 93,000 | Domain value is high, but scene/persistence/observer coupling is severe |
| `stdfx` | 305 | 82,000 | Port by FX family behind a stable render ABI |
| `tnztools` | 119 | 79,000 | High-frequency input and visual parity make this late work |
| `toonzqt` | 115 | 77,000 | Retain Qt; replace backing models/services rather than widgets first |
| `image` | 100 | 44,000 | Replace per format only after compatibility corpora exist |

The most concentrated OpenGL search clusters include drawing-tool gadgets,
Scene Viewer/viewer drawing, color and region styles, `common/tgl`, offline
vector rendering, tessellation, and shader FX. The Qt search is concentrated in
the main `toonz` application, `toonzqt`, `tnztools`, scripting, capture, IO
dialogs, and shared Qt-facing headers. This supports two conclusions:

1. graphics migration boundaries must include tool overlays and vector/style
   rendering, not only the final frame renderer; and
2. “core” cannot be declared Qt-free by moving only the main window.

This is a source-architecture survey. It does not replace runtime profiling,
production project sampling, plugin-user research, or maintainer decisions.
The first migration goal must collect that evidence.

## Current Architecture

### Build And Deployment Shape

`toonz/sources/CMakeLists.txt` is the build root and adds the major shared
libraries in dependency order before the GUI and command-line executables.
The Qt 6 branch still intentionally supports Qt 5 and Qt 6 build lanes. The
preferred local workflow is Nix plus mise, with CMake/Ninja producing the
application and packages.

The eventual Rust workspace should live under `rust/`, but CMake should remain
the top-level product build during the mixed-language period. Cargo should own
Rust dependency resolution, tests, and crate compilation. CMake should import
only the Rust artifacts needed by a given target. CXX-Qt documents a
CMake/Corrosion integration in which Cargo builds a static library and CMake
links it into the Qt executable. [Corrosion imports Cargo packages as ordinary
CMake targets](https://corrosion-rs.github.io/corrosion/), which fits this
repository better than teaching Cargo to reproduce every current package rule.

Before adopting current Corrosion releases, raise the project CMake minimum in
a separate, already-green change: current Corrosion documentation says version
0.6 requires CMake 3.22, while this source tree still declares 3.10 even though
its presets already require a newer CMake.

### Major Subsystem Map

| Current area | Approximate role | Coupling observation | Rust disposition |
|---|---|---|---|
| `common` plus `include` / `tnzcore` | Geometry, raster, image, vector, cache, stream, persistence, platform, GL, audio primitives | Foundational but internally broad; Qt and GL are present inside “core” | Split by capability before porting |
| `tnzbase` | Parameters, base services, platform/scanner support | Smaller but depended on by higher layers | Port pure parameter/value logic early; isolate hardware |
| `tnzext` | Mesh, plastic deformation, numerical extensions | Numerical and GL paths coexist | Port deterministic math after fixtures |
| `toonzlib` | Scene, xsheet, levels, palettes, commands, renderer-facing logic, scripting | Highest-value domain layer; tightly coupled to persistence, observers, Qt, and FX | Build a Rust read model first; mutation much later |
| `toonzqt` | Shared Qt Widgets, viewers, schematics, field editors, style UI | Explicit Qt ownership and UI-thread requirements | Keep; introduce Rust-backed models/services |
| `tnztools` | Drawing/edit tools, input, assistants, brush integration | High-frequency input plus render/UI state | Late port with recorded input and stroke parity |
| `stdfx`, `colorfx` | FX implementations, shaders, pixel processing, plugin behavior | Good functional units, but output parity is strict | Port FX families after render ABI and corpus exist |
| `image` | Raster, movie, SVG, PSD, FFmpeg and other IO | Format compatibility and third-party library behavior dominate | Adapter first, replacement per format |
| `sound` | Sound IO and playback support | Smaller surface but timing/platform sensitive | Decode/cache before device playback |
| `toonz` | Main GUI, commands, rooms, panels, capture, export | Largest UI/application integration point | Keep as shell until late |
| `toonzfarm` | Farm controller/server/task tools | Network and process boundaries are naturally testable | Strong early service candidate |
| `tcleanup`, `tcomposer`, `tconverter` | Headless command-line entry points | Thin executables over deep libraries | Use as parity harnesses, not as isolated rewrites |
| `plugins` | C-style host interface and FX callbacks | Existing dynamic boundary is valuable but not automatically Rust-safe | Preserve ABI first; add safe Rust SDK wrapper |
| `stuff` and translations | Runtime defaults, rooms, QSS, brushes, FX data, locales | Product behavior outside compiled code | Preserve unchanged while engines move |

### Dependency Direction

The broad runtime dependency shape is:

```text
OpenToonz / command-line tools
  -> toonzqt + tnztools + stdfx + image + sound + farm
       -> toonzlib
            -> tnzext + tnzbase + tnzcore
                 -> common algorithms, formats, Qt, OpenGL, platform libraries
```

This is not a clean onion architecture. UI concepts reach downward, Qt and
OpenGL exist in foundational targets, `TRenderSettings` contains a
`QOffscreenSurface`, and higher-level scene and renderer types share intrusive
pointer and persistence conventions. The first architectural work is therefore
boundary extraction, not translation.

## Why A Rewrite Would Fail

### Intrusive Ownership Is Part Of The ABI

`TSmartObject` implements intrusive atomic reference counting and asserts that
objects die with a zero reference count. `TSmartPointerT` and related wrappers
are widely embedded in public types. Raw pointers, intrusive handles,
`std::unique_ptr`, `std::shared_ptr`, Qt parent ownership, and callback
lifetimes coexist.

Rust must not mirror these ownership rules throughout its model. At a bridge:

- existing C++ objects stay opaque and are manipulated through owning handles
  or short-lived borrowed calls;
- Rust-owned objects use Rust ownership internally;
- no borrowed raster, scene, `QString`, Qt object, or callback reference may
  outlive the bridge call unless an explicit pinned/owned handle contract says
  otherwise;
- each allocation is destroyed by the allocator that created it;
- panics and C++ exceptions are converted to typed errors before crossing the
  boundary.

The Rustonomicon explicitly warns against allowing Rust panics to unwind across
an ordinary FFI boundary. [FFI boundary code must contain
unwinding](https://doc.rust-lang.org/nomicon/unwinding.html). Every bridge entry
point needs a tested error and panic policy.

### Persistence Is Behavior, Not Just A Schema

`TPersist`, `TIStream`, `TOStream`, global declaration registration, stream
tags, legacy paths, and class-specific `loadData`/`saveData` implementations
form an object serialization system. Scene and level loading also performs
resource resolution, project-relative path decoding, version compatibility,
and object graph reconstruction.

Do not replace it initially with a Serde derive over a new struct. Use three
layers:

1. a canonical, versioned Rust domain model;
2. a compatibility adapter that reads/writes the existing stream behavior;
3. normalized snapshots used only for comparison and diagnostics.

Read-only parsing comes before write support. Write support comes before C++ is
removed. Round-trip equality is insufficient by itself because old and new
writers may normalize differently; semantic reload equality and byte-stability
where required must both be measured.

### Scene Mutation Combines Several Responsibilities

`ToonzScene`, `TXsheet`, stage objects, levels, columns, FX DAG state,
parameters, observers, caches, undo commands, selection state, and UI handles
are interdependent. A direct Rust translation of classes would reproduce
coupling without establishing safer ownership.

The target model should separate:

- immutable identity and value types;
- scene/xsheet/level state;
- commands and transactions;
- derived indexes and render graphs;
- observer/event projection;
- Qt presentation models;
- persistence adapters.

Rust scene mutation should be command-based. A command produces a new revision,
an undo record, domain events, and explicit invalidations. Qt models observe
committed events rather than holding mutable references into Rust state.

### Rendering Is Both CPU And GPU Behavior

OpenGL calls are spread through viewer drawing, vector rendering, tool
overlays, styles, tessellation, offscreen rendering, standard FX, and shader
paths. The completed Metal/Vulkan migration must first make these responsibilities
visible. A Rust renderer should consume a stable render snapshot and command
stream rather than call back into arbitrary mutable C++ objects while encoding
GPU work.

The C++ graphics migration should leave behind:

- a backend-neutral pixel/texture/command vocabulary;
- explicit resource ownership and lifetime;
- explicit UI-thread versus render-thread rules;
- device-loss and adapter-reselection behavior;
- a deterministic CPU/reference path for important operations;
- golden render and performance corpora;
- no requirement that new Rust code include OpenGL headers or Qt OpenGL types.

If those artifacts do not exist when the graphics migration is declared
complete, create them before porting the renderer.

### Qt Widgets Are Not Rust-Neutral

The main application and `toonzqt` are deeply based on Widgets, MOC, signals,
properties, model/view classes, resources, QSS, Qt Linguist, native event
filters, dialogs, and platform packaging. Recreating these in another toolkit
would be a separate product rewrite. Keeping Qt is the correct choice.

The official Qt Bridge for Rust is not currently a full Qt binding. Its July
2026 public beta creates Rust-backed QML elements, properties, signals, slots,
and models for Qt Quick. Its documentation says that applications mixing
Rust/C++, using Qt Widgets, or accessing C++-only Qt modules should consider
CXX-Qt instead. It currently requires Qt 6.10 or newer, Rust 1.87 or newer,
and lists macOS arm64 as experimental. See the [official `qtbridge` 0.2
documentation](https://doc-snapshots.qt.io/qtbridge-rust/qtbridge/index.html).

This creates a deliberate two-lane plan:

- existing Widgets remain C++, with Rust services exposed through CXX/CXX-Qt;
- new or intentionally converted surfaces use Qt Quick/QML and `qtbridge`
  after a maturity spike passes.

### Threads And Callbacks Cross Ownership Domains

Rendering, Qt event dispatch, farm work, caches, image loading, audio, and
platform integrations all have thread expectations. Rust async runtimes should
not replace Qt's event loop, and Qt objects must not be moved into generic Rust
worker tasks.

Use:

- Qt's GUI thread for all QWidget/QML presentation;
- a Rust runtime owned behind a service boundary for IO and async jobs;
- explicit request IDs, cancellation tokens, progress events, and immutable
  result objects;
- queued Qt delivery at the final UI boundary;
- a separately owned render thread/device model;
- shutdown ordering tests.

The bridge contract must specify which side creates, cancels, joins, and
destroys every task.

## Bridge Technology Recommendation

### Official Qt Bridge for Rust

Qt Bridge for Rust should be the preferred end-state technology for new Qt
Quick/QML UI backed by Rust. It is attractive because it is Qt-owned, uses
Cargo, exposes idiomatic Rust structs to QML, supports properties/signals/slots
and table/list models, and avoids application-written C++ for a Qt Quick
application.

It is not yet the primary migration bridge because:

- it is public beta and not yet Technology Preview;
- its documented focus is QML/Qt Quick, not existing Widgets;
- it requires Qt 6.10+, while the current OpenToonz Qt policy includes a 6.9
  floor lane;
- macOS arm64 support is documented as experimental;
- its docs list future interoperability with CXX-Qt as planned work;
- it uses `Rc<RefCell<_>>` for QML-visible Rust objects and documents runtime
  borrow conflicts, so re-entrant UI call patterns must be tested.

Adopt it only after the gate in “Qt Bridge Maturity Gate” below passes. Pin an
exact crate version and source; never use `qtbridge = "*"`.

### CXX-Qt

CXX-Qt is the correct transition layer for Rust-defined QObjects and
bidirectional Qt/C++ integration. It builds on CXX and generates Qt-facing C++
representations from Rust bridge declarations. Its documentation emphasizes
normal Qt code on one side and normal Rust code on the other, rather than a
one-to-one binding. [CXX-Qt is tested on Linux, Windows, and
macOS](https://kdab.github.io/cxx-qt/book/), though the project must still prove
OpenToonz's supported architectures and packaging.

Use CXX-Qt for:

- Rust-backed service QObjects;
- signals, slots, properties, and presentation models consumed by Widgets;
- queued progress and completion delivery;
- narrow access to existing C++ QObjects through deliberate adapters.

Do not use it to mechanically bind all QWidget APIs or expose the entire scene
graph.

### CXX

CXX is the default bridge for non-Qt domain services. It supports opaque and
shared types and statically checks a deliberately limited common type surface.
The [CXX project describes negligible-overhead, type-checked
interop](https://cxx.rs/), but safety still depends on correct ownership,
threading, and semantic contracts around the generated bridge.

Use it for:

- immutable IDs, rectangles, pixel formats, status enums, and descriptors;
- opaque scene, raster, render-job, and cache handles;
- batch-oriented service calls;
- typed error returns.

Prefer opaque types to mirroring complex C++ layout. CXX shared structs support
only a purposeful cross-language value surface; that limitation is useful.

### C ABI

Retain a small C ABI for:

- externally loaded FX/workbench plugins;
- optional worker processes;
- crash-isolated vendor/hardware adapters;
- long-lived interfaces that must not depend on Rust or C++ ABI stability.

Version every table and capability. Pass lengths with buffers, avoid language
containers and exceptions, and provide explicit create/retain/release
functions. A safe Rust SDK crate should wrap the raw ABI.

### Rejected Default Approaches

| Approach | Reason it is not the default |
|---|---|
| Whole-project `bindgen` | The code relies on templates, inline behavior, Qt/MOC, custom pointers, and complex C++; even bindgen's guide recommends narrow allowlists for C++ |
| C ABI for every internal call | Produces large manual unsafe surfaces and loses expressive ownership |
| Qt Bridge as the only first bridge | Does not target the existing QWidget/C++ application |
| CXX-Qt as a full Qt binding | It is designed around explicit bridges, not wrapping all of Qt |
| IPC for low-latency drawing/render calls | Serialization and scheduling overhead are wrong for per-event/per-tile hot paths |
| Stable Rust dynamic ABI between all crates | Rust has no stable native ABI; use static linking internally and a versioned C ABI where dynamic loading is required |

## Qt Bridge Maturity Gate

Before a production OpenToonz surface depends on `qtbridge`, an isolated spike
must prove all of the following on the same supported Qt release used for
packages:

- Linux x86_64, Windows x64, and macOS arm64 build and package;
- macOS is no longer a project-specific blocker despite upstream's
  “experimental” label;
- exact dependency and license terms are acceptable;
- model reset, row insertion/removal, table editing, selection, and large-model
  behavior pass;
- Rust property/signal re-entrancy does not produce `RefCell` borrow panics;
- queued cross-thread invocation, cancellation, shutdown, and error propagation
  pass;
- QML resources, translations, plugins, deployment tools, signing, and
  notarization are captured in packages;
- keyboard, tablet, accessibility, mixed-DPI, and focus behavior work when a
  Qt Quick surface is embedded in or adjacent to the Widgets shell;
- an upgrade trial to the next compatible bridge version is documented;
- the project can fall back to the CXX-Qt presentation adapter without changing
  the Rust domain service.

Until then, `qtbridge` experiments are advisory and must not become a release
dependency.

## GPU Framework Recommendation

### Use `wgpu` As The Renderer Abstraction

`wgpu` is the best default for a new Rust renderer. It provides a safe,
cross-platform WebGPU-style API and first-class native backends for Vulkan,
Metal, and Direct3D 12. The project also supports a lower-tier OpenGL path.
The current [wgpu backend documentation](https://docs.rs/wgpu/latest/wgpu/enum.Backend.html)
and [project support matrix](https://github.com/gfx-rs/wgpu) document those
backends.

Recommended backend policy:

| Platform | Release backend | Additional lane |
|---|---|---|
| macOS arm64 | Metal | software/reference and validation-enabled Metal |
| Linux x86_64 | Vulkan | best-effort GL only if the support contract requires it |
| Windows x64 | Direct3D 12 by default | Vulkan comparison/diagnostic lane where drivers permit |

The user-visible architecture can still be described as a Metal/Vulkan
migration: Metal and Vulkan are the primary Apple/Linux APIs. Using `wgpu`
rather than forcing Vulkan on every platform gives Windows a native backend and
keeps one renderer implementation.

Pin `wgpu`, Naga, and the Rust toolchain together. `wgpu` intentionally ships
breaking releases frequently, and its WGSL implementation evolves with Naga.
Treat upgrades as renderer migrations with shader compilation and golden-image
evidence, not routine dependency bumps. Naga currently supports WGSL input and
Metal, SPIR-V, HLSL, and GLSL outputs; see its [supported endpoint
matrix](https://docs.rs/naga/latest/naga/).

### Shader Policy

- Author new portable shaders in WGSL.
- Keep shaders versioned beside the Rust render feature that owns them.
- Validate every shader in CI before package builds.
- Retain explicit coordinate, color-space, alpha, sampling, and precision
  conventions.
- Maintain scalar/CPU references for critical compositing operations.
- Store backend, adapter, driver, feature, and limit data with render evidence.
- Permit backend-specific shaders only through a reviewed capability boundary
  with a portable fallback or explicit waiver.

### Use Direct API Crates Only As Escape Hatches

`ash` is a thin Vulkan binding and intentionally leaves validation and much
safety to the caller. `objc2-metal` provides modern generated bindings to
Apple's Metal framework. They are appropriate only where `wgpu` cannot expose a
required feature or a platform interop path.

Any direct backend module must:

- live under `otz-gpu-backend-vulkan` or `otz-gpu-backend-metal`;
- implement an internal backend-neutral trait;
- contain all `unsafe` API use;
- have validation-layer/Metal-validation workflows;
- carry a removal or upstreaming plan;
- never leak raw API objects into scene, Qt, or FX domain crates.

### Do Not Build The Rust Renderer On QRhi

Qt's RHI can target Vulkan, Metal, Direct3D, and OpenGL, and Qt provides
`QQuickRhiItem`/`QRhiWidget` integration. However, Qt documents that the QRhi
class family has no source or binary compatibility guarantee and requires
linking `Qt::GuiPrivate` for direct use. See the [QQuickRhiItem
documentation](https://doc.qt.io/qt-6/qquickrhiitem.html).

QRhi is useful for a bounded integration prototype or a Qt-owned renderer, but
it should not become the Rust engine's public graphics abstraction. Otherwise
the “Rust core” remains coupled to a private-version-sensitive Qt graphics API.

### Qt Presentation Integration Options

Use these in increasing order of complexity:

1. **Offscreen correctness path.** Rust renders to an owned texture/buffer and
   returns a copied image to Qt. This is slow but deterministic and ideal for
   the first oracle, tests, thumbnails, and fallback.
2. **Dedicated native render window.** Rust/`wgpu` owns one or a few surfaces
   associated with a `QWindow`, embedded into the Widgets application through
   `QWidget::createWindowContainer()`. Qt documents stacking, focus, rendering,
   and performance limitations for such containers, so use them for viewer
   surfaces rather than many small widgets. See
   [`QWidget::createWindowContainer`](https://doc.qt.io/qt-6/qwidget.html#createWindowContainer).
3. **Shared texture path.** Share an offscreen texture with Qt through a narrow
   per-platform adapter (for example, IOSurface-backed Metal resources on
   macOS). This can remove copies but introduces explicit synchronization and
   device ownership work.
4. **Qt Quick composition.** A future Qt Quick surface can compose a Rust
   renderer result. Prototype this only after Qt Bridge and renderer gates pass.
   Avoid assuming that independent `wgpu` and QRhi devices can freely share
   resources.

The render engine should not know which of these presentation modes is active.
It should render into a target described by a narrow presentation adapter.

## Target Rust Architecture

Use a Cargo workspace under `rust/`. Do not mirror every C++ directory.

### Foundational crates

| Crate | Responsibility |
|---|---|
| `otz-core` | IDs, frame/time types, dimensions, geometry, errors, diagnostics, versioning |
| `otz-color` | Pixel/color models, premultiplication rules, palettes, color transforms |
| `otz-raster` | Owned pixel buffers, typed views, tiles, scalar/SIMD kernels |
| `otz-vector` | Strokes, regions, topology, fills, tessellation-neutral geometry |
| `otz-command` | Transactions, commands, undo records, domain events, invalidations |

### Domain crates

| Crate | Responsibility |
|---|---|
| `otz-project` | Project paths, variables, defaults, resource resolution |
| `otz-level` | Level/frame identity and level state |
| `otz-scene` | Scenes, xsheets, columns, stage objects, cameras, keyframes |
| `otz-fx` | FX graph, parameters, capabilities, render descriptors |
| `otz-render` | Render snapshots, DAG planning, tiling, scheduling, cancellation |
| `otz-cache` | Content-addressed images, tiles, previews, invalidation |
| `otz-io` | Registry and high-level import/export contracts |

### Backend and adapter crates

| Crate | Responsibility |
|---|---|
| `otz-gpu` | `wgpu` device policy, resources, pipelines, renderer implementation |
| `otz-codec-*` | One format or third-party codec adapter per bounded crate |
| `otz-platform` | Filesystem, process, clipboard, power/session and OS adapters |
| `otz-farm` | Farm protocol, task state, workers, process orchestration |
| `otz-plugin-api` | Versioned safe plugin-facing types and capability model |
| `otz-plugin-sys` | Raw C plugin ABI only |

### Migration and UI crates

| Crate | Responsibility |
|---|---|
| `otz-bridge` | CXX/CXX-Qt definitions and C++ adapter boundary |
| `otz-qt-models` | Presentation models, DTO conversion, UI-thread delivery |
| `otz-qtquick` | Future `qtbridge`-based Qt Quick backend types |
| `otz-oracle` | C++ and Rust snapshot protocol types |
| `otz-compare` | Semantic, image, event, and performance comparisons |
| `otz-cli` | Headless inspection, conversion, comparison, and render commands |

Dependency rules:

```text
UI and FFI adapters
  -> domain services
       -> foundational value/algorithm crates

renderer and codecs
  -> domain contracts + foundation

domain and foundation
  -X-> Qt, CXX-Qt, QWidget, QRhi, platform window handles
```

`otz-scene`, `otz-render`, and `otz-raster` must build and test without Qt.
`otz-gpu` may depend on `wgpu` but not Qt. Qt types are converted at the edge.

## Cross-Language Contract

### Value rules

- Use fixed-width integers and explicit byte order in persisted/FFI data.
- Define pixel channel order, component width, alpha convention, color space,
  row stride, orientation, and alignment.
- Represent paths internally as path-safe Rust types; convert to/from Qt and
  legacy path encodings at adapters.
- Use stable IDs rather than cross-language raw object addresses.
- Version every snapshot and message.
- Batch cells, pixels, strokes, and events; do not cross the bridge per pixel.

### Ownership rules

- One side owns each object and provides its destructor.
- C++ intrusive pointers remain entirely on the C++ side.
- Rust returns opaque handles or owned immutable DTOs.
- Qt parent ownership applies only to Qt wrapper objects.
- GPU resources are destroyed by the device-owning render service.
- Worker callbacks hold an explicit cancellation-safe subscription handle.

### Error rules

- Expected failures return a typed error code plus structured detail.
- Rust panics are contained and reported; they never unwind into C++.
- C++ exceptions are caught by the adapter and never enter Rust.
- A failed GPU device or worker transitions the service to a known state.
- User-visible localization occurs in Qt; domain errors carry stable message
  IDs and arguments, not translated strings.

### Thread rules

- Every API states `gui-thread`, `render-thread`, `worker`, or `thread-safe`.
- No synchronous UI callback is allowed while Rust holds a mutable domain lock.
- Long jobs return immediately with an ID and cancellation token.
- Events are ordered per job and include a monotonic sequence.
- Shutdown stops admission, cancels, drains/joins, releases GPU/platform
  resources, and only then destroys bridge objects.

## Subsystem Port Priority

Scores are relative planning guidance: 1 is low and 5 is high.

| Candidate | Value | Risk | Oracle difficulty | Recommended order |
|---|---:|---:|---:|---|
| Build/bridge spike and comparison protocol | 5 | 2 | 2 | First |
| Pure geometry, IDs, frame/time, hashing | 4 | 2 | 1 | Early |
| Selected scalar raster kernels | 5 | 3 | 2 | Early |
| Farm protocol/process orchestration | 3 | 2 | 2 | Early |
| Read-only scene/level snapshot | 5 | 3 | 3 | Early-middle |
| Cache keys and content-addressed cache | 4 | 3 | 2 | Middle |
| Selected common codecs | 3 | 3 | 3 | Per format |
| FX descriptor/graph read model | 4 | 3 | 3 | Middle |
| Headless render scheduler | 5 | 4 | 4 | Middle |
| `wgpu` compositing and preview renderer | 5 | 4 | 4 | Middle-late |
| Scene/xsheet mutation and undo | 5 | 5 | 5 | Late |
| Vector topology/fill semantics | 5 | 5 | 5 | Late |
| Drawing tools and tablet loops | 5 | 5 | 5 | Late |
| Full FX library | 4 | 5 | 4 | Family by family |
| Audio/video device paths | 3 | 4 | 5 | Late/platform |
| Scanner/camera/vendor SDK paths | 2 | 5 | 5 | Last or isolated |
| Existing QWidget implementation | 2 | 5 | 5 | Keep or convert selectively |

Good first production kernel candidates must satisfy all of these:

- no Qt object ownership;
- deterministic input/output;
- small stable data boundary;
- representative fixtures already exist or can be generated;
- benchmarkable;
- C++ fallback can remain behind the same interface.

Choose the first candidate from profiling and fixture evidence, not intuition.

## Ordered Migration Program

Stable requirement IDs should be used in reports and commits.

### RUST-PRQ: Predecessor Completion And Baseline Freeze

- `RUST-PRQ-01`: Qt 6 release contract is complete.
- `RUST-PRQ-02`: Metal/Vulkan renderer migration is complete and its contract
  is documented.
- `RUST-PRQ-03`: one exact C++ release candidate and package set is retained as
  the oracle.
- `RUST-PRQ-04`: representative production projects and plugin/hardware scope
  are approved.

Exit: a dated evidence record names the commit, packages, platforms, hardware,
fixtures, renderer backend/driver, and unresolved waivers.

### RUST-ARC: Architecture And Build Lane

- `RUST-ARC-01`: Cargo workspace, pinned Rust toolchain, Nix/mise tasks, CMake
  import, formatting, linting, tests, license audit, and artifact packaging.
- `RUST-ARC-02`: written bridge ownership/error/thread contract.
- `RUST-ARC-03`: dependency guard that prevents Qt from entering core/domain
  crates.
- `RUST-ARC-04`: exact bridge and GPU dependency pins with upgrade policy.

Exit: all supported platforms build a no-op Rust service into a package without
changing application behavior.

### RUST-ORC: Oracle And Comparison Platform

- `RUST-ORC-01`: C++ snapshot/render/round-trip oracle.
- `RUST-ORC-02`: versioned fixture manifest and normalized report schema.
- `RUST-ORC-03`: semantic, image, event, error, and performance comparison
  modes.
- `RUST-ORC-04`: explicit passed/failed/unsupported/skipped states.

Exit: one command compares a small corpus and produces retained JSON, Markdown,
and image artifacts.

### RUST-BRG: Qt And Service Bridge

- `RUST-BRG-01`: CXX non-Qt service call with tested lifetime/error behavior.
- `RUST-BRG-02`: CXX-Qt QObject/model with queued completion and shutdown.
- `RUST-BRG-03`: Qt Bridge for Rust maturity spike.
- `RUST-BRG-04`: package, signing, deployment, and license proof.

Exit: maintainers select the production bridge versions and UI policy.

### RUST-KRN: Leaf Kernel Substitution

- `RUST-KRN-01`: first profiled deterministic kernel has scalar Rust parity.
- `RUST-KRN-02`: optional SIMD/parallel path meets tolerances and performance
  budget.
- `RUST-KRN-03`: dual-run telemetry detects mismatch without corrupting output.
- `RUST-KRN-04`: Rust becomes default; C++ fallback remains for one release
  window.

Exit: fallback removal is approved from real package evidence.

### RUST-DOM: Read Models, IO, And Scene Services

- `RUST-DOM-01`: Rust reads canonical snapshots for projects, scenes, levels,
  palettes, and FX graphs.
- `RUST-DOM-02`: selected formats pass semantic read/write/round-trip evidence.
- `RUST-DOM-03`: command/transaction/undo model passes deterministic replay.
- `RUST-DOM-04`: Qt presentation models consume committed Rust revisions.

Exit: one bounded production workflow is Rust-owned end to end, with C++ oracle
comparison.

### RUST-REN: Rust Renderer

- `RUST-REN-01`: offscreen `wgpu` reference/compositing path passes.
- `RUST-REN-02`: Metal, Vulkan, and Windows release backends pass the named
  corpus.
- `RUST-REN-03`: Qt viewer presentation, input mapping, DPI, color, and device
  loss pass.
- `RUST-REN-04`: render scheduling, caches, FX families, and final output meet
  correctness and performance budgets.

Exit: Rust renderer is the default in preview and final render packages; the
C++ backend has an approved removal plan.

### RUST-APP: Application Ownership Convergence

- `RUST-APP-01`: tools and high-frequency input use Rust transactions.
- `RUST-APP-02`: scripting/plugin/farm/hardware contracts are complete.
- `RUST-APP-03`: new Qt Quick surfaces use approved `qtbridge`; retained Widgets
  use a small C++ shell.
- `RUST-APP-04`: remaining C++ inventory is classified as remove, retain, or
  external/vendor.

Exit: Rust owns the agreed product core and the remaining C++ policy is
explicit. “Zero C++” is a separate optional gate.

## Differential Verification Strategy

Every port slice should use the same proof ladder:

1. **Characterization:** capture current behavior, errors, timing, and
   nondeterminism before editing.
2. **Unit/reference:** test pure Rust logic against hand-checked cases and a
   scalar reference.
3. **Differential:** run C++ and Rust on identical normalized input.
4. **Integrated:** run through the real bridge in the Qt application.
5. **Packaged:** run from clean supported packages.
6. **Workflow:** complete the named artist operation, including undo, cancel,
   save, reopen, render, and failure.
7. **Performance:** compare wall time, CPU, peak memory, GPU memory, cache
   behavior, and responsiveness.
8. **Soak/fault:** cancellation, shutdown, corrupt input, out-of-memory,
   device-loss, hotplug, and repeated open/close.

Comparison outputs:

| Surface | Required evidence |
|---|---|
| Domain snapshots | Canonical JSON plus schema version and semantic diff |
| Persistence | Read parity, semantic round trip, byte diff where stability is required, malformed corpus |
| Raster/FX | Exact match for integer/scalar paths; documented tolerance for GPU/AA paths; alpha-edge and color-space checks |
| Vector | Topology, region/fill identity, bounds, control points, rasterized references |
| Commands/undo | State hashes and event sequence before/after/replay |
| UI models | Rows, roles, edits, selections, reset/insert/remove event sequence |
| Input/tools | Recorded device events, produced strokes/commands, cursor/overlay screenshots |
| Renderer | Image artifacts, backend/adapter/driver, pipeline/shader hashes, timing/memory |
| Packages | Clean launch, plugin discovery, resources, translations, signing, crash symbols |

Do not silently update goldens. A golden update must name the intended behavior
change, reviewer, source commit, and affected fixtures.

## Migration Slice Workflow

The repeatable workflow and evidence template are in
`doc/rust_porting_workflow.md`. In summary:

1. select one boundary from evidence;
2. characterize C++ behavior;
3. design the data/ownership/thread contract;
4. implement Rust behind a feature switch;
5. dual-run and compare;
6. enable Rust by default for a narrow cohort or lane;
7. retain fallback through the agreed release window;
8. remove C++ only after package and workflow proof;
9. record a retrospective and strengthen a durable guard only when evidence
   shows repetition.

## Toolchain And Quality Policy

Initial policy:

- pin stable Rust in `rust-toolchain.toml`;
- use the 2024 Rust edition for new crates unless the selected Qt bridge
  requires a documented exception;
- check in `Cargo.lock` for the application workspace;
- deny warnings in project crates after bootstrap;
- run `cargo fmt`, Clippy, unit/integration/doc tests, dependency/license audit,
  and platform builds;
- use sanitizers on the C++/FFI lane where supported;
- use Miri for suitable pure Rust/unsafe-wrapper tests;
- use fuzzing for parsers, plugin messages, and bridge decoding;
- centralize `unsafe` in `*-sys`, GPU backend, SIMD, and bridge modules;
- require a safety comment and focused test for every new `unsafe` block;
- prohibit network access in ordinary builds;
- vendor or mirror bridge/build dependencies according to project release
  policy before relying on them.

The exact Rust version must satisfy both selected `wgpu` and bridge versions.
At the time of this survey, official Qt Bridge and current `wgpu` documentation
both name Rust 1.87 as a minimum, but the project must pin and verify a specific
toolchain rather than infer compatibility from matching minimums.

## Performance Strategy

Rust is not a performance plan by itself. Measure before choosing a slice.

Likely opportunities:

- tile-oriented raster buffers and explicit dirty regions;
- content-addressed render/cache keys;
- immutable render snapshots;
- work-stealing CPU execution for independent tiles;
- GPU compositing, previews, and selected compute kernels;
- bounded decode and thumbnail queues;
- fewer UI/render shared locks;
- batch FFI calls;
- explicit memory budgets and eviction;
- reusable staging/upload buffers.

Every optimization needs:

- a representative workload and cold/warm cases;
- a scalar/reference result;
- peak and steady-state memory;
- cancellation latency;
- UI frame-time or input-latency impact;
- backend/adapter/driver identity;
- regression thresholds in CI or retained benchmark reports.

Do not make GPU output the only correctness oracle. Drivers and antialiasing
vary; important integer compositing and format behavior need deterministic
references.

## Plugin, Scripting, And Compatibility Policy

### Plugins

Preserve the current plugin ABI while the host moves. Wrap it:

- raw `otz-plugin-sys` mirrors versioned C tables and handles;
- safe `otz-plugin-api` owns validation, lifetimes, typed parameters, tiles,
  cancellation, and error conversion;
- a conformance host runs plugins against synthetic and real fixtures;
- plugin crashes may be isolated in a worker process where practical.

Do not expose Rust traits directly as the dynamic ABI.

### Scripting

Qt 6 scripting behavior must be frozen before the Rust application model moves.
Rust domain commands should expose a language-neutral automation API. Existing
scripts can continue through a compatibility adapter. A future scripting
language decision must inventory real scripts and required bindings first.

### Formats

Keep current third-party/native implementations behind adapters until each
format corpus proves a replacement. Pure Rust availability is not sufficient
evidence for PSD, modified TIFF, FFmpeg/movie behavior, MyPaint, color
management, scanners, cameras, or vendor SDKs.

## Risk Register

| Risk | Consequence | Control |
|---|---|---|
| Big-bang rewrite | Years without a trusted release | One bounded replaceable slice at a time |
| Translating classes literally | C++ coupling recreated in Rust | Domain/command architecture before mutation port |
| Bridge sprawl | Unsafe ownership and thread bugs | Few batch APIs, opaque handles, generated bridges, contract tests |
| Premature Qt Bridge adoption | Beta/API/platform blockers enter releases | Maturity spike and exact pin |
| QWidget/Qt Quick split | Inconsistent focus, style, input, accessibility | Convert coherent surfaces; package/manual matrix |
| Two GPU device owners | Copies, synchronization bugs, device loss | One renderer owner and explicit presentation adapter |
| QRhi private API dependence | Qt-minor breakage | Keep QRhi out of Rust core; bounded adapter only |
| `wgpu` breaking cadence | Frequent renderer churn | Pin versions and run explicit upgrade projects |
| Persistence drift | Old scenes load differently or cannot round-trip | Versioned corpus, semantic and byte comparisons |
| Hidden plugin behavior | Community projects break | Plugin inventory, conformance harness, compatibility window |
| GPU nondeterminism | False failures or unnoticed regressions | CPU references, tolerances, backend metadata |
| C++ fallback never removed | Permanent duplicate maintenance | Removal owner/date/gate for every slice |
| “Zero C++” becomes the metric | Safe retained adapters are rewritten without value | Track product ownership and risk, not line count |

## Effort And Staffing Reality

This is a multi-year product migration, not a seasonal refactor. Static source
size alone cannot produce a credible schedule. Before estimating dates, finish
`RUST-ORC` and two representative slices: one pure kernel and one Qt/render
integration slice. Their measured characterization, implementation,
cross-platform, review, and fallback-removal costs provide the first useful
velocity.

Plan around persistent specialties:

- OpenToonz scene/format/domain maintainers;
- Qt Widgets/Qt Quick and cross-platform packaging;
- Rust architecture and FFI;
- GPU/rendering and color;
- QA automation plus artist/studio verification;
- platform/hardware/plugin compatibility.

A small team can establish the architecture and early slices. It cannot safely
port scene, renderer, tools, UI, formats, hardware, and packages in parallel
without increasing integration risk. Scale only after contracts and the oracle
are stable.

## Best First Actions

After predecessor gates close:

1. create a dated baseline record for the C++/Qt 6/Metal-Vulkan release;
2. profile representative projects and choose one deterministic kernel;
3. add the Cargo/Nix/mise/CMake lane with no behavior change;
4. implement the versioned oracle/report protocol;
5. prove CXX and CXX-Qt lifetime, error, queue, shutdown, and packaging;
6. run the official Qt Bridge maturity spike without making it a release
   dependency;
7. run an offscreen `wgpu` triangle/texture/readback package probe on all
   supported platforms;
8. port the selected kernel behind dual-run comparison;
9. publish the first evidence record and retrospective;
10. only then approve the first production ownership transfer.

The implementation contract is
`doc/rust_port_codex_goal_prompt.md`. The repeatable operating procedure is
`doc/rust_porting_workflow.md`.

## Primary Sources

Framework state is time-sensitive. Recheck these sources before implementation
or dependency upgrades:

- [Qt Bridge for Rust 0.2 documentation](https://doc-snapshots.qt.io/qtbridge-rust/qtbridge/index.html)
- [Qt announcement of the Rust bridge public beta, July 1, 2026](https://www.qt.io/blog/qt-bridges-public-beta-for-rust)
- [CXX-Qt documentation](https://kdab.github.io/cxx-qt/book/)
- [CXX safe Rust/C++ interop](https://cxx.rs/)
- [CXX-Qt CMake integration](https://kdab.github.io/cxx-qt/book/getting-started/5-cmake-integration.html)
- [Corrosion CMake/Cargo integration](https://corrosion-rs.github.io/corrosion/)
- [`wgpu` project and platform support matrix](https://github.com/gfx-rs/wgpu)
- [`wgpu` backend reference](https://docs.rs/wgpu/latest/wgpu/enum.Backend.html)
- [Naga shader endpoint matrix](https://docs.rs/naga/latest/naga/)
- [Qt `QQuickRhiItem` and QRhi compatibility notes](https://doc.qt.io/qt-6/qquickrhiitem.html)
- [Qt `QWidget::createWindowContainer` limitations](https://doc.qt.io/qt-6/qwidget.html#createWindowContainer)
- [`ash` Vulkan bindings](https://docs.rs/ash/latest/ash/)
- [`objc2-metal` Metal bindings](https://docs.rs/objc2-metal/latest/objc2_metal/)
- [Rust FFI and unwinding guidance](https://doc.rust-lang.org/nomicon/unwinding.html)
- [bindgen C++ limitations](https://rust-lang.github.io/rust-bindgen/cpp.html)
