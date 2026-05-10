## helpers/views_compile_tui.nim — minimal TUI leaf stubs that let
## the canonical `task_app/core/views.nim` compile against
## `TerminalRenderer`.
##
## EX-M1 compile-check helper. The real production leaves live in
## `isonim-tui/examples/task_app/tui/leaves.nim` today and migrate
## into `isonim-examples/task_app/tui/leaves.nim` in EX-M2; until
## then this stub set proves the include-pattern in `views.nim`
## resolves correctly against the TUI surface.

import isonim_tui/renderer

import ../../task_app/core/vm
export vm

proc appShell*(r: TerminalRenderer; vm: TaskAppVM): TerminalNode =
  discard vm
  r.createElement("div")

proc taskInput*(r: TerminalRenderer; vm: TaskAppVM): TerminalNode =
  discard vm
  r.createElement("input")

proc filterBar*(r: TerminalRenderer; vm: TaskAppVM): TerminalNode =
  discard vm
  r.createElement("nav")

proc taskList*(r: TerminalRenderer; vm: TaskAppVM): TerminalNode =
  discard vm
  r.createElement("ul")

proc summaryBar*(r: TerminalRenderer; vm: TaskAppVM): TerminalNode =
  discard vm
  r.createElement("footer")

include task_app/core/views

proc buildApp*(vm: TaskAppVM): TerminalNode =
  ## Build the cross-platform task-app tree against `TerminalRenderer`.
  ## The production composition root in `isonim-tui` does the same
  ## (modulo using the production leaves instead of these stubs).
  let r = TerminalRenderer()
  renderTaskApp(r, vm)
