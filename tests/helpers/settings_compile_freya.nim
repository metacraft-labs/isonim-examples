## helpers/settings_compile_freya.nim — minimal Freya leaf stubs that
## let the EX-M9 shared components (`settings_app/components/*.nim`)
## compile + run against `FreyaRenderer`.
##
## EX-M9 compile-check helper. A production Freya shell + leaves for
## settings_app is not in the EX-M10..M12 plan, but we exercise the
## include-pattern against `FreyaRenderer` anyway so a future Freya
## settings shell inherits a known-good Layer-2 surface (and so the
## EX-M9 compile-cross test mirrors the 4-renderer pattern EX-M1 set up
## for `task_app`).
##
## The stubs are minimal but real: every leaf returns a real
## `FreyaElement` produced via `renderer.createElement`, so the
## resulting tree is a real shadow tree the test can walk using the
## tree-inspection helpers exposed by the renderer.

import std/strutils

import isonim_freya/renderer

import settings_app/core/types
import settings_app/core/vm
export types
export vm
export renderer

# ----------------------------------------------------------------------------
# Stub leaves — mirror the contract a future Freya leaves module must
# satisfy.
# ----------------------------------------------------------------------------

proc itemContainerLeaf*(r: FreyaRenderer): FreyaElement =
  let node = r.createElement("div")
  r.setAttribute(node, "class", "settings-row")
  node

proc labelLeaf*(r: FreyaRenderer; text: string): FreyaElement =
  let node = r.createElement("label")
  r.setAttribute(node, "class", "settings-label")
  r.setTextContent(node, text)
  node

proc descriptionLeaf*(r: FreyaRenderer; text: string): FreyaElement =
  let node = r.createElement("span")
  r.setAttribute(node, "class", "settings-description")
  r.setTextContent(node, text)
  node

proc toggleLeaf*(r: FreyaRenderer; value: bool;
                 onChange: proc(newValue: bool)): FreyaElement =
  ## `onChange` is intentionally retained but not invoked by the stub —
  ## EX-M9 verifies the *include + leaf surface*, not user-event
  ## dispatch. A future Freya settings shell wires the real handler.
  let _ = onChange
  let node = r.createElement("button")
  r.setAttribute(node, "class", "settings-toggle")
  r.setAttribute(node, "data-value", $value)
  node

proc numberLeaf*(r: FreyaRenderer; value: int;
                 minValue, maxValue, stepValue: int;
                 suffix: string;
                 onChange: proc(newValue: int)): FreyaElement =
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

proc choiceLeaf*(r: FreyaRenderer; value: string;
                 options: seq[string];
                 onChange: proc(newValue: string)): FreyaElement =
  let _ = onChange
  let node = r.createElement("select")
  r.setAttribute(node, "value", value)
  r.setAttribute(node, "data-options", options.join("|"))
  node

proc groupContainerLeaf*(r: FreyaRenderer): FreyaElement =
  let node = r.createElement("section")
  r.setAttribute(node, "class", "settings-group")
  node

proc groupHeaderLeaf*(r: FreyaRenderer; label, description: string): FreyaElement =
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

proc buildToggleRow*(vm: SettingsVM; item: SettingsItem): FreyaElement =
  ## Exercise `renderToggleItem` against `FreyaRenderer`.
  let r = FreyaRenderer()
  renderToggleItem(r, vm, item)

proc buildNumberRow*(vm: SettingsVM; item: SettingsItem): FreyaElement =
  ## Exercise `renderNumberItem` against `FreyaRenderer`.
  let r = FreyaRenderer()
  renderNumberItem(r, vm, item)

proc buildChoiceRow*(vm: SettingsVM; item: SettingsItem): FreyaElement =
  ## Exercise `renderChoiceItem` against `FreyaRenderer`.
  let r = FreyaRenderer()
  renderChoiceItem(r, vm, item)

proc buildGroup*(vm: SettingsVM; group: SettingsGroup): FreyaElement =
  ## Exercise `renderSettingsGroup` against `FreyaRenderer`.
  let r = FreyaRenderer()
  renderSettingsGroup(r, vm, group)
