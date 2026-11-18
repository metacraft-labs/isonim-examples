# isonim-examples

Canonical home for [IsoNim](https://github.com/metacraft-labs/isonim)
showcase applications. Each demo lives once here as a layered set of
modules and is consumed by every platform-specific renderer (TUI, web,
GPUI, Freya, Cocoa, Android) without duplicated business logic.

## What this repo is

`isonim-examples` is the single canonical home for IsoNim demo apps
(the `task_app` showcase plus future demos that exercise the
cross-renderer surface). Renderer repositories such as `isonim-tui`,
`isonim-tui-serve`, `isonim-gpui`, `isonim-freya`, `isonim-cocoa` and
`isonim-android` consume this repo as a path-based dependency and
provide only the per-platform Layer 1 leaves and Layer 4 composition
roots — they never re-implement the demo's view-model or its view
template.

## Layered-demo architecture

Every demo follows the four-layer split documented in
`isonim-specs/isonim-cross-platform-architecture.md`.
Within this repo, the layers are organised on disk so that the shared
slices live under `<demo>/core/` and the per-platform slices live under
`<demo>/<platform>/`:

```text
<demo>/
  core/
    vm.nim               # Layer 3 - ViewModel (state, commands, derived signals)
    views.nim            # Layer 2 - composable view template (DSL idiom)
  tui/
    leaves.nim           # Layer 1 - TUI-specific leaf widgets
    main.nim             # Layer 4 - composition root for the TUI host
  web/
    leaves.nim           # Layer 1 - HTML/DOM leaf widgets
    main.nim             # Layer 4 - composition root for the web host
  gpui/                  # (future) Layer 1 + 4 for GPUI
  freya/                 # (future) Layer 1 + 4 for Freya
  cocoa/                 # (future) Layer 1 + 4 for Cocoa
  android/               # (future) Layer 1 + 4 for Android
```

- **Layer 3 (ViewModel) is shared.** The `core/vm.nim` module owns all
  state, commands, and derived signals. It depends only on the IsoNim
  reactive core — never on a renderer.
- **Layer 2 (view template) is shared.** The `core/views.nim` module
  expresses the demo's structure with the DSL idiom (single `ui()`
  block, slot-based composition); it parametrises over a `Leaves`
  bundle so it can be rendered by any platform.
- **Layer 1 (leaves) is per-platform.** Each `<demo>/<platform>/leaves.nim`
  satisfies the leaf bundle protocol against the renderer it targets.
- **Layer 4 (composition root) is per-platform.** Each
  `<demo>/<platform>/main.nim` wires the shared VM + view template to
  the platform leaves and runs the host loop.

This split is the contract that keeps demo behaviour in lock-step
across every renderer that ships in the IsoNim render-stream effort.

## Status (EX-M0 - scaffold only)

This is the foundational milestone. The repo currently ships only the
repo-requirements scaffold (flake, Justfile, CI, license, AGENTS.md,
.gitignore, .envrc, nimble manifest) plus a single
`tests/test_repo_requirements_skeleton.nim` smoke test that asserts
the scaffold is in place.

EX-M1 migrates the `task_app` shared core (`vm.nim`, `views.nim`)
from `isonim-tui/examples/task_app/core/` into this repo. EX-M2
migrates the TUI and web leaves. EX-M3..M6 add the GPUI, Freya,
Cocoa, and Android leaves.

## Commands

```sh
just build           # placeholder (no demo binaries until EX-M1+)
just test            # run the smoke test suite
just lint            # nim check + nixfmt --check + markdownlint
just format          # nimpretty + nixfmt
just bench           # placeholder until cross-renderer benches land
```

The matrix recipes (`test-arc`, `test-orc`, `test-refc`,
`test-threads-off`) exercise the charter mm x mode x threads grid.

## Project structure

```text
tests/
  test_repo_requirements_skeleton.nim   # asserts scaffold compliance
.github/workflows/ci.yml                # lint + test + charter matrix
flake.nix                               # nix devShell + checks
Justfile                                # build/test/lint/format
isonim_examples.nimble                  # single source of truth for version
AGENTS.md                               # this file (README.md is a symlink to it)
```

## Coding conventions

- Nim style: `--styleCheck:usages --styleCheck:error`, `--mm:orc` by
  default in the matrix.
- Markdown: enforced by `markdownlint-cli2` via the dev-shell
  pre-commit hook.
- Nix: `nixfmt-rfc-style`.
- Each demo's shared core is renderer-agnostic; the only IsoNim layers
  imported there are the reactive primitives + the DSL builder. Never
  import a Layer 1 module from `core/`.

## Try the editor

EX-M14 ships an IsoNim Editor instance configured with the two demo
apps. Build the per-backend launcher binaries, build the editor JS
bundle, and serve it on port 8091 (port 8090 is reserved for the
upstream `isonim` wanderlust editor):

```sh
direnv exec ~/metacraft/isonim-examples just build-backends
direnv exec ~/metacraft/isonim-examples just editor-build
direnv exec ~/metacraft/isonim-examples just editor-serve
```

The editor renders a combined catalog (Foundations / Components /
Patterns / Pages / Flows for both `task_app` and `settings_app`),
plus the M57 edge-strip chrome: the left-edge strip exposes the
Web / TUI / GPUI / Freya / Cocoa / Android backends (Cocoa and
Android surface as unavailable on Linux per the spec), and the
right-edge strip exposes the View / Comment / Edit mode toggle.

Per-backend dispatch convention: one launcher per Linux backend
(`build/backends/isonim-examples-{web,tui,gpui,freya}`). Each
launcher constructs the real demo Layer-4 composition for its
renderer (a `TaskAppVM` seeded with three sample tasks, or the
`SettingsVM` with the demo catalog when `--demo=settings`), wraps
the resulting tree in the matching `isonim-render-serve` adapter
(TUI rasteriser, GPUI tree raster, Freya tree raster, web stub
fingerprint), and streams real demo frames to the bridge.

What this means in practice:

- For the **Web** backend the editor renders the demo in-iframe via
  `srcdoc` (the launcher's WebSocket stream is the symmetric "every
  backend has a registered binary" entry; the iframe path is the
  surface the user sees inside the editor).
- For **TUI**, the launcher mounts a `TerminalTestHarness`, runs
  the demo's TUI composition root, and the bridge rasterises the
  resulting `ScreenBuffer` cell grid through an 8x8 ASCII bitmap
  font. Streamed frames carry real demo text (task names, settings
  group labels).
- For **GPUI** and **Freya**, the launcher builds the demo's
  headless element tree and the bridge rasterises it via the
  existing adapter. Each adapter adds a 2-pixel backend-identifier
  band (teal for GPUI, purple for Freya) so the canvas hashes stay
  pairwise distinct even when the two tree layouts converge.

EX-M15: the Freya backend now dispatches `--demo=tasks|settings`
end-to-end. `--demo=settings` mounts `settings_app/main_freya.nim`,
a vertically stacked card layout where every group renders as its
own `<div class="settings-card">` with the inner shared group
section showing all of its items simultaneously. This makes the
Freya chrome visibly distinct from the TUI accordion (one expanded
section), the web sidebar+pane (only the active group's items), and
the GPUI two-column grid (only the active group's items in the right
column). Cocoa / Android remain visibly disabled on Linux per spec.

## ViewModels over injected services: the conversation app

`conversation_app/` is the reference for writing a ViewModel against
services it is given, and for designing how fast a screen fills with data
while the UI is still a prototype. It is a conversation list beside a
transcript; the assistant's reply to a prompt is a streamed response.

```text
conversation_app/core/
  services.nim          # the service interface the ViewModel calls
  real_service.nim      # the product's service logic (store + language model)
  standin.nim           # the ONE stand-in, parametric (data, reply, failures)
  network_services.nim  # the interface behind a simulated connection
  vm.nim                # the ViewModel
  views.nim             # the View, generic over the renderer
```

The same ViewModel runs over four sets of services: the real service in
the product; a recording mock in unit tests
(`tests/test_conversation_vm_with_mocks.nim`); the real service with only
the language model scripted in the headless integration test
(`tests/test_conversation_headless_integration.nim`); and the stand-in in
the IsoNim Editor. The stand-in runs the product's own service logic over a
fixture store, so every control works in a preview: a sent prompt stays in
the transcript, a new conversation appears in the list. An editor state is
the stand-in's parameters plus a network profile; it never sets ViewModel
signals.

Perceived-performance techniques, each visible in `vm.nim`:

- placeholders: skeleton rows and bubbles until data arrives, a typing
  indicator until the reply's first increment;
- batching: one `loadInitialScreen` call returns the first page of the list
  and the first transcript together;
- initial screen first, then backfill: the rest of the list is fetched in
  pages after the first screen is up;
- streaming: the reply is a `ServiceStream[string]` rendered as it grows;
- readiness marks: `conversations:first`, `conversations`, `transcript` per
  load and `reply:first`, `reply` per prompt (`isonim/services/readiness`).

In the editor (`just editor-serve`, then Pages → "Conversation App / Pages")
each story is an editor state from `conversation_app/editor_states.nim`:
typical data under instant, 4G and slow-3G connections, empty, large (500
conversations backfilled in pages), a failing first screen, and a reply that
breaks off. `editor/conversation_mount.nim` mounts the live screen into the
web preview, so sending a prompt, switching conversations, Retry and New
conversation all work there. `just test-browser-conversation` drives those
stories in a headless browser.

For agents, `conversation_app/measure_readiness.nim` loads editor states
under chosen profiles on simulated time and prints every readiness mark as
JSON, so designs are compared by numbers:

```sh
nim c -r -d:release conversation_app/measure_readiness.nim \
  --profiles:instant,4g,slow-3g "--states:Typical (4G),Large (4G)"
```

`withNetwork(services, profile)` puts any implementation behind a simulated
connection (`isonim/services/network`: latency, bandwidth, jitter, failure
rate; presets from `InstantNetwork` to `Slow3GNetwork`). The integration test
prints the readiness marks per profile as JSON:

```sh
nim c -r --path:tests tests/test_conversation_headless_integration.nim
```

## Testing async ViewModels

The canonical example is `tests/test_async_perf_demo.nim`. Read it to
learn the pattern:

1. Install a `FakeAsyncContext` from nim-everywhere.
2. Construct an `AsyncDriver` bundling the fake clock + a seeded
   `FakeDb` (helper at `tests/helpers/async_drive.nim`).
3. Mount the VM with the driver's db.
4. After each VM action, call `drv.flush()` to advance the clock and
   drain pending callbacks.
5. Assert against VM signals — they reflect the post-async state.

The headline assertion: 100 mixed simulated ops complete in <100 ms
wall-clock, even though each op nominally takes 30-50 ms. Fake time
short-circuits the sleep, but every other path (signal propagation,
generation-counter guard for out-of-order completions, error handling)
runs through the real reactive graph.

## Specs

- The architecture is governed by
  [`isonim-specs/isonim-cross-platform-architecture.md`](../isonim-specs/isonim-cross-platform-architecture.md).
- Per-milestone progress is tracked in
  [`isonim-specs/isonim-render-stream.status.org`](../isonim-specs/isonim-render-stream.status.org).
- Repo-level conformance is governed by
  [`metacraft-specs/policies/repo-requirements.md`](../metacraft-specs/policies/repo-requirements.md).
