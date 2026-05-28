## editor_chrome/web/main.nim — Layer-4 composition root for the
## chrome-icons showcase on the web target.
##
## Wires the shared VM + view template to the web leaves and exposes
## ``buildChromeIconsApp`` for tests + the editor-instance launcher.
## The chrome-icons demo is preview-only — no event listeners are
## installed by the leaves (the editor's in-iframe schema picker is a
## separate, in-document ``<select>`` element wired via vanilla JS in
## the preview hook).

import isonim/testing/mock_dom

import editor_chrome/core/types
import editor_chrome/core/vm
import editor_chrome/core/views
import editor_chrome/web/leaves

export types, vm, views, leaves, mock_dom

proc buildChromeIconsApp*(r: MockRenderer;
                          v: ChromeIconsReactiveVM): MockNode =
  ## Build the chrome-icons showcase tree and return the root node.
  ## Tests call this directly when they already own a renderer.
  let bundle = ChromeIconsLeaves[MockRenderer, MockNode](
    createBar:      chromeIconsCreateBar,
    createButton:   chromeIconsCreateButton,
    setSvgContent:  chromeIconsSetSvgContent,
    setActive:      chromeIconsSetActive,
    addStatusDot:   chromeIconsAddStatusDot,
    createLegend:   chromeIconsCreateLegend,
    appendChild:    chromeIconsAppendChild,
    createRoot:     chromeIconsCreateRoot)
  renderChromeIconsView(r, v, bundle)

when isMainModule:
  let v = createChromeIconsVM()
  let r = MockRenderer()
  let root = buildChromeIconsApp(r, v)
  echo "Chrome-icons web mounted; root.tag=", root.tag
  echo "Icon set: ", v.iconSetId.val
  echo "Chat count: ", v.chatCount.val
  echo "Active index: ", v.activeIndex.val
  echo "Status dots: ", v.showStatus.val
