## settings_app/components/toggle_item.nim — Layer-2 shared component.
##
## Renderer-agnostic builder for a single `sikToggle` settings row. The
## composition root (Layer-4) imports the platform's Layer-1 `leaves`
## module first and then `include`s this file so the leaf names below
## resolve against the platform-specific procs by lexical scope (the
## same include-pattern as `task_app/core/views.nim`).
##
## EX-M16: the component body composes Layer-1 leaves into a single
## settings-row tree. Each leaf is invoked as a plain Nim proc call
## (the leaves are not DSL elements — they're per-platform procs that
## already wire up their own internal event listeners + reactive
## bindings), and the row is assembled with `renderer.appendChild`.
## This mirrors the idiom used by the editor's reference views
## (`isonim/src/isonim/editor/views/component_detail.nim` —
## `renderVariantSection` builds the outer container via `ui(r):` and
## then composes pre-built sub-trees with `appendChild`). Per-row
## reactivity flows through the toggle leaf's own click listener — the
## widget updates its on-DOM value and dispatches `onChange`, which the
## component wires to `vm.setToggle`. The shell-level
## `createRenderEffect` (in `settings_app/{web,tui,gpui,freya}/shell.nim`)
## handles swapping the active group's items in or out when
## `vm.activeGroupId` changes, so the parity tests' scripted
## `vm.setActiveGroup(...)` calls flow through the reactive graph and
## the tree updates without an explicit rebuild call.
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
    let toggleItemId = settingsItem.id
    let row = itemContainerLeaf(renderer)
    renderer.appendChild(row, labelLeaf(renderer, settingsItem.label))
    if settingsItem.description.len > 0:
      renderer.appendChild(row,
        descriptionLeaf(renderer, settingsItem.description))
    renderer.appendChild(row,
      toggleLeaf(renderer, vmRef.toggleValue(toggleItemId),
        proc(newValue: bool) =
          discard vmRef.setToggle(toggleItemId, newValue)))
    row
