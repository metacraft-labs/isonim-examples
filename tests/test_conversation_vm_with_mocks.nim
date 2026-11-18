## Tier-1 unit tests of the conversation ViewModel over a mock of its
## services.
##
## The mock records every call and answers only when the test says so, so
## each test walks the ViewModel through one sequence of events and checks
## its state in between: placeholders before the first response, the batched
## first screen, backfill page by page, a reply rendered increment by
## increment, cancellation, failures, and the readiness marks.

import std/[strutils, unittest]

import isonim/services/deferred
import conversation_app/core/vm
import ./helpers/conversation_drive

type
  MockServices = ref object
    calls: seq[string]
    initial: seq[Deferred[InitialScreen]]
    pages: seq[Deferred[ConversationPage]]
    transcripts: seq[Deferred[seq[Message]]]
    creates: seq[Deferred[ConversationSummary]]
    replies: seq[StreamEmitter[string]]
    replyCancelled: int

proc services(m: MockServices): ConversationServices =
  ConversationServices(
    loadInitialScreen: proc(pageSize: int): PlatformFuture[InitialScreen] =
      m.calls.add "initial " & $pageSize
      let d = newDeferred[InitialScreen]()
      m.initial.add d
      d.future,
    loadConversations: proc(offset, limit: int): PlatformFuture[ConversationPage] =
      m.calls.add "page " & $offset & " " & $limit
      let d = newDeferred[ConversationPage]()
      m.pages.add d
      d.future,
    loadTranscript: proc(id: string): PlatformFuture[seq[Message]] =
      m.calls.add "transcript " & id
      let d = newDeferred[seq[Message]]()
      m.transcripts.add d
      d.future,
    createConversation: proc(title: string): PlatformFuture[ConversationSummary] =
      m.calls.add "create " & title
      let d = newDeferred[ConversationSummary]()
      m.creates.add d
      d.future,
    sendPrompt: proc(id, text: string): ServiceStream[string] =
      m.calls.add "send " & id & " " & text
      newServiceStream[string](proc(e: StreamEmitter[string]) =
        m.replies.add e
        e.onCancel(proc() = inc m.replyCancelled)))

proc summaries(first, count: int): seq[ConversationSummary] =
  for i in first ..< first + count:
    result.add ConversationSummary(id: "c" & $i, title: "Conversation " & $i)

proc screen(total, pageSize: int): InitialScreen =
  InitialScreen(
    conversations: ConversationPage(items: summaries(0, min(total, pageSize)),
      total: total),
    transcript: @[Message(id: 1, role: Role.user, text: "hello"),
                  Message(id: 2, role: Role.assistant, text: "hi")])

template withFakeTime(body: untyped) =
  let ctx {.inject.} = newFakeAsyncContext()
  ctx.install()
  try:
    body
  finally:
    ctx.uninstall()

suite "ConversationVM over mocks":
  test "placeholders until the batched first screen arrives":
    withFakeTime:
      let m = MockServices()
      let vm = newConversationVM(m.services, pageSize = 3)
      check m.calls == @["initial 3"]
      check vm.phase.value == LoadPhase.loading
      check vm.placeholderRows.val == 3
      ctx.step(40)
      m.initial[0].resolve(screen(3, 3))
      ctx.step(1)
      check vm.phase.value == LoadPhase.ready
      check vm.placeholderRows.val == 0
      check vm.conversations.value.len == 3
      check vm.selectedId.value == "c0"
      check vm.transcript.value.len == 2
      # One call carried both the list and the transcript.
      check m.calls == @["initial 3"]
      check vm.readiness.firstAt("conversations") == 40
      check vm.readiness.completeAt("transcript") == 40
      # Nothing left to backfill: the list is complete with the first screen.
      check vm.readiness.completeAt("conversations") == 40

  test "the rest of the list is backfilled page by page":
    withFakeTime:
      let m = MockServices()
      let vm = newConversationVM(m.services, pageSize = 2,
                                 backfillPageSize = 3)
      m.initial[0].resolve(screen(7, 2))
      ctx.step(1)
      check vm.conversations.value.len == 2
      check vm.remaining.val == 5
      check vm.backfilling.value
      check m.calls[^1] == "page 2 3"
      check not vm.readiness.has("conversations")
      ctx.step(10)
      m.pages[0].resolve(ConversationPage(items: summaries(2, 3), offset: 2,
                                          total: 7))
      ctx.step(1)
      check vm.conversations.value.len == 5
      check m.calls[^1] == "page 5 3"
      ctx.step(10)
      m.pages[1].resolve(ConversationPage(items: summaries(5, 2), offset: 5,
                                          total: 7))
      ctx.step(1)
      check vm.conversations.value.len == 7
      check vm.remaining.val == 0
      check not vm.backfilling.value
      check vm.readiness.firstAt("conversations") == 0
      check vm.readiness.completeAt("conversations") == 22
      check m.pages.len == 2

  test "a reply renders increment by increment and then joins the transcript":
    withFakeTime:
      let m = MockServices()
      let vm = newConversationVM(m.services)
      m.initial[0].resolve(screen(1, 20))
      ctx.step(1)
      check not vm.canSend.val
      vm.setDraft("  plan my week ")
      check vm.canSend.val
      vm.send()
      check m.calls[^1] == "send c0 plan my week"
      check vm.draft.value == ""
      check vm.replyPhase.value == ReplyPhase.waiting
      check vm.transcript.value[^1].text == "plan my week"
      check vm.conversations.value[0].messageCount == 3
      ctx.step(30)
      m.replies[0].emit("Mon")
      check vm.replyPhase.value == ReplyPhase.streaming
      check vm.replyText.value == "Mon"
      check vm.replyReadiness.firstAt("reply") == 30
      ctx.step(20)
      m.replies[0].emit("day: rest")
      check vm.replyText.value == "Monday: rest"
      check not vm.canSend.val
      m.replies[0].finish()
      check vm.replyPhase.value == ReplyPhase.idle
      check vm.replyText.value == ""
      check vm.transcript.value[^1].role == Role.assistant
      check vm.transcript.value[^1].text == "Monday: rest"
      check vm.replyReadiness.completeAt("reply") == 50
      check vm.conversations.value[0].preview == "Monday: rest"

  test "stop cancels the stream at the service and discards the partial reply":
    withFakeTime:
      let m = MockServices()
      let vm = newConversationVM(m.services)
      m.initial[0].resolve(screen(1, 20))
      ctx.step(1)
      vm.setDraft("long answer please")
      vm.send()
      m.replies[0].emit("Part one")
      vm.cancelReply()
      check m.replyCancelled == 1
      check vm.replyPhase.value == ReplyPhase.idle
      check vm.replyText.value == ""
      m.replies[0].emit(" part two")
      check vm.replyText.value == ""
      check vm.transcript.value[^1].role == Role.user

  test "a broken reply keeps what arrived and reports the error":
    withFakeTime:
      let m = MockServices()
      let vm = newConversationVM(m.services)
      m.initial[0].resolve(screen(1, 20))
      ctx.step(1)
      vm.setDraft("hi")
      vm.send()
      m.replies[0].emit("Hal")
      m.replies[0].fail("connection reset")
      check vm.replyPhase.value == ReplyPhase.failed
      check vm.replyText.value == "Hal"
      check "connection reset" in vm.replyError.value
      vm.dismissReplyError()
      check vm.replyPhase.value == ReplyPhase.idle

  test "selecting another conversation loads its transcript and cancels a reply":
    withFakeTime:
      let m = MockServices()
      let vm = newConversationVM(m.services)
      m.initial[0].resolve(screen(3, 20))
      ctx.step(1)
      vm.setDraft("question")
      vm.send()
      vm.select("c2")
      check m.replyCancelled == 1
      check m.calls[^1] == "transcript c2"
      check vm.transcriptLoading.value
      check vm.transcript.value.len == 0
      m.transcripts[0].resolve(@[Message(id: 9, role: Role.user, text: "x")])
      ctx.step(1)
      check not vm.transcriptLoading.value
      check vm.transcript.value.len == 1

  test "a failing first screen shows the error and Retry loads again":
    withFakeTime:
      let m = MockServices()
      let vm = newConversationVM(m.services)
      m.initial[0].reject("service unavailable")
      ctx.step(1)
      check vm.phase.value == LoadPhase.failed
      check vm.loadError.value == "service unavailable"
      check vm.placeholderRows.val == 0
      vm.load()
      check vm.phase.value == LoadPhase.loading
      check m.initial.len == 2
      m.initial[1].resolve(screen(1, 20))
      ctx.step(1)
      check vm.phase.value == LoadPhase.ready

  test "a response to an earlier load is ignored":
    withFakeTime:
      let m = MockServices()
      let vm = newConversationVM(m.services)
      vm.load()
      m.initial[1].resolve(screen(2, 20))
      ctx.step(1)
      m.initial[0].resolve(screen(9, 20))
      ctx.step(1)
      check vm.conversations.value.len == 2

  test "a new conversation goes to the top and is selected":
    withFakeTime:
      let m = MockServices()
      let vm = newConversationVM(m.services)
      m.initial[0].resolve(InitialScreen())
      ctx.step(1)
      check vm.conversations.value.len == 0
      check not vm.canSend.val
      vm.newConversation("Ideas")
      m.creates[0].resolve(ConversationSummary(id: "n1", title: "Ideas"))
      ctx.step(1)
      check vm.conversations.value[0].id == "n1"
      check vm.selectedId.value == "n1"
      vm.setDraft("first prompt")
      check vm.canSend.val
