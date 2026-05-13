## test_editor_streaming_preview — EX-M14 strong-integration test for
## the streaming-preview registry + StreamingPreviewVM wiring.
##
## This test does *not* spawn real bridge subprocesses (the
## ``launchBridge`` proc is guarded by ``when not defined(js)`` and is
## reachable on native, but we intentionally avoid spawning binaries
## from the unit-test matrix — that path is exercised by the
## Playwright spec in ``tests/browser/specs/editor-demo.spec.ts``).
##
## What it asserts:
##   * the registry produced by ``newDemoBackendRegistry`` resolves
##     to a path the test can stat after the binary build has run
##     (the test fabricates a sentinel file so the path resolves on
##     a clean checkout too — the Playwright spec runs against the
##     real binaries).
##   * the `StreamingPreviewVM` reports the correct `availableBackends`
##     subset on Linux and behaves correctly when the user picks a
##     backend (selectedBackend / status / needsBridge memo update).

import std/[options, os, unittest]

import isonim/core/owner
import isonim/core/signals
import isonim/core/computation
import isonim/editor/streaming_preview

import editor/workspace as demo_workspace

suite "EX-M14: streaming-preview registry":
  test "registry's registered backend paths resolve":
    let buildDir = getTempDir() / "isonim-examples-test-build"
    createDir(buildDir)
    defer: removeDir(buildDir)
    # Stage sentinel files for each registered backend so the path
    # check matches a real on-disk file even before `build-backends`
    # has run. This is purely for the registry mapping; the bridge
    # launcher is exercised by the Playwright spec.
    for backend in LinuxRegistrableBackends:
      let path = backendBinaryPath(buildDir, backend)
      writeFile(path, "#!/bin/sh\nexit 0\n")
    let reg = newDemoBackendRegistry(buildDir)
    for backend in LinuxRegistrableBackends:
      let p = reg.binaryFor(backend)
      check p.isSome
      check fileExists(p.get())
    when defined(macosx):
      check reg.binaryFor(pbCocoa).isSome
    else:
      check reg.binaryFor(pbCocoa).isNone
    when defined(macosx) or defined(linux):
      check reg.binaryFor(pbAndroid).isSome
    else:
      check reg.binaryFor(pbAndroid).isNone

  test "StreamingPreviewVM reflects available backends on this host":
    createRoot proc(dispose: proc()) =
      let vm = newStreamingPreviewVM(initial = pbWeb,
        available = @[pbWeb, pbTui, pbGpui, pbFreya])
      check vm.selectedBackend.val == pbWeb
      check vm.availableBackends.val == @[pbWeb, pbTui, pbGpui, pbFreya]
      check vm.needsBridge.val == false # Web doesn't need a bridge
      check vm.bridgeUrl.val == ""
      vm.selectBackend(pbGpui)
      check vm.selectedBackend.val == pbGpui
      check vm.needsBridge.val == true
      check vm.status.val == bsLaunching
      vm.selectBackend(pbAndroid) # not in availableBackends
      check vm.lastError.val.len > 0
      check vm.status.val == bsError
      dispose()

  test "registry-driven availability map matches host expectations":
    # Build the registry but DO NOT stage sentinel files. The streaming
    # preview module's availability list is independent of the registry
    # — `detectAvailableBackends` returns what the host can serve; the
    # registry only tells `launchBridge` *where* to find the binary.
    let reg = newDemoBackendRegistry(getTempDir() / "no-such-dir")
    let availableSet = detectAvailableBackends()
    check pbWeb in availableSet
    check pbTui in availableSet
    when defined(linux):
      # Linux must expose GPUI + Freya so the M57 strip can route to
      # them; their bridge binaries are produced by `just build-backends`.
      check pbGpui in availableSet
      check pbFreya in availableSet
      check reg.binaryFor(pbGpui).isSome
      check reg.binaryFor(pbFreya).isSome
