## settings_app/cocoa/shell.nim — Layer-3 shell for the Cocoa target.
##
## EX-M20. The Cocoa shell's composition is deliberately distinct from
## the TUI accordion, web sidebar+pane, GPUI two-column grid, and Freya
## card stack: an **AppKit-style disclosure-group list** where every
## settings group renders as a vertical row whose items are revealed
## only when the group's disclosure triangle is expanded. The active
## group is auto-expanded; clicking a different group's header
## activates it (collapsing the previously-active group and expanding
## the new one).
##
## Visible composition differences:
##   * TUI (EX-M10) — single vertical column; group headers always
##     visible; only the active group's items render below its header
##     (accordion: one expanded section at a time).
##   * web (EX-M11) — `<nav class="settings-sidebar">` plus
##     `<section class="settings-pane">`; only the active group's
##     items render in the pane.
##   * GPUI (EX-M12) — flat 2-column grid; left column lists groups,
##     right column shows only the active group's items.
##   * Freya (EX-M15) — every group renders as a self-contained
##     `<div class="settings-card">` stacked vertically; ALL groups'
##     items render simultaneously inside their respective cards.
##   * Cocoa (this shell) — vertical disclosure-group list. Each group
##     gets its own `<div class="settings-disclosure">` row whose
##     header (the `<header class="settings-group-header">` leaf) is
##     wrapped with a `<span class="settings-disclosure-triangle">`
##     "▶" / "▼" indicator. Only the active group's items render;
##     other groups show just their headers (collapsed). The
##     disclosure-triangle marker on the header is the visibly distinct
##     AppKit-flavoured chrome that none of the other shells produce.
##
## Tree shape::
##
##   <div class="settings-app-cocoa" data-app="settings-app"
##        data-layout="disclosure-list">
##     <div class="settings-disclosure (active|)" data-disclosure-id="appearance">
##       <span class="settings-disclosure-triangle">▼</span>
##       <section class="settings-group" data-group-id="appearance">
##         <header class="settings-group-header">…</header>
##         <div class="settings-item">…</div>  # only when active
##         …
##       </section>
##     </div>
##     <div class="settings-disclosure" data-disclosure-id="editor">
##       <span class="settings-disclosure-triangle">▶</span>
##       <section class="settings-group" data-group-id="editor">
##         <header class="settings-group-header">…</header>
##       </section>
##     </div>
##     …
##
## The shell calls the per-kind component templates (`renderToggleItem`
## / `renderNumberItem` / `renderChoiceItem`) directly rather than the
## umbrella `renderSettingsGroup` template, because the shell owns the
## per-disclosure chrome and the group's container/header. This matches
## the per-shell pattern across TUI / web / GPUI / Freya.
##
## Include-pattern: this file is *included* — never imported — by the
## Layer-4 composition root (`settings_app/main_cocoa.nim`).

template renderSettingsShell*(renderer, vmRef): untyped {.dirty.} =
  ## Build the full settings-app tree against the given renderer and
  ## ViewModel. Returns the root node.
  block:
    let appRoot = renderer.createElement("div")
    renderer.setAttribute(appRoot, "class", "settings-app-cocoa")
    renderer.setAttribute(appRoot, "data-app", "settings-app")
    renderer.setAttribute(appRoot, "data-layout", "disclosure-list")

    for groupIdx in 0 ..< vmRef.catalog.groups.len:
      closureScope:
        let g = vmRef.catalog.groups[groupIdx]
        let gid = g.id
        let initiallyActive = vmRef.activeGroupId.val == gid

        let disclosure = renderer.createElement("div")
        renderer.setAttribute(disclosure, "data-disclosure-id", gid)
        # M-EVP-14 round-3: collapsed groups get a tight fixed height
        # (just the triangle band + header) so the active group
        # absorbs the surrounding vertical slack and its items have
        # room to render meaningfully. Without this, all three groups
        # equally divide the parent's body height regardless of
        # expansion state, which leaves the active group's items
        # squeezed to a few pixels each.
        if not initiallyActive:
          renderer.setAttribute(disclosure, "data-fixed-height", "60")

        let triangle = renderer.createElement("span")
        renderer.setAttribute(triangle, "class", "settings-disclosure-triangle")
        # M-EVP-14 round-3: pin the disclosure triangle to a small
        # fixed band so the rest of the disclosure container's
        # vertical slice is left for the group section underneath.
        # Without this, the prior heuristic split the disclosure 50/50
        # between the triangle marker and the group, halving the
        # group's available height.
        renderer.setAttribute(triangle, "data-fixed-height", "20")
        renderer.setTextContent(triangle, (if initiallyActive: "▼" else: "▶"))
        renderer.appendChild(disclosure, triangle)

        let groupNode = groupContainerLeaf(renderer)
        renderer.setAttribute(groupNode, "data-group-id", gid)

        # Round-5: pass ``isFirst`` so the leaf can add ~8 px extra
        # vertical band above every non-first header (top-of-section
        # spacing) — the first header sits flush with the catalog's
        # top edge.
        let header = groupHeaderLeaf(renderer, g.label, g.description,
                                     isFirst = groupIdx == 0)
        renderer.setAttribute(header, "data-focusable", "true")
        renderer.setAttribute(header, "data-group-id", gid)
        renderer.addEventListener(header, "click", proc() =
          discard vmRef.setActiveGroup(gid))
        renderer.appendChild(groupNode, header)

        # The disclosure model: only the active group's items render.
        # Other groups show just their header (collapsed). This is the
        # mid-distinctness point between TUI accordion (one expanded)
        # and Freya card-stack (all expanded simultaneously).
        if initiallyActive:
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

        renderer.appendChild(disclosure, groupNode)
        renderer.appendChild(appRoot, disclosure)

        # Reactive active-disclosure binding. The disclosure's class,
        # the triangle's text, and aria-expanded all mirror
        # `vm.activeGroupId.val == gid` through a `createRenderEffect`.
        let rCaptured = renderer
        let groupItems = g.items
        let groupId = gid
        let groupContainer = groupNode
        let disclosureNode = disclosure
        let triangleNode = triangle
        createRenderEffect proc() =
          let isActive = vmRef.activeGroupId.val == groupId
          rCaptured.setAttribute(disclosureNode, "class",
            (if isActive: "settings-disclosure active"
             else: "settings-disclosure"))
          rCaptured.setTextContent(triangleNode,
            (if isActive: "▼" else: "▶"))
          # Update the fixed-height marker so the layout pass gives
          # the newly-active group the surrounding vertical slack.
          if isActive:
            rCaptured.removeAttribute(disclosureNode, "data-fixed-height")
          else:
            rCaptured.setAttribute(disclosureNode, "data-fixed-height", "60")
          if isActive:
            rCaptured.setAttribute(disclosureNode, "aria-expanded", "true")
            # When activated, render the items if they aren't already
            # in the tree. After the initial mount, all groups except
            # the initially-active one have their items missing; when
            # the user activates a previously-collapsed group, we
            # materialise the items in place.
            #
            # NB: this re-runs whenever activeGroupId changes. We use
            # the group container's childCount to decide whether items
            # are already mounted (childCount > 1 means header + at
            # least one item). The header is always present at index 0.
            if rCaptured.childCount(groupContainer) <= 1:
              for itemIdx in 0 ..< groupItems.len:
                let it = groupItems[itemIdx]
                case it.kind
                of sikToggle:
                  rCaptured.appendChild(groupContainer,
                    renderToggleItem(rCaptured, vmRef, it))
                of sikNumber:
                  rCaptured.appendChild(groupContainer,
                    renderNumberItem(rCaptured, vmRef, it))
                of sikChoice:
                  rCaptured.appendChild(groupContainer,
                    renderChoiceItem(rCaptured, vmRef, it))
          else:
            rCaptured.removeAttribute(disclosureNode, "aria-expanded")
            # Collapse: remove every child after the header (index 0).
            while rCaptured.childCount(groupContainer) > 1:
              let last = rCaptured.nthChild(groupContainer,
                                            rCaptured.childCount(groupContainer) - 1)
              rCaptured.removeChild(groupContainer, last)

    appRoot

template activateGroup*(vmRef, groupId): untyped =
  ## Activate the group with `groupId`. Re-renders flow through the
  ## reactive graph (the shell's `createRenderEffect` over
  ## `activeGroupId`); tests call this through `vm.setActiveGroup`
  ## directly.
  discard vmRef.setActiveGroup(groupId)
