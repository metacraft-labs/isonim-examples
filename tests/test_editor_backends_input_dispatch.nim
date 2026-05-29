## EPP-M7 — per-backend launcher input-dispatch contract test.
##
## *Claim.* The per-launcher composition built by EPP-M7 routes:
##
##   * ``iekResize`` events through the launcher's resize closure
##     (preserving VRS-M2's byte-exact contract — the launcher mutates
##     its dynamic frame source dimensions).
##   * ``iekMouse`` / ``iekKeyboard`` events through the
##     renderer-specific input adapter (``GpuiInputSink`` /
##     ``FreyaInputSink``) which in turn dispatches via the shadow-tree
##     ``fireEvent`` table.
##   * Pre-EPP-M7 behaviour for ``iekResize`` is unchanged (VRS-M2
##     regression net stays green).
##
## *How.* Re-create the launcher's sink composition shape in-process
## using ``newDispatchingLauncherSink``, drive a synthetic stream of
## ``InputEvent``s through it, and assert the resize closure +
## renderer adapter saw the expected slices.
##
## The test deliberately does NOT spawn real launcher binaries —
## those are covered by ``tests/browser/`` end-to-end specs. This is
## the unit-level contract check for the composition helper the
## launchers all rely on.
##
## Spec: EPP-M7 in
## ``codetracer-specs/Front-Ends/IsoNim/Editor-Preview-Performance.milestones.org``.

import std/unittest

import isonim_gpui/renderer as gpui_renderer
import isonim_gpui/bindings as gpui_bindings
import isonim_freya/renderer as freya_renderer
import isonim_freya/bindings as freya_bindings

import isonim_render_serve
import isonim_render_serve/adapters/gpui_input_adapter
import isonim_render_serve/adapters/freya_input_adapter

import task_app/core/vm as task_vm
import task_app/main_gpui as task_gpui
import task_app/main_freya as task_freya

suite "EPP-M7: launcher sink composition routes mouse + keyboard":

  test "GPUI dispatching sink routes resize, mouse, and keyboard":
    gpui_bindings.gpui_reset_tree()
    gpui_renderer.resetCallbacks()
    let vm = newTaskAppVM()
    let r = GpuiRenderer()
    let root = task_gpui.buildTaskApp(r, vm)

    var dynamicW = 800
    var dynamicH = 600
    let onResize = proc(w, h: int) {.gcsafe.} =
      {.cast(gcsafe).}:
        dynamicW = w
        dynamicH = h

    # The hit-tester routes every click to the demo's composition
    # root so subsequent keyboard events land on it. Mirrors the
    # launcher's pre-RS-M3 fixed-target wiring.
    let capturedRoot = root
    let hitTester = proc(x, y: int): GpuiElement {.gcsafe.} =
      {.cast(gcsafe).}:
        capturedRoot
    let inputAdapter = newGpuiInputSink(hitTester)
    let composite = newDispatchingLauncherSink(onResize,
                                               inputAdapter.toAny())

    # Resize: takes the launcher resize path.
    composite.submit(InputEvent(kind: iekResize, width: 1024, height: 768))
    check dynamicW == 1024
    check dynamicH == 768

    # Mouse click: routes through the GPUI input adapter, which
    # hit-tests + fires the renderer's ``"click"`` event.
    composite.submit(InputEvent(kind: iekMouse, mouseAction: maClick,
                                button: 0, mouseX: 50, mouseY: 50,
                                mouseModifiers: Modifiers()))
    check inputAdapter.events.len >= 1
    check inputAdapter.events[^1].kind == iekMouse
    # The click sets focusedNode so the next keyboard event can
    # dispatch.
    check pointer(inputAdapter.focusedNode) != nil

    # Keyboard down: routes through the GPUI input adapter, fires
    # ``"keydown"`` (and ``"input"`` for text).
    composite.submit(InputEvent(kind: iekKeyboard,
      keyboardAction: kbaDown,
      keyboardKey: "h", keyboardCode: "KeyH", keyboardText: "h",
      keyboardModifiers: Modifiers()))
    check inputAdapter.events.len >= 2
    check inputAdapter.events[^1].kind == iekKeyboard
    check inputAdapter.events[^1].keyboardAction == kbaDown
    check inputAdapter.events[^1].keyboardKey == "h"

    # And keyboard up.
    composite.submit(InputEvent(kind: iekKeyboard,
      keyboardAction: kbaUp,
      keyboardKey: "h", keyboardCode: "KeyH", keyboardText: "",
      keyboardModifiers: Modifiers()))
    check inputAdapter.events[^1].keyboardAction == kbaUp

    # Resize still works after keyboard activity (no state corruption).
    composite.submit(InputEvent(kind: iekResize, width: 1920, height: 1080))
    check dynamicW == 1920
    check dynamicH == 1080

    task_gpui.resetGpuiLeaves()

  test "Freya dispatching sink routes resize, mouse, and keyboard":
    freya_bindings.freya_reset_tree()
    freya_renderer.resetCallbacks()
    let vm = newTaskAppVM()
    let r = FreyaRenderer()
    let root = task_freya.buildTaskApp(r, vm)

    var dynamicW = 800
    var dynamicH = 600
    let onResize = proc(w, h: int) {.gcsafe.} =
      {.cast(gcsafe).}:
        dynamicW = w
        dynamicH = h

    let capturedRoot = root
    let hitTester = proc(x, y: int): FreyaElement {.gcsafe.} =
      {.cast(gcsafe).}:
        capturedRoot
    let inputAdapter = newFreyaInputSink(hitTester)
    let composite = newDispatchingLauncherSink(onResize,
                                               inputAdapter.toAny())

    composite.submit(InputEvent(kind: iekResize, width: 1280, height: 800))
    check dynamicW == 1280
    check dynamicH == 800

    composite.submit(InputEvent(kind: iekMouse, mouseAction: maClick,
                                button: 0, mouseX: 30, mouseY: 30,
                                mouseModifiers: Modifiers()))
    check inputAdapter.events.len >= 1
    check pointer(inputAdapter.focusedNode) != nil

    composite.submit(InputEvent(kind: iekKeyboard,
      keyboardAction: kbaDown,
      keyboardKey: "l", keyboardCode: "KeyL", keyboardText: "l",
      keyboardModifiers: Modifiers()))
    check inputAdapter.events[^1].kind == iekKeyboard
    check inputAdapter.events[^1].keyboardCode == "KeyL"

    composite.submit(InputEvent(kind: iekKeyboard,
      keyboardAction: kbaRepeat,
      keyboardKey: "l", keyboardCode: "KeyL", keyboardText: "l",
      keyboardModifiers: Modifiers()))
    check inputAdapter.events[^1].keyboardAction == kbaRepeat

    task_freya.resetFreyaLeaves()

  test "resize-only events do not leak to the input adapter":
    # VRS-M2 byte-exact regression net: only iekResize events
    # affect the resize callback; never the input adapter.
    var dynamicW = 800
    var dynamicH = 600
    let onResize = proc(w, h: int) {.gcsafe.} =
      {.cast(gcsafe).}:
        dynamicW = w
        dynamicH = h

    let inner = newBufferedInputSink()
    let composite = newDispatchingLauncherSink(onResize, inner.toAny())

    composite.submit(InputEvent(kind: iekResize, width: 320, height: 240))
    composite.submit(InputEvent(kind: iekResize, width: 640, height: 480))
    check dynamicW == 640
    check dynamicH == 480
    # The inner sink did not see the resize events — the
    # newDispatchingLauncherSink contract routes them exclusively
    # to onResize.
    check inner.events.len == 0

  test "mouse-only events do not invoke resize":
    var resizeCount = 0
    let onResize = proc(w, h: int) {.gcsafe.} =
      {.cast(gcsafe).}:
        inc resizeCount

    let inner = newBufferedInputSink()
    let composite = newDispatchingLauncherSink(onResize, inner.toAny())

    composite.submit(InputEvent(kind: iekMouse, mouseAction: maClick,
                                button: 0, mouseX: 1, mouseY: 1,
                                mouseModifiers: Modifiers()))
    composite.submit(InputEvent(kind: iekKeyboard,
      keyboardAction: kbaDown,
      keyboardKey: "k", keyboardCode: "KeyK", keyboardText: "k",
      keyboardModifiers: Modifiers()))

    check resizeCount == 0
    check inner.events.len == 2
    check inner.events[0].kind == iekMouse
    check inner.events[1].kind == iekKeyboard

  test "nil input sink drops non-resize events silently":
    # Defensive case: a launcher that doesn't wire an input adapter
    # falls back to the pre-EPP-M7 behaviour (resize-only).
    var dynamicW = 0
    let onResize = proc(w, h: int) {.gcsafe.} =
      {.cast(gcsafe).}:
        dynamicW = w
    let composite = newDispatchingLauncherSink(onResize, nil)
    composite.submit(InputEvent(kind: iekResize, width: 111, height: 222))
    composite.submit(InputEvent(kind: iekMouse, mouseAction: maClick,
                                button: 0, mouseX: 1, mouseY: 1,
                                mouseModifiers: Modifiers()))
    composite.submit(InputEvent(kind: iekKeyboard,
      keyboardAction: kbaDown,
      keyboardKey: "k", keyboardCode: "KeyK", keyboardText: "k",
      keyboardModifiers: Modifiers()))
    check dynamicW == 111
    # No crash; the events are dropped.
