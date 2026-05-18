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
  ##
  ## Round-10 fix: the reviewer flagged the prior disclosure model
  ## ("only the active group's items render") as making the captured
  ## frame look broken — two of three section headers had no visible
  ## content. Switch to the Freya "card stack" layout where every
  ## group renders its full items list simultaneously, distinguished
  ## via the AppKit-flavoured disclosure-triangle chrome on each
  ## header. The active group's triangle reads ``▼`` (and its header
  ## title flips to the indigo accent), other groups read ``▶`` —
  ## this preserves the per-shell visual distinctness while making
  ## every section's contents legible in the captured PNG.
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

        let triangle = renderer.createElement("span")
        renderer.setAttribute(triangle, "class", "settings-disclosure-triangle")
        # Pin the disclosure triangle to a small fixed band so the
        # rest of the disclosure container's vertical slice is left
        # for the group section underneath.
        renderer.setAttribute(triangle, "data-fixed-height", "20")
        renderer.setTextContent(triangle, (
            if initiallyActive: "▼" else: "▶"))
        # Round-10: indigo accent on the active triangle.
        renderer.setStyle(triangle, "color",
          (if initiallyActive: "#9d9bff" else: "#a3a4ad"))
        renderer.appendChild(disclosure, triangle)

        let groupNode = groupContainerLeaf(renderer)
        renderer.setAttribute(groupNode, "data-group-id", gid)

        # Round-5: pass ``isFirst`` so the leaf can add ~8 px extra
        # vertical band above every non-first header (top-of-section
        # spacing) — the first header sits flush with the catalog's
        # top edge.
        let header = groupHeaderLeaf(renderer, g.label, g.description,
                                     isFirst = groupIdx == 0,
                                     isActive = initiallyActive)
        renderer.setAttribute(header, "data-focusable", "true")
        renderer.setAttribute(header, "data-group-id", gid)
        renderer.addEventListener(header, "click", proc() =
          discard vmRef.setActiveGroup(gid))
        renderer.appendChild(groupNode, header)

        # Round-10: render every group's items simultaneously. The
        # active-vs-inactive distinction now lives in the disclosure
        # triangle + header accent only (mirrors Freya's card stack
        # with the AppKit triangle gloss layered on top).
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
        # the triangle's text + tint, and aria-expanded all mirror
        # `vm.activeGroupId.val == gid` through a `createRenderEffect`.
        # Items stay mounted regardless of active state — the visual
        # accent is the only thing that flips.
        let rCaptured = renderer
        let groupId = gid
        let disclosureNode = disclosure
        let triangleNode = triangle
        createRenderEffect proc() =
          let isActive = vmRef.activeGroupId.val == groupId
          rCaptured.setAttribute(disclosureNode, "class",
            (if isActive: "settings-disclosure active"
              else: "settings-disclosure"))
          rCaptured.setTextContent(triangleNode,
            (if isActive: "▼" else: "▶"))
          rCaptured.setStyle(triangleNode, "color",
            (if isActive: "#9d9bff" else: "#a3a4ad"))
          if isActive:
            rCaptured.setAttribute(disclosureNode, "aria-expanded", "true")
          else:
            rCaptured.removeAttribute(disclosureNode, "aria-expanded")

    appRoot

template activateGroup*(vmRef, groupId): untyped =
  ## Activate the group with `groupId`. Re-renders flow through the
  ## reactive graph (the shell's `createRenderEffect` over
  ## `activeGroupId`); tests call this through `vm.setActiveGroup`
  ## directly.
  discard vmRef.setActiveGroup(groupId)
