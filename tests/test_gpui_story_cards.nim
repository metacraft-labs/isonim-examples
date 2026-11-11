## test_gpui_story_cards — the GPUI trees for a preview card and for the
## "story not available in GPUI" state.
##
## Builds both trees with the real `GpuiRenderer` over the Rust
## `gpui-nim-shim` cdylib (loaded at run time through `LD_LIBRARY_PATH`), then
## reads the text back through the shim's own tree API. No mocks.
##
## The card's expected text is the web preview's output for the same story
## (`wanderlustPreviewHook` with the web platform), so a GPUI card that drifts
## from the web preview fails here.

import std/[strutils, unittest]

import isonim/editor/types
import isonim_gpui/renderer
import examples/wanderlust/stories as wanderlust
import editor/backends/gpui_story_targets
import editor/backends/story_card_gpui

suite "GPUI story cards":
  test "a registered page story renders the title and body the web preview shows":
    let webStory = StoryRef(group: "Pages", name: "Trip Planner", kind: skPage)
    let web = wanderlust.wanderlustPreviewHook(webStory, pbWeb)
    let preview = resolveGpuiPreview("Pages / Trip Planner")
    let r = GpuiRenderer()
    let card = storyCardGpui(r, preview.title, preview.bodyText)
    check childCount(card) == 2
    check textContent(nthChild(card, 0)) == web.title
    check textContent(nthChild(card, 1)) == web.bodyText

  test "an id the launcher does not render shows the explicit unavailable state":
    let r = GpuiRenderer()
    let card = storyUnavailableGpui(r, "Task App / TaskInput / With Draft")
    check childCount(card) == 2
    check textContent(nthChild(card, 0)) == "Story not available in GPUI"
    check "Task App / TaskInput / With Draft" in textContent(nthChild(card, 1))

  test "the unavailable state is not the Task App Inbox":
    let r = GpuiRenderer()
    let card = storyUnavailableGpui(r, "Pages / No Such Page")
    for i in 0 ..< childCount(card):
      check "Buy groceries" notin textContent(nthChild(card, i))
      check "Inbox" notin textContent(nthChild(card, i))
