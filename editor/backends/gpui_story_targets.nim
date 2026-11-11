## editor/backends/gpui_story_targets.nim — which GPUI target a `select-story`
## id resolves to.
##
## The editor sends `storyIdFor(story)` (`group & " / " & name`). The GPUI
## launcher used to send every id it did not know to the Task App Inbox, so a
## page story showed another application under the page's own title. This
## module decides the target without touching the GPUI shim, so the decision is
## unit-testable on its own:
##
## - a Task App or Settings App id the launcher's dispatch table handles goes to
##   that app's view model (`gstTaskApp` / `gstSettingsApp`);
## - a page or other story in the wanderlust registry, the same registry
##   `isonim/editor/main.nim` hands to the web preview (`wanderlustPreviewHook`),
##   is drawn as the preview card the web preview shows (`gstPreview`);
## - anything else is `gstUnavailable`, which the launcher shows as an explicit
##   "story not available in GPUI" state. Nothing falls back silently.

import isonim/editor/types
import examples/wanderlust/stories as wanderlust
import task_app/core/story_ids as task_ids
import settings_app/core/story_ids as settings_ids

type
  GpuiStoryTarget* = enum
    gstTaskApp      ## a Task App story, applied to the live TaskAppVM
    gstSettingsApp  ## a Settings App story, applied to the live SettingsVM
    gstPreview      ## a story in the wanderlust registry, drawn as its preview card
    gstUnavailable  ## no GPUI rendering for this id: an explicit state

const
  TaskStoryIds* = [
    task_ids.TaskAppPagesInbox,
    task_ids.TaskAppPagesToday,
    task_ids.TaskAppPagesCompleted,
    task_ids.TaskAppTaskListEmpty,
    task_ids.TaskAppTaskInputEmpty,
    task_ids.TaskAppTaskListTwoActive,
    task_ids.TaskAppTaskListMixedCompletion,
    task_ids.TaskAppFilterBarAllSelected,
    task_ids.TaskAppFilterBarActiveSelected,
    task_ids.TaskAppFilterBarCompletedSelected,
    task_ids.TaskAppSummaryBarActiveOnly,
    task_ids.TaskAppSummaryBarWithCompleted,
  ]
    ## Exactly the ids `applyTaskStory` maps to a VM state. Any other Task App id
    ## is not rendered by this launcher, so it is `gstUnavailable`.
  SettingsStoryIds* = [
    settings_ids.SettingsAppPagesPreferences,
    settings_ids.SettingsAppPagesAppearanceGroup,
    settings_ids.SettingsAppGroupAppearance,
    settings_ids.SettingsAppToggleItemOff,
    settings_ids.SettingsAppToggleItemOn,
    settings_ids.SettingsAppChoiceItemDefault,
    settings_ids.SettingsAppChoiceItemAlternate,
    settings_ids.SettingsAppNumberItemDefault,
    settings_ids.SettingsAppNumberItemClamped,
    settings_ids.SettingsAppPagesEditorGroup,
    settings_ids.SettingsAppGroupEditor,
    settings_ids.SettingsAppGroupNotifications,
  ]
    ## Exactly the ids `applySettingsStory` maps to an active group.

proc wanderlustStoryRef*(storyId: string; found: var StoryRef): bool =
  ## Finds the registry item whose `group / name` is `storyId`. The match is on
  ## the whole id, so a name that itself contains " / " ("Home / Discover") is
  ## not split at the wrong separator.
  for group in wanderlust.buildWanderlustStoryboard():
    for item in group.items:
      if item.group & " / " & item.name == storyId:
        found = StoryRef(group: item.group, name: item.name, kind: item.kind)
        return true
  false

proc resolveGpuiPreview*(storyId: string): ProjectPreview =
  ## The web preview's own preview for `storyId`: the same hook and the same
  ## platform argument the isonim editor passes, so the title and body match.
  ## Returns the hook's unsupported-story result when the id is not registered.
  var story: StoryRef
  if not wanderlustStoryRef(storyId, story):
    return ProjectPreview(status: ppsUnsupportedStory)
  wanderlust.wanderlustPreviewHook(story, pbGpui)

proc classifyGpuiStory*(storyId: string; settingsDemo: bool): GpuiStoryTarget =
  ## The target for a `select-story` id in the launcher's `--demo` mode.
  if settingsDemo:
    if storyId in SettingsStoryIds: return gstSettingsApp
  elif storyId in TaskStoryIds:
    return gstTaskApp
  var story: StoryRef
  if wanderlustStoryRef(storyId, story):
    return gstPreview
  gstUnavailable
