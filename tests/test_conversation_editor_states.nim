## The conversation app's editor states: each is the stand-in with
## parameters and a network profile, reaches its expected display state,
## and is reachable in the examples editor as a mounted page story.

import std/[strutils, unittest]

import isonim/editor/types
import conversation_app/editor_states
import editor/stories
import editor/workspace as demo_workspace
import ./helpers/conversation_drive

suite "conversation editor states":
  test "every state's ViewModel reaches its expected first-load state":
    for state in conversationEditorStates():
      let ctx = newFakeAsyncContext()
      ctx.install()
      let vm = newConversationVMFor(state)
      check vm.phase.value == LoadPhase.loading
      discard ctx.stepUntil(30_000, proc(): bool =
        vm.phase.value != LoadPhase.loading)
      checkpoint state.name
      check vm.phase.value == state.expected
      if state.expected == LoadPhase.ready:
        check vm.conversations.value.len ==
          min(state.params.conversationCount, vm.pageSize)
        discard ctx.stepUntil(60_000, proc(): bool =
          vm.readiness.has("conversations"))
        check vm.conversations.value.len == state.params.conversationCount
      vm.dispose()
      ctx.uninstall()

  test "the network profile shapes the first load, not the stand-in":
    var firsts: seq[int64]
    for name in ["Typical (instant)", "Typical (4G)", "Typical (slow 3G)"]:
      var state: ConversationEditorState
      check findConversationEditorState(name, state)
      let ctx = newFakeAsyncContext()
      ctx.install()
      let vm = newConversationVMFor(state)
      discard ctx.stepUntil(30_000, proc(): bool =
        vm.readiness.has("conversations:first"))
      firsts.add vm.readiness.firstAt("conversations")
      vm.dispose()
      ctx.uninstall()
    check firsts[0] < firsts[1]
    check firsts[1] < firsts[2]

  test "a prompt sent in the broken-reply state ends in the reply error":
    var state: ConversationEditorState
    check findConversationEditorState("Reply breaks off (4G)", state)
    let ctx = newFakeAsyncContext()
    ctx.install()
    defer: ctx.uninstall()
    let vm = newConversationVMFor(state)
    discard ctx.stepUntil(5000, proc(): bool = vm.phase.value == LoadPhase.ready)
    vm.setDraft("Plan my week")
    vm.send()
    discard ctx.stepUntil(10_000, proc(): bool =
      vm.replyPhase.value == ReplyPhase.failed)
    check vm.replyPhase.value == ReplyPhase.failed
    check "reset" in vm.replyError.value
    check vm.replyText.value.len > 0

  test "the editor catalog lists every state as a mounted page story":
    let ws = newDemoEditorWorkspace()
    var names: seq[string]
    for g in ws.storyGroups:
      if g.name == ConversationStoryGroup:
        check g.kind == skPage
        for item in g.items: names.add item.name
    check names.len == conversationEditorStates().len
    for state in conversationEditorStates():
      check state.name in names
      let preview = ws.previewHook(StoryRef(group: ConversationStoryGroup,
        name: state.name, kind: skPage), pbWeb)
      check preview.status == ppsRendered
      check "data-mounted-story=\"true\"" in preview.documentHtml
      check preview.metadata.sourceFile == ConversationAppViewsSource
