## settings_app/web/shell.nim — Layer-3 shell for the web target.
##
## EX-M11. The web shell's composition is deliberately *different* from
## the TUI accordion: a **sidebar + content pane** layout — the classic
## desktop-web settings pattern. The sidebar (`<nav>`) holds one entry
## per group; clicking an entry calls `vm.setActiveGroup(group.id)`. The
## content pane (`<section>`) renders the *active* group's header +
## items via the shared Layer-2 components. The non-active groups are
## *not* rendered into the pane — they show up only as nav entries.
##
## This makes the 3-layer alternation visibly distinct across renderers:
## the same shared Layer-2 components drive an accordion on TUI, a
## sidebar+pane on web, and (in EX-M12) a grid on GPUI, by virtue of the
## per-platform Layer-3 shell composing the components into a different
## skeleton.
##
## Include-pattern (mirrors `task_app/core/views.nim` + the TUI shell):
## this file is *included* — never imported — by the Layer-4
## composition root (`settings_app/main_web.nim`). The composition root
## imports the web leaves first, then includes the four shared
## components in order (toggle → number → choice → group), and finally
## includes this shell. Name resolution binds the leaf calls inside the
## shared components to the web leaves; the shell's per-kind dispatch
## resolves against the included item templates.
##
## Tree shape::
##
##   <div class="settings-app-web" data-app="settings-app">
##     <nav class="settings-sidebar">
##       <h1 class="settings-sidebar-title">Settings</h1>
##       <ul class="settings-group-list">
##         <li class="(active|)" data-group-id="appearance">
##           <button data-group-id="appearance">Appearance</button>
##         </li>
##         ...
##       </ul>
##     </nav>
##     <section class="settings-pane">
##       <section class="settings-group">    # active group only
##         <header class="settings-group-header">…</header>
##         <div class="settings-item">…</div>  # one per item
##         …
##       </section>
##     </section>
##   </div>
##
## The shell deliberately calls the *per-kind* component templates
## (`renderToggleItem` / `renderNumberItem` / `renderChoiceItem`)
## rather than the umbrella `renderSettingsGroup` template, because the
## shell owns the group container + header in the pane (the sidebar's
## nav entries are separate from the pane's header), and would
## otherwise have to discard the wrapper that `renderSettingsGroup`
## builds.

template renderSettingsShell*(renderer, vmRef): untyped {.dirty.} =
  ## Build the full settings-app tree against the given renderer and
  ## ViewModel. Returns the root node.
  block:
    let appRoot = renderer.createElement("div")
    renderer.setAttribute(appRoot, "class", "settings-app-web")
    renderer.setAttribute(appRoot, "data-app", "settings-app")

    # ---- Sidebar: nav with one entry per group ----------------------
    let sidebar = renderer.createElement("nav")
    renderer.setAttribute(sidebar, "class", "settings-sidebar")

    let sidebarTitle = renderer.createElement("h1")
    renderer.setAttribute(sidebarTitle, "class", "settings-sidebar-title")
    renderer.appendChild(sidebarTitle,
                         renderer.createTextNode("Settings"))
    renderer.appendChild(sidebar, sidebarTitle)

    let groupList = renderer.createElement("ul")
    renderer.setAttribute(groupList, "class", "settings-group-list")

    let activeId = vmRef.activeGroupId.val
    for groupIdx in 0 ..< vmRef.catalog.groups.len:
      closureScope:
        let g = vmRef.catalog.groups[groupIdx]
        let groupLi = renderer.createElement("li")
        renderer.setAttribute(groupLi, "class",
          (if activeId == g.id: "active" else: ""))
        renderer.setAttribute(groupLi, "data-group-id", g.id)

        let groupBtn = renderer.createElement("button")
        renderer.setAttribute(groupBtn, "class", "settings-group-button")
        renderer.setAttribute(groupBtn, "data-group-id", g.id)
        renderer.setAttribute(groupBtn, "type", "button")
        if activeId == g.id:
          renderer.setAttribute(groupBtn, "aria-pressed", "true")
        renderer.appendChild(groupBtn,
                             renderer.createTextNode(g.label))
        # Closure factories live inline; `closureScope` gives each
        # iteration a fresh `g` so the captured group id is correct.
        let gid = g.id
        renderer.addEventListener(groupBtn, "click", proc() =
          discard vmRef.setActiveGroup(gid))
        renderer.appendChild(groupLi, groupBtn)
        renderer.appendChild(groupList, groupLi)

    renderer.appendChild(sidebar, groupList)
    renderer.appendChild(appRoot, sidebar)

    # ---- Content pane: only the active group's items ----------------
    let pane = renderer.createElement("section")
    renderer.setAttribute(pane, "class", "settings-pane")

    if vmRef.catalog.hasGroup(activeId):
      let activeGroup = vmRef.currentGroup
      let paneGroupNode = groupContainerLeaf(renderer)
      renderer.setAttribute(paneGroupNode, "data-group-id", activeGroup.id)
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
      renderer.appendChild(pane, paneGroupNode)

    renderer.appendChild(appRoot, pane)

    appRoot

template selectGroup*(vmRef, groupId): untyped =
  ## Activate the group with `groupId`. Re-renders are driven by the
  ## composition root; tests call this through `vm.setActiveGroup`
  ## directly. The template exists so a sidebar pilot script reads
  ## naturally.
  discard vmRef.setActiveGroup(groupId)
