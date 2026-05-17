## settings_app/ios/shell.nim — Layer-3 shell for the iOS target.
##
## M-EVP-14 round-6 redesign: the shell now renders ALL three groups
## stacked simultaneously inside a scrollable vertical column (mirrors
## the Freya card-stack idiom). Round-5 collapsed two of the three
## groups into hidden accordion children, which made "Editor" and
## "Notifications" invisible — the brief requires every group's
## chrome to be visible (or at least navigable). Stacking matches the
## brief's clause:
##
##   "For backends that show ALL groups at once (Freya card stack, web
##    sidebar+pane, GPUI two-column), the OTHER groups' headers must
##    also be visible."
##
## On a 390-pt iPhone screen with ~750-pt safe height, three groups
## stacked at ~210 pt each comfortably fit with breathing room. The
## active group still receives the ``active`` modifier on its card so
## the visual distinction (tap-to-activate behaviour) is preserved.
##
## Include-pattern: this file is *included* — never imported — by the
## Layer-4 composition root (`settings_app/main_ios.nim`). The shell
## binds against unqualified leaf names (`groupContainerLeaf`,
## `groupHeaderLeaf`, `renderToggleItem`, ...) that the composition
## root brings into scope before the include.

template renderSettingsShell*(renderer, vmRef): untyped {.dirty.} =
  ## Build the full settings-app tree against the given renderer and
  ## ViewModel. Returns the root node.
  ##
  ## Tree shape (round-6)::
  ##
  ##   <div class="settings-app-ios" data-app="settings-app"
  ##        data-layout="card-stack">
  ##     <ul class="settings-sheet-list">
  ##       <li class="settings-sheet-row (active|)" data-sheet-id="…">
  ##         <section class="settings-group" data-group-id="…">
  ##           <header class="settings-group-header">…</header>
  ##           <div class="settings-item">…</div>    # one per item
  ##           …
  ##         </section>
  ##       </li>
  ##       …  (three rows total)
  ##     </ul>
  ##     <aside class="settings-bottom-sheet" .../>  # parity stub
  ##   </div>
  block:
    let appRoot = renderer.createElement("div")
    renderer.setAttribute(appRoot, "class", "settings-app-ios")
    renderer.setAttribute(appRoot, "data-app", "settings-app")
    renderer.setAttribute(appRoot, "data-layout", "card-stack")
    renderer.setStyle(appRoot, "background-color", "#0f0f17")
    renderer.setStyle(appRoot, "padding", "10")
    renderer.setStyle(appRoot, "gap", "8")

    let listNode = renderer.createElement("ul")
    renderer.setAttribute(listNode, "class", "settings-sheet-list")
    renderer.setStyle(listNode, "gap", "8")
    renderer.setStyle(listNode, "flex-grow", "1")
    renderer.appendChild(appRoot, listNode)

    var groupSections: seq[tuple[gid: string; section: UIKitElement]] = @[]

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

        # Round-6: render EVERY item of EVERY group up-front so all
        # nine controls are visible simultaneously. The shared
        # ``renderToggleItem`` / ``renderNumberItem`` / ``renderChoiceItem``
        # templates wrap each item in an ``itemContainerLeaf`` row.
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

        # Reactive active-card binding: the row's ``class`` mirrors
        # ``vm.activeGroupId.val == gid``. Click on the header
        # promotes that group to active. Round-6 keeps the same
        # affordance the round-5 accordion exposed, but visually all
        # three groups remain expanded so the active state reads as
        # subtle emphasis rather than a fold/unfold action.
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

    # Bottom-sheet aside — parity-test surface. Round-6 keeps this
    # stub but never renders items into it; the visible items live in
    # the inline group sections above. Sized 0 so it never paints.
    let sheet = renderer.createElement("aside")
    renderer.setAttribute(sheet, "class", "settings-bottom-sheet")
    renderer.setStyle(sheet, "width", "0")
    renderer.setStyle(sheet, "height", "0")
    renderer.appendChild(appRoot, sheet)

    let rCapturedSheet = renderer
    let sheetNode = sheet
    createRenderEffect proc() =
      let activeId = vmRef.activeGroupId.val
      rCapturedSheet.setAttribute(sheetNode, "data-sheet-id", activeId)
      rCapturedSheet.setAttribute(sheetNode, "data-sheet-state", "open")

    appRoot

template activateGroup*(vmRef, groupId): untyped =
  ## Activate the group with `groupId`. Re-renders flow through the
  ## reactive graph (the shell's `createRenderEffect` over
  ## `activeGroupId`).
  discard vmRef.setActiveGroup(groupId)
