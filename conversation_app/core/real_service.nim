## conversation_app/core/real_service.nim — the app's own service logic.
##
## Conversations live in a `ConversationStore`; the assistant's replies come
## from a `LanguageModel`, a downstream provider that streams text. This is
## what the product runs (with a store backed by its database and a model
## backed by an LLM API), and what headless integration tests run with the
## model replaced by a scripted one.
##
## Every operation answers asynchronously, even though the store is in
## memory, so callers see the same order of events as over a network.

import std/strutils

import nim_everywhere/time
import isonim/services/deferred

import ./services

export services

type
  LanguageModel* = proc(history: seq[Message]; prompt: string):
      ServiceStream[string] {.closure.}
    ## Streams the reply to `prompt` given the conversation so far.

  StoredConversation* = object
    id*: string
    title*: string
    messages*: seq[Message]

  ConversationStore* = ref object
    conversations*: seq[StoredConversation]  ## Newest first.
    nextConversationId*: int
    nextMessageId*: int

proc newConversationStore*(): ConversationStore =
  ConversationStore(nextConversationId: 1, nextMessageId: 1)

proc addConversation*(store: ConversationStore; title: string;
                      messages: seq[(Role, string)] = @[]): string =
  ## Add a conversation at the top of the list; returns its id.
  result = "c" & $store.nextConversationId
  inc store.nextConversationId
  var conv = StoredConversation(id: result, title: title)
  for (role, text) in messages:
    conv.messages.add Message(id: store.nextMessageId, role: role, text: text)
    inc store.nextMessageId
  store.conversations.insert(conv, 0)

proc find(store: ConversationStore; id: string): int =
  for i, c in store.conversations:
    if c.id == id: return i
  -1

proc summary*(c: StoredConversation): ConversationSummary =
  ConversationSummary(id: c.id, title: c.title,
    preview: (if c.messages.len > 0: previewOf(c.messages[^1].text) else: ""),
    messageCount: c.messages.len)

proc page*(store: ConversationStore; offset, limit: int): ConversationPage =
  result = ConversationPage(offset: offset, total: store.conversations.len)
  for i in offset ..< min(offset + max(limit, 0), store.conversations.len):
    result.items.add store.conversations[i].summary

proc later*[T](value: T): PlatformFuture[T] =
  ## `value`, delivered on the next turn of the event loop.
  let d = newDeferred[T]()
  discard scheduleAt(0, proc() = d.resolve(value))
  d.future

proc laterError*[T](message: string): PlatformFuture[T] =
  let d = newDeferred[T]()
  discard scheduleAt(0, proc() = d.reject(message))
  d.future

proc newConversationService*(store: ConversationStore;
                             model: LanguageModel): ConversationServices =
  ## The service the product runs, over `store` and `model`.
  ConversationServices(
    loadInitialScreen: proc(pageSize: int): PlatformFuture[InitialScreen] =
      var screen = InitialScreen(conversations: store.page(0, pageSize))
      if store.conversations.len > 0:
        screen.transcript = store.conversations[0].messages
      later(screen),

    loadConversations: proc(offset, limit: int): PlatformFuture[ConversationPage] =
      later(store.page(offset, limit)),

    loadTranscript: proc(conversationId: string): PlatformFuture[seq[Message]] =
      let i = store.find(conversationId)
      if i < 0: laterError[seq[Message]]("no conversation " & conversationId)
      else: later(store.conversations[i].messages),

    createConversation: proc(title: string): PlatformFuture[ConversationSummary] =
      let name = if title.strip.len == 0: "New conversation" else: title.strip
      let id = store.addConversation(name)
      later(store.conversations[store.find(id)].summary),

    sendPrompt: proc(conversationId, text: string): ServiceStream[string] =
      # Record the prompt when the stream starts, stream the model's reply,
      # and record the reply once it is complete. A cancelled or failed
      # reply is not recorded.
      let prompt = text
      result = proc(sink: StreamSink[string]): StreamSubscription =
        let i = store.find(conversationId)
        if i < 0:
          let e = newStreamEmitter[string](sink)
          discard scheduleAt(0, proc() =
            e.fail("no conversation " & conversationId))
          return e.subscription
        let history = store.conversations[i].messages
        store.conversations[i].messages.add Message(
          id: store.nextMessageId, role: Role.user, text: prompt)
        inc store.nextMessageId
        var reply = ""
        proc collect(chunk: string) = reply.add chunk
        proc record() =
          let j = store.find(conversationId)
          if j >= 0:
            store.conversations[j].messages.add Message(
              id: store.nextMessageId, role: Role.assistant, text: reply)
            inc store.nextMessageId
        let observed = tee(model(history, prompt),
          StreamSink[string](onChunk: collect, onDone: record))
        observed(sink))

proc scriptedModel*(reply: string; chunkRunes = 4; firstDelayMs = 0;
                    intervalMs = 0; failAfterChunks = -1;
                    failure = "the model stopped responding"): LanguageModel =
  ## A model that answers every prompt with `reply`, `chunkRunes` characters
  ## at a time. For tests and stand-ins: it replaces only the downstream
  ## provider, not the service logic.
  let chunks = chunkText(reply, chunkRunes)
  result = proc(history: seq[Message]; prompt: string): ServiceStream[string] =
    pacedStream(chunks, firstDelayMs, intervalMs, failAfterChunks, failure)
