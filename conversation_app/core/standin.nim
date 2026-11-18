## conversation_app/core/standin.nim — the one stand-in implementation of the
## conversation services, for the IsoNim Editor and for demos.
##
## Every editor state of the conversation app is this stand-in with
## different parameters: how many conversations there are and how long their
## transcripts are, what the assistant replies and how fast the reply
## streams, and which operations fail. Nothing else differs between states,
## and no state reaches into the ViewModel.
##
## The stand-in keeps state where the product keeps it: it runs the app's
## own service logic (`real_service`) over a store filled from the
## parameters, with the language model replaced by a scripted one. A prompt
## sent in the editor therefore shows up in the transcript afterwards, a new
## conversation appears in the list, and so on — every control works.
##
## The stand-in never sleeps to imitate a network: wrap it in
## `network_services.withNetwork` for that, so the same profile applies to
## every operation and every state.

import std/strutils

import ./services
import ./real_service

export services, real_service

type
  StandInParams* = object
    conversationCount*: int
    messagesPerConversation*: int
    replyText*: string           ## What the assistant answers to any prompt.
    replyChunkRunes*: int        ## Characters per streamed increment.
    replyIntervalMs*: int        ## Pause between increments, as the model produces them.
    failing*: set[ServiceOp]     ## Operations that fail.
    failReplyAfterChunks*: int   ## >= 0: the reply stream breaks after this many increments.
    failure*: string             ## The error message of a failing operation.

const
  DefaultReply* = "Here is a short plan. First, list what the screen needs " &
    "before anything else is useful. Then load exactly that in one request, " &
    "show placeholders where it will go, and backfill the rest once the " &
    "first screen is up."

  Topics = ["Trip to Lisbon", "Quarterly report", "Kitchen renovation",
    "Reading list", "Team offsite", "Bug triage", "Garden plans",
    "Birthday party", "Job interview prep", "Marathon training"]

proc standInParams*(conversationCount = 12; messagesPerConversation = 6;
                    replyText = DefaultReply; replyChunkRunes = 6;
                    replyIntervalMs = 40; failing: set[ServiceOp] = {};
                    failReplyAfterChunks = -1;
                    failure = "The service is unavailable"): StandInParams =
  StandInParams(conversationCount: conversationCount,
    messagesPerConversation: messagesPerConversation, replyText: replyText,
    replyChunkRunes: replyChunkRunes, replyIntervalMs: replyIntervalMs,
    failing: failing, failReplyAfterChunks: failReplyAfterChunks,
    failure: failure)

proc fixtureStore*(p: StandInParams): ConversationStore =
  ## A store with `p.conversationCount` conversations, each with
  ## `p.messagesPerConversation` alternating messages. Deterministic.
  result = newConversationStore()
  # Added oldest first, so the first topic ends up at the top of the list.
  for n in countdown(p.conversationCount - 1, 0):
    let topic = Topics[n mod Topics.len] &
      (if n >= Topics.len: " (" & $(n div Topics.len + 1) & ")" else: "")
    var messages: seq[(Role, string)]
    for m in 0 ..< p.messagesPerConversation:
      if m mod 2 == 0:
        messages.add (Role.user, "Question " & $(m div 2 + 1) & " about " &
          topic.toLowerAscii & "?")
      else:
        messages.add (Role.assistant, "Answer " & $(m div 2 + 1) &
          ": a few sentences about " & topic.toLowerAscii &
          ", long enough to wrap onto a second line in a narrow column.")
    discard result.addConversation(topic, messages)

proc failingStream(message: string): ServiceStream[string] =
  pacedStream[string](@[], failAfter = 0, failure = message)

proc newConversationStandIn*(p: StandInParams): ConversationServices =
  ## The stand-in for `p`. Each call builds a fresh store, so two editor
  ## states never share data.
  let model = scriptedModel(p.replyText, p.replyChunkRunes,
    firstDelayMs = p.replyIntervalMs, intervalMs = p.replyIntervalMs,
    failAfterChunks = p.failReplyAfterChunks, failure = p.failure)
  let inner = newConversationService(fixtureStore(p), model)
  let failing = p.failing
  let failure = p.failure
  ConversationServices(
    loadInitialScreen: proc(pageSize: int): PlatformFuture[InitialScreen] =
      if ServiceOp.initialScreen in failing: laterError[InitialScreen](failure)
      else: inner.loadInitialScreen(pageSize),
    loadConversations: proc(offset, limit: int): PlatformFuture[ConversationPage] =
      if ServiceOp.conversations in failing: laterError[ConversationPage](failure)
      else: inner.loadConversations(offset, limit),
    loadTranscript: proc(id: string): PlatformFuture[seq[Message]] =
      if ServiceOp.transcript in failing: laterError[seq[Message]](failure)
      else: inner.loadTranscript(id),
    createConversation: proc(title: string): PlatformFuture[ConversationSummary] =
      if ServiceOp.create in failing: laterError[ConversationSummary](failure)
      else: inner.createConversation(title),
    sendPrompt: proc(id, text: string): ServiceStream[string] =
      if ServiceOp.send in failing: failingStream(failure)
      else: inner.sendPrompt(id, text))
