## NH-M1 — the EX-M14 launchers' reactive mount entry, and the "no behaviour
## change for non-HMR callers" deliverable, measured against the REAL demo
## composition root.
##
## MOCK POLICY: no mocks. This drives `task_app/main_tui`'s real
## `buildTaskApp` against the real `TerminalTestHarness` (real renderer, real
## compositor, real headless driver) and the real `TaskAppVM`. Nothing is
## stubbed. The only thing this file does that the launcher does not is skip
## the WebSocket bridge, which is not on the path under test.
##
## WHY THIS FILE EXISTS. The three EX-M14 launchers now mount through
## `renderTui` / `renderGpui` / `renderFreya` rather than building the tree
## imperatively. Routing the root build through a render effect is only safe
## if the accessor does not TRACK the signals the composition root reads while
## constructing itself — otherwise every VM mutation rebuilds and re-mounts
## the whole tree, and the root handle that the frame source, the
## element-tree provider and the hit-tester all captured goes stale.
##
## That is not a hypothetical. MEASURED against this exact composition root:
##
##   tracked accessor   → mount 1, setInputText 2, addTask 2, setFilter 3
##   untracked accessor → mount 1, setInputText 1, addTask 1, setFilter 1
##
## Both arms are asserted below, so the tracked arm is a live falsifier rather
## than a number in a comment: if `staticNativeRoot` ever stopped untracking,
## the second case goes red, and if the composition root ever stopped reading
## signals at build time the first case goes red and this file's premise needs
## revisiting.
##
## NO SKIP ARMS: the TUI stack is headless and needs no TTY and no display.

import std/strutils
import unittest

import isonim_tui/renderer
import isonim_tui/testing/harness
import isonim_tui/testing/snapshot/plaintext as snapPlain
import isonim_tui/reactive_root

import task_app/core/vm as task_vm
import task_app/main_tui as task_tui

# The launcher's own seeding helper, so this suite mounts the same VM state
# the EX-M14 TUI launcher does rather than an approximation of it.
import ../editor/backends/story_dispatch_demo

suite "NH-M1: EX-M14 launcher reactive mount entry":

  test "test_launcher_entry_untracked_accessor_builds_the_root_once":
    # The shape the TUI launcher ships: `renderTui` + `staticNativeRoot`.
    let h = newTerminalTestHarness(80, 24)
    let vm = newTaskAppVM()
    let r = h.renderer
    resetTuiLeaves()

    let handle = renderTui(h, staticNativeRoot(proc(): TerminalNode =
      task_tui.buildTaskApp(r, vm)))

    check handle.renders == 1
    check handle.rootSwaps == 1
    let mountedRoot = h.root
    check mountedRoot != nil

    vm.setInputText("first")
    check handle.renders == 1
    vm.addTask("first")
    check handle.renders == 1
    vm.setFilter(fmActive)
    check handle.renders == 1

    # The root the launcher captured is still the root the harness holds —
    # this is the property the frame source / hit-tester depend on.
    check h.root == mountedRoot
    check handle.rootSwaps == 1

    handle.dispose()
    h.dispose()

  test "test_launcher_entry_tracked_accessor_would_rebuild_the_whole_root":
    # The falsifier for the case above. The composition root DOES read signals
    # while it builds, so a tracked accessor makes the mount seam depend on
    # them. Asserted rather than described, so the decision to untrack stays
    # justified by a measurement that runs on every suite invocation.
    let h = newTerminalTestHarness(80, 24)
    let vm = newTaskAppVM()
    resetTuiLeaves()

    let handle = renderTui(h, proc(rr: TerminalRenderer): TerminalNode =
      task_tui.buildTaskApp(rr, vm))

    check handle.renders == 1
    let firstRoot = h.root

    vm.setInputText("first")
    check handle.renders > 1
    # A different root object is mounted — exactly the staleness the launcher
    # must not have.
    check h.root != firstRoot

    handle.dispose()
    h.dispose()

  test "test_launcher_entry_still_paints_real_demo_content":
    # The launcher's observable output: the harness's screen buffer must carry
    # real task-app content after the reactive mount, the same as it did when
    # the launcher called `runTaskApp` imperatively.
    let h = newTerminalTestHarness(80, 24)
    let vm = newTaskAppVM()
    let r = h.renderer
    resetTuiLeaves()
    seedTaskInboxDefaults(vm)

    let handle = renderTui(h, staticNativeRoot(proc(): TerminalNode =
      task_tui.buildTaskApp(r, vm)))

    let frame = snapPlain.encodePlaintext(h.screenBuffer())
    check frame.len > 0
    check totalCount(vm) > 0
    # Some seeded task text must have reached the painted grid.
    check contains(frame, "Active") or contains(frame, "All") or
          contains(frame, "Add")

    handle.dispose()
    h.dispose()
