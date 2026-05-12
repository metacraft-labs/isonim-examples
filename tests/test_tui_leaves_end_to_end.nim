## test_tui_leaves_end_to_end — EX-M2 mandatory integration test.
##
## Real-stack exercise of the migrated TUI leaves + composition root
## (`task_app/main_tui.nim`, `task_app/tui/leaves.nim`).
##
## EX-M16: the leaves bind reactively via `createRenderEffect` and
## `forEachKeyed`; VM mutations propagate through the reactive graph
## automatically — there is no per-action `rerender(vm)` call.
##
## What this exercises (no mocks):
##   * `newTaskAppVM`        — the canonical Layer-3 ViewModel.
##   * `runTaskApp`          — Layer-4 composition root.
##   * `buildTaskApp` →
##     `renderTaskApp` (Layer-2 view template) →
##     `appShell`/`taskInput`/`filterBar`/`taskList`/`summaryBar`
##                           — the migrated Layer-1 TUI leaves.
##   * `TerminalRenderer`,
##     `TerminalTestHarness`,
##     `InputWidget`,
##     `RadioButtonWidget`   — the real isonim-tui widget runtime
##                              consumed via `--path:../isonim-tui/src`.

import std/[unittest, strutils, tables]

import isonim/core/signals
import isonim_tui  # `newTerminalTestHarness`, `TerminalTestHarness`
import task_app/main_tui

suite "EX-M2: migrated TUI leaves drive the real-stack pipeline":
  test "scripted scenario: add, toggle, filter — VM and tree stay in sync":
    let vm = newTaskAppVM()
    let h = newTerminalTestHarness(60, 14)
    let root = runTaskApp(h, vm)

    # Topology mirrors the architecture spec's worked example.
    check root != nil
    check root.tag == "div"
    check root.attributes.getOrDefault("data-app") == "task-app"
    check root.children.len == 4

    # The four children are appShell's leaf bundle in the documented
    # order (input, filterBar, taskList, summaryBar). The leaf state
    # table tracks the InputWidget + RadioButton handles for the live
    # mutators.
    let s = leavesFor(vm)
    check s.inputWidget != nil
    check s.filterButtons.len == 3
    check s.listNode != nil
    check s.summaryNode != nil

    # ── 1. Drive the VM through addTask; the list grows reactively.
    vm.addTask("buy milk")
    vm.addTask("write specs")
    vm.addTask("review pr")

    check vm.totalCount == 3
    check vm.activeCount == 3
    check s.listNode.children.len == 3
    # Row text starts with the "[ ]" marker and contains the name.
    let row0 = s.listNode.children[0]
    check row0.children.len >= 1
    let row0Text = row0.children[0].text
    check "[ ]" in row0Text
    check "buy milk" in row0Text

    # Summary shows "3 of 3 remaining".
    check s.summaryNode.children.len == 1
    let summaryText = s.summaryNode.children[0].children[0].text
    check summaryText == "3 of 3 remaining"

    # ── 2. Toggle the first task → it becomes [x] and active drops by 1.
    let firstId = vm.tasks.val[0].id
    vm.toggleTask(firstId)

    check vm.activeCount == 2
    check vm.completedCount == 1
    # Find the toggled row by id (forEachKeyed may reorder by identity).
    var row0After: TerminalNode = nil
    for child in s.listNode.children:
      if child.attributes.getOrDefault("data-task-id") == $firstId:
        row0After = child
        break
    check row0After != nil
    check "[x]" in row0After.children[0].text
    let summaryText2 = s.summaryNode.children[0].children[0].text
    check summaryText2 == "2 of 3 remaining"

    # ── 3. Switch filter to Active via the VM (the reactive effect
    #       syncs the radio-button selection state).
    vm.setFilter(fmActive)

    check vm.filter.val == fmActive
    check vm.visibleTasks.len == 2
    # The "Active" radio button is button index 1; setSelected(true)
    # reflects the VM filter through to the widget state.
    check s.filterButtons[0].selected == false
    check s.filterButtons[1].selected == true
    check s.filterButtons[2].selected == false
    # Only active rows render.
    check s.listNode.children.len == 2
    for child in s.listNode.children:
      let rowText = child.children[0].text
      check "[ ]" in rowText
      check "[x]" notin rowText

    # ── 4. Filter Completed → only the [x] row.
    vm.setFilter(fmCompleted)

    check vm.filter.val == fmCompleted
    check s.listNode.children.len == 1
    check "[x]" in s.listNode.children[0].children[0].text
    check s.filterButtons[2].selected == true

    # ── 5. Empty-state placeholder for an unused filter.
    let vm2 = newTaskAppVM()
    let h2 = newTerminalTestHarness(60, 14)
    discard runTaskApp(h2, vm2)
    let s2 = leavesFor(vm2)
    check s2.listNode.children.len == 1  # placeholder row
    check "(no tasks yet)" in s2.listNode.children[0].children[0].text

    h.dispose()
    h2.dispose()
