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
    pbCocoa:   "",  # left unregistered on Linux — M57 strip surfaces as disabled
    pbAndroid: "",
  ]

  LinuxRegistrableBackends* = [pbWeb, pbTui, pbGpui, pbFreya]
    ## The four backends whose binaries the
    ## ``just build-backends`` Justfile target produces on Linux.

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
  ## for every Linux backend. Cocoa and Android remain unregistered —
  ## the M57 strip surfaces them as unavailable, matching the spec's
  ## EX-M5 / EX-M6 treatment of those scaffolds.
  result = newBackendBinaryRegistry()
  for backend in LinuxRegistrableBackends:
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
