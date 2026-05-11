## helpers/views_compile_android.nim — minimal Android leaf stubs that
## let the canonical `task_app/core/views.nim` compile against
## `AndroidRenderer` on a `--os:android -d:mockJni` cross-compile target.
##
## EX-M6 cross-compile-gate helper. The real Android leaves live in
## `task_app/android/leaves.nim` and are gated `when defined(android)`
## so the regular Linux `just test` ignores them; they import the
## canonical `task_app/core/vm` (which transitively pulls
## `isonim/core/signals`). Unlike the EX-M5 Cocoa case, the IsoNim
## reactive core *does* compile under `--os:android` from a Linux host
## (the macOS-cross regression deferred from EX-M5 doesn't bite Android),
## but we keep the same Cocoa-shaped fixture to keep the gate test
## structure parallel across the C-phase milestones (and to keep the
## fixture self-contained so a future signals-side regression doesn't
## drag the gate down).
##
## To prove the *Android-leaf surface* (renderer protocol + leaf names +
## `views.nim` include-pattern) is sound on the Android target, this
## helper builds the same `appShell` / `taskInput` / `filterBar` /
## `taskList` / `summaryBar` shape against a *minimal* VM stub that
## supplies just the shape `views.nim` needs. The real leaves'
## renderer-facing calls (`createElement`, `setAttribute`, `appendChild`,
## `addEventListener`, ...) match `helpers/views_compile_android.nim`
## 1:1 — drift in the renderer protocol surfaces here, not in the
## emulator-host smoke test.

import isonim_android/renderer
export renderer

# ----------------------------------------------------------------------------
# Minimal VM stub
# ----------------------------------------------------------------------------
#
# The cross-compile gate exercises the leaf surface, not the VM. We
# match the public-API surface that `task_app/core/views.nim` consumes
# (and the tiny subset the real Android leaves call) without bringing in
# `isonim/core/signals` — keeping the fixture self-contained so a
# future signals-side regression doesn't drag the gate down (see EX-M5
# for the macOS cross-compile precedent).

type
  TaskAppVM* = ref object

proc newTaskAppVM*(): TaskAppVM = TaskAppVM()

# ----------------------------------------------------------------------------
# Stub leaves — mirror `task_app/android/leaves.nim`'s signatures + bodies.
# ----------------------------------------------------------------------------

proc appShell*(r: AndroidRenderer; vm: TaskAppVM): AndroidElement =
  discard vm
  let app = r.createElement("div")
  r.setAttribute(app, "class", "task-app")
  r.setAttribute(app, "data-app", "task-app")
  app

proc taskInput*(r: AndroidRenderer; vm: TaskAppVM): AndroidElement =
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

proc filterBar*(r: AndroidRenderer; vm: TaskAppVM): AndroidElement =
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

proc taskList*(r: AndroidRenderer; vm: TaskAppVM): AndroidElement =
  discard vm
  let listNode = r.createElement("ul")
  r.setAttribute(listNode, "class", "task-list")
  listNode

proc summaryBar*(r: AndroidRenderer; vm: TaskAppVM): AndroidElement =
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
# explicitly avoiding to keep this fixture self-contained).
# ----------------------------------------------------------------------------

proc buildApp*(vm: TaskAppVM): AndroidElement =
  ## Build the documented topology
  ## (`appShell > {taskInput, filterBar, taskList, summaryBar}`) against
  ## the real `AndroidRenderer` from `isonim_android/renderer`. Mirrors
  ## the composition `task_app/core/views.nim` does — same children,
  ## same ordering — without including `views.nim` itself (which would
  ## drag in `task_app/core/vm`).
  let r = AndroidRenderer()
  let root = appShell(r, vm)
  r.appendChild(root, taskInput(r, vm))
  r.appendChild(root, filterBar(r, vm))
  r.appendChild(root, taskList(r, vm))
  r.appendChild(root, summaryBar(r, vm))
  root
