## settings_app/freya/shell.nim — Layer-3 shell for the Freya target.
##
## EX-M15. The Freya shell's composition is deliberately *different*
## from the TUI accordion, the web sidebar+pane, and the GPUI two-column
## grid: a **vertically stacked card layout** where every settings group
## renders as its own Freya card, each card showing its header AND all
## its items simultaneously. The active group's card carries an
## ``active`` class for visual emphasis (e.g. accent border, raised
## shadow); the chrome around each card (the ``settings-card`` wrapper)
## gives the layout a distinctly "Material/Freya card stack" feel that
## the three other shells do not share.
##
## EX-M16: each card is built once at mount time with all of its items
## already rendered. The card's ``active`` class + ``aria-pressed``
## flow through ``createRenderEffect`` over ``vm.activeGroupId.val``;
## clicking the card's header (or calling ``vm.setActiveGroup`` directly
## from a test) updates the visible state without an explicit rebuild
## call from the composition root.
##
## Visible composition differences:
##   * TUI (EX-M10) — single vertical column; group headers always
##     visible; only the active group's items render below its header
##     (accordion: one expanded section at a time).
##   * web (EX-M11) — ``<nav class="settings-sidebar">`` plus
##     ``<section class="settings-pane">``; only the active group's
##     items render in the pane.
##   * GPUI (EX-M12) — flat 2-column grid; left column lists groups,
##     right column shows only the active group's items.
##   * Freya (this shell) — every group renders as a self-contained
##     ``<div class="settings-card">`` stacked vertically; ALL groups'
##     items are rendered simultaneously inside their respective cards.
##     The "all expanded at once" property is the key distinctness
##     against TUI/web/GPUI, each of which only renders the active
##     group's items.
##
## Tree shape::
##
##   <div class="settings-app-freya" data-app="settings-app"
##        data-layout="card-stack">
##     <div class="settings-card (active|)" data-card-id="appearance">
##       <section class="settings-group" data-group-id="appearance">
##         <header class="settings-group-header">…</header>
##         <div class="settings-item">…</div>  # one per item
##         …
##       </section>
##     </div>
##     <div class="settings-card" data-card-id="editor">
##       <section class="settings-group" data-group-id="editor">…</section>
##     </div>
##     <div class="settings-card" data-card-id="notifications">…</div>
##   </div>
##
## The shell deliberately calls the *per-kind* component templates
## (``renderToggleItem`` / ``renderNumberItem`` / ``renderChoiceItem``)
## rather than the umbrella ``renderSettingsGroup`` template, because
## the shell owns the per-card chrome and the group's container/header
## (the card wraps the section + adds click-to-activate behaviour on
## the header); going direct keeps the rendered tree minimal and the
## shell's intent explicit. This matches the pattern used by the TUI /
## web / GPUI shells.
##
## Include-pattern (mirrors `task_app/core/views.nim` + the TUI/web/GPUI
## shells): this file is *included* — never imported — by the Layer-4
## composition root (`settings_app/main_freya.nim`).

template renderSettingsShell*(renderer, vmRef): untyped {.dirty.} =
  ## Build the full settings-app tree against the given renderer and
  ## ViewModel. Returns the root node.
  block:
    let appRoot = renderer.createElement("div")
    renderer.setAttribute(appRoot, "class", "settings-app-freya")
    renderer.setAttribute(appRoot, "data-app", "settings-app")
    renderer.setAttribute(appRoot, "data-layout", "card-stack")

    for groupIdx in 0 ..< vmRef.catalog.groups.len:
      closureScope:
        let g = vmRef.catalog.groups[groupIdx]
        let gid = g.id
        # Outer card wrapper: a `<div class="settings-card">` with an
        # `active` modifier when this is the active group. The card is
        # the Freya-specific chrome layer; the inner `<section>` is the
        # shared group container leaf so cross-renderer parity probes
        # still see `class="settings-group"` + `data-group-id` at the
        # documented depth.
        let card = renderer.createElement("div")
        renderer.setAttribute(card, "data-card-id", gid)

        let groupNode = groupContainerLeaf(renderer)
        renderer.setAttribute(groupNode, "data-group-id", gid)

        let header = groupHeaderLeaf(renderer, g.label, g.description)
        renderer.setAttribute(header, "data-focusable", "true")
        renderer.setAttribute(header, "data-group-id", gid)
        renderer.addEventListener(header, "click", proc() =
          discard vmRef.setActiveGroup(gid))
        renderer.appendChild(groupNode, header)

        # Every card shows ALL its items, regardless of which group is
        # active. This is the visibly distinct property versus TUI/web/
        # GPUI, where only the active group's items render. The same
        # SettingsVM drives the data; only the shell's chrome differs.
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

        renderer.appendChild(card, groupNode)
        renderer.appendChild(appRoot, card)

        # Reactive active-card binding. The card's class + aria-pressed
        # mirror `vm.activeGroupId.val == gid` through a
        # `createRenderEffect`.
        createRenderEffect proc() =
          let isActive = vmRef.activeGroupId.val == gid
          renderer.setAttribute(card, "class",
            (if isActive: "settings-card active"
             else: "settings-card"))
          if isActive:
            renderer.setAttribute(card, "aria-pressed", "true")
          else:
            renderer.removeAttribute(card, "aria-pressed")

    appRoot

template activateGroup*(vmRef, groupId): untyped =
  ## Activate the group with `groupId`. Re-renders flow through the
  ## reactive graph (the shell's `createRenderEffect` over
  ## `activeGroupId`); tests call this through `vm.setActiveGroup`
  ## directly. The template exists so a click-driver pilot script
  ## reads naturally.
  discard vmRef.setActiveGroup(groupId)
