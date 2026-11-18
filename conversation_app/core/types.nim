## conversation_app/core/types.nim — the data the conversation app shows.

import std/hashes

type
  Role* {.pure.} = enum
    user = "user"
    assistant = "assistant"

  Message* = object
    id*: int
    role*: Role
    text*: string

  ConversationSummary* = object
    id*: string
    title*: string
    preview*: string      ## The latest message, shortened.
    messageCount*: int

  ConversationPage* = object
    ## One page of the conversation list, newest first.
    items*: seq[ConversationSummary]
    offset*: int
    total*: int           ## Size of the whole list, so the client knows what is left.

  InitialScreen* = object
    ## Everything the first screen needs, in one response: the first page of
    ## the list and the transcript of its first conversation. Batching them
    ## saves a round trip before the transcript can show.
    conversations*: ConversationPage
    transcript*: seq[Message]

proc hash*(m: Message): Hash = hash(m.id) !& hash(m.text) !& hash(ord(m.role))
proc hash*(c: ConversationSummary): Hash =
  hash(c.id) !& hash(c.preview) !& hash(c.messageCount)

const PreviewRunes* = 60

proc previewOf*(text: string): string =
  ## A one-line preview of `text`.
  var count = 0
  for ch in text:
    if count >= PreviewRunes:
      result.add "..."
      return
    result.add(if ch == '\n': ' ' else: ch)
    if (ord(ch) and 0xC0) != 0x80: inc count
