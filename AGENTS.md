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
`codetracer-specs/Front-Ends/IsoNim/isonim-cross-platform-architecture.md`.
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
AGENTS.md                               # this file (README/CLAUDE symlink)
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

## Specs

- The architecture is governed by
  [`codetracer-specs/Front-Ends/IsoNim/isonim-cross-platform-architecture.md`](../codetracer-specs/Front-Ends/IsoNim/isonim-cross-platform-architecture.md).
- Per-milestone progress is tracked in
  [`codetracer-specs/Front-Ends/IsoNim/isonim-render-stream.status.org`](../codetracer-specs/Front-Ends/IsoNim/isonim-render-stream.status.org).
- Repo-level conformance is governed by
  [`metacraft-specs/policies/repo-requirements.md`](../metacraft-specs/policies/repo-requirements.md).
