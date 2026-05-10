## test_views_compile_cross_renderer — EX-M1 mandatory integration test.
##
## Driver test that compiles + runs the two cross-renderer compile
## checks defined in their own files (because the include-pattern in
## `task_app/core/views.nim` requires the leaf-name procs to live at
## module scope, and a single test module can't sensibly host two
## include-instances without the leaf names colliding).
##
## The actual checks are:
##
##   * `helpers/views_compile_tui.nim`   — `views.nim` compiles +
##     runs against `TerminalRenderer` (TUI target) using stub leaves.
##   * `helpers/views_compile_web.nim`   — `views.nim` compiles +
##     runs against `MockRenderer` (web target) using stub leaves.
##
## Each helper exposes a `buildApp` proc that returns the root node;
## this driver test calls both, asserts the documented topology
## (`appShell > {taskInput, filterBar, taskList, summaryBar}`) holds
## under each, and asserts the leaf order matches across renderers
## (a behavioral fingerprint that would fail if the include-pattern
## broke for either side).
##
## The leaves are deliberately minimal stubs — EX-M2 brings the real
## leaves into `isonim-examples`. The point of EX-M1's compile check
## is the *template-include pattern*, not leaf functionality, so
## reusing the EX-M2 leaves here would obscure what's being tested.
##
## No mocks of the renderer or the VM. Only the leaf bundle is the
## smallest set of mutators that lets the include compile.

import std/unittest

import task_app/core/vm

import ./helpers/views_compile_tui as tuiCompile
import ./helpers/views_compile_web as webCompile

suite "EX-M1: views.nim compiles unchanged against both renderers":
  test "TerminalRenderer composition produces the documented topology":
    let vm = newTaskAppVM()
    let root = tuiCompile.buildApp(vm)
    check root != nil
    check root.tag == "div"
    check root.children.len == 4
    check root.children[0].tag == "input"
    check root.children[1].tag == "nav"
    check root.children[2].tag == "ul"
    check root.children[3].tag == "footer"

  test "MockRenderer composition produces the documented topology":
    let vm = newTaskAppVM()
    let root = webCompile.buildApp(vm)
    check root != nil
    check root.tag == "div"
    check root.children.len == 4
    check root.children[0].tag == "input"
    check root.children[1].tag == "nav"
    check root.children[2].tag == "ul"
    check root.children[3].tag == "footer"

  test "leaf-order fingerprint matches across renderers":
    ## If the include-pattern broke for either renderer, the resulting
    ## tree shape would necessarily diverge. This is a behavioral
    ## parity guard.
    let tuiRoot = tuiCompile.buildApp(newTaskAppVM())
    let webRoot = webCompile.buildApp(newTaskAppVM())
    check tuiRoot.children.len == webRoot.children.len
    for i in 0 ..< tuiRoot.children.len:
      check tuiRoot.children[i].tag == webRoot.children[i].tag
