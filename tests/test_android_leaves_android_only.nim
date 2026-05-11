## test_android_leaves_android_only — EX-M6 emulator-host integration
## test.
##
## Real-stack exercise of the new Android leaves + composition root
## (`task_app/main_android.nim`, `task_app/android/leaves.nim`). Lives
## here, in the canonical examples repo, alongside the GPUI/Freya/Cocoa
## end-to-end tests so the macOS engineer (per the EX-M6 hand-off
## checklist) has a single drop-in test to run on a real Android
## emulator.
##
## On Linux the test compiles and skips with a `check true` — the
## assertions are gated entirely with `when defined(android)` since the
## whole `task_app/main_android.nim` composition root is Android-only
## (see `task_app/android/leaves.nim` docstring for the gating
## rationale).
##
## On Android the assertions mirror EX-M3 (`test_gpui_leaves_end_to_end`),
## EX-M4 (`test_freya_leaves_end_to_end`), and EX-M5
## (`test_cocoa_leaves_macos_only`):
##
##   * `newTaskAppVM`        — the canonical Layer-3 ViewModel
##                              (`task_app/core/vm.nim`).
##   * `runTaskApp`          — Layer-4 Android composition root
##                              (`task_app/main_android.nim`).
##   * `buildTaskApp` ->
##     `renderTaskApp` (Layer-2 view template) ->
##     `appShell` / `taskInput` / `filterBar` / `taskList` /
##     `summaryBar`           — the new Layer-1 Android leaves
##                              (`task_app/android/leaves.nim`).
##   * `AndroidRenderer`     — the real renderer wrapping the JNI
##                              bridge in `isonim_android/renderer`.
##                              Uses the MockJNI shim (`-d:mockJni`)
##                              for host-side runs and the real JNI
##                              bridge (`-d:commandBuffer`) for the
##                              emulator path.
##   * `fireEvent`           — the real `renderer.nim` testing dispatch
##                              helper.
##
## A scripted scenario adds tasks via the input + Add-button click
## handler, toggles tasks via the per-row toggle button, and switches
## the filter via the filter-bar buttons. The macOS engineer should
## extend the cross-renderer parity test in
## `test_freya_leaves_end_to_end.nim` to include an Android case (gated
## `when defined(android)`) once this passes — see the EX-M6 status
## block's hand-off checklist.

import std/unittest

when defined(android):
  import std/strutils
  import isonim/core/signals
  import isonim_android/renderer

  # Composition root — drags in the leaves + the Layer-2 view template.
  import task_app/main_android as android_app

  suite "EX-M6: Android leaves drive the canonical core through real JNI":

    test "scripted scenario: add 3, toggle 1, filter switches stay consistent":
      let vm = newTaskAppVM()
      let root = android_app.runTaskApp(vm)
      let r = AndroidRenderer()

      # ── Topology: appShell wrapper + 4 leaves (input / filter / list /
      #    summary). Mirrors the TUI/web/GPUI/Freya/Cocoa checks so the
      #    cross-renderer invariants stay visible on Android too.
      check root != 0
      check r.childCount(root) == 4
      check r.getAttribute(root, "class") == "task-app"
      check r.getAttribute(root, "data-app") == "task-app"

      # The first child is the input wrapper (taskInput leaf), exposing
      # the Add button handle through the leaves table.
      let s = android_app.leavesFor(vm)
      check s.inputNode != 0
      check s.addBtn != 0
      check s.listNode != 0
      check s.summaryNode != 0
      check s.filterButtons.len == 3

      # ── 1. Add three tasks via the real Add-button click handler.
      vm.setInputText("buy milk")
      r.fireEvent(s.addBtn, "click")
      vm.setInputText("write specs")
      r.fireEvent(s.addBtn, "click")
      vm.setInputText("review pr")
      r.fireEvent(s.addBtn, "click")

      check vm.tasks.val.len == 3
      check vm.activeCount == 3
      check vm.completedCount == 0
      check r.childCount(s.listNode) == 3
      let row0 = r.nthChild(s.listNode, 0)
      check row0 != 0
      check r.getAttribute(row0, "data-task-id") == "1"
      check "buy milk" in r.treeTextContent(row0)
      check "[ ]" in r.treeTextContent(row0)
      check "3 of 3 remaining" in r.treeTextContent(s.summaryNode)

      # ── 2. Toggle the first task via its per-row toggle button.
      let toggleBtn0 = r.nthChild(row0, 0)
      check toggleBtn0 != 0
      r.fireEvent(toggleBtn0, "click")

      check vm.tasks.val[0].completed == true
      check vm.activeCount == 2
      check vm.completedCount == 1
      let row0After = r.nthChild(s.listNode, 0)
      check row0After != 0
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
      let vm2 = newTaskAppVM()
      let root2 = android_app.runTaskApp(vm2)
      check root2 != 0
      let s2 = android_app.leavesFor(vm2)
      check r.childCount(s2.listNode) == 1
      let placeholder = r.nthChild(s2.listNode, 0)
      check "(no tasks yet)" in r.treeTextContent(placeholder)

else:
  suite "EX-M6: Android leaves android-only test (skipped on Linux)":
    test "Linux skip stub — see test_android_leaves_compile.nim for the gate":
      ## On Linux the Android composition root collapses to an empty
      ## `when defined(android)` block (`task_app/main_android.nim`),
      ## so there's nothing to drive here. The cross-compile gate test
      ## (`test_android_leaves_compile.nim`) validates the leaf
      ## surface from this host; the macOS engineer runs *this* test
      ## on a real Android emulator (Apple Silicon) per the EX-M6
      ## hand-off checklist in the status file.
      check true
