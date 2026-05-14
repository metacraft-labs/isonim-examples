## task_app/core/story_ids.nim — canonical storyId taxonomy for the
## task-app demo.
##
## RS-M12. The editor sends ``select-story`` I packets carrying the
## composite identifier ``"<group> / <name>"`` (see
## ``isonim/src/isonim/editor/views/canvas_mount.nim`` for the
## sender; ``editor/stories.nim`` for the source group / name
## strings). Each launcher imports this module and dispatches on the
## constants here so an editor-side typo can't silently fall back to
## "wrong story rendered" — the launcher's case-on-storyId will hit
## its default branch and log a warning.
##
## The constants below mirror EXACTLY what
## ``isonim-examples/editor/stories.nim`` emits as
## ``item.group & " / " & item.name`` for every task_app story.
##
## Spec: RS-M12 § *Scope* —
## ``codetracer-specs/Front-Ends/IsoNim/isonim-render-stream.status.org``.

const
  # ---- Pages ----
  TaskAppPagesInbox* = "Task App / Pages / Inbox"
  TaskAppPagesToday* = "Task App / Pages / Today"
  TaskAppPagesCompleted* = "Task App / Pages / Completed"

  # ---- Components: TaskInput ----
  TaskAppTaskInputEmpty* = "Task App / TaskInput / Empty"
  TaskAppTaskInputWithDraft* = "Task App / TaskInput / With Draft"

  # ---- Components: FilterBar ----
  TaskAppFilterBarAllSelected* = "Task App / FilterBar / All Selected"
  TaskAppFilterBarActiveSelected* = "Task App / FilterBar / Active Selected"
  TaskAppFilterBarCompletedSelected* =
    "Task App / FilterBar / Completed Selected"

  # ---- Components: TaskList ----
  TaskAppTaskListEmpty* = "Task App / TaskList / Empty"
  TaskAppTaskListTwoActive* = "Task App / TaskList / Two Active"
  TaskAppTaskListMixedCompletion* = "Task App / TaskList / Mixed Completion"

  # ---- Components: SummaryBar ----
  TaskAppSummaryBarActiveOnly* = "Task App / SummaryBar / Active Only"
  TaskAppSummaryBarWithCompleted* = "Task App / SummaryBar / With Completed"

  # ---- Foundations ----
  TaskAppFoundationsSpacing* = "Task App / Foundations / Spacing"
  TaskAppFoundationsTypography* = "Task App / Foundations / Typography"

  # ---- Vector Symbols (out-of-scope for launcher mount — routed to
  # the vector editor, not a launcher canvas — but listed for
  # taxonomy completeness so future renderer specialisations can
  # reference them by const.) ----
  TaskAppVectorSymbolsTaskCheckIcon* =
    "Task App / Vector Symbols / Task Check Icon"
  TaskAppVectorSymbolsTaskFilterIcon* =
    "Task App / Vector Symbols / Task Filter Icon"
  TaskAppVectorSymbolsTaskSortIcon* =
    "Task App / Vector Symbols / Task Sort Icon"
  TaskAppVectorSymbolsEmptyGlyph* =
    "Task App / Vector Symbols / Empty Glyph"

  # ---- Flows (storyboard-level steps; per-launcher mount falls back
  # to the default Inbox page since flows are recorded scripts of
  # actions, not single-frame renders.) ----
  TaskAppFlowTypesTaskName* = "Add Task Flow / Types a task name"
  TaskAppFlowPressesEnter* = "Add Task Flow / Presses Enter to add"
  TaskAppFlowTogglesComplete* = "Add Task Flow / Toggles the task complete"
  TaskAppFlowClearsCompleted* = "Add Task Flow / Clears completed tasks"
