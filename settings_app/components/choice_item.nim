## settings_app/components/choice_item.nim — Layer-2 shared component.
##
## EX-M17: the choice component now passes `vmRef` + `itemId` to the
## leaf so the widget subscribes to `vmRef.choiceValue(itemId)` and
## dispatches writes through `vmRef.setChoice(itemId, ...)` directly.
## See toggle_item.nim for the full rationale.
##
## Leaf surface required in scope at the include site (all per-
## platform; never imported here):
##
##   * ``itemContainerLeaf(renderer): Node`` — row container element.
##   * ``labelLeaf(renderer, text: string): Node`` — primary text label.
##   * ``descriptionLeaf(renderer, text: string): Node`` — secondary
##     descriptive text. Called only when `item.description.len > 0`.
##   * ``choiceLeaf(renderer, vmRef: SettingsVM, itemId: string,
##                  options: seq[string]): Node`` — the actual choice
##     widget. The leaf subscribes to `vmRef.choiceValue(itemId)` and
##     dispatches writes through `vmRef.setChoice(itemId, ...)`.

template renderChoiceItem*(renderer, vmRef, settingsItem): untyped {.dirty.} =
  ## Build a choice-style settings row and return its container node.
  block:
    let choiceItemId = settingsItem.id
    let row = itemContainerLeaf(renderer)
    renderer.appendChild(row, labelLeaf(renderer, settingsItem.label))
    if settingsItem.description.len > 0:
      renderer.appendChild(row,
        descriptionLeaf(renderer, settingsItem.description))
    renderer.appendChild(row,
      choiceLeaf(renderer, vmRef, choiceItemId,
        settingsItem.choiceOptions))
    row
