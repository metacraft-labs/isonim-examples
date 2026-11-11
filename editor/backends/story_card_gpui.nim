## editor/backends/story_card_gpui.nim — the GPUI trees the launcher shows for a
## story that is not a Task App or Settings App view.
##
## Both trees are built with the GPUI renderer's element API and carry only
## text and style, so the streamed frame and the element manifest read the same
## strings the web preview shows:
##
## - `storyCardGpui` is the page-preview card: the title, then the body, as the
##   web preview's fallback panel draws them for a page with no document.
## - `storyUnavailableGpui` is the explicit state for an id this launcher cannot
##   render. It names the id, so a capture shows which story was refused.

import isonim_gpui/renderer

proc titleAndBody(r: GpuiRenderer; root: GpuiElement; title, body: string) =
  # The title is a heading and the body a paragraph. The two tags also draw
  # in different colours in the synthetic raster, so the frame shows the
  # boundary between them.
  let heading = r.createElement("h1")
  r.setStyle(heading, "font-size", "24px")
  r.setStyle(heading, "font-weight", "700")
  r.setStyle(heading, "color", "#111827")
  r.setTextContent(heading, title)
  r.appendChild(root, heading)
  let paragraph = r.createElement("p")
  r.setStyle(paragraph, "font-size", "14px")
  r.setStyle(paragraph, "color", "#4b5563")
  r.setTextContent(paragraph, body)
  r.appendChild(root, paragraph)

proc pageRoot(r: GpuiRenderer): GpuiElement =
  result = r.createElement("div")
  r.setStyle(result, "width", "100%")
  r.setStyle(result, "height", "100%")
  r.setStyle(result, "padding", "24px")
  r.setStyle(result, "background-color", "#ffffff")
  r.setStyle(result, "flex-direction", "column")
  r.setStyle(result, "gap", "12px")

proc storyCardGpui*(r: GpuiRenderer; title, body: string): GpuiElement =
  ## The preview card for a registered story: its title and its body text.
  result = pageRoot(r)
  titleAndBody(r, result, title, body)

proc storyUnavailableGpui*(r: GpuiRenderer; storyId: string): GpuiElement =
  ## The explicit "not available" state for `storyId`.
  result = pageRoot(r)
  titleAndBody(r, result, "Story not available in GPUI",
    "\"" & storyId & "\" has no GPUI rendering in this launcher.")
