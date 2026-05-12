## settings_app/main_web.nim — Layer-4 composition root for the
## settings-app web target.
##
## EX-M11. Mirrors `settings_app/main_tui.nim` in shape: the composition
## root imports the platform leaves first, then includes the shared
## components and the shell in dependency order so the unqualified leaf
## calls inside the components / shell bind to the web procs in
## `settings_app/web/leaves.nim`.
##
## Include order (load-bearing):
##
##   1. ``import isonim/testing/mock_dom`` — provides `MockRenderer`,
##      `MockNode`, `MockEvent` (used by the shell's click handler
##      closure and by tests that fire events).
##   2. ``import settings_app/core/{vm, demo_catalog}`` — VM type +
##      actions + the canonical demo catalog.
##   3. ``import settings_app/web/leaves`` — the 8-leaf surface.
##      Bringing this in *first* (before the component / shell
##      includes) is what makes the unqualified `toggleLeaf` /
##      `numberLeaf` / etc. references inside the component templates
##      resolve to the web procs.
##   4. ``include settings_app/components/{toggle,number,choice}_item``
##      then ``include settings_app/components/group`` — the shared
##      Layer-2 component templates. They reference the leaves by
##      name; Nim resolves those names by lexical scope at the include
##      point.
##   5. ``include settings_app/web/shell`` — the Layer-3 shell.
##      References the per-kind item templates `renderToggleItem` /
##      `renderNumberItem` / `renderChoiceItem` from step 4.
##
## Public surface:
##
##   * ``buildSettingsApp(r, vm)`` — returns the root node. Tests call
##     this directly when they already own a renderer.
##
## EX-M16: the explicit ``rebuildSettingsApp`` proc is gone. The shell
## binds its dynamic state (active sidebar entry highlight, active
## group's pane contents) via ``createRenderEffect`` over
## ``vm.activeGroupId.val``, so VM mutations propagate to the rendered
## tree through the reactive graph instead.

import std/tables

import isonim/core/signals
import isonim/core/computation  # createRenderEffect
import isonim/testing/mock_dom

import settings_app/core/vm
import settings_app/core/demo_catalog
import settings_app/web/leaves

export tables, signals, mock_dom, vm, demo_catalog, leaves

include settings_app/components/toggle_item
include settings_app/components/number_item
include settings_app/components/choice_item
include settings_app/components/group
include settings_app/web/shell

proc buildSettingsApp*(r: MockRenderer; vm: SettingsVM): MockNode =
  ## Convenience wrapper exported for tests. Builds the full
  ## settings-app web tree (Layer 3 → Layer 2 → Layer 1) and returns
  ## the root node.
  renderSettingsShell(r, vm)

when isMainModule:
  let catalog = buildDemoSettingsCatalog()
  let settingsVm = newSettingsVM(catalog)
  let r = MockRenderer()
  let root = buildSettingsApp(r, settingsVm)
  echo "Settings app web mounted; root.tag=", root.tag
  echo "Groups: ", catalog.groups.len
  echo "Active: ", settingsVm.activeGroupId.val
  echo "Top-level children (sidebar + pane): ", root.children.len
