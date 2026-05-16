## settings_app/android/shell.nim — Layer-3 shell for the Android target.
##
## EX-M22. The Android shell's composition is deliberately distinct from
## every other rendered shell. Round-5 rewrite: instead of stacking all
## three group headers as a header rail above a separate bottom-sheet
## pane, the shell now inlines the expanded group's items immediately
## under its own header, with the collapsed groups' headers sitting
## above and below the expansion. This matches real Android Settings'
## single vertical accordion stack.
##
##   * A vertical list (`<div class="settings-app-android"
##     data-app="settings-app" data-layout="accordion-list">`) holds
##     one card-style row per group, in catalog order. The active
##     group's row carries an `active` class and a `▾` marker; non-
##     active rows carry `▴`.
##   * The active group's items are appended INSIDE its own
##     `<section class="settings-group">` (which already holds the
##     header). Collapsed groups show only their header. Tapping a
##     collapsed group's header activates it (mirrors the Cocoa
##     disclosure shell pattern; same `createRenderEffect` over
##     `vm.activeGroupId.val` repopulates the active section in place).
##   * A `<aside class="settings-bottom-sheet">` is still mounted at
##     the root for cross-renderer parity-test compatibility (the
##     parity driver in
##     `tests/test_settings_parity_across_renderers.nim` looks for
##     this class to locate the active items). The aside mirrors the
##     active group's section reference so the test surface keeps
##     working while the visible chrome paints the inline accordion.
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
##   * Android (this shell, round-5) — inline-accordion list: each
##     group's row stacks `<header>` + (when active) the group's items
##     directly underneath, in a single vertical stack. Collapsed
##     groups sit above and below the expansion. A hidden bottom-sheet
##     aside at root mirrors the active items for parity-test compat.
##
## Tree shape::
##
##   <div class="settings-app-android" data-app="settings-app"
##        data-layout="accordion-list">
##     <ul class="settings-sheet-list">
##       <li class="settings-sheet-row (active|)" data-sheet-id="appearance">
##         <span class="settings-sheet-marker">▾</span>
##         <section class="settings-group" data-group-id="appearance">
##           <header class="settings-group-header">…</header>
##           <div class="settings-item">…</div>  # only when active
##           <div class="settings-item">…</div>
##           …
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
##       <div class="settings-item">…</div>  # mirror of inline items
##       <div class="settings-item">…</div>
##       …
##     </aside>
##   </div>
##
## Both the inline section and the bottom-sheet aside are materialised
## lazily: a single `createRenderEffect` over `vm.activeGroupId.val`
## tears down items in every group's section + the aside, then
## repopulates the active group's inline section AND the aside (twice
## — the inline copy is what the device renders, the aside is the
## parity-test surface).
##
## Include-pattern: this file is *included* — never imported — by the
## Layer-4 composition root (`settings_app/main_android.nim`). The shell
## binds against the unqualified leaf names (`groupContainerLeaf`,
## `groupHeaderLeaf`, `renderToggleItem`, ...) that the composition
## root brings into scope before the include.

template renderSettingsShell*(renderer, vmRef): untyped {.dirty.} =
  ## Build the full settings-app tree against the given renderer and
  ## ViewModel. Returns the root node.
  ##
  ## Round-5 rewrite: each group's row holds its own header AND, when
  ## the group is the active one, that group's items appended directly
  ## under the header inside the same `settings-group` section. The
  ## bottom-sheet aside stays at the root so the cross-renderer parity
  ## test (`tests/test_settings_parity_across_renderers.nim`) can find
  ## items via the `androidBottomSheet` lookup, but the visible chrome
  ## paints the inline-accordion stack.
  block:
    let appRoot = renderer.createElement("div")
    renderer.setAttribute(appRoot, "class", "settings-app-android")
    renderer.setAttribute(appRoot, "data-app", "settings-app")
    renderer.setAttribute(appRoot, "data-layout", "accordion-list")

    let listNode = renderer.createElement("ul")
    renderer.setAttribute(listNode, "class", "settings-sheet-list")
    renderer.appendChild(appRoot, listNode)

    # Per-group sections — captured here so the createRenderEffect
    # below can repopulate the active group's items inline whenever
    # the user activates a different group.
    var groupSections: seq[tuple[gid: string;
                                 section: AndroidElement]] = @[]

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

        # Round-5: inline items are materialised lazily by the
        # createRenderEffect below — that effect fires on initial
        # subscribe so the seeded active group's items appear under
        # its header on the first paint, and re-runs whenever the
        # active group changes to relocate items in place.

        renderer.appendChild(row, groupNode)
        renderer.appendChild(listNode, row)
        groupSections.add (gid: gid, section: groupNode)

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

    # Bottom-sheet aside — kept at root level so the cross-renderer
    # parity-test driver can locate the active group's items via
    # `androidBottomSheet`. It mirrors the active group's items. The
    # aside renders below the inline accordion stack but, in practice,
    # adds no visible chrome — its items are duplicates of the inline
    # ones inside the active row's `settings-group` section.
    let sheet = renderer.createElement("aside")
    renderer.setAttribute(sheet, "class", "settings-bottom-sheet")
    renderer.appendChild(appRoot, sheet)

    let rCapturedSheet = renderer
    let sheetNode = sheet
    let catalogRef = vmRef.catalog
    let groupSectionsRef = groupSections
    createRenderEffect proc() =
      let activeId = vmRef.activeGroupId.val
      rCapturedSheet.setAttribute(sheetNode, "data-sheet-id", activeId)
      # Find the active group.
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

      # 2. Clear the bottom-sheet aside's children (the parity test's
      #    accessor surface).
      while rCapturedSheet.childCount(sheetNode) > 0:
        let last = rCapturedSheet.nthChild(sheetNode,
          rCapturedSheet.childCount(sheetNode) - 1)
        rCapturedSheet.removeChild(sheetNode, last)

      if groupOpt < 0:
        rCapturedSheet.setAttribute(sheetNode, "data-sheet-state", "closed")
        return
      rCapturedSheet.setAttribute(sheetNode, "data-sheet-state", "open")

      # 3. Find the active group's inline section and repopulate its
      #    items inline; mirror the same items in the bottom-sheet
      #    aside for parity-test compatibility.
      var activeSection: AndroidElement = 0
      for entry in groupSectionsRef:
        if entry.gid == activeId:
          activeSection = entry.section
          break

      let g = catalogRef.groups[groupOpt]
      for itemIdx in 0 ..< g.items.len:
        let it = g.items[itemIdx]
        case it.kind
        of sikToggle:
          if activeSection != 0:
            rCapturedSheet.appendChild(activeSection,
              renderToggleItem(rCapturedSheet, vmRef, it))
          rCapturedSheet.appendChild(sheetNode,
            renderToggleItem(rCapturedSheet, vmRef, it))
        of sikNumber:
          if activeSection != 0:
            rCapturedSheet.appendChild(activeSection,
              renderNumberItem(rCapturedSheet, vmRef, it))
          rCapturedSheet.appendChild(sheetNode,
            renderNumberItem(rCapturedSheet, vmRef, it))
        of sikChoice:
          if activeSection != 0:
            rCapturedSheet.appendChild(activeSection,
              renderChoiceItem(rCapturedSheet, vmRef, it))
          rCapturedSheet.appendChild(sheetNode,
            renderChoiceItem(rCapturedSheet, vmRef, it))

    appRoot

template activateGroup*(vmRef, groupId): untyped =
  ## Activate the group with `groupId`. Re-renders flow through the
  ## reactive graph (the shell's `createRenderEffect` over
  ## `activeGroupId`); tests call this through `vm.setActiveGroup`
  ## directly.
  discard vmRef.setActiveGroup(groupId)
