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
## EX-M16: the shell builds the chrome once at mount time; the
## ``active`` class + ``aria-pressed`` on each group row and the items
## column's child group section flow through ``createRenderEffect``
## over ``vm.activeGroupId.val``. A direct ``vm.setActiveGroup(id)``
## call (whether driven by a click or by a test script) updates the
## visible state without an explicit rebuild call from the composition
## root.
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
  ##
  ## RS-M14 Phase 2 round-2 review: the appRoot is laid out as a
  ## ``flex-direction: row`` parent with a fixed-width groups column on
  ## the left and a remaining-width items column on the right. The shim
  ## only accepts pixel widths or ``100%`` / ``full`` for ``width`` (see
  ## ``isonim-gpui/rust/.../gpui_app.rs apply_styles_to_div``), so the
  ## brief's "~30% / ~70%" split is encoded as concrete pixel widths
  ## (240px / 540px) sized for the canonical 800x600 surface.
  block:
    let appRoot = renderer.createElement("div")
    renderer.setAttribute(appRoot, "class", "settings-app-gpui")
    renderer.setAttribute(appRoot, "data-app", "settings-app")
    renderer.setAttribute(appRoot, "data-layout", "grid")
    renderer.setStyle(appRoot, "background", "#0f0f14")
    renderer.setStyle(appRoot, "color", "#e8e9f0")
    renderer.setStyle(appRoot, "padding", "16")
    renderer.setStyle(appRoot, "gap", "12")
    renderer.setStyle(appRoot, "flex-direction", "row")
    renderer.setStyle(appRoot, "align-items", "start")
    renderer.setStyle(appRoot, "width", "100%")
    renderer.setStyle(appRoot, "height", "100%")

    # ---- Groups column: a clickable row per group --------------------
    let groupsCol = renderer.createElement("div")
    renderer.setAttribute(groupsCol, "class", "settings-groups-column")
    renderer.setStyle(groupsCol, "background", "#15151c")
    renderer.setStyle(groupsCol, "padding", "8")
    renderer.setStyle(groupsCol, "gap", "6")
    renderer.setStyle(groupsCol, "flex-direction", "column")
    renderer.setStyle(groupsCol, "width", "220")
    renderer.setStyle(groupsCol, "border-radius", "8")
    renderer.appendChild(appRoot, groupsCol)

    for groupIdx in 0 ..< vmRef.catalog.groups.len:
      closureScope:
        let g = vmRef.catalog.groups[groupIdx]
        let gid = g.id
        let row = renderer.createElement("div")
        renderer.setAttribute(row, "data-group-id", gid)
        renderer.setStyle(row, "padding", "10")
        renderer.setStyle(row, "border-radius", "6")
        renderer.setStyle(row, "cursor", "pointer")
        renderer.setStyle(row, "flex-direction", "row")
        renderer.setStyle(row, "align-items", "center")

        # Inner label keeps the visible text reachable via textContent
        # without colliding with the click handler on the row itself.
        let rowLabel = renderer.createElement("span")
        renderer.setAttribute(rowLabel, "class", "settings-group-row-label")
        renderer.setTextContent(rowLabel, g.label)
        renderer.appendChild(row, rowLabel)

        renderer.addEventListener(row, "click", proc() =
          discard vmRef.setActiveGroup(gid))
        renderer.appendChild(groupsCol, row)

        # Reactive active-state binding for this group row.
        # Active rows carry an indigo accent fill (per RS-M14 Phase 2
        # the shim drops border-width / font-weight, so emphasis is
        # achieved via background + text-color contrast only).
        let rowRef = row
        let labelRef = rowLabel
        createRenderEffect proc() =
          let isActive = vmRef.activeGroupId.val == gid
          renderer.setAttribute(rowRef, "class",
            (if isActive: "settings-group-row active"
             else: "settings-group-row"))
          if isActive:
            renderer.setAttribute(rowRef, "aria-pressed", "true")
            renderer.setStyle(rowRef, "background", "#7c7aed")
            renderer.setStyle(labelRef, "color", "#ffffff")
          else:
            renderer.removeAttribute(rowRef, "aria-pressed")
            renderer.setStyle(rowRef, "background", "#22232e")
            renderer.setStyle(labelRef, "color", "#a0a2b0")

    # ---- Items column: only the active group's header + items --------
    let itemsCol = renderer.createElement("div")
    renderer.setAttribute(itemsCol, "class", "settings-items-column")
    renderer.setStyle(itemsCol, "background", "#15151c")
    renderer.setStyle(itemsCol, "padding", "12")
    renderer.setStyle(itemsCol, "gap", "10")
    renderer.setStyle(itemsCol, "flex-direction", "column")
    renderer.setStyle(itemsCol, "width", "520")
    renderer.setStyle(itemsCol, "border-radius", "8")
    renderer.appendChild(appRoot, itemsCol)

    # The items column's child group section is rebuilt whenever
    # `vm.activeGroupId` changes. Old per-item event listeners are
    # dropped along with the old DOM nodes.
    var currentItemsSection = renderer.createElement("section")
    var hasItemsSection = false

    createRenderEffect proc() =
      let activeId = vmRef.activeGroupId.val
      if hasItemsSection:
        renderer.removeChild(itemsCol, currentItemsSection)
        hasItemsSection = false
      if vmRef.catalog.hasGroup(activeId):
        let activeGroup = vmRef.currentGroup
        let paneGroupNode = groupContainerLeaf(renderer)
        renderer.setAttribute(paneGroupNode, "data-group-id",
                              activeGroup.id)
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
        currentItemsSection = paneGroupNode
        hasItemsSection = true

    appRoot

template selectGroup*(vmRef, groupId): untyped =
  ## Activate the group with `groupId`. Re-renders flow through the
  ## reactive graph (the shell's `createRenderEffect` over
  ## `activeGroupId`); tests call this through `vm.setActiveGroup`
  ## directly. The template exists so a click-driver pilot script
  ## reads naturally.
  discard vmRef.setActiveGroup(groupId)
