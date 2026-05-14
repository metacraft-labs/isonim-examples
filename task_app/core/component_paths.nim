## task_app/core/component_paths.nim — canonical ``componentPath``
## taxonomy for the task-app demo.
##
## RS-M11b / EX-M23b: the TUI, GPUI, and Freya leaves each annotate
## their user-visible nodes with ``data-component-path``. The strings
## MUST be set-identical across the three renderers — the cross-
## renderer parity test
## (``isonim-examples/tests/test_cross_renderer_component_paths.nim``)
## decodes the live manifests from all three launcher binaries and
## asserts the set of paths matches.
##
## Lifting the strings into this single module makes the parity
## invariant statically enforceable at compile time: a leaf that
## referenced an undefined identifier fails ``nim c``, not the
## subprocess test. The constants here are the single source of
## truth; no Layer-1 leaf may invent a new component-path literal.
##
## The string values mirror what the EX-M23 TUI leaves originally
## embedded; this is a refactor, not a behaviour change.

const
  TaskAppPath* = "task_app/views/TaskApp"
    ## App shell root. One entry per demo.

  TaskInputPath* = "task_app/views/TaskInput"
    ## Single-line "add task" text field. One entry per demo.

  FilterBarPath* = "task_app/views/FilterBar"
    ## All / Active / Completed filter selector. One entry per demo.

  TaskListPath* = "task_app/views/TaskList"
    ## Container for the visible task rows. One entry per demo.

  TaskRowPathPrefix* = "task_app/views/TaskRow"
    ## Prefix; the per-row path appends ``#<id>`` (e.g.
    ## ``task_app/views/TaskRow#7``). The hash-suffix discipline
    ## (``^[a-zA-Z0-9_./-]+(#[0-9]+)?$``) is locked by RS-M11.

  SummaryBarPath* = "task_app/views/SummaryBar"
    ## "N of M remaining" footer. One entry per demo.

  TaskCheckIconPath* = "task_app/views/TaskCheckIcon"
    ## M-EVP-11: minimal vector-symbol leaf nested inside the summary
    ## bar. Annotated with ``ElementKindAttr = "vector-symbol"`` so the
    ## editor's canvas dblclick handler can resolve the click back to
    ## the ``skVectorSymbol`` story in the demo catalog and call
    ## ``openVectorEditor``. Every renderer (TUI / GPUI / Freya /
    ## Cocoa / Android) emits this entry; the cross-renderer parity
    ## test enforces set-equality of the
    ## ``(componentPath, kind="vector-symbol")`` pairs.

  TaskCheckIconStoryName* = "Task Check Icon"
    ## Sidebar story name for the seeded skVectorSymbol catalog entry
    ## that pairs with ``TaskCheckIconPath``. The editor's
    ## ``findStoryByComponentPath`` lookup maps the manifest's
    ## componentPath suffix to this story.

proc taskRowPath*(id: int): string {.inline.} =
  ## Build the per-row path for a task with id ``id``. Centralising
  ## the formatting keeps every renderer's ``#<id>`` suffix in lock-
  ## step.
  TaskRowPathPrefix & "#" & $id
