## settings_app/components/number_item.nim — Layer-2 shared component.
##
## EX-M17: the number component now passes `vmRef` + `itemId` to the
## leaf so the widget subscribes to `vmRef.numberValue(itemId)` and
## dispatches writes through `vmRef.setNumber(itemId, ...)` directly.
## See toggle_item.nim for the full rationale.
##
## Leaf surface required in scope at the include site (all per-
## platform; never imported here):
##
##   * ``itemContainerLeaf(renderer): Node`` — row container element.
##   * ``labelLeaf(renderer, text: string): Node`` — primary text label.
##   * ``descriptionLeaf(renderer, text: string): Node`` — secondary
##     descriptive text. Called only when `item.description.len > 0`.
##   * ``numberLeaf(renderer, vmRef: SettingsVM, itemId: string,
##                  minValue, maxValue, stepValue: int, suffix: string): Node``
##     — the actual numeric input widget. The leaf subscribes to
##     `vmRef.numberValue(itemId)` and dispatches writes through
##     `vmRef.setNumber(itemId, ...)`.

template renderNumberItem*(renderer, vmRef, settingsItem): untyped {.dirty.} =
  ## Build a number-style settings row and return its container node.
  block:
    let numberItemId = settingsItem.id
    let row = itemContainerLeaf(renderer)
    renderer.appendChild(row, labelLeaf(renderer, settingsItem.label))
    if settingsItem.description.len > 0:
      renderer.appendChild(row,
        descriptionLeaf(renderer, settingsItem.description))
    renderer.appendChild(row,
      numberLeaf(renderer, vmRef, numberItemId,
        settingsItem.numberMin,
        settingsItem.numberMax,
        settingsItem.numberStep,
        settingsItem.numberSuffix))
    row
