## settings_app/gpui/shell.nim — Layer-3 shell for the GPUI target.
##
## EX-M12. The GPUI shell's composition is deliberately *different*
## from the TUI accordion and the web sidebar+pane: a **grid layout
## with a groups column and an items column**, side-by-side. The
## groups column shows every group as a clickable row (the active row
## carries the `active` class and `aria-pressed=true`); clicking a row
## calls `vm.setActiveGroup(group.id)`. The items column shows the
## active group's header + items via the shared Layer-2 components.
##
## Visible composition differences:
##   * TUI (EX-M10) — single vertical column; group headers always
##     visible; the active group expands inline below its header.
##   * web (EX-M11) — `<nav class="settings-sidebar">` plus
##     `<section class="settings-pane">`; the sidebar contains a
##     hierarchical title + a list of group buttons.
##   * GPUI (this shell) — two flat sibling columns directly under the
##     app root: `<div class="settings-groups-column">` and
##     `<div class="settings-items-column">`. No sidebar title, no
##     hierarchical `<nav>` wrapper, no in-line expansion of the
##     non-active groups; the topology is a flat 2-column grid.
##
## Tree shape::
##
##   <div class="settings-app-gpui" data-app="settings-app"
##        data-layout="grid">
##     <div class="settings-groups-column">
##       <div class="settings-group-row (active|)"
##            data-group-id="appearance">…click toggles activeGroup…</div>
##       <div class="settings-group-row" data-group-id="editor">…</div>
##       …
##     </div>
##     <div class="settings-items-column">
##       <section class="settings-group" data-group-id="…">
##         <header class="settings-group-header">…</header>
##         <div class="settings-item">…</div>
##         …
##       </section>
##     </div>
##   </div>
##
## The shell deliberately calls the *per-kind* component templates
## (`renderToggleItem` / `renderNumberItem` / `renderChoiceItem`)
## rather than the umbrella `renderSettingsGroup` template, because
## the shell owns the group container + header in the items column
## (the groups column's rows are independent of the pane's header) and
## would otherwise have to discard the wrapper that
## `renderSettingsGroup` builds.
##
## Include-pattern (mirrors `task_app/core/views.nim` + the TUI/web
## shells): this file is *included* — never imported — by the Layer-4
## composition root (`settings_app/main_gpui.nim`).

template renderSettingsShell*(renderer, vmRef): untyped {.dirty.} =
  ## Build the full settings-app tree against the given renderer and
  ## ViewModel. Returns the root node.
  block:
    let appRoot = renderer.createElement("div")
    renderer.setAttribute(appRoot, "class", "settings-app-gpui")
    renderer.setAttribute(appRoot, "data-app", "settings-app")
    renderer.setAttribute(appRoot, "data-layout", "grid")

    let activeId = vmRef.activeGroupId.val

    # ---- Groups column: a clickable row per group --------------------
    let groupsCol = renderer.createElement("div")
    renderer.setAttribute(groupsCol, "class", "settings-groups-column")

    for groupIdx in 0 ..< vmRef.catalog.groups.len:
      closureScope:
        let g = vmRef.catalog.groups[groupIdx]
        let row = renderer.createElement("div")
        renderer.setAttribute(row, "class",
          (if activeId == g.id: "settings-group-row active"
           else: "settings-group-row"))
        renderer.setAttribute(row, "data-group-id", g.id)
        if activeId == g.id:
          renderer.setAttribute(row, "aria-pressed", "true")

        # Inner label keeps the visible text reachable via textContent
        # without colliding with the click handler on the row itself.
        let rowLabel = renderer.createElement("span")
        renderer.setAttribute(rowLabel, "class", "settings-group-row-label")
        renderer.setTextContent(rowLabel, g.label)
        renderer.appendChild(row, rowLabel)

        let gid = g.id
        renderer.addEventListener(row, "click", proc() =
          discard vmRef.setActiveGroup(gid))
        renderer.appendChild(groupsCol, row)

    renderer.appendChild(appRoot, groupsCol)

    # ---- Items column: only the active group's header + items --------
    let itemsCol = renderer.createElement("div")
    renderer.setAttribute(itemsCol, "class", "settings-items-column")

    if vmRef.catalog.hasGroup(activeId):
      let activeGroup = vmRef.currentGroup
      let paneGroupNode = groupContainerLeaf(renderer)
      renderer.setAttribute(paneGroupNode, "data-group-id", activeGroup.id)
      renderer.appendChild(paneGroupNode,
        groupHeaderLeaf(renderer, activeGroup.label,
                        activeGroup.description))
      for itemIdx in 0 ..< activeGroup.items.len:
        closureScope:
          let it = activeGroup.items[itemIdx]
          case it.kind
          of sikToggle:
            renderer.appendChild(paneGroupNode,
              renderToggleItem(renderer, vmRef, it))
          of sikNumber:
            renderer.appendChild(paneGroupNode,
              renderNumberItem(renderer, vmRef, it))
          of sikChoice:
            renderer.appendChild(paneGroupNode,
              renderChoiceItem(renderer, vmRef, it))
      renderer.appendChild(itemsCol, paneGroupNode)

    renderer.appendChild(appRoot, itemsCol)

    appRoot

template selectGroup*(vmRef, groupId): untyped =
  ## Activate the group with `groupId`. Re-renders are driven by the
  ## composition root; tests call this through `vm.setActiveGroup`
  ## directly. The template exists so a click-driver pilot script
  ## reads naturally.
  discard vmRef.setActiveGroup(groupId)
