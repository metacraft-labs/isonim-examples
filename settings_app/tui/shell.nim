## settings_app/tui/shell.nim — Layer-3 shell for the TUI target.
##
## EX-M10. The TUI shell's composition is deliberately *different*
## from the web sidebar+pane and the GPUI grid: it is an
## **expand-collapse list of group sections**. Every `SettingsGroup`
## renders its header unconditionally; the per-item rows only render
## when the group is the active one (`vm.activeGroupId == group.id`).
## This makes the 3-layer alternation visibly distinct across
## renderers — the same shared Layer-2 components drive a vertically
## stacked accordion on TUI and a sidebar+pane on web, by virtue of
## the shell calling the per-kind item components only for the
## expanded section.
##
## Include-pattern (mirrors `task_app/core/views.nim`): this file is
## *included* — never imported — by the Layer-4 composition root
## (`settings_app/main_tui.nim`). The composition root imports the
## TUI leaves first, then includes the four shared components in
## order (toggle → number → choice → group), and finally includes
## this shell. Name resolution binds the leaf calls inside the shared
## components to the TUI leaves; the shell's per-kind dispatch
## resolves against the included item templates.
##
## The shell deliberately calls the *per-kind* component templates
## (`renderToggleItem` / `renderNumberItem` / `renderChoiceItem`)
## rather than the umbrella `renderSettingsGroup` template, because
## the shell owns the group container + header (with its own
## `data-group-id` + click handler for the accordion toggle) and
## would otherwise have to discard the inner header that
## `renderSettingsGroup` builds. Going direct keeps the rendered tree
## minimal and the shell's intent explicit.
##
## Keyboard nav contract (the shell wires it; tests drive it through
## `vm.setActiveGroup`, which is the canonical way to script the
## accordion in headless mode):
##
##   * Each group header carries `data-focusable=true` and a click
##     handler that calls `vm.setActiveGroup(group.id)`.
##   * Helper templates `expandGroup` / `collapseAll` exist so a
##     keyboard pilot reads naturally.
##
## The shell's `renderSettingsShell` template returns the root node.

template renderSettingsShell*(renderer, vmRef): untyped {.dirty.} =
  ## Build the full settings-app tree against the given renderer and
  ## ViewModel. Returns the root node. The shape is:
  ##
  ##   <div class="settings-app-tui">
  ##     <section class="settings-group" data-expanded="…">   # one per group
  ##       <header class="settings-group-header">…</header>
  ##       <div class="settings-row">…</div>                  # only when expanded
  ##       …
  ##     </section>
  ##     …
  block:
    let appRoot = renderer.createElement("div")
    renderer.setAttribute(appRoot, "class", "settings-app-tui")
    renderer.setAttribute(appRoot, "data-app", "settings-app")

    let activeId = vmRef.activeGroupId.val
    for groupIdx in 0 ..< vmRef.catalog.groups.len:
      closureScope:
        let g = vmRef.catalog.groups[groupIdx]
        let groupNode = groupContainerLeaf(renderer)
        renderer.setAttribute(groupNode, "data-group-id", g.id)
        let isExpanded = activeId == g.id
        renderer.setAttribute(groupNode, "data-expanded",
                              (if isExpanded: "true" else: "false"))

        let header = groupHeaderLeaf(renderer, g.label, g.description)
        renderer.setAttribute(header, "data-focusable", "true")
        renderer.setAttribute(header, "data-group-id", g.id)
        renderer.addEventListener(header, "click", proc(ev: TerminalEvent) =
          discard vmRef.setActiveGroup(g.id))
        renderer.appendChild(groupNode, header)

        if isExpanded:
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

        renderer.appendChild(appRoot, groupNode)

    appRoot

template expandGroup*(vmRef, groupId): untyped =
  ## Activate the group with `groupId`. Re-renders are driven by the
  ## composition root; tests call this through `vm.setActiveGroup`
  ## directly. The template exists so a keyboard pilot script reads
  ## naturally.
  discard vmRef.setActiveGroup(groupId)

template collapseAll*(vmRef): untyped =
  ## Set the active group id to an empty string so no group is
  ## expanded. Useful in the headless test for asserting the
  ## collapsed state.
  discard vmRef.setActiveGroup("")
