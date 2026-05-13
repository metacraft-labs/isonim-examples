## test_cocoa_leaves_compile — EX-M5 Linux-side cross-compile gate.
##
## EX-M5 ships the Cocoa leaves as a partial-linux scaffold: the actual
## leaf bodies (in `task_app/cocoa/leaves.nim`) are gated `when
## defined(macosx)` because `isonim_cocoa/renderer` transitively
## imports the AppKit / Objective-C-runtime wrappers, which cannot be
## compiled on a Linux host. The macOS engineer runs the real
## integration test (`test_cocoa_leaves_macos_only.nim`) on a macOS
## box; this test runs *here on Linux* and validates the leaf surface
## without needing AppKit, by:
##
##   1. **Cross-compile gate.** Driving `nim check --os:macosx` over
##      the Cocoa-only fixture in `tests/helpers/views_compile_cocoa.nim`
##      (which mirrors the renderer-facing surface of the real Cocoa
##      leaves byte-for-byte). This proves the `CocoaRenderer`
##      protocol surface (`createElement`, `setAttribute`,
##      `appendChild`, `addEventListener`, `setTextContent`,
##      `removeAttribute`, ...) compiles on the macOS target — drift
##      in the leaves' calls into `isonim_cocoa/renderer` surfaces
##      here, not on the macOS host.
##
##   2. **Static surface check.** Greping the real
##      `task_app/cocoa/leaves.nim` to assert the five canonical leaf
##      signatures (`appShell`, `taskInput`, `filterBar`, `taskList`,
##      `summaryBar`) are present, plus the per-VM `leavesFor` /
##      `resetCocoaLeaves` helpers. The leaves bind to VM signals
##      reactively via `createRenderEffect` / `forEachKeyed` (matching
##      the GPUI / Freya pattern) — there is no longer a `rerender(vm)`
##      proc. If anyone deletes one of these without renaming the
##      contract, the gate fails before the macOS engineer has to find
##      out at integration time.
##
##   3. **Composition-root surface check.** Same idea for
##      `task_app/main_cocoa.nim` — assert the composition root still
##      exports `runTaskApp` / `buildTaskApp` and gates its body with
##      `when defined(macosx)`.
##
## Mirrors the L3 / M10 cross-compile-gate pattern used by `just
## check-windows-cross` / `just check-macos-cross` elsewhere in
## metacraft. It is **not** a substitute for the macOS-host integration
## test — see `test_cocoa_leaves_macos_only.nim` and the EX-M5 status
## block's hand-off checklist.
##
## Known caveat: the IsoNim reactive core (`isonim/core/signals.nim`)
## is itself currently un-compilable under `--os:macosx --mm:orc` from
## a Linux host (the `Updates` / `Effects` global-var declarations
## become ambiguous against macOS-only stdlib symbols). The
## cross-compile fixture in `tests/helpers/views_compile_cocoa.nim`
## therefore avoids importing `isonim/core/signals` and substitutes a
## minimal `TaskAppVM` shape so the leaf-surface check can run today.
## Fixing the reactive-core macOS regression is tracked outside this
## milestone — when it lands, this test will be extended to drive the
## *real* `task_app/cocoa/leaves.nim` through `nim check --os:macosx`
## as well.

import std/[unittest, os, osproc, strutils]

const
  # The repo root is two parents up from this test file. We use
  # `currentSourcePath()` so the test works regardless of where it's
  # invoked from (Justfile recipes `cd` into the repo first; manual
  # `nim c -r` invocations might not).
  repoRoot = currentSourcePath().parentDir.parentDir
  cocoaLeavesPath = repoRoot / "task_app" / "cocoa" / "leaves.nim"
  cocoaMainPath = repoRoot / "task_app" / "main_cocoa.nim"
  cocoaFixturePath = repoRoot / "tests" / "helpers" / "views_compile_cocoa.nim"

suite "EX-M5: Cocoa leaves cross-compile gate (Linux-side)":

  test "cross-compile: nim check --os:macosx accepts the Cocoa fixture":
    ## Drive `nim check --os:macosx` over `helpers/views_compile_cocoa.nim`.
    ## The fixture exercises the same renderer-facing surface the real
    ## Cocoa leaves use; if `isonim_cocoa/renderer`'s API drifts under
    ## `--os:macosx` the gate catches it from this Linux host.
    let cmd = "nim check --os:macosx --mm:orc " &
              "--styleCheck:usages --styleCheck:error " &
              "--path:" & repoRoot / "tests" & " " &
              "--path:" & repoRoot & " " &
              cocoaFixturePath.quoteShell
    let (output, exitCode) = execCmdEx(cmd)
    if exitCode != 0:
      echo "----- nim check --os:macosx output -----"
      echo output
      echo "----------------------------------------"
    check exitCode == 0

  test "static surface: real leaves file declares the canonical signatures":
    ## The `nim check` gate above runs against the *fixture*, not the
    ## real leaves (because the real leaves transitively import
    ## `isonim/core/signals`, which has its own pre-existing macOS
    ## cross-compile bug — see module docstring). To catch leaf-name
    ## or signature drift in the real file, grep for the canonical
    ## procs.
    check fileExists(cocoaLeavesPath)
    let body = readFile(cocoaLeavesPath)
    # Five canonical leaf names — must match `core/views.nim`'s expectations.
    check "proc appShell*(r: CocoaRenderer; vm: TaskAppVM): CocoaElement" in body
    check "proc taskInput*(r: CocoaRenderer; vm: TaskAppVM): CocoaElement" in body
    check "proc filterBar*(r: CocoaRenderer; vm: TaskAppVM): CocoaElement" in body
    check "proc taskList*(r: CocoaRenderer; vm: TaskAppVM): CocoaElement" in body
    check "proc summaryBar*(r: CocoaRenderer; vm: TaskAppVM): CocoaElement" in body
    # Per-VM bookkeeping helpers used by the composition root + tests.
    check "proc leavesFor*(vm: TaskAppVM): TaskAppCocoaLeavesState" in body
    check "proc resetCocoaLeaves*()" in body
    # EX-M23c follow-up: the leaves are now reactive (each `createElement`
    # is paired with a `createRenderEffect` so VM mutations propagate
    # through the reactive graph). There is no longer a public
    # `rerender(vm)` proc; instead, assert the reactive pattern is in
    # use.
    check "createRenderEffect" in body
    check "forEachKeyed" in body
    # The whole module body must be gated on `macosx` so a Linux build
    # sees an empty shell; protect against accidental ungating.
    check "when defined(macosx):" in body

  test "static surface: composition root exports the canonical entry points":
    check fileExists(cocoaMainPath)
    let body = readFile(cocoaMainPath)
    check "proc buildTaskApp*(r: CocoaRenderer; vm: TaskAppVM): CocoaElement" in body
    check "proc runTaskApp*(vm: TaskAppVM): CocoaElement" in body
    check "include task_app/core/views" in body
    check "when defined(macosx):" in body
