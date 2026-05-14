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
  of skVectorSymbol:
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
                kind: skPage, group: "Task App / Pages",
                usesVectorSymbols: @["Task Check Icon", "Task Filter Icon"]),
      StoryItem(name: "Today",
                description: "Active filter with a single in-progress task",
                kind: skPage, group: "Task App / Pages",
                usesVectorSymbols: @["Task Check Icon", "Task Filter Icon"]),
      StoryItem(name: "Completed",
                description: "Completed filter with cleared affordance",
                kind: skPage, group: "Task App / Pages",
                usesVectorSymbols: @["Task Check Icon"]),
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
                kind: skComponent, group: "Task App / TaskList",
                usesVectorSymbols: @["Task Check Icon"]),
      StoryItem(name: "Two Active",
                description: "Two unchecked tasks in insertion order",
                kind: skComponent, group: "Task App / TaskList",
                usesVectorSymbols: @["Task Check Icon", "Task Sort Icon"]),
      StoryItem(name: "Mixed Completion",
                description: "One active, one completed",
                kind: skComponent, group: "Task App / TaskList",
                usesVectorSymbols: @["Task Check Icon", "Task Sort Icon"]),
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

  # ---- Vector Symbols (M-EVP-11) ----------------------------------------
  # The seeded skVectorSymbol entry "Task Check Icon" pairs with the
  # ``task_app/views/TaskCheckIcon`` leaf rendered inside every
  # task-app summary bar (TUI / GPUI / Freya / Cocoa / Android). The
  # editor's canvas dblclick handler hits the leaf's manifest entry,
  # extracts the trailing path segment, and uses it to look up this
  # story — opening the vector editor on the matching skVectorSymbol
  # target.
  #
  # M-EVP-12: two additional skVectorSymbol stories ("Task Filter
  # Icon", "Task Sort Icon") + one orphan ("Empty Glyph") give the
  # vector-editor visual-review briefs deterministic data:
  #
  #   - "Task Check Icon" — usesVectorSymbols mentions it in 6 stories
  #     → carousel variant (>3 usages). Drives the
  #     ``vector-editor-carousel`` screenshot.
  #   - "Task Filter Icon" — used in 2 Page stories → split (stacked)
  #     variant (<=3 usages). Drives the
  #     ``vector-editor-with-symbol`` screenshot.
  #   - "Empty Glyph" — no usesVectorSymbols mentions it → empty
  #     usage-panel state. Drives the ``vector-editor-empty``
  #     screenshot.
  groups.add StoryGroup(
    name: "Task App / Vector Symbols", kind: skVectorSymbol, expanded: false,
    description: "Reusable vector glyphs annotated for the canvas dblclick hit-test.",
    items: @[
      StoryItem(name: "Task Check Icon",
                description: "Check-mark glyph beside the task summary count.",
                kind: skVectorSymbol,
                group: "Task App / Vector Symbols"),
      StoryItem(name: "Task Filter Icon",
                description: "Funnel glyph used in filter-bar affordances.",
                kind: skVectorSymbol,
                group: "Task App / Vector Symbols"),
      StoryItem(name: "Task Sort Icon",
                description: "Up/down arrows for the task-list sort affordance.",
                kind: skVectorSymbol,
                group: "Task App / Vector Symbols"),
      StoryItem(name: "Empty Glyph",
                description: "Reserved glyph with no current usages (visual-review baseline).",
                kind: skVectorSymbol,
                group: "Task App / Vector Symbols"),
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
  of skVectorSymbol: "vector-symbol"

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
  ##
  ## The body embeds the active backend label so consumers (and tests)
  ## can observe which backend the preview was generated for. The body
  ## text is used by `previewDocumentHtmlFor` as the subtitle on the
  ## rendered showcase HTML; the backend label is also rendered as a
  ## visible "band" in the document via `backendBandLabel`.
  let base = case item.kind
    of skPage: item.group & " / " & item.name
    of skComponent: item.description
    of skPattern: item.description
    of skFoundation: item.description
    of skGuideline: item.description
    of skFlow: item.description
    of skVectorSymbol: item.description
  case platform
  of pbWeb: base
  else: base & " — " & $platform

const previewBaseStyles = """
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body {
  height: 100%;
  background: #0D0E14;
  color: #ECEDF3;
  font-family: -apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', system-ui, sans-serif;
  font-size: 14px;
  -webkit-font-smoothing: antialiased;
}
body { padding: 32px; overflow-y: auto; }
.app {
  max-width: 720px;
  margin: 0 auto;
  display: flex;
  flex-direction: column;
  gap: 24px;
}
.app-header { display: flex; flex-direction: column; gap: 6px; }
.app-title { font-size: 20px; font-weight: 600; letter-spacing: -0.01em; color: #ECEDF3; }
.app-subtitle { font-size: 13px; color: #9CA0B0; line-height: 1.5; }
.card {
  background: #15161F;
  border: 1px solid #2A2C3A;
  border-radius: 10px;
  padding: 20px 22px;
  display: flex;
  flex-direction: column;
  gap: 14px;
}
.row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 10px 0;
  border-bottom: 1px solid #1F212C;
}
.row:last-child { border-bottom: none; padding-bottom: 0; }
.row-label { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.row-title { font-size: 13px; color: #ECEDF3; font-weight: 500; }
.row-hint  { font-size: 11px; color: #6B6F80; }
.toggle {
  width: 36px; height: 20px;
  background: #2A2C3A;
  border-radius: 999px;
  position: relative;
  flex-shrink: 0;
}
.toggle::after {
  content: '';
  position: absolute;
  top: 2px; left: 2px;
  width: 16px; height: 16px;
  background: #ECEDF3;
  border-radius: 50%;
  transition: transform 0.18s;
}
.toggle.on { background: #7C7AED; }
.toggle.on::after { transform: translateX(16px); }
.choice { display: flex; gap: 6px; }
.choice-pill {
  font-size: 12px;
  padding: 4px 12px;
  border-radius: 999px;
  background: transparent;
  color: #9CA0B0;
  border: 1px solid #2A2C3A;
  font-weight: 500;
}
.choice-pill.active {
  background: #272752;
  color: #ECEDF3;
  border-color: #7C7AED;
}
.number {
  background: #1A1B26;
  border: 1px solid #2A2C3A;
  border-radius: 6px;
  padding: 6px 10px;
  font-size: 13px;
  color: #ECEDF3;
  width: 80px;
  text-align: center;
  font-variant-numeric: tabular-nums;
}
.group-title {
  font-size: 11px;
  font-weight: 600;
  color: #9CA0B0;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  margin-bottom: 4px;
}
.task-input {
  display: flex;
  align-items: center;
  gap: 10px;
  background: #15161F;
  border: 1px solid #2A2C3A;
  border-radius: 10px;
  padding: 12px 16px;
}
.task-input-glyph { font-size: 14px; color: #6B6F80; }
.task-input-text { color: #6B6F80; font-size: 13px; }
.task-list { display: flex; flex-direction: column; gap: 2px; }
.task {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 10px 16px;
  background: #15161F;
  border: 1px solid #2A2C3A;
  border-radius: 8px;
}
.task .checkbox {
  width: 18px; height: 18px;
  border: 1.5px solid #363849;
  border-radius: 5px;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
}
.task.done .checkbox {
  background: #7C7AED;
  border-color: #7C7AED;
}
.task.done .checkbox::after {
  content: '\\2713';
  color: #fff;
  font-size: 12px;
  font-weight: 700;
}
.task .name { font-size: 13px; color: #ECEDF3; flex: 1; }
.task.done .name { color: #6B6F80; text-decoration: line-through; }
.task .badge {
  font-size: 10px;
  font-weight: 600;
  color: #9CA0B0;
  background: #1A1B26;
  border: 1px solid #2A2C3A;
  padding: 2px 7px;
  border-radius: 999px;
}
.filter-bar {
  display: flex;
  gap: 4px;
  background: #1A1B26;
  border-radius: 8px;
  padding: 4px;
  align-self: flex-start;
}
.filter-bar .pill {
  font-size: 12px;
  padding: 6px 12px;
  border-radius: 6px;
  color: #9CA0B0;
  font-weight: 500;
}
.filter-bar .pill.active {
  background: #15161F;
  color: #ECEDF3;
  box-shadow: 0 1px 0 #2A2C3A inset;
}
.summary {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 12px;
  color: #6B6F80;
}
.summary .clear {
  color: #7C7AED;
  font-weight: 500;
  font-size: 12px;
}
.swatch-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(96px, 1fr)); gap: 10px; }
.swatch {
  display: flex;
  flex-direction: column;
  gap: 6px;
  font-size: 11px;
  color: #9CA0B0;
}
.swatch-chip {
  height: 56px;
  border-radius: 8px;
  border: 1px solid #2A2C3A;
}
.type-stack { display: flex; flex-direction: column; gap: 12px; }
.type-row { display: flex; flex-direction: column; gap: 2px; }
.flow-step {
  display: flex;
  gap: 14px;
  padding: 12px 0;
  border-bottom: 1px solid #1F212C;
}
.flow-step:last-child { border-bottom: none; }
.flow-step .num {
  width: 24px; height: 24px;
  border-radius: 999px;
  background: #272752;
  color: #A5A4F3;
  display: flex; align-items: center; justify-content: center;
  font-size: 12px;
  font-weight: 600;
  flex-shrink: 0;
}
.flow-step .body { display: flex; flex-direction: column; gap: 2px; }
.flow-step .body .step-title { font-size: 13px; color: #ECEDF3; font-weight: 500; }
.flow-step .body .step-desc { font-size: 12px; color: #6B6F80; line-height: 1.5; }
"""

func renderSettingsAppearanceHtml(): string =
  """
<section class="card">
  <div class="group-title">Appearance</div>
  <div class="row">
    <div class="row-label">
      <div class="row-title">Dark mode</div>
      <div class="row-hint">Use the system preference at startup, then remember the choice</div>
    </div>
    <div class="toggle on"></div>
  </div>
  <div class="row">
    <div class="row-label">
      <div class="row-title">Theme</div>
      <div class="row-hint">Color scheme applied to the entire workspace</div>
    </div>
    <div class="choice">
      <span class="choice-pill active">Default</span>
      <span class="choice-pill">Solarized</span>
      <span class="choice-pill">Solar</span>
      <span class="choice-pill">Mono</span>
    </div>
  </div>
  <div class="row">
    <div class="row-label">
      <div class="row-title">Font size</div>
      <div class="row-hint">Editor body text, points</div>
    </div>
    <input class="number" value="14" />
  </div>
</section>
"""

func renderSettingsEditorHtml(): string =
  """
<section class="card">
  <div class="group-title">Editor</div>
  <div class="row">
    <div class="row-label">
      <div class="row-title">Tabs to spaces</div>
      <div class="row-hint">Convert tab keypresses to soft tabs on commit</div>
    </div>
    <div class="toggle on"></div>
  </div>
  <div class="row">
    <div class="row-label">
      <div class="row-title">Tab width</div>
      <div class="row-hint">Number of spaces per indent level</div>
    </div>
    <input class="number" value="2" />
  </div>
  <div class="row">
    <div class="row-label">
      <div class="row-title">Line endings</div>
      <div class="row-hint">End-of-line sequence written on save</div>
    </div>
    <div class="choice">
      <span class="choice-pill active">LF</span>
      <span class="choice-pill">CRLF</span>
    </div>
  </div>
</section>
"""

func renderSettingsNotificationsHtml(): string =
  """
<section class="card">
  <div class="group-title">Notifications</div>
  <div class="row">
    <div class="row-label">
      <div class="row-title">Email digest</div>
      <div class="row-hint">Daily roll-up of mentions and assigned issues</div>
    </div>
    <div class="toggle"></div>
  </div>
  <div class="row">
    <div class="row-label">
      <div class="row-title">Desktop alerts</div>
      <div class="row-hint">Pop a system notification for new mentions</div>
    </div>
    <div class="toggle on"></div>
  </div>
  <div class="row">
    <div class="row-label">
      <div class="row-title">Poll interval</div>
      <div class="row-hint">Milliseconds between server checks</div>
    </div>
    <input class="number" value="2000" />
  </div>
</section>
"""

func renderTaskInboxHtml(): string =
  """
<div class="task-input">
  <span class="task-input-glyph">+</span>
  <span class="task-input-text">Add a task and press Enter to save</span>
</div>
<div class="filter-bar">
  <span class="pill active">All</span>
  <span class="pill">Active</span>
  <span class="pill">Completed</span>
</div>
<div class="task-list">
  <div class="task">
    <div class="checkbox"></div>
    <div class="name">Review the new editor chrome screenshots</div>
    <span class="badge">today</span>
  </div>
  <div class="task done">
    <div class="checkbox"></div>
    <div class="name">Wire the M57 backend strip to the absolute left edge</div>
    <span class="badge">done</span>
  </div>
  <div class="task">
    <div class="checkbox"></div>
    <div class="name">Replace placeholder preview with a real settings card</div>
    <span class="badge">soon</span>
  </div>
</div>
<div class="summary">
  <span>2 active &middot; 1 completed</span>
  <span class="clear">Clear completed</span>
</div>
"""

func renderTokensHtml(title: string): string =
  let titleHtml = title
  """
<section class="card">
  <div class="group-title">""" & titleHtml & """</div>
  <div class="swatch-grid">
    <div class="swatch">
      <div class="swatch-chip" style="background: #0D0E14"></div>
      <span>Canvas</span>
      <span style="color:#4A4D5C">#0D0E14</span>
    </div>
    <div class="swatch">
      <div class="swatch-chip" style="background: #15161F"></div>
      <span>Surface</span>
      <span style="color:#4A4D5C">#15161F</span>
    </div>
    <div class="swatch">
      <div class="swatch-chip" style="background: #1A1B26"></div>
      <span>Raised</span>
      <span style="color:#4A4D5C">#1A1B26</span>
    </div>
    <div class="swatch">
      <div class="swatch-chip" style="background: #7C7AED"></div>
      <span>Accent</span>
      <span style="color:#4A4D5C">#7C7AED</span>
    </div>
    <div class="swatch">
      <div class="swatch-chip" style="background: #ECEDF3"></div>
      <span>Text</span>
      <span style="color:#4A4D5C">#ECEDF3</span>
    </div>
    <div class="swatch">
      <div class="swatch-chip" style="background: #2A2C3A"></div>
      <span>Divider</span>
      <span style="color:#4A4D5C">#2A2C3A</span>
    </div>
  </div>
</section>
"""

func renderTypographyHtml(): string =
  """
<section class="card">
  <div class="group-title">Typography</div>
  <div class="type-stack">
    <div class="type-row">
      <span style="font-size:22px;font-weight:600;letter-spacing:-0.01em;color:#ECEDF3">Display 22 / 600</span>
      <span style="font-size:11px;color:#6B6F80">Page hero · -apple-system, Inter</span>
    </div>
    <div class="type-row">
      <span style="font-size:16px;font-weight:600;color:#ECEDF3">Heading 16 / 600</span>
      <span style="font-size:11px;color:#6B6F80">Card title · system stack</span>
    </div>
    <div class="type-row">
      <span style="font-size:13px;color:#ECEDF3">Body 13 / 400</span>
      <span style="font-size:11px;color:#6B6F80">Default reading size</span>
    </div>
    <div class="type-row">
      <span style="font-size:11px;color:#9CA0B0;text-transform:uppercase;letter-spacing:0.08em">Eyebrow 11 / 600</span>
      <span style="font-size:11px;color:#6B6F80">Section caps, status badges</span>
    </div>
  </div>
</section>
"""

func renderFlowHtml(steps: openArray[(string, string)]): string =
  result = "<section class=\"card\"><div class=\"group-title\">Flow</div>"
  for i in 0 ..< steps.len:
    result.add "<div class=\"flow-step\"><div class=\"num\">"
    result.add $(i + 1)
    result.add "</div><div class=\"body\"><div class=\"step-title\">"
    result.add steps[i][0]
    result.add "</div><div class=\"step-desc\">"
    result.add steps[i][1]
    result.add "</div></div></div>"
  result.add "</section>"

func renderTaskComponentHtml(name: string): string =
  case name
  of "Empty":
    """
<div class="task-input">
  <span class="task-input-glyph">+</span>
  <span class="task-input-text">Add a task and press Enter to save</span>
</div>
"""
  of "With Draft":
    """
<div class="task-input">
  <span class="task-input-glyph">+</span>
  <span style="color:#ECEDF3;font-size:13px">buy milk</span>
</div>
"""
  of "All Selected":
    """
<div class="filter-bar">
  <span class="pill active">All</span>
  <span class="pill">Active</span>
  <span class="pill">Completed</span>
</div>
"""
  of "Active Selected":
    """
<div class="filter-bar">
  <span class="pill">All</span>
  <span class="pill active">Active</span>
  <span class="pill">Completed</span>
</div>
"""
  of "Completed Selected":
    """
<div class="filter-bar">
  <span class="pill">All</span>
  <span class="pill">Active</span>
  <span class="pill active">Completed</span>
</div>
"""
  of "Two Active":
    """
<div class="task-list">
  <div class="task"><div class="checkbox"></div><div class="name">Pick up groceries</div></div>
  <div class="task"><div class="checkbox"></div><div class="name">Reply to design feedback</div></div>
</div>
"""
  of "Mixed Completion":
    """
<div class="task-list">
  <div class="task"><div class="checkbox"></div><div class="name">Pick up groceries</div></div>
  <div class="task done"><div class="checkbox"></div><div class="name">Reply to design feedback</div></div>
</div>
"""
  of "Active Only":
    """
<div class="summary">
  <span>1 item left</span>
</div>
"""
  of "With Completed":
    """
<div class="summary">
  <span>1 item left</span>
  <span class="clear">Clear completed</span>
</div>
"""
  else:
    """
<div class="task-list">
  <div class="task"><div class="checkbox"></div><div class="name">Sample task row</div></div>
</div>
"""

func renderSettingsComponentHtml(group, name: string): string =
  if group == "Settings App / Group":
    case name
    of "Appearance": renderSettingsAppearanceHtml()
    of "Editor": renderSettingsEditorHtml()
    of "Notifications": renderSettingsNotificationsHtml()
    else: renderSettingsAppearanceHtml()
  elif group == "Settings App / ToggleItem":
    let state = (if name == "On": "on" else: "")
    """
<div class="card">
  <div class="row">
    <div class="row-label">
      <div class="row-title">Dark mode</div>
      <div class="row-hint">Use the system preference at startup</div>
    </div>
    <div class="toggle """ & state & """"></div>
  </div>
</div>
"""
  elif group == "Settings App / ChoiceItem":
    let active = (if name == "Alternate": 1 else: 0)
    let p0 = if active == 0: " active" else: ""
    let p1 = if active == 1: " active" else: ""
    """
<div class="card">
  <div class="row">
    <div class="row-label">
      <div class="row-title">Theme</div>
      <div class="row-hint">Color scheme applied to the entire workspace</div>
    </div>
    <div class="choice">
      <span class="choice-pill""" & p0 & """">Default</span>
      <span class="choice-pill""" & p1 & """">Solarized</span>
    </div>
  </div>
</div>
"""
  elif group == "Settings App / NumberItem":
    let value = (if name == "Clamped": "10" else: "14")
    """
<div class="card">
  <div class="row">
    <div class="row-label">
      <div class="row-title">Font size</div>
      <div class="row-hint">Editor body text, points</div>
    </div>
    <input class="number" value=""" & "\"" & value & "\"" & """ />
  </div>
</div>
"""
  else:
    """
<div class="card">
  <div class="group-title">""" & group & """</div>
  <div class="row">
    <div class="row-label">
      <div class="row-title">""" & name & """</div>
    </div>
  </div>
</div>
"""

proc renderPreviewContentHtml(item: StoryItem): string =
  ## Build the rich showcase HTML for an item. The output is a fragment
  ## (no <html>/<body>); `previewDocumentHtmlFor` wraps it.
  case item.kind
  of skPage:
    case item.group
    of "Task App / Pages":
      case item.name
      of "Inbox", "Today", "Completed": renderTaskInboxHtml()
      else: renderTaskInboxHtml()
    of "Settings App / Pages":
      case item.name
      of "Preferences":
        renderSettingsAppearanceHtml() & renderSettingsEditorHtml() &
          renderSettingsNotificationsHtml()
      of "Appearance Group": renderSettingsAppearanceHtml()
      of "Editor Group": renderSettingsEditorHtml()
      else: renderSettingsAppearanceHtml()
    else: renderTaskInboxHtml()
  of skComponent:
    if item.group.startsWith("Task App"):
      renderTaskComponentHtml(item.name)
    else:
      renderSettingsComponentHtml(item.group, item.name)
  of skPattern:
    """
<div class="card">
  <div class="group-title">""" & item.name & """</div>
  <div class="row">
    <div class="row-label">
      <div class="row-title">""" & item.description & """</div>
    </div>
  </div>
</div>
"""
  of skFoundation:
    if item.name == "Typography": renderTypographyHtml()
    else: renderTokensHtml(item.name)
  of skFlow:
    renderFlowHtml([(item.name, item.description)])
  of skGuideline:
    """
<div class="card">
  <div class="group-title">Guideline</div>
  <div class="row">
    <div class="row-label">
      <div class="row-title">""" & item.name & """</div>
      <div class="row-hint">""" & item.description & """</div>
    </div>
  </div>
</div>
"""
  of skVectorSymbol:
    """
<div class="card">
  <div class="group-title">Vector Symbol</div>
  <div class="row">
    <div class="row-label">
      <div class="row-title">""" & item.name & """</div>
      <div class="row-hint">""" & item.description & """</div>
    </div>
  </div>
</div>
"""

const tuiOverlayStyles = """
/* TUI backend overlay — monospace cell-grid look. The HTML structure
   is shared across backends; this stylesheet recasts every Web card /
   pill / row into ASCII-bordered terminal frames. */
body {
  background: #050606 !important;
  color: #C8FFCB !important;
  font-family: 'JetBrains Mono', Menlo, Consolas, 'Courier New', monospace !important;
  font-size: 13px !important;
  line-height: 1.4 !important;
  letter-spacing: 0 !important;
  padding: 20px !important;
}
.app { max-width: 720px !important; gap: 16px !important; }
.app-title, .app-subtitle, .row-title, .row-hint, .group-title,
.choice-pill, .number, .task .name, .task .badge, .summary, .summary .clear,
.flow-step .body .step-title, .flow-step .body .step-desc,
.task-input-text, .task-input-glyph, .swatch {
  font-family: inherit !important;
  letter-spacing: 0 !important;
}
.app-header {
  border-bottom: 1px dashed #1F4D2F !important;
  padding-bottom: 8px !important;
}
.app-title { color: #BFFFC1 !important; font-weight: 600 !important; }
.app-subtitle { color: #66996B !important; }
.card, .filter-bar, .task-input, .task {
  background: #0B0F0C !important;
  border: 1px solid #2E6B3C !important;
  border-radius: 0 !important;
  box-shadow: none !important;
  padding: 12px 14px !important;
}
.card::before {
  content: '+-- ' attr(class) ' --------------------------------+';
  display: block;
  color: #2E6B3C;
  font-size: 11px;
  margin-bottom: 8px;
  letter-spacing: 0;
  white-space: nowrap;
  overflow: hidden;
}
.group-title {
  color: #6BCC7A !important;
  text-transform: none !important;
  letter-spacing: 0 !important;
  margin-bottom: 6px !important;
}
.row {
  border-bottom: 1px dashed #1F4D2F !important;
  padding: 6px 0 !important;
}
.row::before {
  content: '| ';
  color: #2E6B3C;
  margin-right: 4px;
}
.row-title { color: #DAFFD4 !important; font-weight: 500 !important; }
.row-hint { color: #61996A !important; }
/* Toggle as text [ ] / [x]. */
.toggle {
  width: auto !important;
  height: auto !important;
  background: transparent !important;
  border-radius: 0 !important;
  color: #BFFFC1 !important;
  font-family: inherit !important;
}
.toggle::after { content: ''; background: none; position: static; width: 0; height: 0; }
.toggle::before {
  content: '[ ]';
  color: #6BCC7A;
}
.toggle.on::before { content: '[x]'; color: #BFFFC1; }
/* Choice pills as ( ) / (*). */
.choice { gap: 12px !important; }
.choice-pill {
  background: transparent !important;
  border: none !important;
  color: #66996B !important;
  padding: 0 !important;
  border-radius: 0 !important;
  font-weight: 500 !important;
}
.choice-pill::before {
  content: '( ) ';
  color: #2E6B3C;
}
.choice-pill.active {
  color: #BFFFC1 !important;
  background: transparent !important;
}
.choice-pill.active::before {
  content: '(*) ';
  color: #6BCC7A;
}
.number {
  background: #0B0F0C !important;
  border: 1px solid #2E6B3C !important;
  color: #BFFFC1 !important;
  border-radius: 0 !important;
  padding: 4px 8px !important;
  width: 64px !important;
}
.filter-bar { padding: 6px !important; gap: 0 !important; }
.filter-bar .pill {
  background: transparent !important;
  border-radius: 0 !important;
  color: #66996B !important;
}
.filter-bar .pill::before {
  content: '[ ';
  color: #2E6B3C;
}
.filter-bar .pill::after {
  content: ' ]';
  color: #2E6B3C;
}
.filter-bar .pill.active {
  color: #BFFFC1 !important;
  background: transparent !important;
  box-shadow: none !important;
}
.filter-bar .pill.active::before { content: '[*'; color: #6BCC7A; }
.filter-bar .pill.active::after { content: '*]'; color: #6BCC7A; }
.task .checkbox {
  width: auto !important; height: auto !important;
  border: none !important;
  background: transparent !important;
  border-radius: 0 !important;
}
.task .checkbox::before { content: '[ ]'; color: #6BCC7A; }
.task.done .checkbox { background: transparent !important; }
.task.done .checkbox::before { content: '[x]'; color: #BFFFC1; }
.task.done .checkbox::after { content: ''; }
.task-input-glyph::before { content: '> '; color: #6BCC7A; }
.task-input-glyph { color: transparent !important; }
.summary .clear, .flow-step .num {
  background: transparent !important;
  color: #6BCC7A !important;
  border-radius: 0 !important;
}
.flow-step { border-bottom: 1px dashed #1F4D2F !important; }
.backend-band {
  font-family: inherit;
  font-size: 11px;
  color: #2E6B3C;
  padding: 6px 0;
  letter-spacing: 0;
}
"""

const gpuiOverlayStyles = """
/* GPUI backend overlay — bright, tight, AppKit/Big Sur-ish vibe. */
body {
  background: #1A1B22 !important;
  color: #F0F1F5 !important;
  font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif !important;
  font-size: 13px !important;
  padding: 28px !important;
}
.card, .task-input, .task, .filter-bar {
  background: linear-gradient(180deg, #2B2E3A 0%, #232631 100%) !important;
  border: 1px solid #3A3D4A !important;
  border-radius: 12px !important;
  box-shadow: 0 1px 0 rgba(255,255,255,0.04) inset, 0 12px 28px rgba(0,0,0,0.32) !important;
}
.app-title { color: #FFFFFF !important; font-weight: 600 !important; }
.app-subtitle { color: #B5B9C9 !important; }
.row-title { font-weight: 500 !important; }
.toggle { box-shadow: 0 1px 2px rgba(0,0,0,0.5) inset !important; }
.toggle.on {
  background: linear-gradient(180deg, #3CB0FE 0%, #0079FF 100%) !important;
}
.choice-pill.active {
  background: linear-gradient(180deg, #3CB0FE 0%, #0079FF 100%) !important;
  border-color: #0066CC !important;
  color: #FFFFFF !important;
}
.number {
  background: #14151B !important;
  border-color: #3A3D4A !important;
  border-radius: 6px !important;
}
.backend-band {
  background: #14ACA1;
  color: #0E342F;
  font-weight: 600;
  font-size: 10px;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  padding: 4px 14px;
  display: inline-block;
  border-radius: 999px;
}
"""

const freyaOverlayStyles = """
/* Freya backend overlay — Material 3 card aesthetic. */
body {
  background: #F4F6FA !important;
  color: #1B1D29 !important;
  font-family: 'Roboto', 'Inter', -apple-system, system-ui, sans-serif !important;
  font-size: 14px !important;
  padding: 28px !important;
}
.app { gap: 20px !important; }
.app-header { padding-bottom: 12px !important; border-bottom: 1px solid #E0E3EC !important; }
.app-title { color: #1B1D29 !important; font-weight: 500 !important; }
.app-subtitle { color: #555867 !important; }
.card, .task-input, .task, .filter-bar {
  background: #FFFFFF !important;
  border: none !important;
  border-radius: 18px !important;
  box-shadow: 0 2px 6px rgba(20, 22, 34, 0.05), 0 0 0 1px #E2E5EE inset !important;
  padding: 18px 20px !important;
}
.group-title {
  color: #6E5BFF !important;
  text-transform: none !important;
  font-size: 13px !important;
  font-weight: 600 !important;
  letter-spacing: 0 !important;
}
.row { border-bottom: 1px solid #ECEFF7 !important; }
.row-title { color: #1B1D29 !important; font-weight: 500 !important; }
.row-hint { color: #5A5E6C !important; }
.toggle { background: #C8CBD8 !important; }
.toggle.on { background: #6E5BFF !important; }
.toggle::after { background: #FFFFFF !important; }
.choice-pill {
  background: transparent !important;
  border: 1px solid #C8CBD8 !important;
  color: #555867 !important;
}
.choice-pill.active {
  background: #EFEBFF !important;
  color: #4F3CD9 !important;
  border-color: #6E5BFF !important;
}
.number {
  background: #F4F6FA !important;
  border: 1px solid #C8CBD8 !important;
  color: #1B1D29 !important;
  border-radius: 8px !important;
}
.filter-bar { background: #EFF1F8 !important; }
.filter-bar .pill { color: #555867 !important; }
.filter-bar .pill.active {
  background: #FFFFFF !important;
  color: #4F3CD9 !important;
  box-shadow: 0 1px 3px rgba(20,22,34,0.08) !important;
}
.task { padding: 14px 18px !important; }
.task .name { color: #1B1D29 !important; }
.task .checkbox { border-color: #6E5BFF !important; }
.task.done .checkbox { background: #6E5BFF !important; border-color: #6E5BFF !important; }
.backend-band {
  background: #6E5BFF;
  color: #FFFFFF;
  font-weight: 600;
  font-size: 10px;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  padding: 4px 14px;
  display: inline-block;
  border-radius: 999px;
}
"""

const cocoaOverlayStyles = """
/* Cocoa backend overlay — AppKit / NSWindow vibrancy. */
body {
  background: linear-gradient(180deg, #2E3034 0%, #1A1C1F 100%) !important;
  color: #F2F2F7 !important;
  font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif !important;
  font-size: 13px !important;
  padding: 24px !important;
}
.card, .task-input, .task, .filter-bar {
  background: rgba(58, 60, 66, 0.65) !important;
  backdrop-filter: blur(40px);
  border: 1px solid rgba(255, 255, 255, 0.08) !important;
  border-radius: 10px !important;
  box-shadow: 0 0 0 0.5px rgba(255,255,255,0.04), 0 10px 24px rgba(0,0,0,0.4) !important;
}
.app-title { color: #FFFFFF !important; font-weight: 590 !important; letter-spacing: -0.01em !important; }
.app-subtitle { color: rgba(235, 235, 245, 0.6) !important; }
.row-title { color: #FFFFFF !important; font-weight: 510 !important; }
.row-hint { color: rgba(235, 235, 245, 0.55) !important; }
.toggle { background: rgba(120, 120, 128, 0.32) !important; }
.toggle.on { background: #30D158 !important; }
.choice-pill {
  background: rgba(120, 120, 128, 0.20) !important;
  border-color: rgba(255, 255, 255, 0.10) !important;
  color: rgba(235, 235, 245, 0.78) !important;
}
.choice-pill.active {
  background: #007AFF !important;
  border-color: #007AFF !important;
  color: #FFFFFF !important;
}
.filter-bar .pill.active { background: rgba(120, 120, 128, 0.32) !important; color: #FFFFFF !important; }
.number {
  background: rgba(118, 118, 128, 0.24) !important;
  border-color: rgba(255, 255, 255, 0.10) !important;
  color: #FFFFFF !important;
  border-radius: 6px !important;
}
.backend-band {
  background: rgba(0,122,255,0.85);
  color: #FFFFFF;
  font-weight: 600;
  font-size: 10px;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  padding: 4px 14px;
  display: inline-block;
  border-radius: 999px;
  backdrop-filter: blur(20px);
}
"""

const androidOverlayStyles = """
/* Android backend overlay — Material 3 dark theme tile. */
body {
  background: #16131B !important;
  color: #E6E0EC !important;
  font-family: 'Roboto', 'Inter', -apple-system, system-ui, sans-serif !important;
  font-size: 14px !important;
  padding: 22px !important;
}
.card, .task-input, .task, .filter-bar {
  background: #221E29 !important;
  border: none !important;
  border-radius: 20px !important;
  box-shadow: 0 1px 0 #2D2935 inset !important;
  padding: 18px 20px !important;
}
.app-title { color: #E6E0EC !important; font-weight: 500 !important; }
.app-subtitle { color: #CAC4D0 !important; }
.group-title {
  color: #D0BCFF !important;
  text-transform: none !important;
  letter-spacing: 0 !important;
}
.row-title { color: #E6E0EC !important; }
.row-hint { color: #CAC4D0 !important; }
.toggle { background: #49454F !important; }
.toggle.on { background: #D0BCFF !important; }
.toggle::after { background: #381E72 !important; }
.toggle.on::after { background: #FFFFFF !important; }
.choice-pill {
  background: transparent !important;
  border: 1px solid #79747E !important;
  color: #CAC4D0 !important;
  border-radius: 999px !important;
}
.choice-pill.active {
  background: #4F378B !important;
  border-color: #4F378B !important;
  color: #FFFFFF !important;
}
.number {
  background: #2B2730 !important;
  border-color: #49454F !important;
  color: #E6E0EC !important;
  border-radius: 8px !important;
}
.backend-band {
  background: #D0BCFF;
  color: #381E72;
  font-weight: 600;
  font-size: 10px;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  padding: 4px 14px;
  display: inline-block;
  border-radius: 999px;
}
"""

func backendOverlayStylesFor(platform: Platform): string =
  ## Per-backend CSS overlay layered on top of the shared base styles.
  ## Each non-Web backend gets a distinct visual signature so clicking a
  ## chip in the preview-pane top toolbar visibly changes the iframe.
  case platform
  of pbWeb: ""
  of pbTui: tuiOverlayStyles
  of pbGpui: gpuiOverlayStyles
  of pbFreya: freyaOverlayStyles
  of pbCocoa: cocoaOverlayStyles
  of pbAndroid: androidOverlayStyles

func backendBandLabel(platform: Platform): string =
  case platform
  of pbWeb: ""
  of pbTui: "TUI - monospace cell grid"
  of pbGpui: "GPUI - native macOS-style adapter"
  of pbFreya: "Freya - Material card adapter"
  of pbCocoa: "Cocoa - AppKit vibrancy"
  of pbAndroid: "Android - Material 3 dark"

func previewDocumentHtmlFor(item: StoryItem; title, body: string;
                            platform: Platform): string =
  let subtitle = if body.len > 0: body else: item.description
  result = "<!doctype html><html><head><meta charset=\"utf-8\"/><title>"
  result.add title
  result.add "</title><style>"
  result.add previewBaseStyles
  result.add "</style>"
  let overlay = backendOverlayStylesFor(platform)
  if overlay.len > 0:
    result.add "<style data-backend=\""
    result.add $platform
    result.add "\">"
    result.add overlay
    result.add "</style>"
  result.add "</head><body data-backend=\""
  result.add $platform
  result.add "\"><main class=\"app\" data-story=\""
  result.add item.group
  result.add "/"
  result.add item.name
  result.add "\">"
  let band = backendBandLabel(platform)
  if band.len > 0:
    result.add "<div class=\"backend-band\">"
    result.add band
    result.add "</div>"
  result.add "<header class=\"app-header\"><span class=\"app-title\">"
  result.add item.name
  result.add "</span><span class=\"app-subtitle\">"
  result.add subtitle
  result.add "</span></header>"
  result.add renderPreviewContentHtml(item)
  result.add "</main></body></html>"

proc demoPreviewHook*(story: StoryRef; platform: Platform): ProjectPreview =
  ## Project-owned preview hook for the demo editor. The `platform`
  ## argument carries the currently-selected `PreviewBackend`; the
  ## returned `documentHtml` is per-backend styled so clicking a chip
  ## in the preview-pane toolbar visibly changes the iframe.
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
  let html = previewDocumentHtmlFor(item, title, body, platform)
  ProjectPreview(
    status: ppsRendered,
    story: resolvedStory,
    title: title,
    bodyText: body,
    documentHtml: html,
    metadata: metadata)
