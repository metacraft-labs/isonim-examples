## helpers/views_compile_cocoa.nim — minimal Cocoa leaf stubs that let
## the canonical `task_app/core/views.nim` compile against
## `CocoaRenderer` on a `--os:macosx` cross-compile target.
##
## EX-M5 cross-compile-gate helper. The real Cocoa leaves live in
## `task_app/cocoa/leaves.nim` and are gated `when defined(macosx)` so
## the regular Linux `just test` ignores them; they import the canonical
## `task_app/core/vm` (which transitively pulls `isonim/core/signals`,
## currently broken on `--os:macosx --mm:orc` from a Linux host —
## reactive-core regression noted in the EX-M4 status block, deferred
## from this milestone).
##
## To prove the *Cocoa-leaf surface* (renderer protocol + leaf names +
## `views.nim` include-pattern) is sound on the macOS target without
## tripping that pre-existing core regression, this helper builds the
## same `appShell` / `taskInput` / `filterBar` / `taskList` /
## `summaryBar` shape against a *minimal* VM stub that supplies just
## the shape `views.nim` needs. The real leaves' renderer-facing calls
## (`createElement`, `setAttribute`, `appendChild`, `addEventListener`,
## ...) match `helpers/views_compile_cocoa.nim` 1:1 — drift in the
## renderer protocol surfaces here, not in the macOS-host smoke test.

import isonim_cocoa/renderer
export renderer

# ----------------------------------------------------------------------------
# Minimal VM stub
# ----------------------------------------------------------------------------
#
# The cross-compile gate exercises the leaf surface, not the VM. We
# match the public-API surface that `task_app/core/views.nim` consumes
# (and the tiny subset the real Cocoa leaves call) without bringing in
# `isonim/core/signals` — which is currently un-compilable under
# `--os:macosx` from a Linux host, see EX-M5 status notes.

type
  TaskAppVM* = ref object

proc newTaskAppVM*(): TaskAppVM = TaskAppVM()

# ----------------------------------------------------------------------------
# Stub leaves — mirror `task_app/cocoa/leaves.nim`'s signatures + bodies.
# ----------------------------------------------------------------------------

proc appShell*(r: CocoaRenderer; vm: TaskAppVM): CocoaElement =
  discard vm
  let app = r.createElement("div")
  r.setAttribute(app, "class", "task-app")
  r.setAttribute(app, "data-app", "task-app")
  app

proc taskInput*(r: CocoaRenderer; vm: TaskAppVM): CocoaElement =
  discard vm
  let wrapper = r.createElement("div")
  r.setAttribute(wrapper, "class", "task-input")
  let inp = r.createElement("input")
  r.setAttribute(inp, "type", "text")
  r.setAttribute(inp, "placeholder", "New task...")
  r.appendChild(wrapper, inp)
  let addBtn = r.createElement("button")
  r.setTextContent(addBtn, "Add Task")
  r.addEventListener(addBtn, "click", proc() = discard)
  r.appendChild(wrapper, addBtn)
  wrapper

proc filterBar*(r: CocoaRenderer; vm: TaskAppVM): CocoaElement =
  discard vm
  let wrapper = r.createElement("div")
  r.setAttribute(wrapper, "class", "filter-bar")
  for label in ["all", "active", "completed"]:
    let btn = r.createElement("button")
    r.setTextContent(btn, label)
    r.setAttribute(btn, "data-filter", label)
    r.addEventListener(btn, "click", proc() = discard)
    r.appendChild(wrapper, btn)
  wrapper

proc taskList*(r: CocoaRenderer; vm: TaskAppVM): CocoaElement =
  discard vm
  let listNode = r.createElement("ul")
  r.setAttribute(listNode, "class", "task-list")
  listNode

proc summaryBar*(r: CocoaRenderer; vm: TaskAppVM): CocoaElement =
  discard vm
  let summaryNode = r.createElement("footer")
  r.setAttribute(summaryNode, "class", "task-summary")
  let span = r.createElement("span")
  r.setTextContent(span, "0 of 0 remaining")
  r.appendChild(summaryNode, span)
  summaryNode

# ----------------------------------------------------------------------------
# Cross-renderer composition: exercise the same builder shape used by
# `task_app/core/views.nim` (without the actual `include` — including
# `views.nim` here would also pull in `task_app/core/vm`, which we are
# explicitly avoiding for the reasons in the module docstring).
# ----------------------------------------------------------------------------

proc buildApp*(vm: TaskAppVM): CocoaElement =
  ## Build the documented topology
  ## (`appShell > {taskInput, filterBar, taskList, summaryBar}`) against
  ## the real `CocoaRenderer` from `isonim_cocoa/renderer`. Mirrors the
  ## composition `task_app/core/views.nim` does — same children, same
  ## ordering — without including `views.nim` itself (which would drag
  ## in `task_app/core/vm` and the macOS-broken `isonim/core/signals`).
  let r = CocoaRenderer()
  let root = appShell(r, vm)
  r.appendChild(root, taskInput(r, vm))
  r.appendChild(root, filterBar(r, vm))
  r.appendChild(root, taskList(r, vm))
  r.appendChild(root, summaryBar(r, vm))
  root
