## The conversation stand-in implements every operation, keeps state where
## the product does, and fails exactly the operations its parameters name.

import std/[strutils, unittest]

import conversation_app/core/standin
import ./helpers/conversation_drive

proc await[T](ctx: FakeAsyncContext; f: PlatformFuture[T]): (bool, T, string) =
  var done = false
  var value: T
  var error = ""
  proc ok(v: T) =
    done = true
    value = v
  proc failed(m: string) =
    done = true
    error = m
  f.onComplete(ok, failed)
  discard ctx.stepUntil(1000, proc(): bool = done)
  (done, value, error)

proc collect(ctx: FakeAsyncContext; s: ServiceStream[string]):
    (seq[string], bool, string) =
  var chunks: seq[string]
  var finished = false
  var error = ""
  proc onChunk(c: string) = chunks.add(c)
  proc onDone() = finished = true
  proc onError(m: string) = error = m
  discard s.subscribe(onChunk, onDone, onError)
  discard ctx.stepUntil(5000, proc(): bool = finished or error.len > 0)
  (chunks, finished, error)

template withFakeTime(body: untyped) =
  let ctx {.inject.} = newFakeAsyncContext()
  ctx.install()
  try:
    body
  finally:
    ctx.uninstall()

suite "conversation stand-in":
  test "the fixture follows the parameters":
    withFakeTime:
      let s = newConversationStandIn(standInParams(conversationCount = 25,
        messagesPerConversation = 4))
      let (ok, screen, err) = ctx.await(s.loadInitialScreen(10))
      check ok and err == ""
      check screen.conversations.total == 25
      check screen.conversations.items.len == 10
      check screen.transcript.len == 4
      let (_, page, _) = ctx.await(s.loadConversations(20, 10))
      check page.items.len == 5

  test "a sent prompt and its reply are in the next transcript read":
    withFakeTime:
      let s = newConversationStandIn(standInParams(conversationCount = 2,
        replyText = "Sure thing.", replyChunkRunes = 3, replyIntervalMs = 10))
      let (_, screen, _) = ctx.await(s.loadInitialScreen(5))
      let id = screen.conversations.items[0].id
      let (chunks, finished, _) = ctx.collect(s.sendPrompt(id, "Can you?"))
      check finished
      check chunks.join("") == "Sure thing."
      check chunks.len == 4
      let (_, messages, _) = ctx.await(s.loadTranscript(id))
      check messages[^2].text == "Can you?"
      check messages[^1].text == "Sure thing."
      let (_, created, _) = ctx.await(s.createConversation("Fresh"))
      let (_, after, _) = ctx.await(s.loadInitialScreen(5))
      check after.conversations.items[0].id == created.id
      check after.conversations.total == 3

  test "the failure switches fail exactly the named operations":
    withFakeTime:
      let s = newConversationStandIn(standInParams(
        failing = {ServiceOp.transcript, ServiceOp.send},
        failure = "down for maintenance"))
      let (_, screen, err) = ctx.await(s.loadInitialScreen(5))
      check err == ""
      let id = screen.conversations.items[0].id
      check ctx.await(s.loadTranscript(id))[2] == "down for maintenance"
      check ctx.collect(s.sendPrompt(id, "x"))[2] == "down for maintenance"
      check ctx.await(s.createConversation("ok"))[2] == ""

  test "a reply can break off after some increments":
    withFakeTime:
      let s = newConversationStandIn(standInParams(replyText = "abcdefgh",
        replyChunkRunes = 2, failReplyAfterChunks = 2, failure = "reset"))
      let (_, screen, _) = ctx.await(s.loadInitialScreen(5))
      let (chunks, finished, err) = ctx.collect(
        s.sendPrompt(screen.conversations.items[0].id, "go"))
      check chunks == @["ab", "cd"]
      check not finished
      check err == "reset"
