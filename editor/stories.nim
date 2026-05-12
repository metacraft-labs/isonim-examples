## isonim-examples/editor/stories.nim — story catalog for the demo editor.
##
## EX-M14: brings up an IsoNim Editor instance over the two demo apps that
## ship in this repo (`task_app`, `settings_app`) so the M57 edge-strip
## chrome + RS-M7 streaming-preview integration can be exercised against
## a real, runnable design-system catalog.
##
## The catalog mirrors the shape used by the wanderlust example
## (`isonim/examples/wanderlust/stories.nim`): groups of `StoryItem`s
## organised by `StoryKind`. The editor framework reads
## `EditorWorkspace.storyGroups` directly so the catalog must use the
## upstream `StoryGroup` / `StoryItem` / `StoryRef` types from
## `isonim/editor/types`.
##
## Source-file metadata is captured via the `StoryRenderMetadata` returned
## by `demoPreviewHook` — when the editor selects a story, the
## source-impact view points at the corresponding demo component file in
## this repo, which is the same convention wanderlust uses to surface
## demo source paths.
##
## Cross-references:
##   - spec entry: codetracer-specs/Front-Ends/IsoNim/isonim-render-stream.status.org §EX-M14
##   - editor chrome: codetracer-specs/Front-Ends/IsoNim/isonim-editor.md §Preview-pane chrome layout
##   - upstream pattern: isonim/examples/wanderlust/stories.nim

import std/strutils

import isonim/editor/types

const
  TaskAppSource* = "task_app/core/vm.nim"
  TaskAppViewsSource* = "task_app/core/views.nim"
  TaskAppWebLeaves* = "task_app/web/leaves.nim"
  TaskAppTuiLeaves* = "task_app/tui/leaves.nim"
  SettingsAppCatalogSource* = "settings_app/core/demo_catalog.nim"
  SettingsAppVmSource* = "settings_app/core/vm.nim"
  SettingsAppGroupSource* = "settings_app/components/group.nim"
  SettingsAppToggleSource* = "settings_app/components/toggle_item.nim"
  SettingsAppChoiceSource* = "settings_app/components/choice_item.nim"
  SettingsAppNumberSource* = "settings_app/components/number_item.nim"

  DemoEditorWorkspaceSource* = "isonim-examples/editor/stories.nim"

# ---------------------------------------------------------------------------
# Source-file mapping per story name. Returns the canonical demo-source
# path that drives the editor's source-impact view. Kept as a single
# proc so future additions only need one edit site.
# ---------------------------------------------------------------------------

func sourceFileFor*(group, name: string; kind: StoryKind): string =
  case kind
  of skComponent:
    case group
    of "Task App / TaskInput": TaskAppViewsSource
    of "Task App / FilterBar": TaskAppViewsSource
    of "Task App / TaskList": TaskAppViewsSource
    of "Task App / SummaryBar": TaskAppViewsSource
    of "Settings App / Group": SettingsAppGroupSource
    of "Settings App / ToggleItem": SettingsAppToggleSource
    of "Settings App / ChoiceItem": SettingsAppChoiceSource
    of "Settings App / NumberItem": SettingsAppNumberSource
    else: TaskAppViewsSource
  of skPage:
    case group
    of "Task App / Pages":
      case name
      of "Inbox", "Today", "Completed": TaskAppViewsSource
      else: TaskAppViewsSource
    of "Settings App / Pages":
      case name
      of "Preferences", "Appearance Group", "Editor Group": SettingsAppCatalogSource
      else: SettingsAppCatalogSource
    else: TaskAppViewsSource
  of skFoundation:
    case group
    of "Task App / Foundations": TaskAppSource
    of "Settings App / Foundations": SettingsAppVmSource
    else: TaskAppSource
  of skPattern:
    case group
    of "Patterns": TaskAppViewsSource
    else: TaskAppViewsSource
  of skFlow:
    case group
    of "Add Task Flow": TaskAppViewsSource
    of "Toggle Setting Flow": SettingsAppCatalogSource
    else: TaskAppViewsSource
  of skGuideline:
    DemoEditorWorkspaceSource

func appOf*(group: string): string =
  ## Best-effort recovery of the parent demo app from a story group.
  if group.startsWith("Task App"): "task_app"
  elif group.startsWith("Settings App"): "settings_app"
  else: ""

# ---------------------------------------------------------------------------
# Catalog
# ---------------------------------------------------------------------------

proc buildDemoStoryGroups*(): seq[StoryGroup] =
  ## Return the editor's storyboard for the isonim-examples demo apps.
  ##
  ## Layout (most-important first, mirroring the wanderlust ordering):
  ##   Flows -> Pages -> Components -> Patterns -> Foundations -> Guidelines.
  var groups: seq[StoryGroup]

  # ---- 1. Flows ----------------------------------------------------------
  groups.add StoryGroup(
    name: "Add Task Flow", kind: skFlow, expanded: true,
    description: "User adds a task, toggles it, then clears completed.",
    items: @[
      StoryItem(name: "Types a task name",
                description: "Focuses the input and types 'pick up groceries'",
                kind: skFlow, group: "Add Task Flow"),
      StoryItem(name: "Presses Enter to add",
                description: "Submits the task; list now has 1 active row",
                kind: skFlow, group: "Add Task Flow"),
      StoryItem(name: "Toggles the task complete",
                description: "Checkbox flips to checked; summary updates",
                kind: skFlow, group: "Add Task Flow"),
      StoryItem(name: "Clears completed tasks",
                description: "Pressing the clear-completed button removes the row",
                kind: skFlow, group: "Add Task Flow"),
    ])

  groups.add StoryGroup(
    name: "Toggle Setting Flow", kind: skFlow, expanded: true,
    description: "User flips a toggle setting and tweaks a number.",
    items: @[
      StoryItem(name: "Opens Appearance group",
                description: "Selects the Appearance section in the sidebar",
                kind: skFlow, group: "Toggle Setting Flow"),
      StoryItem(name: "Toggles dark mode",
                description: "Switch flips; preview pane re-renders dark",
                kind: skFlow, group: "Toggle Setting Flow"),
      StoryItem(name: "Adjusts font size",
                description: "Number input clamps below min, reaches 18pt",
                kind: skFlow, group: "Toggle Setting Flow"),
    ])

  # ---- 2. Pages ----------------------------------------------------------
  groups.add StoryGroup(
    name: "Task App / Pages", kind: skPage, expanded: true,
    description: "Full task-app screens rendered against the shared VM.",
    items: @[
      StoryItem(name: "Inbox",
                description: "All tasks (filter=All) with two active rows",
                kind: skPage, group: "Task App / Pages"),
      StoryItem(name: "Today",
                description: "Active filter with a single in-progress task",
                kind: skPage, group: "Task App / Pages"),
      StoryItem(name: "Completed",
                description: "Completed filter with cleared affordance",
                kind: skPage, group: "Task App / Pages"),
    ])

  groups.add StoryGroup(
    name: "Settings App / Pages", kind: skPage, expanded: true,
    description: "Full settings-app screens against the shared SettingsVM.",
    items: @[
      StoryItem(name: "Preferences",
                description: "All three groups (Appearance, Editor, Notifications)",
                kind: skPage, group: "Settings App / Pages"),
      StoryItem(name: "Appearance Group",
                description: "Single-group preview: dark mode + theme + font",
                kind: skPage, group: "Settings App / Pages"),
      StoryItem(name: "Editor Group",
                description: "Tabs-to-spaces, tab width, line endings",
                kind: skPage, group: "Settings App / Pages"),
    ])

  # ---- 3. Components -----------------------------------------------------
  groups.add StoryGroup(
    name: "Task App / TaskInput", kind: skComponent, expanded: false,
    description: "Single-line task input with Enter-to-submit.",
    items: @[
      StoryItem(name: "Empty",
                description: "Placeholder visible, no draft text",
                kind: skComponent, group: "Task App / TaskInput"),
      StoryItem(name: "With Draft",
                description: "Draft text 'buy milk' awaiting submit",
                kind: skComponent, group: "Task App / TaskInput"),
    ])

  groups.add StoryGroup(
    name: "Task App / FilterBar", kind: skComponent, expanded: false,
    description: "All / Active / Completed segmented control.",
    items: @[
      StoryItem(name: "All Selected",
                description: "Default selection — every task visible",
                kind: skComponent, group: "Task App / FilterBar"),
      StoryItem(name: "Active Selected",
                description: "Only uncompleted tasks visible",
                kind: skComponent, group: "Task App / FilterBar"),
      StoryItem(name: "Completed Selected",
                description: "Only completed tasks visible",
                kind: skComponent, group: "Task App / FilterBar"),
    ])

  groups.add StoryGroup(
    name: "Task App / TaskList", kind: skComponent, expanded: false,
    description: "Reactive task list with per-row toggle and remove.",
    items: @[
      StoryItem(name: "Empty",
                description: "No tasks; empty-state copy",
                kind: skComponent, group: "Task App / TaskList"),
      StoryItem(name: "Two Active",
                description: "Two unchecked tasks in insertion order",
                kind: skComponent, group: "Task App / TaskList"),
      StoryItem(name: "Mixed Completion",
                description: "One active, one completed",
                kind: skComponent, group: "Task App / TaskList"),
    ])

  groups.add StoryGroup(
    name: "Task App / SummaryBar", kind: skComponent, expanded: false,
    description: "Active count + clear-completed affordance.",
    items: @[
      StoryItem(name: "Active Only",
                description: "1 item left; no clear-completed visible",
                kind: skComponent, group: "Task App / SummaryBar"),
      StoryItem(name: "With Completed",
                description: "1 item left; clear button enabled",
                kind: skComponent, group: "Task App / SummaryBar"),
    ])

  groups.add StoryGroup(
    name: "Settings App / Group", kind: skComponent, expanded: false,
    description: "Wraps header + items for one settings group.",
    items: @[
      StoryItem(name: "Appearance",
                description: "Dark mode toggle + theme choice + font number",
                kind: skComponent, group: "Settings App / Group"),
      StoryItem(name: "Editor",
                description: "Tabs-to-spaces toggle + tab width + line endings",
                kind: skComponent, group: "Settings App / Group"),
      StoryItem(name: "Notifications",
                description: "Two toggles + poll interval (ms)",
                kind: skComponent, group: "Settings App / Group"),
    ])

  groups.add StoryGroup(
    name: "Settings App / ToggleItem", kind: skComponent, expanded: false,
    description: "Bool setting with label, description, and switch.",
    items: @[
      StoryItem(name: "Off",
                description: "Default value, switch in off position",
                kind: skComponent, group: "Settings App / ToggleItem"),
      StoryItem(name: "On",
                description: "User flipped it on",
                kind: skComponent, group: "Settings App / ToggleItem"),
    ])

  groups.add StoryGroup(
    name: "Settings App / ChoiceItem", kind: skComponent, expanded: false,
    description: "Enum setting rendered as a dropdown / option list.",
    items: @[
      StoryItem(name: "Default",
                description: "First option selected (theme=Default)",
                kind: skComponent, group: "Settings App / ChoiceItem"),
      StoryItem(name: "Alternate",
                description: "Second option selected (theme=Solarized)",
                kind: skComponent, group: "Settings App / ChoiceItem"),
    ])

  groups.add StoryGroup(
    name: "Settings App / NumberItem", kind: skComponent, expanded: false,
    description: "Bounded integer setting with min/max/step clamping.",
    items: @[
      StoryItem(name: "Default",
                description: "Initial value (font_size=14)",
                kind: skComponent, group: "Settings App / NumberItem"),
      StoryItem(name: "Clamped",
                description: "Value rejected below min, snapped to 10",
                kind: skComponent, group: "Settings App / NumberItem"),
    ])

  # ---- 4. Patterns -------------------------------------------------------
  groups.add StoryGroup(
    name: "Patterns", kind: skPattern, expanded: false,
    description: "Cross-app compositions shared between the demos.",
    items: @[
      StoryItem(name: "Form With Inline Error",
                description: "Validation message under an input",
                kind: skPattern, group: "Patterns"),
      StoryItem(name: "List With Empty State",
                description: "List or grid with an empty-state placeholder",
                kind: skPattern, group: "Patterns"),
      StoryItem(name: "Segmented Control",
                description: "Radio-style group used by filters and choice items",
                kind: skPattern, group: "Patterns"),
    ])

  # ---- 5. Foundations ----------------------------------------------------
  groups.add StoryGroup(
    name: "Task App / Foundations", kind: skFoundation, expanded: false,
    description: "Design tokens used by the task app.",
    items: @[
      StoryItem(name: "Spacing",
                description: "Padding / gap scale used by list rows",
                kind: skFoundation, group: "Task App / Foundations"),
      StoryItem(name: "Typography",
                description: "Body / label / placeholder type styles",
                kind: skFoundation, group: "Task App / Foundations"),
    ])

  groups.add StoryGroup(
    name: "Settings App / Foundations", kind: skFoundation, expanded: false,
    description: "Design tokens used by the settings app.",
    items: @[
      StoryItem(name: "Item Density",
                description: "Row height + label-control alignment rhythm",
                kind: skFoundation, group: "Settings App / Foundations"),
      StoryItem(name: "Control States",
                description: "Default / hover / disabled tonal palette",
                kind: skFoundation, group: "Settings App / Foundations"),
    ])

  # ---- 6. Guidelines -----------------------------------------------------
  groups.add StoryGroup(
    name: "Guidelines", kind: skGuideline, expanded: false,
    description: "Cross-app usage rules and conventions.",
    items: @[
      StoryItem(name: "Cross-renderer parity",
                description: "Every demo component must round-trip on TUI/web/GPUI/Freya",
                kind: skGuideline, group: "Guidelines"),
      StoryItem(name: "Layer separation",
                description: "Never import a Layer-1 leaf from core/",
                kind: skGuideline, group: "Guidelines"),
    ])

  groups

# ---------------------------------------------------------------------------
# Flattened story-item list used by tests and by demoCanvasItems.
# ---------------------------------------------------------------------------

iterator allStoryItems*(groups: seq[StoryGroup]): tuple[group: StoryGroup;
    item: StoryItem; index: int] =
  for g in groups:
    for i, it in g.items:
      yield (group: g, item: it, index: i)

func storyRefFor*(item: StoryItem; index: int): StoryRef =
  StoryRef(group: item.group, name: item.name, kind: item.kind, index: index)

# ---------------------------------------------------------------------------
# Canvas items + flow steps.
# ---------------------------------------------------------------------------

func demoCanvasItems*(groups: seq[StoryGroup]): seq[CanvasItem] =
  var index = 0
  for g in groups:
    if g.kind == skPage:
      for it in g.items:
        result.add CanvasItem(
          storyRef: storyRefFor(it, index),
          x: float(index mod 3) * 360.0,
          y: float(index div 3) * 240.0,
          width: 320.0,
          height: 200.0,
          label: it.group & " / " & it.name)
        inc index

func demoFlowSteps*(groups: seq[StoryGroup]): seq[FlowStep] =
  for g in groups:
    if g.kind == skFlow:
      for it in g.items:
        let screenGroup =
          if g.name == "Add Task Flow": "Task App / Pages"
          else: "Settings App / Pages"
        let screenName =
          if g.name == "Add Task Flow": "Inbox"
          else: "Preferences"
        result.add FlowStep(
          screenRef: StoryRef(group: screenGroup, name: screenName,
            kind: skPage),
          action: it.name,
          description: it.description)

# ---------------------------------------------------------------------------
# Preview hook — produces a `ProjectPreview` for each story in the catalog.
# The editor renders this in the in-iframe `Web` preview; for the other
# backends the bridge process owns the rendering and the hook simply
# carries the story metadata so the source-impact view can resolve files.
# ---------------------------------------------------------------------------

func storyTitle*(item: StoryItem): string =
  item.group & " / " & item.name

func renderKind(kind: StoryKind): string =
  case kind
  of skFoundation: "foundation"
  of skComponent: "component"
  of skPattern: "pattern"
  of skPage: "page"
  of skFlow: "flow"
  of skGuideline: "guideline"

func findStoryItem(groups: seq[StoryGroup]; story: StoryRef;
    itemOut: var StoryItem; indexOut: var int): bool =
  for g in groups:
    if g.name == story.group and g.kind == story.kind:
      for i, it in g.items:
        if it.name == story.name and it.kind == story.kind:
          itemOut = it
          indexOut = i
          return true

func storyMetadataFromGroups*(groups: seq[StoryGroup];
    story: StoryRef): StoryRenderMetadata =
  var item: StoryItem
  var itemIndex = -1
  if findStoryItem(groups, story, item, itemIndex):
    return StoryRenderMetadata(
      story: StoryRef(group: item.group, name: item.name, kind: item.kind,
        index: itemIndex),
      title: storyTitle(item),
      sourceFile: sourceFileFor(item.group, item.name, item.kind),
      sourceLine: 1,
      fixtureName: item.group & "." & item.name,
      renderKind: story.kind.renderKind)

func previewBodyFor(item: StoryItem; platform: Platform): string =
  ## The body text that gets rendered into the Web (iframe) preview. The
  ## native streaming backends ignore this — they render the real demo
  ## binary's UI — but the editor's source-impact view still reads it for
  ## the title / breadcrumb.
  let backendLabel =
    case platform
    of pbWeb: "Web"
    of pbTui: "TUI"
    of pbGpui: "GPUI"
    of pbFreya: "Freya"
    of pbCocoa: "Cocoa"
    of pbAndroid: "Android"
  let suffix = " (" & backendLabel & " backend)"
  case item.kind
  of skPage:
    "Page preview for " & item.group & " / " & item.name &
      " rendered against the " & backendLabel & " backend"
  of skComponent:
    "Component fixture " & item.group & " / " & item.name &
      " — " & item.description & suffix
  of skPattern:
    "Pattern fixture for " & toLowerAscii(item.name) & suffix
  of skFoundation:
    "Foundation tokens — " & toLowerAscii(item.name) & suffix
  of skGuideline:
    "Guideline note — " & toLowerAscii(item.name) & suffix
  of skFlow:
    "Flow step — " & item.description & suffix

proc demoPreviewHook*(story: StoryRef; platform: Platform): ProjectPreview =
  ## Project-owned preview hook for the demo editor.
  let groups = buildDemoStoryGroups()
  var item: StoryItem
  var itemIndex = -1
  if not findStoryItem(groups, story, item, itemIndex):
    return ProjectPreview(status: ppsUnsupportedStory, story: story)
  let resolvedStory = StoryRef(group: item.group, name: item.name,
    kind: item.kind, index: itemIndex)
  let title = storyTitle(item)
  let body = previewBodyFor(item, platform)
  let metadata = StoryRenderMetadata(
    story: resolvedStory,
    title: title,
    sourceFile: sourceFileFor(item.group, item.name, item.kind),
    sourceLine: 1,
    fixtureName: item.group & "." & item.name,
    renderKind: item.kind.renderKind)
  let html =
    "<!doctype html><html><head><meta charset=\"utf-8\"/>" &
    "<title>" & title & "</title></head><body>" &
    "<main data-story=\"" & item.group & "/" & item.name & "\">" &
    "<h1>" & title & "</h1>" &
    "<p>" & body & "</p>" &
    "<dl><dt>Backend</dt><dd>" & $platform & "</dd>" &
    "<dt>Source</dt><dd>" & metadata.sourceFile & "</dd></dl>" &
    "</main></body></html>"
  ProjectPreview(
    status: ppsRendered,
    story: resolvedStory,
    title: title,
    bodyText: body,
    documentHtml: html,
    metadata: metadata)
