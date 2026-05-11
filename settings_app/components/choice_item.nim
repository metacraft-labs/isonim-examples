## settings_app/components/choice_item.nim — Layer-2 shared component.
##
## Renderer-agnostic builder for a single `sikChoice` settings row. The
## composition root (Layer-4) imports the platform's Layer-1 `leaves`
## module first and then `include`s this file so the leaf names below
## resolve against the platform-specific procs by lexical scope (the
## same include-pattern as `task_app/core/views.nim`).
##
## Leaf surface required in scope at the include site (all per-
## platform; never imported here):
##
##   * ``itemContainerLeaf(renderer): Node`` — row container element.
##   * ``labelLeaf(renderer, text: string): Node`` — primary text label.
##   * ``descriptionLeaf(renderer, text: string): Node`` — secondary
##     descriptive text. Called only when `item.description.len > 0`.
##   * ``choiceLeaf(renderer, value: string, options: seq[string],
##                  onChange: proc(newValue: string)): Node`` — the
##     actual choice widget (radio group on TUI, ``<select>`` on web,
##     segmented control on GPUI / Cocoa, etc.). The component wires
##     `onChange` to `vm.setChoice`; the VM rejects values outside
##     `options` so a leaf can safely forward any string it produces.
##
## EX-M9 milestone reference:
## `codetracer-specs/Front-Ends/IsoNim/isonim-render-stream.status.org`.
##
## Cross-platform architecture:
## `codetracer-specs/Front-Ends/IsoNim/isonim-cross-platform-architecture.md`
## §"3-layer alternation".

# Note: imports for `settings_app/core/{types, vm}` and the per-
# platform leaves module are made by the composition root before this
# file is included. See toggle_item.nim for the rationale.

template renderChoiceItem*(renderer, vmRef, settingsItem): untyped {.dirty.} =
  ## Build a choice-style settings row and return its container node.
  ##
  ## `settingsItem` is a `SettingsItem` value (caller must ensure it is
  ## of kind `sikChoice`). `vmRef` is the `SettingsVM` whose
  ## `setChoice` action is wired to the choice widget's `onChange`.
  ##
  ## The resulting tree is::
  ##
  ##   itemContainerLeaf
  ##     labelLeaf
  ##     descriptionLeaf      (only when description is non-empty)
  ##     choiceLeaf
  block:
    let row = itemContainerLeaf(renderer)
    renderer.appendChild(row, labelLeaf(renderer, settingsItem.label))
    if settingsItem.description.len > 0:
      renderer.appendChild(row,
        descriptionLeaf(renderer, settingsItem.description))
    let initialValue = vmRef.choiceValue(settingsItem.id)
    let choiceNode = choiceLeaf(renderer, initialValue,
      settingsItem.choiceOptions,
      proc(newValue: string) =
        discard vmRef.setChoice(settingsItem.id, newValue))
    renderer.appendChild(row, choiceNode)
    row
