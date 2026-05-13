## test_editor_workspace — EX-M14 strong-integration test for the
## demo editor's workspace + story catalog.
##
## Asserts the demo-editor catalog covers both apps with real
## `StoryGroup` shapes, that every catalogued component points at a
## source file that actually exists on disk, that the workspace
## constructor wires the catalog + preview hook + read-only
## permissions correctly, and that the `previewHook` returns
## non-empty HTML for representative component stories from each
## app.
##
## No mocks: imports the real `editor/workspace.nim` and exercises
## the upstream `EditorWorkspace` and `ProjectPreview` types.

import std/[os, strutils, unittest, options]

import isonim/editor/types
import isonim/editor/streaming_preview

import editor/stories
import editor/workspace as demo_workspace

# Resolve `isonim-examples` repo root by walking up from this test file.
const RepoRoot = currentSourcePath().parentDir.parentDir

# ---------------------------------------------------------------------------
# Story catalog
# ---------------------------------------------------------------------------

suite "EX-M14: demoStoryGroups catalog":
  let groups = buildDemoStoryGroups()

  test "catalog is non-empty and spans both demo apps":
    check groups.len > 0
    var taskAppGroups = 0
    var settingsAppGroups = 0
    for g in groups:
      if g.name.startsWith("Task App"): inc taskAppGroups
      if g.name.startsWith("Settings App"): inc settingsAppGroups
    check taskAppGroups >= 4 # TaskInput, FilterBar, TaskList, SummaryBar
    check settingsAppGroups >= 4 # Group, ToggleItem, ChoiceItem, NumberItem

  test "every StoryKind value in catalog has at least one entry":
    var kinds: set[StoryKind]
    for tup in allStoryItems(groups):
      kinds.incl tup.item.kind
    # We must cover the six canonical kinds the catalog promises.
    check skFoundation in kinds
    check skComponent in kinds
    check skPattern in kinds
    check skPage in kinds
    check skFlow in kinds
    check skGuideline in kinds

  test "specific stories from both apps exist":
    var taskInputEmpty = false
    var filterBarAll = false
    var settingsGroupAppearance = false
    var settingsToggleOn = false
    var settingsChoiceDefault = false
    var settingsNumberClamped = false
    for tup in allStoryItems(groups):
      let key = tup.item.group & " / " & tup.item.name
      case key
      of "Task App / TaskInput / Empty": taskInputEmpty = true
      of "Task App / FilterBar / All Selected": filterBarAll = true
      of "Settings App / Group / Appearance": settingsGroupAppearance = true
      of "Settings App / ToggleItem / On": settingsToggleOn = true
      of "Settings App / ChoiceItem / Default": settingsChoiceDefault = true
      of "Settings App / NumberItem / Clamped": settingsNumberClamped = true
      else: discard
    check taskInputEmpty
    check filterBarAll
    check settingsGroupAppearance
    check settingsToggleOn
    check settingsChoiceDefault
    check settingsNumberClamped

  test "every component story's source path exists on disk":
    var checked = 0
    for tup in allStoryItems(groups):
      if tup.item.kind == skComponent:
        let path = sourceFileFor(tup.item.group, tup.item.name, tup.item.kind)
        check path.len > 0
        let abs = RepoRoot / path
        check fileExists(abs)
        inc checked
    check checked >= 6 # task_app + settings_app components

  test "canvas items are produced for pages":
    let canvas = demoCanvasItems(groups)
    var pageCount = 0
    for tup in allStoryItems(groups):
      if tup.item.kind == skPage: inc pageCount
    check canvas.len == pageCount
    check canvas.len >= 4

  test "flow steps reference real pages":
    let flow = demoFlowSteps(groups)
    check flow.len >= 4
    for step in flow:
      check step.screenRef.kind == skPage
      check step.action.len > 0
      check step.description.len > 0

# ---------------------------------------------------------------------------
# Editor workspace
# ---------------------------------------------------------------------------

suite "EX-M14: newDemoEditorWorkspace":
  test "workspace defaults to pbWeb with read-only permissions":
    let ws = newDemoEditorWorkspace()
    check ws.platform == pbWeb
    check ws.title == DemoEditorTitle
    check ws.id == DemoEditorId
    check ws.permissions.readSource
    check not ws.permissions.writeSource
    check not ws.permissions.createStory
    check not ws.permissions.duplicate

  test "workspace catalogues both demo apps":
    let ws = newDemoEditorWorkspace()
    var hasTaskApp = false
    var hasSettingsApp = false
    for g in ws.storyGroups:
      if g.name.startsWith("Task App"): hasTaskApp = true
      if g.name.startsWith("Settings App"): hasSettingsApp = true
    check hasTaskApp
    check hasSettingsApp

  test "previewHook returns non-empty HTML for representative stories":
    let ws = newDemoEditorWorkspace()
    let taskInput = StoryRef(group: "Task App / TaskInput", name: "Empty",
      kind: skComponent)
    let settingsGroup = StoryRef(group: "Settings App / Group",
      name: "Appearance", kind: skComponent)
    let webTask = ws.previewHook(taskInput, pbWeb)
    let webSettings = ws.previewHook(settingsGroup, pbWeb)
    check webTask.status == ppsRendered
    check webSettings.status == ppsRendered
    check webTask.documentHtml.len > 0
    check webSettings.documentHtml.len > 0
    check "<h1>" in webTask.documentHtml
    check "<h1>" in webSettings.documentHtml
    check "Task App / TaskInput / Empty" in webTask.documentHtml
    check "Settings App / Group / Appearance" in webSettings.documentHtml
    # metadata's source file should match the catalog's mapping
    check webTask.metadata.sourceFile == TaskAppViewsSource
    check webSettings.metadata.sourceFile == SettingsAppGroupSource

  test "previewHook reports backend in body across backends":
    let ws = newDemoEditorWorkspace()
    let story = StoryRef(group: "Task App / TaskList", name: "Two Active",
      kind: skComponent)
    let backends = [pbWeb, pbTui, pbGpui, pbFreya]
    var seen: seq[string]
    for b in backends:
      let p = ws.previewHook(story, b)
      check p.status == ppsRendered
      check p.bodyText.len > 0
      seen.add p.bodyText
    # at least the web vs tui/gpui/freya bodies should differ — the body
    # text embeds the backend label
    check seen[0] != seen[1]

  test "previewHook on an unknown story returns ppsUnsupportedStory":
    let ws = newDemoEditorWorkspace()
    let bogus = StoryRef(group: "Made Up Group", name: "Nope",
      kind: skComponent)
    let p = ws.previewHook(bogus, pbWeb)
    check p.status == ppsUnsupportedStory

# ---------------------------------------------------------------------------
# BackendBinaryRegistry
# ---------------------------------------------------------------------------

suite "EX-M14: newDemoBackendRegistry":
  test "registers exactly Web / TUI / GPUI / Freya plus host-specific extras":
    let reg = newDemoBackendRegistry("/tmp/isonim-examples-build")
    check reg.binaryFor(pbWeb).isSome
    check reg.binaryFor(pbTui).isSome
    check reg.binaryFor(pbGpui).isSome
    check reg.binaryFor(pbFreya).isSome
    when defined(macosx):
      check reg.binaryFor(pbCocoa).isSome
    else:
      check reg.binaryFor(pbCocoa).isNone
    when defined(macosx) or defined(linux):
      check reg.binaryFor(pbAndroid).isSome
    else:
      check reg.binaryFor(pbAndroid).isNone

  test "registered paths use the build directory":
    let reg = newDemoBackendRegistry("/tmp/isonim-examples-build")
    let webPath = reg.binaryFor(pbWeb).get()
    let tuiPath = reg.binaryFor(pbTui).get()
    let gpuiPath = reg.binaryFor(pbGpui).get()
    let freyaPath = reg.binaryFor(pbFreya).get()
    check webPath == "/tmp/isonim-examples-build/isonim-examples-web"
    check tuiPath == "/tmp/isonim-examples-build/isonim-examples-tui"
    check gpuiPath == "/tmp/isonim-examples-build/isonim-examples-gpui"
    check freyaPath == "/tmp/isonim-examples-build/isonim-examples-freya"
