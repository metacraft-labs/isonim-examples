## test_gpui_story_targets — which GPUI target a `select-story` id resolves to.
##
## Pure decision, no shim: the classifier and the registry lookup run on the
## real isonim wanderlust registry (`examples/wanderlust/stories`, the one the
## isonim editor's web preview uses) and on the launcher's own Task App and
## Settings App id tables. No mocks.
##
## What it pins down:
##   * a Task App id in the Task App demo is applied to the Task App VM, and
##     every id the launcher's dispatch table handles is classified that way;
##   * a registered page story (Pages / Trip Planner) is a preview card, and the
##     card's text is the web preview's own hook output for that story;
##   * an id the launcher does not render is `gstUnavailable`, never the Task App
##     Inbox. The Task App id `TaskInputWithDraft` is one such id: it is in the
##     catalog but has no VM state in `applyTaskStory`.

import std/unittest

import isonim/editor/types
import examples/wanderlust/stories as wanderlust
import editor/backends/gpui_story_targets

suite "GPUI story targets":
  test "Task App ids in the Task App demo go to the Task App view model":
    for id in TaskStoryIds:
      check classifyGpuiStory(id, settingsDemo = false) == gstTaskApp

  test "Settings App ids in the Settings demo go to the Settings view model":
    for id in SettingsStoryIds:
      check classifyGpuiStory(id, settingsDemo = true) == gstSettingsApp

  test "a Settings App id is not shown as the Task App Inbox":
    check classifyGpuiStory("Settings App / Pages / Preferences",
      settingsDemo = false) == gstUnavailable

  test "a Task App id without VM state is unavailable, not the Inbox":
    check classifyGpuiStory("Task App / TaskInput / With Draft",
      settingsDemo = false) == gstUnavailable
    check classifyGpuiStory("Task App / Foundations / Spacing",
      settingsDemo = false) == gstUnavailable

  test "a registered page story is a preview card in either demo":
    check classifyGpuiStory("Pages / Trip Planner", settingsDemo = false) == gstPreview
    check classifyGpuiStory("Pages / Trip Planner", settingsDemo = true) == gstPreview

  test "a registered story whose name contains a separator is matched whole":
    # storyIdFor is "group / name", and the name "Home / Discover" holds " / ".
    check classifyGpuiStory("Pages / Home / Discover", settingsDemo = false) == gstPreview

  test "an unregistered id is unavailable":
    check classifyGpuiStory("Pages / No Such Page", settingsDemo = false) == gstUnavailable
    check classifyGpuiStory("", settingsDemo = false) == gstUnavailable

  test "the GPUI preview of a registered story is the web preview's hook output":
    # The expectation is the web preview's own result for the same story, not
    # the GPUI card: `wanderlustPreviewHook` with the web platform.
    let webStory = StoryRef(group: "Pages", name: "Trip Planner", kind: skPage)
    let web = wanderlust.wanderlustPreviewHook(webStory, pbWeb)
    check web.status == ppsRendered
    let gpui = resolveGpuiPreview("Pages / Trip Planner")
    check gpui.status == ppsRendered
    check gpui.title == web.title
    check gpui.bodyText == web.bodyText
    check gpui.title == "Pages / Trip Planner"
    check gpui.bodyText == "Morocco trip planner with itinerary builder and budget summary"

  test "an unregistered id resolves to an unsupported story":
    check resolveGpuiPreview("Pages / No Such Page").status == ppsUnsupportedStory
