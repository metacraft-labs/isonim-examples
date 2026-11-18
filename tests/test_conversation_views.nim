## Tier-2 tests of the conversation View over `MockRenderer`: what the
## ViewModel's states look like, and that the controls drive it.
##
## The ViewModel runs over the stand-in services (so every control has a
## working operation behind it), on fake time.

import std/[strutils, tables, unittest]

import isonim/core/owner
import isonim/testing/mock_dom
import conversation_app/core/[views, standin, network_services]
import ./helpers/conversation_drive

proc byTestId(node: MockNode; id: string; acc: var seq[MockNode]) =
  if node.attributes.getOrDefault("data-testid") == id: acc.add node
  for child in node.children: byTestId(child, id, acc)

proc all(root: MockNode; id: string): seq[MockNode] =
  byTestId(root, id, result)

proc one(root: MockNode; id: string): MockNode =
  let found = root.all(id)
  doAssert found.len == 1, "expected one " & id & ", found " & $found.len
  found[0]

proc visible(node: MockNode): bool =
  var n = node
  while n != nil:
    if n.styles.getOrDefault("display") == "none": return false
    n = n.parent
  true

template mount(params: StandInParams; profile: NetworkProfile;
               body: untyped) =
  let ctx {.inject.} = newFakeAsyncContext()
  ctx.install()
  try:
    createRoot proc(dispose: proc()) =
      let vm {.inject.} = newConversationVM(
        newConversationStandIn(params).withNetwork(profile), pageSize = 4,
        backfillPageSize = 4)
      let root {.inject.} = renderConversationApp[MockRenderer, MockNode](
        MockRenderer(), vm)
      body
      dispose()
  finally:
    ctx.uninstall()

suite "conversation View":
  test "skeleton rows and bubbles while the first screen loads":
    mount(standInParams(conversationCount = 10), FourGNetwork):
      check root.all("conversation-skeleton").len == 4
      check root.all("message-skeleton").len == 3
      check root.all("conversation-row").len == 0
      discard ctx.stepUntil(2000, proc(): bool =
        vm.phase.value == LoadPhase.ready)
      check root.all("conversation-skeleton").len == 0
      check root.all("conversation-row").len >= 4
      check root.all("message").len == 6

  test "the backfill status counts down and disappears":
    mount(standInParams(conversationCount = 10), FourGNetwork):
      discard ctx.stepUntil(2000, proc(): bool =
        vm.phase.value == LoadPhase.ready)
      let status = root.one("backfill-status")
      check status.visible
      check "6 more" in status.textContent
      discard ctx.stepUntil(5000, proc(): bool = vm.remaining.val == 0)
      check not status.visible
      check root.all("conversation-row").len == 10

  test "the reply grows on screen with each increment, then joins the transcript":
    mount(standInParams(conversationCount = 2, replyText = "abcdefghijkl",
                        replyChunkRunes = 4, replyIntervalMs = 50),
          InstantNetwork):
      discard ctx.stepUntil(100, proc(): bool =
        vm.phase.value == LoadPhase.ready)
      let draft = root.one("draft")
      MockRenderer().setInputValue(draft, "tell me")
      draft.fireEvent("input")
      check vm.draft.value == "tell me"
      root.one("send").fireEvent("click")
      check root.one("typing").visible
      check root.one("stop").visible
      var seen: seq[string]
      for _ in 0 ..< 400:
        ctx.step(1)
        let shown = root.one("reply-text").textContent
        if shown.len > 0 and (seen.len == 0 or seen[^1] != shown):
          seen.add shown
        if vm.replyPhase.value == ReplyPhase.idle: break
      check seen == @["abcd", "abcdefgh"]
      check not root.one("streaming-reply").visible
      let messages = root.all("message")
      check messages[^1].textContent == "abcdefghijkl"
      check messages[^2].textContent == "tell me"

  test "clicking a row shows its transcript":
    mount(standInParams(conversationCount = 3), InstantNetwork):
      discard ctx.stepUntil(100, proc(): bool =
        vm.phase.value == LoadPhase.ready)
      let rows = root.all("conversation-row")
      let target = rows[2].attributes["data-conversation-id"]
      rows[2].fireEvent("click")
      check vm.selectedId.value == target
      check root.all("message-skeleton").len == 3
      ctx.step(5)
      check root.all("message").len == 6
      check root.all("conversation-row")[2].attributes.getOrDefault(
        "aria-current") == "true"

  test "an error state offers Retry":
    mount(standInParams(failing = {ServiceOp.initialScreen}), InstantNetwork):
      ctx.step(5)
      let error = root.one("load-error")
      check error.visible
      check "unavailable" in error.textContent
      root.one("retry").fireEvent("click")
      check vm.phase.value == LoadPhase.loading

  test "the empty state lets the user start a conversation":
    mount(standInParams(conversationCount = 0), InstantNetwork):
      ctx.step(5)
      check root.all("conversation-list-empty").len == 1
      check root.all("transcript-empty").len == 1
      root.one("new-conversation").fireEvent("click")
      ctx.step(5)
      check root.all("conversation-row").len == 1
      check root.all("transcript-empty").len == 0
