## editor_chrome/tui/main.nim — Layer-4 composition root for the
## chrome-icons showcase on the TUI target.
##
## The TUI build piggybacks on the same ``MockRenderer`` that drives
## the web variant — the showcase doesn't need a real terminal raster
## because the only thing being demonstrated is the *catalog* of icon
## sets, which isn't a terminal-renderable artifact in the first
## place. The TUI variant renders ASCII placeholders so the demo is
## still browsable on a TUI launcher; production use would not pin
## the icon set choice to TUI builds.

import isonim/testing/mock_dom

import editor_chrome/core/types
import editor_chrome/core/vm
import editor_chrome/core/views
import editor_chrome/tui/leaves

export types, vm, views, leaves, mock_dom

proc buildChromeIconsTuiApp*(r: MockRenderer;
                              v: ChromeIconsReactiveVM): MockNode =
  ## Build the TUI-variant showcase tree and return the root node.
  let bundle = ChromeIconsLeaves[MockRenderer, MockNode](
    createBar:      chromeIconsTuiCreateBar,
    createButton:   chromeIconsTuiCreateButton,
    setSvgContent:  chromeIconsTuiSetSvgContent,
    setActive:      chromeIconsTuiSetActive,
    addStatusDot:   chromeIconsTuiAddStatusDot,
    createLegend:   chromeIconsTuiCreateLegend,
    appendChild:    chromeIconsTuiAppendChild,
    createRoot:     chromeIconsTuiCreateRoot)
  renderChromeIconsView(r, v, bundle)

when isMainModule:
  let v = createChromeIconsVM()
  let r = MockRenderer()
  let root = buildChromeIconsTuiApp(r, v)
  echo "Chrome-icons TUI mounted; root.tag=", root.tag
  echo "Icon set: ", v.iconSetId.val
  echo "Chat count: ", v.chatCount.val
  echo "Top-level children (bar + legend): ", root.children.len
