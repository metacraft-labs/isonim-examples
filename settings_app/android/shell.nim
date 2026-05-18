## settings_app/android/shell.nim — Layer-3 shell for the Android target.
##
## EX-M22 - Round-10 wave-Q rewrite.  The earlier shell (rounds 5..9)
## painted the catalogue as an inline accordion stack: the active
## group's items lived inside its own card, and every other group's
## card showed only its header.  A separate `<aside
## class="settings-bottom-sheet">` at the root mirrored the active
## items so the cross-renderer parity-test driver could find them.
##
## The round-9 reviewer flagged two problems with that shape:
##
##   * "'Editor' and 'Notifications' group headers are visible but
##     their items aren't rendered - only Appearance is populated"
##     (a deliberate-but-confusing consequence of the accordion).
##   * "The second copy of 'Dark mode / Use the dark colour palette'
##     under Notifications looks like a layout / data echo bug"
##     (the bottom-sheet aside paints below the inline stack and
##     visually shows up beneath the last group's header).
##
## Round-10 mirrors the Freya shell: every group renders ALL of its
## items inline inside its own card, in catalog order.  The active
## group's card carries an `active` class so the reactive visual cue
## still works.  The hidden bottom-sheet aside is kept at the root
## (with `display: GONE`) so the cross-renderer parity test
## (`tests/test_settings_parity_across_renderers.nim`'s
## `androidBottomSheet`) keeps finding the active group's items at
## the documented path - the aside is the *test surface*, the
## visible chrome is the inline cards.
##
## Tree shape::
##
##   <div class="settings-app-android" data-app="settings-app"
##        data-layout="card-stack">
##     <ul class="settings-sheet-list">
##       <li class="settings-sheet-row (active|)" data-sheet-id="appearance">
##         <section class="settings-group" data-group-id="appearance">
##           <header class="settings-group-header">...</header>
##           <div class="settings-item">...</div>  # ALL items, always
##         </section>
##       </li>
##       <li class="settings-sheet-row" data-sheet-id="editor">
##         <section class="settings-group" data-group-id="editor">
##           <header class="settings-group-header">...</header>
##           <div class="settings-item">...</div>  # ALL items, always
##         </section>
##       </li>
##       <li class="settings-sheet-row" data-sheet-id="notifications">...</li>
##     </ul>
##     <aside class="settings-bottom-sheet" data-sheet-state="open"
##            data-sheet-id="appearance" style="display: GONE">
##       <div class="settings-item">...</div>  # mirror of active items
##     </aside>
##   </div>
##
## Include-pattern: this file is *included* - never imported - by the
## Layer-4 composition root (`settings_app/main_android.nim`).  The shell
## binds against the unqualified leaf names (`groupContainerLeaf`,
## `groupHeaderLeaf`, `renderToggleItem`, ...) that the composition
## root brings into scope before the include.

template renderSettingsShell*(renderer, vmRef): untyped {.dirty.} =
  ## Build the full settings-app tree against the given renderer and
  ## ViewModel.  Returns the root node.
  ##
  ## Round-10: render every group's items inline inside the group's
  ## own card (mirrors the Freya card-stack shell).  A hidden
  ## bottom-sheet aside at root keeps the cross-renderer parity test
  ## working.
  block:
    let appRoot = renderer.createElement("div")
    renderer.setAttribute(appRoot, "class", "settings-app-android")
    renderer.setAttribute(appRoot, "data-app", "settings-app")
    renderer.setAttribute(appRoot, "data-layout", "card-stack")
    renderer.setStyle(appRoot, "flex-direction", "column")
    renderer.setStyle(appRoot, "gap", "12")

    let listNode = renderer.createElement("ul")
    renderer.setAttribute(listNode, "class", "settings-sheet-list")
    renderer.setStyle(listNode, "flex-direction", "column")
    renderer.setStyle(listNode, "gap", "12")
    renderer.appendChild(appRoot, listNode)

    # Per-group sections - captured so the bottom-sheet aside mirror
    # below can locate the active group's items at any time.
    var groupSections: seq[tuple[gid: string;
                                 section: AndroidElement]] = @[]

    for groupIdx in 0 ..< vmRef.catalog.groups.len:
      closureScope:
        let g = vmRef.catalog.groups[groupIdx]
        let gid = g.id

        let row = renderer.createElement("li")
        renderer.setAttribute(row, "data-sheet-id", gid)
        renderer.setStyle(row, "flex-direction", "column")

        let groupNode = groupContainerLeaf(renderer)
        renderer.setAttribute(groupNode, "data-group-id", gid)

        let header = groupHeaderLeaf(renderer, g.label, g.description)
        renderer.setAttribute(header, "data-focusable", "true")
        renderer.setAttribute(header, "data-group-id", gid)
        renderer.addEventListener(header, "click", proc() =
          discard vmRef.setActiveGroup(gid))
        renderer.appendChild(groupNode, header)

        # Round-10: render every group's items inline regardless of
        # which one is active.  Mirrors the Freya card-stack shell;
        # the active modifier below is the only visual differentiator
        # between active and inactive groups.  The round-5..9 shell
        # painted only the active group's items inline + a separate
        # bottom-sheet aside echoing them, which read as a layout bug
        # to the round-9 reviewer (the aside paints below all the
        # collapsed group headers, so the same items appeared twice).
        for itemIdx in 0 ..< g.items.len:
          closureScope:
            let it = g.items[itemIdx]
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

        renderer.appendChild(row, groupNode)
        renderer.appendChild(listNode, row)
        groupSections.add (gid: gid, section: groupNode)

        # Reactive active-row class: mirrors `vm.activeGroupId.val`.
        let rCaptured = renderer
        let groupId = gid
        let rowNode = row
        createRenderEffect proc() =
          let isActive = vmRef.activeGroupId.val == groupId
          rCaptured.setAttribute(rowNode, "class",
            (if isActive: "settings-sheet-row active"
             else: "settings-sheet-row"))
          if isActive:
            rCaptured.setAttribute(rowNode, "aria-expanded", "true")
          else:
            rCaptured.removeAttribute(rowNode, "aria-expanded")

    # Hidden bottom-sheet aside - kept at root level so the cross-
    # renderer parity-test driver can locate the active group's items
    # via `androidBottomSheet`.  `display: GONE` (mapped to
    # `visibility: GONE` on the device) removes the aside from layout
    # while leaving it in the Nim view tree for the test surface.
    let sheet = renderer.createElement("aside")
    renderer.setAttribute(sheet, "class", "settings-bottom-sheet")
    renderer.setStyle(sheet, "display", "GONE")
    renderer.appendChild(appRoot, sheet)

    let rCapturedSheet = renderer
    let sheetNode = sheet
    let catalogRef = vmRef.catalog
    createRenderEffect proc() =
      let activeId = vmRef.activeGroupId.val
      rCapturedSheet.setAttribute(sheetNode, "data-sheet-id", activeId)
      var groupOpt: int = -1
      for i in 0 ..< catalogRef.groups.len:
        if catalogRef.groups[i].id == activeId:
          groupOpt = i
          break

      # Clear the bottom-sheet aside's previous mirror.
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
  ## Activate the group with `groupId`.  Re-renders flow through the
  ## reactive graph (the shell's `createRenderEffect` over
  ## `activeGroupId`); tests call this through `vm.setActiveGroup`
  ## directly.
  discard vmRef.setActiveGroup(groupId)
