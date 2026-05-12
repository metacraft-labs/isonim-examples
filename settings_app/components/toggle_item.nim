## settings_app/components/toggle_item.nim — Layer-2 shared component.
##
## EX-M17: the toggle component now passes `vmRef` + `itemId` to the
## leaf rather than a one-shot `value` + `onChange` pair. The leaf
## subscribes to `vmRef.toggleValue(itemId)` via `createRenderEffect`
## so programmatic VM mutations (e.g. fake_db's `saveSetting` success
## refreshing the resource snapshot) propagate to the DOM without a
## re-mount. This is the load-bearing fix for the EX-M16 review's
## architectural note — see the milestone tracker for the rationale.
##
## Leaf surface required in scope at the include site (all per-
## platform; never imported here):
##
##   * ``itemContainerLeaf(renderer): Node`` — row container element
##     that hosts the label, optional description, and the toggle widget.
##   * ``labelLeaf(renderer, text: string): Node`` — primary text label.
##   * ``descriptionLeaf(renderer, text: string): Node`` — secondary
##     descriptive text. Called only when `item.description.len > 0`.
##   * ``toggleLeaf(renderer, vmRef: SettingsVM, itemId: string): Node``
##     — the actual checkbox / switch widget. The leaf is now
##     responsible for subscribing to `vmRef.toggleValue(itemId)` and
##     for dispatching writes through `vmRef.setToggle(itemId, ...)`.
##
## EX-M9 milestone reference:
## `codetracer-specs/Front-Ends/IsoNim/isonim-render-stream.status.org`.

# Note: imports for `settings_app/core/{types, vm}` and the per-
# platform leaves module are made by the composition root before this
# file is included.

template renderToggleItem*(renderer, vmRef, settingsItem): untyped {.dirty.} =
  ## Build a toggle-style settings row and return its container node.
  ##
  ## `settingsItem` is a `SettingsItem` value (caller must ensure it is
  ## of kind `sikToggle`; the dispatcher in `group.nim` enforces this).
  ## `vmRef` is the `SettingsVM` the leaf reads from and writes to.
  ##
  ## Resulting tree::
  ##
  ##   itemContainerLeaf
  ##     labelLeaf
  ##     descriptionLeaf      (only when description is non-empty)
  ##     toggleLeaf
  block:
    let toggleItemId = settingsItem.id
    let row = itemContainerLeaf(renderer)
    renderer.appendChild(row, labelLeaf(renderer, settingsItem.label))
    if settingsItem.description.len > 0:
      renderer.appendChild(row,
        descriptionLeaf(renderer, settingsItem.description))
    renderer.appendChild(row,
      toggleLeaf(renderer, vmRef, toggleItemId))
    row
