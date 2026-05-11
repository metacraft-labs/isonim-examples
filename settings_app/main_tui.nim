## settings_app/main_tui.nim — Layer-4 composition root for the
## settings-app TUI target.
##
## EX-M10. Mirrors `task_app/main_tui.nim` in shape: the composition
## root imports the platform leaves first, then includes the shared
## components and the shell in dependency order so the unqualified
## leaf calls inside the components / shell bind to the TUI procs in
## `settings_app/tui/leaves.nim`.
##
## Include order (load-bearing):
##
##   1. ``import isonim_tui`` and ``import isonim_tui/events`` —
##      provides `TerminalRenderer`, `TerminalNode`, `TerminalEvent`
##      (used by the shell's click handler closure).
##   2. ``import settings_app/core/{vm, demo_catalog}`` — VM type +
##      its actions + the canonical demo catalog. Reading
##      `vm.activeGroupId.val` etc. inside the shell template is what
##      drives expand/collapse decisions.
##   3. ``import settings_app/tui/leaves`` — the 8-leaf surface.
##      Bringing this in *first* (before the component / shell
##      includes) is what makes the unqualified `toggleLeaf` /
##      `numberLeaf` / etc. references inside the component templates
##      resolve to the TUI procs.
##   4. ``include settings_app/components/{toggle,number,choice}_item``
##      then ``include settings_app/components/group`` — the shared
##      Layer-2 component templates. They reference the leaves by
##      name; Nim resolves those names by lexical scope at the
##      include point.
##   5. ``include settings_app/tui/shell`` — the Layer-3 shell.
##      References the per-kind item templates `renderToggleItem` /
##      `renderNumberItem` / `renderChoiceItem` from step 4.
##
## Public surface:
##
##   * ``buildSettingsApp(r, vm)`` — returns the root node. Tests
##     call this directly when they already own a renderer.
##   * ``runSettingsApp(h, vm)`` — mounts the tree under a
##     `TerminalTestHarness` and returns the root. Mirrors
##     `runTaskApp` from the task-app composition root.
##   * ``rebuildSettingsApp(h, vm)`` — wipes the harness's root and
##     rebuilds the tree from the current VM state. Used by the
##     integration test after every `vm.setActiveGroup` /
##     `vm.setToggle` / etc. mutation to assert the new tree shape.
##
## A manual rebuild path is used here (rather than an in-place
## `createRenderEffect`) for the same reasons documented in
## `task_app/tui/leaves.nim`: the cross-platform contract only requires
## byte-identical Layer-3 / Layer-2 across platforms; the leaves are
## explicitly per-platform and the settings-app's mutation surface is
## small enough that an explicit rebuild path is simpler to reason
## about than a fan-out of `Signal[T]` observers wired through the
## widget runtime.

import isonim_tui
import isonim_tui/events

import settings_app/core/vm
import settings_app/core/demo_catalog
import settings_app/tui/leaves

export vm, demo_catalog, leaves

include settings_app/components/toggle_item
include settings_app/components/number_item
include settings_app/components/choice_item
include settings_app/components/group
include settings_app/tui/shell

proc buildSettingsApp*(r: TerminalRenderer; vm: SettingsVM): TerminalNode =
  ## Convenience wrapper exported for tests. Builds the full
  ## settings-app tree (Layer 3 → Layer 2 → Layer 1) and returns the
  ## root node.
  renderSettingsShell(r, vm)

proc runSettingsApp*(h: TerminalTestHarness;
                     vm: SettingsVM): TerminalNode =
  ## Mount the settings app into a `TerminalTestHarness` and return
  ## the root node. Used by tests + by an interactive entry point.
  var rootRef: TerminalNode
  h.mount(proc(r: TerminalRenderer): TerminalNode =
    rootRef = buildSettingsApp(r, vm)
    rootRef)
  rootRef

proc rebuildSettingsApp*(h: TerminalTestHarness;
                         vm: SettingsVM): TerminalNode =
  ## Re-mount the settings app under the existing harness. The shell
  ## reads `vm.activeGroupId` + the per-item value tables on every
  ## build, so calling this after a VM mutation paints the new state.
  runSettingsApp(h, vm)

when isMainModule:
  let catalog = buildDemoSettingsCatalog()
  let settingsVm = newSettingsVM(catalog)
  let h = newTerminalTestHarness(80, 24)
  discard runSettingsApp(h, settingsVm)
  echo "Settings app TUI mounted (", h.cols, "x", h.rows, ")."
  echo "Groups: ", catalog.groups.len
  echo "Active: ", settingsVm.activeGroupId.val
  h.dispose()
