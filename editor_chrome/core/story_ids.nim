## editor_chrome/core/story_ids.nim — canonical storyId taxonomy for
## the chrome-icons showcase demo.
##
## Mirrors ``settings_app/core/story_ids.nim``. The constants below
## match exactly what ``isonim-examples/editor/stories.nim`` emits
## as ``item.group & " / " & item.name`` for every editor_chrome story.

const
  # ---- Components ----
  EditorChromeSidebarTabBar* = "Editor Chrome / Icons / Sidebar Tab Bar"
    ## The brief's primary story: a horizontal row mimicking the
    ## editor's right-sidebar top tab bar — [wrench] [robot]*N [+]
    ## with overlaid status dots and a legend showing the active
    ## icon set's name + license. The schema-driven picker under the
    ## preview swaps which library's glyphs are rendered.
