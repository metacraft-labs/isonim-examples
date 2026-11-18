## conversation_app/core/services.nim — the services the ViewModel is given.
##
## The ViewModel calls these operations and nothing else. Which
## implementation it gets decides where it runs:
##
## - in the product: `real_service.newConversationService` (the app's own
##   service logic over its store and a language-model provider);
## - in unit tests: a mock that records calls and answers as each test
##   scripts it;
## - in headless integration tests: the real service, with only the
##   downstream language model replaced by a scripted one;
## - in the IsoNim Editor: `standin.newConversationStandIn`, the one
##   stand-in implementation, tuned by parameters for each editor state.
##
## Any of them can be put behind `network_services.withNetwork` to see the
## UI under a slower connection.
##
## `sendPrompt` answers with a stream: the assistant's reply arrives in
## increments, and the ViewModel shows each as it comes.

import nim_everywhere/async_compat
import isonim/services/streams

import ./types

export types, async_compat, streams

type
  ConversationServices* = ref object
    loadInitialScreen*: proc(pageSize: int): PlatformFuture[InitialScreen] {.closure.}
      ## The first page of conversations plus the first one's transcript.
    loadConversations*: proc(offset, limit: int): PlatformFuture[ConversationPage] {.closure.}
      ## A later page of the list, for backfilling it.
    loadTranscript*: proc(conversationId: string): PlatformFuture[seq[Message]] {.closure.}
    createConversation*: proc(title: string): PlatformFuture[ConversationSummary] {.closure.}
    sendPrompt*: proc(conversationId, text: string): ServiceStream[string] {.closure.}
      ## Records the prompt and streams the assistant's reply; the complete
      ## reply is part of the transcript once the stream is done.

  ServiceOp* {.pure.} = enum
    ## The operations, by name — for stand-in failure switches and reports.
    initialScreen = "loadInitialScreen"
    conversations = "loadConversations"
    transcript = "loadTranscript"
    create = "createConversation"
    send = "sendPrompt"

# Sizes on the wire, for simulating transfer time. Rough JSON sizes: the
# text plus a fixed overhead per record.

const RecordOverhead = 32

proc wireSize*(m: Message): int = m.text.len + RecordOverhead
proc wireSize*(c: ConversationSummary): int =
  c.id.len + c.title.len + c.preview.len + RecordOverhead
proc wireSize*(ms: seq[Message]): int =
  result = RecordOverhead
  for m in ms: result += m.wireSize
proc wireSize*(p: ConversationPage): int =
  result = RecordOverhead
  for c in p.items: result += c.wireSize
proc wireSize*(s: InitialScreen): int =
  s.conversations.wireSize + s.transcript.wireSize
