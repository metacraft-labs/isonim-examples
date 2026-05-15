## isonim-examples/editor/workspace.nim — constructs the
## `EditorWorkspace` consumed by the standalone IsoNim editor instance
## for the demo apps, plus the matching `BackendBinaryRegistry` used by
## the RS-M7 streaming-preview module to spawn per-backend bridges.
##
## EX-M14: documented under the editor-instance milestone in
## `codetracer-specs/Front-Ends/IsoNim/isonim-render-stream.status.org`.
##
## *Per-backend dispatch convention.* This workspace registers one
## binary per backend (Web / TUI / GPUI / Freya). Each binary is a
## single launcher that selects which demo to render via the
## ``--demo=<task|settings>`` CLI flag. Cocoa and Android are
## intentionally left unregistered on Linux so the M57 left-edge
## strip lists them as aria-disabled (the spec's "host can't serve
## the backend; surface, don't hide" rule).

import std/os

import isonim/editor/types
import isonim/editor/workspace as editor_workspace
import isonim/editor/streaming_preview

import ./stories

export editor_workspace, streaming_preview, stories

const
  DemoEditorTitle* = "IsoNim Examples Editor"
  DemoEditorId* = "isonim-examples"
  DemoEditorDescription* =
    "Editor workspace for the task_app and settings_app showcase demos"

# ---------------------------------------------------------------------------
# Backend binary registry
# ---------------------------------------------------------------------------

const
  BackendBinaryNames*: array[PreviewBackend, string] = [
    pbWeb:     "isonim-examples-web",
    pbTui:     "isonim-examples-tui",
    pbGpui:    "isonim-examples-gpui",
    pbFreya:   "isonim-examples-freya",
    pbCocoa:   (when defined(macosx): "isonim-examples-cocoa" else: ""),
      # EX-M19: registered on macOS hosts (the launcher binary is
      # produced by `just build-backends-macos`). On Linux remains
      # unregistered so the M57 left-edge strip surfaces Cocoa as
      # aria-disabled per the spec's "host can't serve the backend;
      # surface, don't hide" rule.
    pbAndroid: (when defined(macosx) or defined(linux):
                  "isonim-examples-android" else: ""),
      # EX-M21: registered on macOS + Linux hosts (the launcher binary
      # is produced by `just build-backends-android`). The launcher
      # itself is a host-side process that talks to a connected
      # Android device via `adb`; both macOS and Linux dev hosts can
      # build + run it. Other hosts (Windows in principle) remain
      # unregistered.
    pbIos:     (when defined(macosx): "isonim-examples-ios" else: ""),
      # iOS UIKit-on-device launcher (host-side). macOS-only because
      # Apple's iOS dev tooling (Bonjour discovery + Wi-Fi pairing) is
      # Mac-only. Linux iOS-on-network is theoretically possible but
      # out-of-scope for the prototype; the registry leaves pbIos
      # unregistered there so the M57 left-edge strip surfaces it as
      # aria-disabled per the spec's "host can't serve the backend;
      # surface, don't hide" rule.
  ]

  LinuxRegistrableBackends* = [pbWeb, pbTui, pbGpui, pbFreya]
    ## The four backends whose binaries the
    ## ``just build-backends`` Justfile target produces on Linux.
    ## Cocoa registration happens via the macOS-only build path
    ## (`just build-backends-macos`); the editor's
    ## ``newDemoBackendRegistry`` proc consults
    ## ``BackendBinaryNames[pbCocoa]`` at runtime, which evaluates to
    ## non-empty on macOS hosts.

  MacosRegistrableBackends* = [pbCocoa, pbIos]
    ## The macOS-only launcher binaries: Cocoa (EX-M19) and iOS (host-
    ## side launcher that streams UIKit frames from a paired iPhone
    ## over Wi-Fi). Both are produced by the macOS-only
    ## ``just build-backends-macos`` + ``just build-backends-ios``
    ## Justfile targets.

  AndroidRegistrableBackends* = [pbAndroid]
    ## The Android launcher binary that the
    ## ``just build-backends-android`` Justfile target produces
    ## (EX-M21). The launcher itself runs on the host (macOS or Linux);
    ## it drives a connected Android device via `adb`.

proc backendBinaryPath*(buildDir: string; backend: PreviewBackend): string =
  ## Resolve the absolute path of the binary that hosts the streaming
  ## bridge for ``backend``. Returns the empty string for backends that
  ## the demo workspace does not register on the current host.
  let name = BackendBinaryNames[backend]
  if name.len == 0:
    return ""
  buildDir / name

proc newDemoBackendRegistry*(buildDir: string): BackendBinaryRegistry =
  ## Populate a `BackendBinaryRegistry` with the demo-app launcher paths
  ## available on the current host:
  ##   * Linux:  Web, TUI, GPUI, Freya, Android (EX-M21's launcher;
  ##             host-side process that talks to a connected device
  ##             over `adb`).
  ##   * macOS:  the Linux five PLUS Cocoa (EX-M19's launcher).
  ##   * Other (e.g. Windows): only the four Linux launchers; both
  ##     Cocoa and Android remain unregistered and the M57 strip
  ##     surfaces them as aria-disabled per the spec's "host can't
  ##     serve the backend; surface, don't hide" rule.
  result = newBackendBinaryRegistry()
  for backend in LinuxRegistrableBackends:
    let path = backendBinaryPath(buildDir, backend)
    if path.len > 0:
      result.registerBackendBinary(backend, path)
  when defined(macosx):
    for backend in MacosRegistrableBackends:
      let path = backendBinaryPath(buildDir, backend)
      if path.len > 0:
        result.registerBackendBinary(backend, path)
  when defined(macosx) or defined(linux):
    for backend in AndroidRegistrableBackends:
      let path = backendBinaryPath(buildDir, backend)
      if path.len > 0:
        result.registerBackendBinary(backend, path)

proc defaultDemoBuildDir*(): string =
  ## Convenience for tests + the standalone editor: resolve the
  ## ``build/backends`` directory relative to this source file. The
  ## absolute path is preferred over a relative one so the bridge
  ## launcher's `fileExists` check works no matter the cwd at launch.
  currentSourcePath().parentDir.parentDir / "build" / "backends"

# ---------------------------------------------------------------------------
# Editor workspace constructor
# ---------------------------------------------------------------------------

proc newDemoEditorWorkspace*(initialPlatform: Platform = pbWeb;
                              previewHook: ProjectPreviewHook = demoPreviewHook):
                              EditorWorkspace =
  ## Build the `EditorWorkspace` the demo editor mounts. Read-only
  ## permissions for EX-M14 — the milestone's edit mode stays
  ## read-only; write-back is M11 in the editor spec.
  let groups = buildDemoStoryGroups()
  let canvas = demoCanvasItems(groups)
  let flow = demoFlowSteps(groups)
  newEditorWorkspace(
    title = DemoEditorTitle,
    storyGroups = groups,
    id = DemoEditorId,
    description = DemoEditorDescription,
    canvasItems = canvas,
    flowSteps = flow,
    previewHook = previewHook,
    permissions = EditorWorkspacePermissions(
      readSource: true,
      writeSource: false,
      createStory: false,
      createVariant: false,
      duplicate: false,
      delete: false),
    platform = initialPlatform)
