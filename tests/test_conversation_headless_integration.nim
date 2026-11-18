## Headless integration test of the conversation app: the ViewModel over the
## real service (store + service logic), with only the downstream language
## model scripted, behind a simulated connection, on fake time.
##
## It checks the perceived-performance design end to end: the batched first
## screen shows the list and the transcript after one round trip, the rest of
## the list is backfilled afterwards, and the reply's first increment shows
## well before its end. It also prints the readiness marks per network
## profile as JSON, which is how an agent compares designs by numbers.

import std/[json, strutils, unittest]

import conversation_app/core/[vm, real_service, network_services]
import ./helpers/conversation_drive

const Reply = "Book the flights first, then the hotel near the old town, " &
  "and keep one day free for a trip to the coast."

proc seededStore(conversations: int): ConversationStore =
  result = newConversationStore()
  for i in countdown(conversations - 1, 0):
    discard result.addConversation("Conversation " & $i, @[
      (Role.user, "What should I do first for trip " & $i & "?"),
      (Role.assistant, "Start with the dates. " & "Details follow. ".repeat(8))])

type Run = object
  profile: string
  conversationsFirst, conversationsComplete, transcriptComplete: int64
  replyFirst, replyComplete: int64
  persisted: seq[Message]

proc runOnce(profile: NetworkProfile): Run =
  let ctx = newFakeAsyncContext()
  ctx.install()
  defer: ctx.uninstall()
  let store = seededStore(120)
  let model = scriptedModel(Reply, chunkRunes = 8, firstDelayMs = 150,
                            intervalMs = 30)
  let services = newConversationService(store, model).withNetwork(profile,
    seed = 3)
  let vm = newConversationVM(services, pageSize = 20, backfillPageSize = 50)
  discard ctx.stepUntil(60_000, proc(): bool =
    vm.readiness.has("conversations"))
  result.profile = profile.name
  result.conversationsFirst = vm.readiness.firstAt("conversations")
  result.conversationsComplete = vm.readiness.completeAt("conversations")
  result.transcriptComplete = vm.readiness.completeAt("transcript")
  check vm.conversations.value.len == 120
  check vm.phase.value == LoadPhase.ready

  let conversationId = vm.selectedId.value
  vm.setDraft("Plan the Lisbon trip")
  vm.send()
  discard ctx.stepUntil(60_000, proc(): bool =
    vm.replyReadiness.has("reply"))
  result.replyFirst = vm.replyReadiness.firstAt("reply")
  result.replyComplete = vm.replyReadiness.completeAt("reply")
  check vm.transcript.value[^1].text == Reply
  for c in store.conversations:
    if c.id == conversationId: result.persisted = c.messages
  vm.dispose()

proc toJson(r: Run): JsonNode =
  %*{"profile": r.profile,
     "marks": {"conversations:first": r.conversationsFirst,
               "conversations": r.conversationsComplete,
               "transcript": r.transcriptComplete,
               "reply:first": r.replyFirst,
               "reply": r.replyComplete}}

suite "conversation app, headless, real service behind a simulated network":
  test "4G: one round trip to the first screen, backfill after, reply streamed":
    let r = runOnce(FourGNetwork)
    let rtt = FourGNetwork.latencyMs
    # The first screen needs one response: at least one latency, and well
    # under two (the payload is small).
    check r.conversationsFirst >= rtt
    check r.conversationsFirst < 2 * rtt
    # Batched: the transcript arrived in the same response as the list.
    check r.transcriptComplete == r.conversationsFirst
    # 100 more conversations in pages of 50: two more round trips at least.
    check r.conversationsComplete >= r.conversationsFirst + 2 * rtt
    # The reply's first increment shows long before its last.
    check r.replyFirst >= rtt
    # The model produces it over about 400 ms.
    check r.replyComplete > r.replyFirst + 300
    # The real service recorded the prompt and the complete reply.
    check r.persisted[^2].text == "Plan the Lisbon trip"
    check r.persisted[^1].text == Reply

  test "the marks order the profiles, and are reported for agents":
    var report = newJArray()
    var runs: seq[Run]
    for p in [InstantNetwork, FourGNetwork, Slow3GNetwork]:
      let r = runOnce(p)
      runs.add r
      report.add r.toJson
    echo report.pretty
    check runs[0].conversationsFirst < runs[1].conversationsFirst
    check runs[1].conversationsFirst < runs[2].conversationsFirst
    check runs[0].conversationsComplete < runs[2].conversationsComplete
    check runs[0].replyFirst < runs[2].replyFirst
    # With no network delay, the first screen is there at once.
    check runs[0].conversationsFirst == 0
