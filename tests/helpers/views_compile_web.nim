## helpers/views_compile_web.nim — minimal web leaf stubs that let
## the canonical `task_app/core/views.nim` compile against
## `MockRenderer` (the canonical headless surface for web tests; the
## browser `WebRenderer` exposes the same proc shape).
##
## EX-M1 compile-check helper. The real production leaves live in
## `isonim-tui/examples/task_app/web/leaves.nim` today and migrate
## into `isonim-examples/task_app/web/leaves.nim` in EX-M2; until
## then this stub set proves the include-pattern in `views.nim`
## resolves correctly against the web surface.

import isonim/testing/mock_dom

import ../../task_app/core/vm
export vm

proc appShell*(r: MockRenderer; vm: TaskAppVM): MockNode =
  discard vm
  r.createElement("div")

proc taskInput*(r: MockRenderer; vm: TaskAppVM): MockNode =
  discard vm
  r.createElement("input")

proc filterBar*(r: MockRenderer; vm: TaskAppVM): MockNode =
  discard vm
  r.createElement("nav")

proc taskList*(r: MockRenderer; vm: TaskAppVM): MockNode =
  discard vm
  r.createElement("ul")

proc summaryBar*(r: MockRenderer; vm: TaskAppVM): MockNode =
  discard vm
  r.createElement("footer")

include task_app/core/views

proc buildApp*(vm: TaskAppVM): MockNode =
  ## Build the cross-platform task-app tree against `MockRenderer`.
  ## A browser deploy swaps in `WebRenderer`; the leaf-and-view code
  ## is unchanged.
  let r = MockRenderer()
  renderTaskApp(r, vm)
