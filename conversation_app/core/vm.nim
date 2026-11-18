## conversation_app/core/vm.nim — the conversation app's ViewModel.
##
## The ViewModel holds the screen's state as signals and reaches the outside
## world only through the `ConversationServices` it is given (see
## `services.nim` for which implementation runs where). It never sleeps,
## never builds fixture data and never knows whether a network is simulated.
##
## How it keeps the screen useful while data is on its way:
##
## - *Placeholders.* Until the first response, `phase` is `loading` and the
##   View draws skeleton rows (`placeholderRows`); while a transcript loads it
##   draws skeleton bubbles; after a prompt is sent and before the first
##   increment of the reply, `replyPhase` is `waiting` and the View shows a
##   typing indicator.
## - *Batching.* The first screen comes from one call, `loadInitialScreen`,
##   which returns the first page of the list and the first conversation's
##   transcript together: one round trip before both can show, not two.
## - *Initial screen first, then backfill.* Only `pageSize` conversations
##   are requested up front; the rest of the list is fetched afterwards in
##   pages of `backfillPageSize` while the user can already read and type.
## - *Streaming.* The reply to a prompt is a stream; `replyText` grows with
##   each increment and the View shows it as it grows. `cancelReply` stops it.
## - *Readiness marks.* `readiness` records, per load, when the conversation
##   list and the transcript first show real data and when they are
##   complete; `replyReadiness` does the same for each reply. Tests, the
##   editor and measurement tools read them.

import std/strutils

import isonim/viewmodel
import isonim/core/[signals, computation, batch]
import isonim/services/readiness

import ./services

export services, readiness, viewmodel, signals, computation

type
  LoadPhase* {.pure.} = enum
    loading, ready, failed

  ReplyPhase* {.pure.} = enum
    idle      ## No reply in progress.
    waiting   ## Prompt sent, no increment yet.
    streaming ## Increments arriving.
    failed    ## The reply broke off; `replyError` says why.

  ConversationVM* = ref object of ViewModel
    services: ConversationServices
    pageSize*: int
    backfillPageSize*: int
    readiness*: ReadinessMarks       ## Elements "conversations" and "transcript".
    replyReadiness*: ReadinessMarks  ## Element "reply", one load per prompt.

    phase*: Signal[LoadPhase]
    loadError*: Signal[string]
    conversations*: Signal[seq[ConversationSummary]]
    totalConversations*: Signal[int]
    backfilling*: Signal[bool]
    selectedId*: Signal[string]
    transcriptLoading*: Signal[bool]
    transcript*: Signal[seq[Message]]
    transcriptError*: Signal[string]
    draft*: Signal[string]
    replyPhase*: Signal[ReplyPhase]
    replyText*: Signal[string]
    replyError*: Signal[string]

    placeholderRows*: Memo[int]   ## Skeleton rows the list shows now.
    remaining*: Memo[int]         ## Conversations not yet in the list.
    canSend*: Memo[bool]

    loadGeneration: int
    transcriptGeneration: int
    reply: StreamSubscription

const
  DefaultPageSize* = 20
  DefaultBackfillPageSize* = 50

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

proc selectedIndex(vm: ConversationVM): int =
  let id = vm.selectedId.value
  for i, c in vm.conversations.value:
    if c.id == id: return i
  -1

proc refreshSelectedSummary(vm: ConversationVM) =
  ## Keep the list row of the selected conversation in step with its
  ## transcript (count and preview), as the next list read would.
  let i = vm.selectedIndex
  if i < 0: return
  var rows = vm.conversations.value
  let msgs = vm.transcript.value
  rows[i].messageCount = msgs.len
  rows[i].preview = (if msgs.len > 0: previewOf(msgs[^1].text) else: "")
  vm.conversations.val = rows

proc stopReply(vm: ConversationVM) =
  if vm.reply != nil:
    vm.reply.cancel()
    vm.reply = nil
  vm.replyText.val = ""
  vm.replyError.val = ""
  vm.replyPhase.val = ReplyPhase.idle

proc backfill(vm: ConversationVM; generation: int) =
  ## Fetch the next page after what the list holds, until it is complete.
  if generation != vm.loadGeneration: return
  let have = vm.conversations.value.len
  if have >= vm.totalConversations.value:
    vm.backfilling.val = false
    vm.readiness.markComplete("conversations")
    return
  vm.backfilling.val = true

  proc arrived(page: ConversationPage) =
    if generation != vm.loadGeneration: return
    var rows = vm.conversations.value
    # Only rows not already present: a conversation created meanwhile
    # shifts the server's offsets by one.
    for item in page.items:
      var known = false
      for r in rows:
        if r.id == item.id:
          known = true
          break
      if not known: rows.add item
    let total = if page.items.len == 0: rows.len else: max(page.total, rows.len)
    batch proc() =
      vm.conversations.val = rows
      vm.totalConversations.val = total
    vm.backfill(generation)

  proc failed(message: string) =
    if generation != vm.loadGeneration: return
    # The first screen is already usable; a failed backfill leaves the
    # list short, which `remaining` shows.
    vm.backfilling.val = false

  vm.services.loadConversations(have, vm.backfillPageSize).onComplete(
    arrived, failed)

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

proc load*(vm: ConversationVM) =
  ## Load the first screen (one batched call), then backfill the list.
  ## Calling it again (Retry) starts a new load; responses to an older load
  ## are ignored.
  inc vm.loadGeneration
  let generation = vm.loadGeneration
  vm.stopReply()
  vm.readiness.beginLoad()
  batch proc() =
    vm.phase.val = LoadPhase.loading
    vm.loadError.val = ""
    vm.backfilling.val = false

  proc arrived(screen: InitialScreen) =
    if generation != vm.loadGeneration: return
    let items = screen.conversations.items
    batch proc() =
      vm.conversations.val = items
      vm.totalConversations.val = screen.conversations.total
      vm.selectedId.val = (if items.len > 0: items[0].id else: "")
      vm.transcript.val = screen.transcript
      vm.transcriptLoading.val = false
      vm.transcriptError.val = ""
      vm.phase.val = LoadPhase.ready
    vm.readiness.markFirst("conversations")
    vm.readiness.markComplete("transcript")
    vm.backfill(generation)

  proc failed(message: string) =
    if generation != vm.loadGeneration: return
    batch proc() =
      vm.loadError.val = message
      vm.phase.val = LoadPhase.failed

  vm.services.loadInitialScreen(vm.pageSize).onComplete(arrived, failed)

proc select*(vm: ConversationVM; conversationId: string) =
  ## Show another conversation. A reply still streaming is cancelled.
  if conversationId == vm.selectedId.value and
      not vm.transcriptLoading.value: return
  vm.stopReply()
  inc vm.transcriptGeneration
  let generation = vm.transcriptGeneration
  batch proc() =
    vm.selectedId.val = conversationId
    vm.transcript.val = @[]
    vm.transcriptError.val = ""
    vm.transcriptLoading.val = true

  proc arrived(messages: seq[Message]) =
    if generation != vm.transcriptGeneration: return
    batch proc() =
      vm.transcript.val = messages
      vm.transcriptLoading.val = false

  proc failed(message: string) =
    if generation != vm.transcriptGeneration: return
    batch proc() =
      vm.transcriptError.val = message
      vm.transcriptLoading.val = false

  vm.services.loadTranscript(conversationId).onComplete(arrived, failed)

proc setDraft*(vm: ConversationVM; text: string) =
  vm.draft.val = text

proc send*(vm: ConversationVM) =
  ## Send the draft as a prompt and stream the reply into `replyText`. When
  ## the reply is complete it joins the transcript.
  if not untrack(proc(): bool = vm.canSend.val): return
  let text = vm.draft.value.strip
  let conversationId = vm.selectedId.value
  let sentIn = vm.transcriptGeneration
  var shown = vm.transcript.value
  shown.add Message(id: -(shown.len + 1), role: Role.user, text: text)
  vm.replyReadiness.beginLoad()
  batch proc() =
    vm.draft.val = ""
    vm.transcript.val = shown
    vm.replyText.val = ""
    vm.replyError.val = ""
    vm.replyPhase.val = ReplyPhase.waiting
  vm.refreshSelectedSummary()

  proc chunkArrived(chunk: string) =
    if sentIn != vm.transcriptGeneration: return
    batch proc() =
      vm.replyText.val = vm.replyText.value & chunk
      vm.replyPhase.val = ReplyPhase.streaming
    vm.replyReadiness.markFirst("reply")

  proc done() =
    if sentIn != vm.transcriptGeneration: return
    vm.reply = nil
    var msgs = vm.transcript.value
    msgs.add Message(id: -(msgs.len + 1), role: Role.assistant,
      text: vm.replyText.value)
    batch proc() =
      vm.transcript.val = msgs
      vm.replyText.val = ""
      vm.replyPhase.val = ReplyPhase.idle
    vm.refreshSelectedSummary()
    vm.replyReadiness.markComplete("reply")

  proc failed(message: string) =
    if sentIn != vm.transcriptGeneration: return
    vm.reply = nil
    batch proc() =
      vm.replyError.val = message
      vm.replyPhase.val = ReplyPhase.failed

  vm.reply = vm.services.sendPrompt(conversationId, text).subscribe(
    chunkArrived, done, failed)

proc cancelReply*(vm: ConversationVM) =
  ## Stop the reply being streamed; what arrived so far is discarded, as the
  ## service does not record a cancelled reply.
  vm.stopReply()

proc dismissReplyError*(vm: ConversationVM) =
  vm.stopReply()

proc newConversation*(vm: ConversationVM; title = "") =
  ## Create a conversation and show it at the top of the list.
  proc created(summary: ConversationSummary) =
    vm.stopReply()
    inc vm.transcriptGeneration
    var rows = vm.conversations.value
    rows.insert(summary, 0)
    batch proc() =
      vm.conversations.val = rows
      vm.totalConversations.val = vm.totalConversations.value + 1
      vm.selectedId.val = summary.id
      vm.transcript.val = @[]
      vm.transcriptLoading.val = false
      vm.transcriptError.val = ""
      vm.phase.val = LoadPhase.ready

  proc failed(message: string) =
    vm.loadError.val = message

  vm.services.createConversation(title).onComplete(created, failed)

# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

proc newConversationVM*(services: ConversationServices;
                        pageSize = DefaultPageSize;
                        backfillPageSize = DefaultBackfillPageSize;
                        autoLoad = true): ConversationVM =
  ## A ViewModel over `services`. With `autoLoad` it starts loading the
  ## first screen at once.
  result = withViewModel proc(dispose: proc()): ConversationVM =
    let vm = ConversationVM(
      services: services,
      pageSize: pageSize,
      backfillPageSize: backfillPageSize,
      readiness: newReadinessMarks("conversation:"),
      replyReadiness: newReadinessMarks("conversation:"),
      phase: createSignal(LoadPhase.loading),
      loadError: createSignal(""),
      conversations: createSignal[seq[ConversationSummary]](@[]),
      totalConversations: createSignal(0),
      backfilling: createSignal(false),
      selectedId: createSignal(""),
      transcriptLoading: createSignal(false),
      transcript: createSignal[seq[Message]](@[]),
      transcriptError: createSignal(""),
      draft: createSignal(""),
      replyPhase: createSignal(ReplyPhase.idle),
      replyText: createSignal(""),
      replyError: createSignal(""),
      disposeProc: dispose)
    vm.placeholderRows = createMemo(proc(): int =
      if vm.phase.val == LoadPhase.loading: min(vm.pageSize, 6) else: 0)
    vm.remaining = createMemo(proc(): int =
      max(0, vm.totalConversations.val - vm.conversations.val.len))
    vm.canSend = createMemo(proc(): bool =
      vm.phase.val == LoadPhase.ready and vm.selectedId.val.len > 0 and
        not vm.transcriptLoading.val and vm.draft.val.strip.len > 0 and
        vm.replyPhase.val in {ReplyPhase.idle, ReplyPhase.failed})
    vm
  if autoLoad: result.load()
