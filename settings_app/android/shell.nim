## settings_app/android/shell.nim — Layer-3 shell for the Android target.
##
## EX-M22. The Android shell's composition is deliberately distinct from
## every other rendered shell — a **bottom-sheet drawer** per group:
##
##   * A scrollable vertical list (`<div class="settings-app-android"
##     data-app="settings-app" data-layout="bottom-sheet-list">`) holds
##     one card-style row per group, each showing the group header
##     only. No items are inlined into the list.
##   * Tapping a row "opens" that group's bottom sheet — a sibling
##     `<aside class="settings-bottom-sheet">` slides up below the list
##     in document order. The bottom-sheet pane carries the items of
##     the currently-active group.
##   * The currently-active group's row in the list carries an `active`
##     class and a `▾` marker; non-active rows carry `▴`. Tapping the
##     active row again is idempotent (the shell does not implement
##     close-by-double-tap — selecting a different group transitions to
##     it, mirroring the cross-renderer test surface that always picks
##     one active group at a time).
##
## Visible composition differences:
##   * TUI (EX-M10) — single vertical column accordion; one expanded
##     section at a time.
##   * web (EX-M11) — `<nav class="settings-sidebar">` + `<section
##     class="settings-pane">`.
##   * GPUI (EX-M12) — flat 2-column grid.
##   * Freya (EX-M15) — every group's items expanded simultaneously
##     inside its card.
##   * Cocoa (EX-M20) — disclosure-list with `▶`/`▼` triangle markers
##     directly under each group's header.
##   * Android (this shell) — header rows in a scrollable list, items
##     deferred to a single bottom-sheet pane that swaps content as the
##     active group changes. The pane carries `data-sheet-state="open"`
##     when an active group's items are visible.
##
## Tree shape::
##
##   <div class="settings-app-android" data-app="settings-app"
##        data-layout="bottom-sheet-list">
##     <ul class="settings-sheet-list">
##       <li class="settings-sheet-row (active|)" data-sheet-id="appearance">
##         <span class="settings-sheet-marker">▾</span>
##         <section class="settings-group" data-group-id="appearance">
##           <header class="settings-group-header">…</header>
##         </section>
##       </li>
##       <li class="settings-sheet-row" data-sheet-id="editor">
##         <span class="settings-sheet-marker">▴</span>
##         <section class="settings-group" data-group-id="editor">
##           <header class="settings-group-header">…</header>
##         </section>
##       </li>
##       …
##     </ul>
##     <aside class="settings-bottom-sheet" data-sheet-state="open"
##            data-sheet-id="appearance">
##       <div class="settings-item">…</div>
##       <div class="settings-item">…</div>
##       …
##     </aside>
##   </div>
##
## The bottom-sheet pane is materialised lazily: on initial mount it
## carries the items for the default-active group, and a
## `createRenderEffect` over `vm.activeGroupId.val` swaps the pane's
## contents whenever the active group changes (removing the old items
## and appending the new group's items in their declared order).
##
## Include-pattern: this file is *included* — never imported — by the
## Layer-4 composition root (`settings_app/main_android.nim`). The shell
## binds against the unqualified leaf names (`groupContainerLeaf`,
## `groupHeaderLeaf`, `renderToggleItem`, ...) that the composition
## root brings into scope before the include.

template renderSettingsShell*(renderer, vmRef): untyped {.dirty.} =
  ## Build the full settings-app tree against the given renderer and
  ## ViewModel. Returns the root node.
  block:
    let appRoot = renderer.createElement("div")
    renderer.setAttribute(appRoot, "class", "settings-app-android")
    renderer.setAttribute(appRoot, "data-app", "settings-app")
    renderer.setAttribute(appRoot, "data-layout", "bottom-sheet-list")

    let listNode = renderer.createElement("ul")
    renderer.setAttribute(listNode, "class", "settings-sheet-list")
    renderer.appendChild(appRoot, listNode)

    for groupIdx in 0 ..< vmRef.catalog.groups.len:
      closureScope:
        let g = vmRef.catalog.groups[groupIdx]
        let gid = g.id
        let initiallyActive = vmRef.activeGroupId.val == gid

        let row = renderer.createElement("li")
        renderer.setAttribute(row, "data-sheet-id", gid)

        let marker = renderer.createElement("span")
        renderer.setAttribute(marker, "class", "settings-sheet-marker")
        # "\xE2\x96\xBE" is "▾" (U+25BE), "\xE2\x96\xB4" is "▴"
        # (U+25B4). Hard-coded UTF-8 byte sequences keep the template
        # include-friendly across renderers that don't interpret the
        # source file's encoding the same way (a needless concern on
        # Android specifically, but consistent with the Cocoa triangle
        # pattern).
        renderer.setTextContent(marker,
                                (if initiallyActive: "\xE2\x96\xBE"
                                 else: "\xE2\x96\xB4"))
        renderer.appendChild(row, marker)

        let groupNode = groupContainerLeaf(renderer)
        renderer.setAttribute(groupNode, "data-group-id", gid)

        let header = groupHeaderLeaf(renderer, g.label, g.description)
        renderer.setAttribute(header, "data-focusable", "true")
        renderer.setAttribute(header, "data-group-id", gid)
        renderer.addEventListener(header, "click", proc() =
          discard vmRef.setActiveGroup(gid))
        renderer.appendChild(groupNode, header)

        renderer.appendChild(row, groupNode)
        renderer.appendChild(listNode, row)

        # Reactive row class: the row carries an `active` modifier
        # whenever its group is the current `activeGroupId`. Mirrors
        # the Cocoa shell's disclosure-class binding.
        let rCaptured = renderer
        let groupId = gid
        let rowNode = row
        let markerNode = marker
        createRenderEffect proc() =
          let isActive = vmRef.activeGroupId.val == groupId
          rCaptured.setAttribute(rowNode, "class",
            (if isActive: "settings-sheet-row active"
             else: "settings-sheet-row"))
          rCaptured.setTextContent(markerNode,
            (if isActive: "\xE2\x96\xBE" else: "\xE2\x96\xB4"))
          if isActive:
            rCaptured.setAttribute(rowNode, "aria-expanded", "true")
          else:
            rCaptured.removeAttribute(rowNode, "aria-expanded")

    # Bottom-sheet pane. Mount it empty; a `createRenderEffect` over
    # `activeGroupId` populates the pane on initial subscribe and
    # repopulates it whenever the active group changes (matches the
    # Cocoa disclosure shell's lazy materialisation pattern but for a
    # single pane shared across all groups).
    let sheet = renderer.createElement("aside")
    renderer.setAttribute(sheet, "class", "settings-bottom-sheet")
    renderer.appendChild(appRoot, sheet)

    let rCapturedSheet = renderer
    let sheetNode = sheet
    let catalogRef = vmRef.catalog
    createRenderEffect proc() =
      let activeId = vmRef.activeGroupId.val
      rCapturedSheet.setAttribute(sheetNode, "data-sheet-id", activeId)
      # Find the active group.
      var groupOpt: int = -1
      for i in 0 ..< catalogRef.groups.len:
        if catalogRef.groups[i].id == activeId:
          groupOpt = i
          break
      # Clear the pane's children before repopulating. On the initial
      # subscribe the pane is empty so this is a no-op; on subsequent
      # `activeGroupId` changes we remove the previous group's items.
      while rCapturedSheet.childCount(sheetNode) > 0:
        let last = rCapturedSheet.nthChild(sheetNode,
          rCapturedSheet.childCount(sheetNode) - 1)
        rCapturedSheet.removeChild(sheetNode, last)
      if groupOpt < 0:
        rCapturedSheet.setAttribute(sheetNode, "data-sheet-state", "closed")
        return
      rCapturedSheet.setAttribute(sheetNode, "data-sheet-state", "open")
      let g = catalogRef.groups[groupOpt]
      for itemIdx in 0 ..< g.items.len:
        let it = g.items[itemIdx]
        case it.kind
        of sikToggle:
          rCapturedSheet.appendChild(sheetNode,
            renderToggleItem(rCapturedSheet, vmRef, it))
        of sikNumber:
          rCapturedSheet.appendChild(sheetNode,
            renderNumberItem(rCapturedSheet, vmRef, it))
        of sikChoice:
          rCapturedSheet.appendChild(sheetNode,
            renderChoiceItem(rCapturedSheet, vmRef, it))

    appRoot

template activateGroup*(vmRef, groupId): untyped =
  ## Activate the group with `groupId`. Re-renders flow through the
  ## reactive graph (the shell's `createRenderEffect` over
  ## `activeGroupId`); tests call this through `vm.setActiveGroup`
  ## directly.
  discard vmRef.setActiveGroup(groupId)
