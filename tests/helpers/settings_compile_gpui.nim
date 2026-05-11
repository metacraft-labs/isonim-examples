## helpers/settings_compile_gpui.nim — minimal GPUI leaf stubs that let
## the EX-M9 shared components (`settings_app/components/*.nim`)
## compile + run against `GpuiRenderer`.
##
## EX-M9 compile-check helper. The real production leaves land in
## `isonim-examples/settings_app/gpui/leaves.nim` in EX-M12; until then
## this stub set proves the include-pattern in each component file
## resolves correctly against the GPUI surface.
##
## The stubs are minimal but real: every leaf returns a real
## `GpuiElement` produced via `renderer.createElement`, so the
## resulting tree is a real shadow tree the test can walk using the
## tree-inspection helpers exposed by the renderer
## (`childCount`, `nthChild`, `getAttribute`, `textContent`).

import std/strutils

import isonim_gpui/renderer

import settings_app/core/types
import settings_app/core/vm
export types
export vm
export renderer

# ----------------------------------------------------------------------------
# Stub leaves — mirror the contract the EX-M12 GPUI leaves must satisfy
# ----------------------------------------------------------------------------

proc itemContainerLeaf*(r: GpuiRenderer): GpuiElement =
  let node = r.createElement("div")
  r.setAttribute(node, "class", "settings-row")
  node

proc labelLeaf*(r: GpuiRenderer; text: string): GpuiElement =
  let node = r.createElement("label")
  r.setAttribute(node, "class", "settings-label")
  r.setTextContent(node, text)
  node

proc descriptionLeaf*(r: GpuiRenderer; text: string): GpuiElement =
  let node = r.createElement("span")
  r.setAttribute(node, "class", "settings-description")
  r.setTextContent(node, text)
  node

proc toggleLeaf*(r: GpuiRenderer; value: bool;
                 onChange: proc(newValue: bool)): GpuiElement =
  ## `onChange` is intentionally retained but not invoked by the stub —
  ## EX-M9 verifies the *include + leaf surface*, not user-event
  ## dispatch. EX-M12 wires the real handler.
  let _ = onChange
  let node = r.createElement("button")
  r.setAttribute(node, "class", "settings-toggle")
  r.setAttribute(node, "data-value", $value)
  node

proc numberLeaf*(r: GpuiRenderer; value: int;
                 minValue, maxValue, stepValue: int;
                 suffix: string;
                 onChange: proc(newValue: int)): GpuiElement =
  let _ = onChange
  let node = r.createElement("input")
  r.setAttribute(node, "type", "number")
  r.setAttribute(node, "value", $value)
  r.setAttribute(node, "data-min", $minValue)
  r.setAttribute(node, "data-max", $maxValue)
  r.setAttribute(node, "data-step", $stepValue)
  if suffix.len > 0:
    r.setAttribute(node, "data-suffix", suffix)
  node

proc choiceLeaf*(r: GpuiRenderer; value: string;
                 options: seq[string];
                 onChange: proc(newValue: string)): GpuiElement =
  let _ = onChange
  let node = r.createElement("select")
  r.setAttribute(node, "value", value)
  r.setAttribute(node, "data-options", options.join("|"))
  node

proc groupContainerLeaf*(r: GpuiRenderer): GpuiElement =
  let node = r.createElement("section")
  r.setAttribute(node, "class", "settings-group")
  node

proc groupHeaderLeaf*(r: GpuiRenderer; label, description: string): GpuiElement =
  let node = r.createElement("header")
  r.setAttribute(node, "class", "settings-group-header")
  r.setAttribute(node, "data-label", label)
  if description.len > 0:
    r.setAttribute(node, "data-description", description)
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

proc buildToggleRow*(vm: SettingsVM; item: SettingsItem): GpuiElement =
  ## Exercise `renderToggleItem` against `GpuiRenderer`.
  let r = GpuiRenderer()
  renderToggleItem(r, vm, item)

proc buildNumberRow*(vm: SettingsVM; item: SettingsItem): GpuiElement =
  ## Exercise `renderNumberItem` against `GpuiRenderer`.
  let r = GpuiRenderer()
  renderNumberItem(r, vm, item)

proc buildChoiceRow*(vm: SettingsVM; item: SettingsItem): GpuiElement =
  ## Exercise `renderChoiceItem` against `GpuiRenderer`.
  let r = GpuiRenderer()
  renderChoiceItem(r, vm, item)

proc buildGroup*(vm: SettingsVM; group: SettingsGroup): GpuiElement =
  ## Exercise `renderSettingsGroup` against `GpuiRenderer`.
  let r = GpuiRenderer()
  renderSettingsGroup(r, vm, group)
