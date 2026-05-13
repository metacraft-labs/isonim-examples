## test_android_leaves_compile — EX-M6 Linux-side cross-compile gate.
##
## EX-M6 ships the Android leaves as a partial-linux scaffold: the
## actual leaf bodies (in `task_app/android/leaves.nim`) are gated `when
## defined(android)` because driving them end-to-end requires either an
## Android emulator (the macOS-host responsibility per EX-M6) or the
## host-side MockJNI shim (`-d:mockJni`) that the existing
## `isonim-android` tests use. The macOS engineer runs the real
## integration test (`test_android_leaves_android_only.nim`) on an
## emulator (Android Studio's emulator runs natively on Apple Silicon);
## this test runs *here on Linux* and validates the leaf surface
## without needing an emulator, by:
##
##   1. **Cross-compile gate.** Driving `nim check --os:android
##      -d:mockJni` over the Android-only fixture in
##      `tests/helpers/views_compile_android.nim` (which mirrors the
##      renderer-facing surface of the real Android leaves
##      byte-for-byte). This proves the `AndroidRenderer` protocol
##      surface (`createElement`, `setAttribute`, `appendChild`,
##      `addEventListener`, `setTextContent`, `removeAttribute`, ...)
##      compiles on the Android target — drift in the leaves' calls
##      into `isonim_android/renderer` surfaces here, not on the
##      emulator host. (Unlike the EX-M5 Cocoa case, the IsoNim
##      reactive core compiles cleanly under `--os:android` from a
##      Linux host, but we still drive the surface fixture rather than
##      the real leaves so a future signals-side regression doesn't
##      drag the gate down.)
##
##   2. **Static surface check.** Greping the real
##      `task_app/android/leaves.nim` to assert the five canonical leaf
##      signatures (`appShell`, `taskInput`, `filterBar`, `taskList`,
##      `summaryBar`) are present, plus the per-VM `leavesFor` /
##      `resetAndroidLeaves` helpers. The leaves bind to VM signals
##      reactively via `createRenderEffect` / `forEachKeyed` (matching
##      the GPUI / Freya / Cocoa pattern) — there is no longer a
##      `rerender(vm)` proc. If anyone deletes one of these without
##      renaming the contract, the gate fails before the macOS engineer
##      has to find out at integration time.
##
##   3. **Composition-root surface check.** Same idea for
##      `task_app/main_android.nim` — assert the composition root still
##      exports `runTaskApp` / `buildTaskApp` and gates its body with
##      `when defined(android)`.
##
## Mirrors the EX-M5 Cocoa cross-compile gate
## (`test_cocoa_leaves_compile.nim`) and the L3 / M10 cross-compile-gate
## pattern used by `just check-windows-cross` / `just check-macos-cross`
## elsewhere in metacraft. It is **not** a substitute for the
## emulator-host integration test — see
## `test_android_leaves_android_only.nim` and the EX-M6 status block's
## hand-off checklist.

import std/[unittest, os, osproc, strutils]

const
  # The repo root is two parents up from this test file. We use
  # `currentSourcePath()` so the test works regardless of where it's
  # invoked from (Justfile recipes `cd` into the repo first; manual
  # `nim c -r` invocations might not).
  repoRoot = currentSourcePath().parentDir.parentDir
  androidLeavesPath = repoRoot / "task_app" / "android" / "leaves.nim"
  androidMainPath = repoRoot / "task_app" / "main_android.nim"
  androidFixturePath = repoRoot / "tests" / "helpers" / "views_compile_android.nim"

suite "EX-M6: Android leaves cross-compile gate (Linux-side)":

  test "cross-compile: nim check --os:android accepts the Android fixture":
    ## Drive `nim check --os:android -d:mockJni` over
    ## `helpers/views_compile_android.nim`. The fixture exercises the
    ## same renderer-facing surface the real Android leaves use; if
    ## `isonim_android/renderer`'s API drifts under `--os:android` the
    ## gate catches it from this Linux host.
    ##
    ## We pass `-d:mockJni` because `isonim_android/jni_callbacks` has
    ## a hard `{.error.}` requiring either `-d:mockJni` (host-side
    ## test shim) or `-d:commandBuffer` (real Android JNI bridge). On
    ## a Linux host with no Android NDK, mockJni is the only option.
    let cmd = "nim check --os:android --mm:orc " &
              "-d:mockJni " &
              "--styleCheck:usages --styleCheck:error " &
              "--path:" & repoRoot / "tests" & " " &
              "--path:" & repoRoot & " " &
              androidFixturePath.quoteShell
    let (output, exitCode) = execCmdEx(cmd)
    if exitCode != 0:
      echo "----- nim check --os:android output -----"
      echo output
      echo "-----------------------------------------"
    check exitCode == 0

  test "cross-compile sanity: nim check --os:linux accepts the Android fixture":
    ## Sanity check requested by the EX-M6 brief: the fixture should
    ## also compile under the host OS (`--os:linux` here) with
    ## `-d:mockJni`. This catches surface drift that would only show
    ## up on the host's preferred toolchain, separate from the
    ## `--os:android` cross-compile path above.
    let cmd = "nim check --os:linux --mm:orc " &
              "-d:mockJni " &
              "--styleCheck:usages --styleCheck:error " &
              "--path:" & repoRoot / "tests" & " " &
              "--path:" & repoRoot & " " &
              androidFixturePath.quoteShell
    let (output, exitCode) = execCmdEx(cmd)
    if exitCode != 0:
      echo "----- nim check --os:linux output -----"
      echo output
      echo "---------------------------------------"
    check exitCode == 0

  test "static surface: real leaves file declares the canonical signatures":
    ## The `nim check` gates above run against the *fixture*, not the
    ## real leaves (because the real leaves transitively import
    ## `isonim/core/signals` and `task_app/core/vm`; we keep the
    ## fixture self-contained for the same reason EX-M5 did, even
    ## though the Android cross-compile case doesn't trip the
    ## reactive-core macOS regression). To catch leaf-name or
    ## signature drift in the real file, grep for the canonical
    ## procs.
    check fileExists(androidLeavesPath)
    let body = readFile(androidLeavesPath)
    # Five canonical leaf names — must match `core/views.nim`'s expectations.
    check "proc appShell*(r: AndroidRenderer; vm: TaskAppVM): AndroidElement" in body
    check "proc taskInput*(r: AndroidRenderer; vm: TaskAppVM): AndroidElement" in body
    check "proc filterBar*(r: AndroidRenderer; vm: TaskAppVM): AndroidElement" in body
    check "proc taskList*(r: AndroidRenderer; vm: TaskAppVM): AndroidElement" in body
    check "proc summaryBar*(r: AndroidRenderer; vm: TaskAppVM): AndroidElement" in body
    # Per-VM bookkeeping helpers used by the composition root + tests.
    check "proc leavesFor*(vm: TaskAppVM): TaskAppAndroidLeavesState" in body
    check "proc resetAndroidLeaves*()" in body
    # EX-M23c follow-up: the leaves are now reactive (each `createElement`
    # is paired with a `createRenderEffect` so VM mutations propagate
    # through the reactive graph). There is no longer a public
    # `rerender(vm)` proc; instead, assert the reactive pattern is in
    # use.
    check "createRenderEffect" in body
    check "forEachKeyed" in body
    # The whole module body must be gated on `android` so a Linux build
    # sees an empty shell; protect against accidental ungating.
    # RS-M11c relaxed the gate to also accept ``defined(mockJni)`` so
    # the host-side launcher can build an in-process Android tree
    # for the element-tree manifest builder.
    check ("when defined(android):" in body or
           "when defined(android) or defined(mockJni):" in body)

  test "static surface: composition root exports the canonical entry points":
    check fileExists(androidMainPath)
    let body = readFile(androidMainPath)
    check "proc buildTaskApp*(r: AndroidRenderer; vm: TaskAppVM): AndroidElement" in body
    check "proc runTaskApp*(vm: TaskAppVM): AndroidElement" in body
    check "include task_app/core/views" in body
    check ("when defined(android):" in body or
           "when defined(android) or defined(mockJni):" in body)
