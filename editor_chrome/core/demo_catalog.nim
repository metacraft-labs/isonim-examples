## editor_chrome/core/demo_catalog.nim — story entry the chrome-icons
## demo contributes to the global editor catalog.
##
## Mirrors ``settings_app/core/demo_catalog.nim`` in shape: a single
## ``proc`` returning the story metadata the editor's
## ``buildDemoStoryGroups`` proc reads. The chrome-icons demo
## contributes one story — the sidebar tab-bar showcase — under a new
## ``Editor Chrome / Icons`` group.

import isonim/editor/types as editor_types

import ./story_ids

const
  EditorChromeIconsGroup* = "Editor Chrome / Icons"
    ## Story group label the editor sidebar tree displays. Matches the
    ## ``StoryItem.group`` field on every chrome-icons story.

proc buildChromeIconsStoryGroup*(): editor_types.StoryGroup =
  ## Return the single ``StoryGroup`` the chrome-icons demo
  ## contributes to the editor catalog. The demo registers under
  ## ``skComponent`` so the editor's auto-schema mechanism populates
  ## a generic Component Properties panel below the preview — the
  ## panel is augmented by the in-iframe schema-driven picker that
  ## the chrome-icons preview embeds.
  editor_types.StoryGroup(
    name: EditorChromeIconsGroup,
    kind: editor_types.skComponent,
    expanded: true,
    description: "Eight icon sets rendered in the editor's right-sidebar tab bar mock.",
    items: @[
      editor_types.StoryItem(
        name: "Sidebar Tab Bar",
        description: "Wrench + N robots + plus, with status dots, against the chosen icon set.",
        kind: editor_types.skComponent,
        group: EditorChromeIconsGroup),
    ])

const
  EditorChromeSidebarTabBarStoryId* = EditorChromeSidebarTabBar
    ## Re-export the brief's canonical story-id constant so callers
    ## (tests, downstream consumers) only need one import. The string
    ## value matches the editor's ``group & " / " & name`` convention.
