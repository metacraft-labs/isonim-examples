## isonim-examples/editor/main.nim — JS entry point for the demo
## editor instance.
##
## Compiled with ``nim js`` and served from ``build/editor/index.html``.
## See the Justfile targets ``editor-build`` and ``editor-serve``. This
## entry point mirrors the upstream wanderlust main
## (``isonim/src/isonim/editor/main.nim``) but constructs the demo
## workspace defined in ``./workspace`` instead of the wanderlust one,
## and intentionally stays read-only against the demo source: EX-M14
## focuses on live preview + the M57 chrome story; the editor's M11
## write-back path is out of scope for this milestone.

when not defined(js):
  {.error: "The demo editor entry point must be compiled with `nim js`".}

import isonim/editor/browser

import ./workspace

proc main() =
  let ws = newDemoEditorWorkspace()
  discard mountEditor(ws)

main()
