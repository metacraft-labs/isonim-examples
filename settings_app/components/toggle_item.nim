## settings_app/components/toggle_item.nim — Layer-2 shared component.
##
## Renderer-agnostic builder for a single `sikToggle` settings row. The
## composition root (Layer-4) imports the platform's Layer-1 `leaves`
## module first and then `include`s this file so the leaf names below
## resolve against the platform-specific procs by lexical scope (the
## same include-pattern as `task_app/core/views.nim`).
##
## Leaf surface required in scope at the include site (all per-
## platform; never imported here):
##
##   * ``itemContainerLeaf(renderer): Node`` — row container element
##     that hosts the label, optional description, and the toggle widget.
##   * ``labelLeaf(renderer, text: string): Node`` — primary text label.
##   * ``descriptionLeaf(renderer, text: string): Node`` — secondary
##     descriptive text. Called only when `item.description.len > 0`.
##   * ``toggleLeaf(renderer, value: bool, onChange: proc(newValue: bool)): Node``
##     — the actual checkbox / switch widget. The component wires
##     `onChange` to `vm.setToggle(item.id, newValue)`.
##
## The component never touches the renderer's mutators directly except
## through `renderer.appendChild`, which is part of the shared
## RendererBackend conformance surface that every platform satisfies.
##
## EX-M9 milestone reference:
## `codetracer-specs/Front-Ends/IsoNim/isonim-render-stream.status.org`.
##
## Cross-platform architecture:
## `codetracer-specs/Front-Ends/IsoNim/isonim-cross-platform-architecture.md`
## §"3-layer alternation".

# Note: imports for `settings_app/core/{types, vm}` and the per-
# platform leaves module are made by the composition root before this
# file is included. Adding `import` statements here would shadow that
# arrangement and re-create the Layer-1 coupling the include-pattern is
# designed to avoid.

template renderToggleItem*(renderer, vmRef, settingsItem): untyped {.dirty.} =
  ## Build a toggle-style settings row and return its container node.
  ##
  ## `settingsItem` is a `SettingsItem` value (caller must ensure it is
  ## of kind `sikToggle`; the dispatcher in `group.nim` enforces this).
  ## `vmRef` is the `SettingsVM` whose `setToggle` action is wired to
  ## the toggle widget's `onChange`.
  ##
  ## The resulting tree is::
  ##
  ##   itemContainerLeaf
  ##     labelLeaf
  ##     descriptionLeaf      (only when description is non-empty)
  ##     toggleLeaf
  ##
  ## Order matches every other item component (number_item, choice_item)
  ## so platform shells can rely on a stable per-row child ordering.
  block:
    let row = itemContainerLeaf(renderer)
    renderer.appendChild(row, labelLeaf(renderer, settingsItem.label))
    if settingsItem.description.len > 0:
      renderer.appendChild(row,
        descriptionLeaf(renderer, settingsItem.description))
    let initialValue = vmRef.toggleValue(settingsItem.id)
    let toggleNode = toggleLeaf(renderer, initialValue,
      proc(newValue: bool) =
        discard vmRef.setToggle(settingsItem.id, newValue))
    renderer.appendChild(row, toggleNode)
    row
