## helpers/settings_compile_tui.nim — minimal TUI leaf stubs that let
## the EX-M9 shared components (`settings_app/components/*.nim`)
## compile + run against `TerminalRenderer`.
##
## EX-M9 compile-check helper. The real production leaves land in
## `isonim-examples/settings_app/tui/leaves.nim` in EX-M10; until then
## this stub set proves the include-pattern in each component file
## resolves correctly against the TUI surface.
##
## The stubs are minimal but real: every leaf returns a real
## `TerminalNode` produced via `renderer.createElement`, so the
## resulting tree is a real tree the test can walk with the same
## attribute / child machinery the production leaves emit.

import std/strutils
import std/tables

import isonim_tui/renderer

import settings_app/core/types
import settings_app/core/vm
export types
export vm

# ----------------------------------------------------------------------------
# Stub leaves — mirror the contract the EX-M10 TUI leaves must satisfy
# ----------------------------------------------------------------------------

proc itemContainerLeaf*(r: TerminalRenderer): TerminalNode =
  let node = r.createElement("div")
  node.attributes["class"] = "settings-row"
  node

proc labelLeaf*(r: TerminalRenderer; text: string): TerminalNode =
  let node = r.createElement("span")
  node.attributes["class"] = "settings-label"
  node.text = text
  node

proc descriptionLeaf*(r: TerminalRenderer; text: string): TerminalNode =
  let node = r.createElement("span")
  node.attributes["class"] = "settings-description"
  node.text = text
  node

proc toggleLeaf*(r: TerminalRenderer; value: bool;
                 onChange: proc(newValue: bool)): TerminalNode =
  ## `onChange` is intentionally retained but not invoked by the stub —
  ## EX-M9 verifies the *include + leaf surface*, not user-event
  ## dispatch. EX-M10 wires the real handler.
  let _ = onChange
  let node = r.createElement("button")
  node.attributes["role"] = "switch"
  node.attributes["aria-checked"] = $value
  node

proc numberLeaf*(r: TerminalRenderer; value: int;
                 minValue, maxValue, stepValue: int;
                 suffix: string;
                 onChange: proc(newValue: int)): TerminalNode =
  let _ = onChange
  let node = r.createElement("input")
  node.attributes["type"] = "number"
  node.attributes["value"] = $value
  node.attributes["min"] = $minValue
  node.attributes["max"] = $maxValue
  node.attributes["step"] = $stepValue
  if suffix.len > 0:
    node.attributes["data-suffix"] = suffix
  node

proc choiceLeaf*(r: TerminalRenderer; value: string;
                 options: seq[string];
                 onChange: proc(newValue: string)): TerminalNode =
  let _ = onChange
  let node = r.createElement("select")
  node.attributes["value"] = value
  node.attributes["data-options"] = options.join("|")
  node

proc groupContainerLeaf*(r: TerminalRenderer): TerminalNode =
  let node = r.createElement("section")
  node.attributes["class"] = "settings-group"
  node

proc groupHeaderLeaf*(r: TerminalRenderer; label, description: string):
                    TerminalNode =
  let node = r.createElement("header")
  node.attributes["class"] = "settings-group-header"
  node.attributes["data-label"] = label
  if description.len > 0:
    node.attributes["data-description"] = description
  node

# ----------------------------------------------------------------------------
# Include the EX-M9 shared components in this order: the per-kind item
# components first so the dispatch in `group.nim` can resolve them, then
# `group.nim` itself.
# ----------------------------------------------------------------------------

include settings_app/components/toggle_item
include settings_app/components/number_item
include settings_app/components/choice_item
include settings_app/components/group

proc buildToggleRow*(vm: SettingsVM; item: SettingsItem): TerminalNode =
  ## Exercise `renderToggleItem` against `TerminalRenderer`.
  let r = TerminalRenderer()
  renderToggleItem(r, vm, item)

proc buildNumberRow*(vm: SettingsVM; item: SettingsItem): TerminalNode =
  ## Exercise `renderNumberItem` against `TerminalRenderer`.
  let r = TerminalRenderer()
  renderNumberItem(r, vm, item)

proc buildChoiceRow*(vm: SettingsVM; item: SettingsItem): TerminalNode =
  ## Exercise `renderChoiceItem` against `TerminalRenderer`.
  let r = TerminalRenderer()
  renderChoiceItem(r, vm, item)

proc buildGroup*(vm: SettingsVM; group: SettingsGroup): TerminalNode =
  ## Exercise `renderSettingsGroup` against `TerminalRenderer`.
  let r = TerminalRenderer()
  renderSettingsGroup(r, vm, group)
