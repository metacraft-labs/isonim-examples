## editor_chrome/core/views.nim — Layer-2 composable view template
## for the chrome-icons showcase.
##
## The shared view template parametrises over a *leaves* bundle so it
## can be rendered by any platform (web, TUI, ...). The function
## ``renderChromeIconsView`` is the canonical entry point — each
## per-platform composition root calls it with the platform-specific
## leaf procs and the shared ``ChromeIconsReactiveVM``.
##
## Tree shape produced::
##
##   <div class="chrome-icons" data-app="editor-chrome">
##     <div class="chrome-icons-bar" role="toolbar">
##       <button class="ci-btn ci-wrench">…wrench svg…</button>
##       <button class="ci-btn ci-bot" data-active="true">
##         …bot svg…
##         <span class="ci-status ci-status-active"></span>
##       </button>
##       …more bot buttons…
##       <button class="ci-btn ci-plus">…plus svg…</button>
##     </div>
##     <footer class="chrome-icons-legend">
##       <span class="legend-label">Lucide</span>
##       <span class="legend-license">ISC</span>
##     </footer>
##   </div>
##
## The view is *passive* — it only renders. State changes flow through
## the VM signals, and the per-platform leaves subscribe via
## ``createRenderEffect`` to keep the rendered tree in sync.
##
## The view template is intentionally renderer-agnostic — it never
## imports a Layer-1 leaf module directly. The composition root
## supplies the leaves through a strongly-typed parameter so the
## demo's behaviour is identical on every renderer.

import isonim/editor/views/icons as editor_icons

import ./vm
export vm, editor_icons.IconSet, editor_icons.iconSets,
       editor_icons.iconSetById

type
  ChromeIconsLeaves*[Renderer; Node] = object
    ## The leaf-bundle protocol the per-platform Layer-1 modules
    ## satisfy. Each field is a proc value the shared view template
    ## calls; the platform leaves wire each to its renderer-specific
    ## DOM / cell-grid / element-tree primitive.
    ##
    ## The two type parameters (``Renderer``, ``Node``) are the
    ## platform's renderer + node types — for the web target these
    ## resolve to ``MockRenderer`` + ``MockNode``; for TUI they
    ## resolve to ``TerminalRenderer`` + ``TerminalNode`` once that
    ## adapter is wired.
    createBar*: proc (r: Renderer): Node
    createButton*: proc (r: Renderer; cls, ariaLabel: string): Node
    setSvgContent*: proc (r: Renderer; node: Node; svg: string)
    setActive*: proc (r: Renderer; node: Node; isActive: bool)
    addStatusDot*: proc (r: Renderer; node: Node; kind: ChromeIconsStatusKind)
    createLegend*: proc (r: Renderer; label, license: string): Node
    appendChild*: proc (r: Renderer; parent, child: Node)
    createRoot*: proc (r: Renderer): Node

proc renderChromeIconsView*[Renderer, Node](
    r: Renderer;
    vm: ChromeIconsReactiveVM;
    leaves: ChromeIconsLeaves[Renderer, Node]): Node =
  ## Build the chrome-icons showcase tree against the given renderer
  ## and ViewModel. Returns the root node.
  ##
  ## The view captures the current state of the VM's signals at build
  ## time *and* registers callbacks for each — the platform leaves
  ## are expected to wrap their mutation paths in ``createRenderEffect``
  ## so changes to ``vm.iconSetId`` / ``vm.chatCount`` /
  ## ``vm.activeIndex`` / ``vm.showStatus`` reflect in the rendered
  ## tree without an explicit rebuild call from the caller.
  let root = leaves.createRoot(r)
  let bar = leaves.createBar(r)
  leaves.appendChild(r, root, bar)

  let setId = vm.iconSetId.val
  let chats = vm.chatCount.val
  let active = vm.activeIndex.val
  let dots = vm.showStatus.val
  let chosen = iconSetById(setId)

  # --- Wrench (leftmost) -----------------------------------------------
  let wrenchBtn = leaves.createButton(r, "ci-btn ci-wrench", "Manual")
  leaves.setSvgContent(r, wrenchBtn, chosen.wrench)
  leaves.appendChild(r, bar, wrenchBtn)

  # --- Chat (bot) buttons ----------------------------------------------
  for i in 0 ..< chats:
    let btn = leaves.createButton(r, "ci-btn ci-bot", "Chat " & $(i + 1))
    leaves.setSvgContent(r, btn, chosen.bot)
    leaves.setActive(r, btn, i == active)
    if dots:
      leaves.addStatusDot(r, btn, statusForIndex(i, chats))
    leaves.appendChild(r, bar, btn)

  # --- Plus (rightmost) ------------------------------------------------
  let plusBtn = leaves.createButton(r, "ci-btn ci-plus", "New chat")
  leaves.setSvgContent(r, plusBtn, chosen.plus)
  leaves.appendChild(r, bar, plusBtn)

  # --- Legend ----------------------------------------------------------
  let legend = leaves.createLegend(r, chosen.label, chosen.license)
  leaves.appendChild(r, root, legend)

  root
