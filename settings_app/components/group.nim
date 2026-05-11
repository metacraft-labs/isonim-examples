## settings_app/components/group.nim — Layer-2 shared component.
##
## Renderer-agnostic builder for a single `SettingsGroup`. Builds the
## group's header (label + optional description) and then iterates the
## group's items, dispatching to the per-kind item component
## (`renderToggleItem` / `renderNumberItem` / `renderChoiceItem`) by
## the `SettingsItem.kind` discriminator. The exhaustive `case` keeps
## Nim's compile-time totality check honest — adding a new
## `SettingsItemKind` triggers a compile error here until the dispatch
## is updated.
##
## Composition contract: the includer must already have the three
## per-kind item components in scope (the includer typically `include`s
## `toggle_item.nim`, `number_item.nim`, `choice_item.nim` before this
## file). This file does not `include` the item components itself so
## the per-kind templates can be re-used independently by shells that
## render a single item kind without a surrounding group.
##
## Leaf surface required in scope at the include site (all per-
## platform; never imported here):
##
##   * ``groupContainerLeaf(renderer): Node`` — container element that
##     wraps the entire group (header + items).
##   * ``groupHeaderLeaf(renderer, label: string, description: string): Node``
##     — header element. `description` is passed through whether or
##     not it is empty; the leaf decides how to render the empty case
##     (most platforms collapse the description span when empty).
##
## Plus the per-kind item leaves required by the item components (see
## `toggle_item.nim`, `number_item.nim`, `choice_item.nim`):
## ``itemContainerLeaf``, ``labelLeaf``, ``descriptionLeaf``,
## ``toggleLeaf``, ``numberLeaf``, ``choiceLeaf``.
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

template renderSettingsGroup*(renderer, vmRef, settingsGroup): untyped
                              {.dirty.} =
  ## Build a settings-group container with its header and item rows,
  ## returning the container node.
  ##
  ## `settingsGroup` is a `SettingsGroup` value. `vmRef` is the
  ## `SettingsVM` from which the per-item values are read and through
  ## which the item widgets dispatch user input.
  ##
  ## Resulting tree::
  ##
  ##   groupContainerLeaf
  ##     groupHeaderLeaf
  ##     <itemContainerLeaf>*       (one per item, kind-dispatched)
  ##
  ## The per-item containers are produced by `renderToggleItem` /
  ## `renderNumberItem` / `renderChoiceItem` (defined in the sibling
  ## component files), so the resulting trees keep the same shape
  ## documented in those modules.
  block:
    let groupNode = groupContainerLeaf(renderer)
    renderer.appendChild(groupNode,
      groupHeaderLeaf(renderer, settingsGroup.label,
                      settingsGroup.description))
    for itemIdx in 0 ..< settingsGroup.items.len:
      # `closureScope` (from `system.nim`) introduces a fresh
      # closure environment per iteration. Without it, the `onChange`
      # closures wired inside `renderToggleItem` / `renderNumberItem` /
      # `renderChoiceItem` would all capture the same loop-scoped `it`
      # variable and read its *last* value at fire time — every closure
      # would dispatch against the catalog's final item.
      closureScope:
        let it = settingsGroup.items[itemIdx]
        case it.kind
        of sikToggle:
          renderer.appendChild(groupNode,
            renderToggleItem(renderer, vmRef, it))
        of sikNumber:
          renderer.appendChild(groupNode,
            renderNumberItem(renderer, vmRef, it))
        of sikChoice:
          renderer.appendChild(groupNode,
            renderChoiceItem(renderer, vmRef, it))
    groupNode
