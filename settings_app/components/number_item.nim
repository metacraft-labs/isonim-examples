## settings_app/components/number_item.nim — Layer-2 shared component.
##
## Renderer-agnostic builder for a single `sikNumber` settings row. The
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
##   * ``numberLeaf(renderer, value: int, min: int, max: int, step: int,
##                  suffix: string, onChange: proc(newValue: int)): Node``
##     — the actual numeric input widget. The component passes the
##     catalog item's `numberMin`/`numberMax`/`numberStep`/`numberSuffix`
##     to the leaf so the platform can render its own constraint UI; the
##     VM's `setNumber` clamps too, so the leaf only needs to forward
##     user-typed values.
##
## The component wires `onChange` to `vm.setNumber(item.id, newValue)`;
## clamping happens inside the VM so a leaf is free to emit out-of-
## range values without crashing.
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

template renderNumberItem*(renderer, vmRef, settingsItem): untyped {.dirty.} =
  ## Build a number-style settings row and return its container node.
  ##
  ## `settingsItem` is a `SettingsItem` value (caller must ensure it is
  ## of kind `sikNumber`). `vmRef` is the `SettingsVM` whose
  ## `setNumber` action is wired to the input's `onChange`. The min /
  ## max / step / suffix metadata is forwarded to the leaf so the
  ## platform can render its own constraint UI; the VM clamps writes
  ## anyway so a leaf that emits out-of-range values is still safe.
  ##
  ## The resulting tree is::
  ##
  ##   itemContainerLeaf
  ##     labelLeaf
  ##     descriptionLeaf      (only when description is non-empty)
  ##     numberLeaf
  block:
    let row = itemContainerLeaf(renderer)
    renderer.appendChild(row, labelLeaf(renderer, settingsItem.label))
    if settingsItem.description.len > 0:
      renderer.appendChild(row,
        descriptionLeaf(renderer, settingsItem.description))
    let initialValue = vmRef.numberValue(settingsItem.id)
    let numNode = numberLeaf(renderer, initialValue,
      settingsItem.numberMin,
      settingsItem.numberMax,
      settingsItem.numberStep,
      settingsItem.numberSuffix,
      proc(newValue: int) =
        discard vmRef.setNumber(settingsItem.id, newValue))
    renderer.appendChild(row, numNode)
    row
