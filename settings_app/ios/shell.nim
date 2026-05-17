## settings_app/ios/shell.nim — Layer-3 shell for the iOS target.
##
## Mirrors `settings_app/android/shell.nim` (inline-accordion list)
## because on a phone form factor the accordion is the idiomatic
## chrome. Each group's card stacks its header on top with the items
## immediately underneath when the group is active; collapsed groups
## show only their header.
##
## Include-pattern: this file is *included* — never imported — by the
## Layer-4 composition root (`settings_app/main_ios.nim`). The shell
## binds against unqualified leaf names (`groupContainerLeaf`,
## `groupHeaderLeaf`, `renderToggleItem`, ...) that the composition
## root brings into scope before the include.

template renderSettingsShell*(renderer, vmRef): untyped {.dirty.} =
  ## Build the full settings-app tree against the given renderer and
  ## ViewModel. Returns the root node. Re-rendering of the active
  ## group's body is driven by a `createRenderEffect` that observes
  ## `vmRef.activeGroupId.val`.
  block:
    let appRoot = renderer.createElement("div")
    renderer.setAttribute(appRoot, "class", "settings-app-ios")
    renderer.setAttribute(appRoot, "data-app", "settings-app")
    renderer.setAttribute(appRoot, "data-layout", "accordion-list")
    renderer.setStyle(appRoot, "background-color", "#0f0f17")
    renderer.setStyle(appRoot, "padding", "16")
    renderer.setStyle(appRoot, "gap", "12")

    let listNode = renderer.createElement("ul")
    renderer.setAttribute(listNode, "class", "settings-sheet-list")
    renderer.setStyle(listNode, "gap", "12")
    renderer.appendChild(appRoot, listNode)

    var groupSections: seq[tuple[gid: string; section: UIKitElement]] = @[]

    for groupIdx in 0 ..< vmRef.catalog.groups.len:
      closureScope:
        let g = vmRef.catalog.groups[groupIdx]
        let gid = g.id
        let initiallyActive = vmRef.activeGroupId.val == gid

        let row = renderer.createElement("li")
        renderer.setAttribute(row, "data-sheet-id", gid)

        let marker = renderer.createElement("span")
        renderer.setAttribute(marker, "class", "settings-sheet-marker")
        renderer.setTextContent(marker,
                                (if initiallyActive: "\xE2\x96\xBE"
                                 else: "\xE2\x96\xB4"))
        renderer.setStyle(marker, "color", "#7c7aed")
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
        groupSections.add (gid: gid, section: groupNode)

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

    # Bottom-sheet aside — parity-test surface.
    let sheet = renderer.createElement("aside")
    renderer.setAttribute(sheet, "class", "settings-bottom-sheet")
    # Collapse on the device; the visible items live in the inline
    # group sections above.
    renderer.setStyle(sheet, "width", "0")
    renderer.setStyle(sheet, "height", "0")
    renderer.appendChild(appRoot, sheet)

    let rCapturedSheet = renderer
    let sheetNode = sheet
    let catalogRef = vmRef.catalog
    let groupSectionsRef = groupSections
    createRenderEffect proc() =
      let activeId = vmRef.activeGroupId.val
      rCapturedSheet.setAttribute(sheetNode, "data-sheet-id", activeId)

      var groupOpt: int = -1
      for i in 0 ..< catalogRef.groups.len:
        if catalogRef.groups[i].id == activeId:
          groupOpt = i
          break

      # 1. Clear inline items from every group section (every child
      #    after the header at index 0).
      for entry in groupSectionsRef:
        let sec = entry.section
        while rCapturedSheet.childCount(sec) > 1:
          let last = rCapturedSheet.nthChild(sec,
            rCapturedSheet.childCount(sec) - 1)
          rCapturedSheet.removeChild(sec, last)

      # 2. Clear the bottom-sheet aside's children.
      while rCapturedSheet.childCount(sheetNode) > 0:
        let last = rCapturedSheet.nthChild(sheetNode,
          rCapturedSheet.childCount(sheetNode) - 1)
        rCapturedSheet.removeChild(sheetNode, last)

      if groupOpt < 0:
        rCapturedSheet.setAttribute(sheetNode, "data-sheet-state", "closed")
        return
      rCapturedSheet.setAttribute(sheetNode, "data-sheet-state", "open")

      var activeSection: UIKitElement = UIKitElement(Id(nil))
      for entry in groupSectionsRef:
        if entry.gid == activeId:
          activeSection = entry.section
          break

      let g = catalogRef.groups[groupOpt]
      for itemIdx in 0 ..< g.items.len:
        let it = g.items[itemIdx]
        case it.kind
        of sikToggle:
          if pointer(activeSection) != nil:
            rCapturedSheet.appendChild(activeSection,
              renderToggleItem(rCapturedSheet, vmRef, it))
          rCapturedSheet.appendChild(sheetNode,
            renderToggleItem(rCapturedSheet, vmRef, it))
        of sikNumber:
          if pointer(activeSection) != nil:
            rCapturedSheet.appendChild(activeSection,
              renderNumberItem(rCapturedSheet, vmRef, it))
          rCapturedSheet.appendChild(sheetNode,
            renderNumberItem(rCapturedSheet, vmRef, it))
        of sikChoice:
          if pointer(activeSection) != nil:
            rCapturedSheet.appendChild(activeSection,
              renderChoiceItem(rCapturedSheet, vmRef, it))
          rCapturedSheet.appendChild(sheetNode,
            renderChoiceItem(rCapturedSheet, vmRef, it))

    appRoot

template activateGroup*(vmRef, groupId): untyped =
  ## Activate the group with `groupId`. Re-renders flow through the
  ## reactive graph (the shell's `createRenderEffect` over
  ## `activeGroupId`).
  discard vmRef.setActiveGroup(groupId)
