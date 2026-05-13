## test_cocoa_leaves_macos_only — EX-M5 macOS-host integration test.
##
## Real-stack exercise of the new Cocoa leaves + composition root
## (`task_app/main_cocoa.nim`, `task_app/cocoa/leaves.nim`). Lives
## here, in the canonical examples repo, alongside the GPUI/Freya
## end-to-end tests so the macOS engineer (per the EX-M5 hand-off
## checklist) has a single drop-in test to run on a real macOS box.
##
## On Linux the test compiles and skips with a `check true` — the
## assertions are gated entirely with `when defined(macosx)` since the
## whole `task_app/main_cocoa.nim` composition root is macOS-only (see
## `task_app/cocoa/leaves.nim` docstring for the gating rationale).
##
## On macOS the assertions mirror EX-M3 (`test_gpui_leaves_end_to_end`)
## and EX-M4 (`test_freya_leaves_end_to_end`):
##
##   * `newTaskAppVM`        — the canonical Layer-3 ViewModel
##                              (`task_app/core/vm.nim`).
##   * `runTaskApp`          — Layer-4 Cocoa composition root
##                              (`task_app/main_cocoa.nim`).
##   * `buildTaskApp` ->
##     `renderTaskApp` (Layer-2 view template) ->
##     `appShell` / `taskInput` / `filterBar` / `taskList` /
##     `summaryBar`           — the new Layer-1 Cocoa leaves
##                              (`task_app/cocoa/leaves.nim`).
##   * `CocoaRenderer`       — the real renderer wrapping the AppKit
##                              ObjC FFI in `isonim_cocoa/renderer`.
##   * `fireEvent`           — the real `renderer.nim` testing dispatch
##                              helper.
##
## A scripted scenario adds tasks via the input + Add-button click
## handler, toggles tasks via the per-row toggle button, and switches
## the filter via the filter-bar buttons. The macOS engineer should
## extend the cross-renderer parity test in
## `test_freya_leaves_end_to_end.nim` to include a Cocoa case (gated
## `when defined(macosx)`) once this passes — see the EX-M5 status
## block's hand-off checklist.

import std/unittest

when defined(macosx):
  import std/strutils
  import isonim/core/signals
  import isonim_cocoa/renderer

  # Composition root — drags in the leaves + the Layer-2 view template.
  import task_app/main_cocoa as cocoa_app
  import ./helpers/async_drive

  suite "EX-M5: Cocoa leaves drive the canonical core through real AppKit":

    test "scripted scenario: add 3, toggle 1, filter switches stay consistent":
      ## EX-M23c follow-up: this test was failing under the old
      ## imperative `rerender(vm)` pattern because the click handler
      ## fired `rerender` synchronously, before the async
      ## `db.saveTask` chain settled — so the rendered tree never
      ## reflected the new task. With the reactive leaves
      ## (`createRenderEffect + forEachKeyed`) the rendered tree
      ## reacts to `vm.tasks.data` settling, so the test now drives
      ## the same `AsyncDriver` pattern used by the GPUI / Freya
      ## end-to-end tests (`drv.flush()` after every action).
      let drv = newAsyncDriver()
      defer: drv.shutdown()
      let vm = newTaskAppVM(drv.db)
      let root = cocoa_app.runTaskApp(vm)
      drv.flush()
      let r = CocoaRenderer()

      # ── Topology: appShell wrapper + 4 leaves (input / filter / list /
      #    summary). Mirrors the TUI/web/GPUI/Freya checks so the
      #    cross-renderer invariants stay visible on Cocoa too.
      check pointer(root) != nil
      check r.childCount(root) == 4
      check r.getAttribute(root, "class") == "task-app"
      check r.getAttribute(root, "data-app") == "task-app"

      # The first child is the input wrapper (taskInput leaf), exposing
      # the Add button handle through the leaves table.
      let s = cocoa_app.leavesFor(vm)
      check pointer(s.inputNode) != nil
      check pointer(s.addBtn) != nil
      check pointer(s.listNode) != nil
      check pointer(s.summaryNode) != nil
      check s.filterButtons.len == 3

      # ── 1. Add three tasks via the real Add-button click handler.
      vm.setInputText("buy milk")
      r.fireEvent(s.addBtn, "click"); drv.flush()
      vm.setInputText("write specs")
      r.fireEvent(s.addBtn, "click"); drv.flush()
      vm.setInputText("review pr")
      r.fireEvent(s.addBtn, "click"); drv.flush()

      check vm.tasks.val.len == 3
      check vm.activeCount == 3
      check vm.completedCount == 0
      check r.childCount(s.listNode) == 3
      let row0 = r.nthChild(s.listNode, 0)
      check pointer(row0) != nil
      check r.getAttribute(row0, "data-task-id") == "1"
      check "buy milk" in r.treeTextContent(row0)
      check "[ ]" in r.treeTextContent(row0)
      check "3 of 3 remaining" in r.treeTextContent(s.summaryNode)

      # ── 2. Toggle the first task via its per-row toggle button.
      let toggleBtn0 = r.nthChild(row0, 0)
      check pointer(toggleBtn0) != nil
      r.fireEvent(toggleBtn0, "click"); drv.flush()

      check vm.tasks.val[0].completed == true
      check vm.activeCount == 2
      check vm.completedCount == 1
      let row0After = r.nthChild(s.listNode, 0)
      check pointer(row0After) != nil
      check r.getAttribute(row0After, "class") == "completed"
      check "[x]" in r.treeTextContent(row0After)
      check "2 of 3 remaining" in r.treeTextContent(s.summaryNode)

      # ── 3. Switch filter to Active via the second filter button.
      r.fireEvent(s.filterButtons[1], "click")
      check vm.filter.val == fmActive
      check vm.visibleTasks.len == 2
      check r.childCount(s.listNode) == 2
      check r.getAttribute(s.filterButtons[0], "class") == ""
      check r.getAttribute(s.filterButtons[1], "class") == "selected"
      check r.getAttribute(s.filterButtons[2], "class") == ""
      check r.getAttribute(s.filterButtons[1], "aria-pressed") == "true"
      for i in 0 ..< r.childCount(s.listNode):
        let row = r.nthChild(s.listNode, i)
        check "[x]" notin r.treeTextContent(row)
        check "[ ]" in r.treeTextContent(row)

      # ── 4. Switch filter to Completed; only the toggled task shows.
      r.fireEvent(s.filterButtons[2], "click")
      check vm.filter.val == fmCompleted
      check vm.visibleTasks.len == 1
      check r.childCount(s.listNode) == 1
      let onlyRow = r.nthChild(s.listNode, 0)
      check "[x]" in r.treeTextContent(onlyRow)
      check "buy milk" in r.treeTextContent(onlyRow)
      check r.getAttribute(s.filterButtons[2], "class") == "selected"

      # ── 5. Empty-state placeholder for a fresh VM.
      let vm2 = newTaskAppVM(newFakeDb(seed = 99))
      let root2 = cocoa_app.runTaskApp(vm2)
      drv.flush()
      check pointer(root2) != nil
      let s2 = cocoa_app.leavesFor(vm2)
      check r.childCount(s2.listNode) == 1
      let placeholder = r.nthChild(s2.listNode, 0)
      check "(no tasks yet)" in r.treeTextContent(placeholder)

else:
  suite "EX-M5: Cocoa leaves macOS-only test (skipped on Linux)":
    test "Linux skip stub — see test_cocoa_leaves_compile.nim for the gate":
      ## On Linux the Cocoa composition root collapses to an empty
      ## `when defined(macosx)` block (`task_app/main_cocoa.nim`), so
      ## there's nothing to drive here. The cross-compile gate test
      ## (`test_cocoa_leaves_compile.nim`) validates the leaf surface
      ## from this host; the macOS engineer runs *this* test on a real
      ## AppKit box per the EX-M5 hand-off checklist in the status
      ## file.
      check true
