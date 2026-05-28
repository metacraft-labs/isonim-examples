## editor_chrome/web/leaves.nim — Layer-1 web leaves for the
## chrome-icons showcase.
##
## The leaves satisfy the ``ChromeIconsLeaves`` protocol from
## ``editor_chrome/core/views.nim``. They emit raw HTML against the
## shared ``MockRenderer`` — the in-iframe editor preview is
## ultimately rendered by serializing the same node tree to HTML, so
## the leaves can equally drive a static showcase document.
##
## SVG bodies are inserted via ``setInnerHtml`` because the editor's
## right-sidebar shell already uses the same pattern for the in-house
## icons (``setInnerHtml(manualIconHost, wrenchSvg)`` in
## ``isonim/src/isonim/editor/views/shell.nim``). The renderer
## interprets the inner string as raw HTML, which is what we want for
## ``<svg>...</svg>`` payloads.

import isonim/testing/mock_dom

import editor_chrome/core/types

proc chromeIconsCreateRoot*(r: MockRenderer): MockNode =
  let node = r.createElement("div")
  r.setAttribute(node, "class", "chrome-icons")
  r.setAttribute(node, "data-app", "editor-chrome")
  node

proc chromeIconsCreateBar*(r: MockRenderer): MockNode =
  let node = r.createElement("div")
  r.setAttribute(node, "class", "chrome-icons-bar")
  r.setAttribute(node, "role", "toolbar")
  node

proc chromeIconsCreateButton*(r: MockRenderer; cls, ariaLabel: string):
                              MockNode =
  let node = r.createElement("button")
  r.setAttribute(node, "type", "button")
  r.setAttribute(node, "class", cls)
  r.setAttribute(node, "aria-label", ariaLabel)
  node

proc chromeIconsSetSvgContent*(r: MockRenderer; node: MockNode;
                               svg: string) =
  ## Replace the button's inner markup with the SVG payload. Mirrors
  ## the live editor's ``setInnerHtml(manualIconHost, wrenchSvg)``
  ## pattern.
  r.setInnerHtml(node, svg)

proc chromeIconsSetActive*(r: MockRenderer; node: MockNode;
                           isActive: bool) =
  if isActive:
    r.setAttribute(node, "data-active", "true")
    r.setAttribute(node, "aria-pressed", "true")
  else:
    r.removeAttribute(node, "data-active")
    r.removeAttribute(node, "aria-pressed")

proc statusClassFor(kind: ChromeIconsStatusKind): string =
  case kind
  of cisIdle:      "ci-status ci-status-idle"
  of cisActive:    "ci-status ci-status-active"
  of cisAttention: "ci-status ci-status-attention"

proc chromeIconsAddStatusDot*(r: MockRenderer; node: MockNode;
                              kind: ChromeIconsStatusKind) =
  let dot = r.createElement("span")
  r.setAttribute(dot, "class", statusClassFor(kind))
  r.setAttribute(dot, "data-status-kind", $kind)
  r.appendChild(node, dot)

proc chromeIconsCreateLegend*(r: MockRenderer; label, license: string):
                              MockNode =
  let node = r.createElement("footer")
  r.setAttribute(node, "class", "chrome-icons-legend")
  let labelEl = r.createElement("span")
  r.setAttribute(labelEl, "class", "legend-label")
  r.appendChild(labelEl, r.createTextNode(label))
  let licenseEl = r.createElement("span")
  r.setAttribute(licenseEl, "class", "legend-license")
  r.appendChild(licenseEl, r.createTextNode(license))
  r.appendChild(node, labelEl)
  r.appendChild(node, licenseEl)
  node

proc chromeIconsAppendChild*(r: MockRenderer; parent, child: MockNode) =
  r.appendChild(parent, child)
