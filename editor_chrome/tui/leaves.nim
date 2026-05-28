## editor_chrome/tui/leaves.nim — Layer-1 TUI fallback for the
## chrome-icons showcase.
##
## SVG glyphs don't render in a terminal, so the TUI leaves render
## *text labels* in place of icons. The wrench becomes ``[wrench]``,
## each chat becomes ``[bot N]`` (with an inline ``*`` marker on the
## active chat and a status hint when overlays are enabled), and the
## plus becomes ``[+]``. The legend prints the icon-set's name and
## license as plain text. Style classes are still applied so the
## rendered cell grid is structurally similar to the web variant —
## that's what keeps the cross-renderer parity test happy.
##
## The leaves piggyback on ``MockRenderer`` because the TUI backend
## ultimately serializes a node tree before rasterising — using the
## mock renderer keeps the demo's TUI variant runnable in tests
## without spinning up the real isonim-tui adapter (which is overkill
## for an icon-set showcase).

import std/strutils

import isonim/testing/mock_dom

import editor_chrome/core/types

proc chromeIconsTuiCreateRoot*(r: MockRenderer): MockNode =
  let node = r.createElement("div")
  r.setAttribute(node, "class", "chrome-icons-tui")
  r.setAttribute(node, "data-app", "editor-chrome")
  node

proc chromeIconsTuiCreateBar*(r: MockRenderer): MockNode =
  let node = r.createElement("div")
  r.setAttribute(node, "class", "chrome-icons-bar")
  r.setAttribute(node, "role", "toolbar")
  node

proc chromeIconsTuiCreateButton*(r: MockRenderer;
                                 cls, ariaLabel: string): MockNode =
  ## In the TUI variant the "button" is a span carrying the same
  ## semantic class as the web button so cross-renderer queries
  ## (``data-app`` + ``class`` selectors) work uniformly. The text
  ## label is decided by the SVG-setter (which interprets the
  ## ``cls`` field to pick the right ASCII tag).
  let node = r.createElement("span")
  r.setAttribute(node, "class", cls)
  r.setAttribute(node, "aria-label", ariaLabel)
  node

proc chromeIconsTuiSetSvgContent*(r: MockRenderer; node: MockNode;
                                  svg: string) =
  ## Discard the SVG payload; emit an ASCII placeholder derived from
  ## the button's class. The class string is the most reliable hint
  ## available here — the views layer hands us ``ci-wrench`` /
  ## ``ci-bot`` / ``ci-plus`` plus the leading ``ci-btn`` token.
  discard svg
  let cls = r.getAttribute(node, "class")
  let label =
    if "ci-wrench" in cls: "[wrench]"
    elif "ci-bot" in cls: "[bot]"
    elif "ci-plus" in cls: "[+]"
    else: "[?]"
  # Clear existing children before appending the label.
  while node.children.len > 0:
    r.removeChild(node, node.children[0])
  r.appendChild(node, r.createTextNode(label))

proc chromeIconsTuiSetActive*(r: MockRenderer; node: MockNode;
                              isActive: bool) =
  if isActive:
    r.setAttribute(node, "data-active", "true")
  else:
    r.removeAttribute(node, "data-active")

proc statusTextFor(kind: ChromeIconsStatusKind): string =
  case kind
  of cisIdle:      " ."
  of cisActive:    " *"
  of cisAttention: " !"

proc chromeIconsTuiAddStatusDot*(r: MockRenderer; node: MockNode;
                                 kind: ChromeIconsStatusKind) =
  let dot = r.createElement("span")
  r.setAttribute(dot, "class", "ci-status")
  r.setAttribute(dot, "data-status-kind", $kind)
  r.appendChild(dot, r.createTextNode(statusTextFor(kind)))
  r.appendChild(node, dot)

proc chromeIconsTuiCreateLegend*(r: MockRenderer;
                                 label, license: string): MockNode =
  let node = r.createElement("footer")
  r.setAttribute(node, "class", "chrome-icons-legend")
  r.appendChild(node,
                r.createTextNode("-- " & label & " (" & license & ") --"))
  node

proc chromeIconsTuiAppendChild*(r: MockRenderer;
                                parent, child: MockNode) =
  r.appendChild(parent, child)
