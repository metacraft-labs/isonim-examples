## helpers/settings_compile_web.nim — minimal web leaf stubs that let
## the EX-M9 shared components (`settings_app/components/*.nim`)
## compile + run against `MockRenderer` (the canonical headless surface
## for web tests; the browser `WebRenderer` exposes the same proc
## shape).
##
## EX-M9 compile-check helper. The real production leaves land in
## `isonim-examples/settings_app/web/leaves.nim` in EX-M11; until then
## this stub set proves the include-pattern in each component file
## resolves correctly against the web surface.
##
## The stubs are minimal but real: every leaf returns a real
## `MockNode` produced via `renderer.createElement`, so the resulting
## tree is a real tree the test can walk with the same attribute /
## child machinery the production leaves emit.

import std/strutils

import isonim/testing/mock_dom

import settings_app/core/types
import settings_app/core/vm
export types
export vm

# ----------------------------------------------------------------------------
# Capture buffer for the wired-up onChange closures. The components
# wire `vm.setToggle` / `vm.setNumber` / `vm.setChoice` through the
# `onChange` parameter; the leaf stubs below stash the latest closure
# of each kind so the EX-M9 driver test can fire it and prove the
# wiring round-trips through the real `SettingsVM`. This is the
# "exercise the wired closure" check that keeps the EX-M9 test from
# being a fig-leaf: the components must really invoke `vm.set*` from
# the closure (not just construct it), otherwise the captured-handler
# round-trip would fail.
# ----------------------------------------------------------------------------

var capturedToggleHandler*: proc(newValue: bool)
var capturedNumberHandler*: proc(newValue: int)
var capturedChoiceHandler*: proc(newValue: string)

proc clearCapturedHandlers*() =
  ## Reset every captured closure. Tests call this between fixtures so
  ## state from one builder does not leak into the next.
  capturedToggleHandler = nil
  capturedNumberHandler = nil
  capturedChoiceHandler = nil

# ----------------------------------------------------------------------------
# Stub leaves — mirror the contract the EX-M11 web leaves must satisfy
# ----------------------------------------------------------------------------

proc itemContainerLeaf*(r: MockRenderer): MockNode =
  let node = r.createElement("div")
  r.setAttribute(node, "class", "settings-row")
  node

proc labelLeaf*(r: MockRenderer; text: string): MockNode =
  let node = r.createElement("label")
  r.setAttribute(node, "class", "settings-label")
  r.setTextContent(node, text)
  node

proc descriptionLeaf*(r: MockRenderer; text: string): MockNode =
  let node = r.createElement("span")
  r.setAttribute(node, "class", "settings-description")
  r.setTextContent(node, text)
  node

proc toggleLeaf*(r: MockRenderer; value: bool;
                 onChange: proc(newValue: bool)): MockNode =
  ## Captures the wired-up `onChange` closure into
  ## `capturedToggleHandler` so the EX-M9 driver test can fire it and
  ## assert the VM round-trip. EX-M11 binds the real DOM event.
  capturedToggleHandler = onChange
  let node = r.createElement("input")
  r.setAttribute(node, "type", "checkbox")
  if value:
    r.setAttribute(node, "checked", "checked")
  node

proc numberLeaf*(r: MockRenderer; value: int;
                 minValue, maxValue, stepValue: int;
                 suffix: string;
                 onChange: proc(newValue: int)): MockNode =
  capturedNumberHandler = onChange
  let node = r.createElement("input")
  r.setAttribute(node, "type", "number")
  r.setAttribute(node, "value", $value)
  r.setAttribute(node, "min", $minValue)
  r.setAttribute(node, "max", $maxValue)
  r.setAttribute(node, "step", $stepValue)
  if suffix.len > 0:
    r.setAttribute(node, "data-suffix", suffix)
  node

proc choiceLeaf*(r: MockRenderer; value: string;
                 options: seq[string];
                 onChange: proc(newValue: string)): MockNode =
  capturedChoiceHandler = onChange
  let node = r.createElement("select")
  r.setAttribute(node, "value", value)
  r.setAttribute(node, "data-options", options.join("|"))
  for opt in options:
    let optNode = r.createElement("option")
    r.setAttribute(optNode, "value", opt)
    r.setTextContent(optNode, opt)
    r.appendChild(node, optNode)
  node

proc groupContainerLeaf*(r: MockRenderer): MockNode =
  let node = r.createElement("section")
  r.setAttribute(node, "class", "settings-group")
  node

proc groupHeaderLeaf*(r: MockRenderer; label, description: string): MockNode =
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

proc buildToggleRow*(vm: SettingsVM; item: SettingsItem): MockNode =
  ## Exercise `renderToggleItem` against `MockRenderer`.
  let r = MockRenderer()
  renderToggleItem(r, vm, item)

proc buildNumberRow*(vm: SettingsVM; item: SettingsItem): MockNode =
  ## Exercise `renderNumberItem` against `MockRenderer`.
  let r = MockRenderer()
  renderNumberItem(r, vm, item)

proc buildChoiceRow*(vm: SettingsVM; item: SettingsItem): MockNode =
  ## Exercise `renderChoiceItem` against `MockRenderer`.
  let r = MockRenderer()
  renderChoiceItem(r, vm, item)

proc buildGroup*(vm: SettingsVM; group: SettingsGroup): MockNode =
  ## Exercise `renderSettingsGroup` against `MockRenderer`.
  let r = MockRenderer()
  renderSettingsGroup(r, vm, group)
