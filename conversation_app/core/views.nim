## conversation_app/core/views.nim — the conversation app's View.
##
## Maps the ViewModel's state to elements and nothing else: every decision
## about what to show (placeholders, the typing indicator, the growing reply,
## the backfill status) is a signal or memo of `ConversationVM`, read in a
## render effect here. Generic over the renderer, so the same View runs over
## `MockRenderer` in tests and over the browser DOM in the IsoNim Editor.
##
## Elements carry `data-testid` attributes so tests and the editor's tools
## can find them.

import isonim/core/[signals, computation]
import isonim/dsl/ui

import ./vm

export vm

const
  Canvas = "#0F1117"
  Surface = "#1d1d28"
  SurfaceBorder = "#25263A"
  TextPrimary = "#E8E9F0"
  TextMuted = "#A0A2B0"
  Accent = "#7c7aed"
  Danger = "#f87171"
  Skeleton = "#2a2b3d"

proc el[R, E](r: R; tag: string; css = ""; testId = ""; text = ""): E =
  result = r.createElement(tag)
  if css.len > 0: r.setAttribute(result, "style", css)
  if testId.len > 0: r.setAttribute(result, "data-testid", testId)
  if text.len > 0: r.setTextContent(result, text)

proc show[R, E](r: R; node: E; visible: bool) =
  r.setStyle(node, "display", if visible: "" else: "none")

proc clicked[R, E](r: R; node: E; action: proc()) =
  r.addEventListener(node, "click", action)

# ---------------------------------------------------------------------------
# Conversation list
# ---------------------------------------------------------------------------

proc skeletonRow[R, E](r: R): E =
  result = el[R, E](r, "li", "list-style:none;padding:12px;border-radius:8px;" &
    "background:" & Surface & ";display:flex;flex-direction:column;gap:6px",
    testId = "conversation-skeleton")
  r.appendChild(result, el[R, E](r, "div",
    "height:12px;width:60%;border-radius:4px;background:" & Skeleton))
  r.appendChild(result, el[R, E](r, "div",
    "height:10px;width:85%;border-radius:4px;background:" & Skeleton))

proc conversationRow[R, E](r: R; vm: ConversationVM;
                           c: ConversationSummary; selected: bool): E =
  let border = if selected: Accent else: SurfaceBorder
  result = el[R, E](r, "li", "list-style:none;padding:10px 12px;" &
    "border-radius:8px;cursor:pointer;background:" & Surface &
    ";border:1px solid " & border, testId = "conversation-row")
  r.setAttribute(result, "data-conversation-id", c.id)
  if selected: r.setAttribute(result, "aria-current", "true")
  r.appendChild(result, el[R, E](r, "div",
    "font-weight:600;font-size:14px;color:" & TextPrimary, text = c.title))
  r.appendChild(result, el[R, E](r, "div",
    "font-size:12px;color:" & TextMuted & ";white-space:nowrap;" &
    "overflow:hidden;text-overflow:ellipsis",
    text = (if c.preview.len > 0: c.preview else: "No messages yet")))
  let id = c.id
  clicked(r, result, proc() = vm.select(id))

proc renderConversationList[R, E](r: R; vm: ConversationVM): E =
  var list, status, newButton: E
  result = ui(r):
    tdiv(class = "conversation-sidebar", width = "280px", min_width = "240px",
         display = "flex", flex_direction = "column", gap = "8px",
         padding = "12px", border_right = "1px solid " & SurfaceBorder,
         overflow_y = "auto"):
      button(ref = newButton, `data-testid` = "new-conversation",
             background = Accent, color = "#fff", border = "none",
             border_radius = "6px", padding = "8px 12px", cursor = "pointer",
             font_weight = "600"):
        text "New conversation"
      ul(ref = list, `data-testid` = "conversation-list", margin = "0",
         padding = "0", display = "flex", flex_direction = "column",
         gap = "6px")
      tdiv(ref = status, `data-testid` = "backfill-status",
           font_size = "12px", color = TextMuted, padding = "4px 2px")
  clicked(r, newButton, proc() = vm.newConversation())

  createRenderEffect proc() =
    let skeletons = vm.placeholderRows.val
    let rows = vm.conversations.val
    let selected = vm.selectedId.val
    let phase = vm.phase.val
    r.clearChildren(list)
    if skeletons > 0:
      for _ in 0 ..< skeletons:
        r.appendChild(list, skeletonRow[R, E](r))
    elif phase == LoadPhase.ready and rows.len == 0:
      r.appendChild(list, el[R, E](r, "li",
        "list-style:none;color:" & TextMuted & ";padding:12px;font-size:13px",
        testId = "conversation-list-empty", text = "No conversations yet."))
    else:
      for c in rows:
        r.appendChild(list, conversationRow[R, E](r, vm, c, c.id == selected))

  createRenderEffect proc() =
    let remaining = vm.remaining.val
    if vm.phase.val != LoadPhase.ready or remaining == 0:
      r.setTextContent(status, "")
      show(r, status, false)
    else:
      r.setTextContent(status, (if vm.backfilling.val: "Loading " else: "") &
        $remaining & " more conversation" & (if remaining == 1: "" else: "s") &
        (if vm.backfilling.val: "..." else: " not loaded"))
      show(r, status, true)

# ---------------------------------------------------------------------------
# Transcript and composer
# ---------------------------------------------------------------------------

proc bubble[R, E](r: R; role: Role; text: string; testId: string): E =
  let mine = role == Role.user
  result = el[R, E](r, "div", "max-width:75%;padding:10px 12px;" &
    "border-radius:10px;font-size:14px;line-height:1.45;white-space:pre-wrap;" &
    "align-self:" & (if mine: "flex-end" else: "flex-start") &
    ";background:" & (if mine: Accent else: Surface) &
    ";color:" & (if mine: "#fff" else: TextPrimary),
    testId = testId, text = text)
  r.setAttribute(result, "data-role", $role)

proc skeletonBubble[R, E](r: R; wide: bool): E =
  el[R, E](r, "div", "height:38px;border-radius:10px;background:" & Skeleton &
    ";width:" & (if wide: "70%" else: "45%") &
    ";align-self:" & (if wide: "flex-start" else: "flex-end"),
    testId = "message-skeleton")

proc renderTranscript[R, E](r: R; vm: ConversationVM): E =
  var messages, reply, replyText, typing, replyError, dismiss: E
  var errorBox, errorText, retry: E
  var draft, send, stop: E
  result = ui(r):
    tdiv(class = "conversation-main", flex = "1", display = "flex",
         flex_direction = "column", min_width = "0"):
      tdiv(ref = errorBox, `data-testid` = "load-error", padding = "16px",
           color = Danger, display = "none"):
        span(ref = errorText)
        button(ref = retry, `data-testid` = "retry", margin_left = "12px"):
          text "Retry"
      tdiv(ref = messages, `data-testid` = "transcript", flex = "1",
           overflow_y = "auto", display = "flex", flex_direction = "column",
           gap = "10px", padding = "16px")
      tdiv(ref = reply, `data-testid` = "streaming-reply", display = "none",
           padding = "0 16px 8px"):
        tdiv(ref = typing, `data-testid` = "typing", color = TextMuted,
             font_size = "13px"):
          text "Assistant is typing..."
        tdiv(ref = replyText, `data-testid` = "reply-text",
             background = Surface, color = TextPrimary, padding = "10px 12px",
             border_radius = "10px", white_space = "pre-wrap",
             font_size = "14px", line_height = "1.45", max_width = "75%")
        tdiv(ref = replyError, `data-testid` = "reply-error", color = Danger,
             font_size = "13px", margin_top = "6px")
        button(ref = dismiss, `data-testid` = "dismiss-reply-error"):
          text "Dismiss"
      tdiv(class = "composer", display = "flex", gap = "8px",
           padding = "12px 16px", border_top = "1px solid " & SurfaceBorder):
        input(ref = draft, `type` = "text", `data-testid` = "draft",
              placeholder = "Ask something...", flex = "1",
              background = Surface, color = TextPrimary,
              border = "1px solid " & SurfaceBorder, border_radius = "6px",
              padding = "8px 10px")
        button(ref = send, `data-testid` = "send", background = Accent,
               color = "#fff", border = "none", border_radius = "6px",
               padding = "8px 14px", cursor = "pointer"):
          text "Send"
        button(ref = stop, `data-testid` = "stop", border_radius = "6px",
               padding = "8px 14px"):
          text "Stop"

  clicked(r, retry, proc() = vm.load())
  clicked(r, send, proc() = vm.send())
  clicked(r, stop, proc() = vm.cancelReply())
  clicked(r, dismiss, proc() = vm.dismissReplyError())
  let draftNode = draft
  r.addEventListener(draftNode, "input", proc() =
    vm.setDraft(r.inputValue(draftNode)))

  createRenderEffect proc() =
    let failed = vm.phase.val == LoadPhase.failed
    show(r, errorBox, failed)
    r.setTextContent(errorText,
      if failed: "Could not load conversations: " & vm.loadError.val else: "")

  createRenderEffect proc() =
    let phase = vm.phase.val
    let loading = phase == LoadPhase.loading or vm.transcriptLoading.val
    let msgs = vm.transcript.val
    let error = vm.transcriptError.val
    r.clearChildren(messages)
    if loading:
      for i in 0 ..< 3:
        r.appendChild(messages, skeletonBubble[R, E](r, i mod 2 == 0))
    elif error.len > 0:
      r.appendChild(messages, el[R, E](r, "div", "color:" & Danger,
        testId = "transcript-error", text = error))
    elif phase == LoadPhase.ready and vm.selectedId.val.len == 0:
      r.appendChild(messages, el[R, E](r, "div", "color:" & TextMuted,
        testId = "transcript-empty",
        text = "Start a conversation to ask the assistant something."))
    else:
      for m in msgs:
        r.appendChild(messages, bubble[R, E](r, m.role, m.text, "message"))

  createRenderEffect proc() =
    let phase = vm.replyPhase.val
    show(r, reply, phase != ReplyPhase.idle)
    show(r, typing, phase == ReplyPhase.waiting)
    let partial = vm.replyText.val
    r.setTextContent(replyText, partial)
    show(r, replyText, partial.len > 0)
    let error = vm.replyError.val
    r.setTextContent(replyError,
      if error.len > 0: "The reply was interrupted: " & error else: "")
    show(r, replyError, phase == ReplyPhase.failed)
    show(r, dismiss, phase == ReplyPhase.failed)
    show(r, stop, phase in {ReplyPhase.waiting, ReplyPhase.streaming})

  createRenderEffect proc() =
    let text = vm.draft.val
    if r.inputValue(draftNode) != text:
      r.setInputValue(draftNode, text)
    if vm.canSend.val: r.removeAttribute(send, "disabled")
    else: r.setAttribute(send, "disabled", "true")

# ---------------------------------------------------------------------------
# The screen
# ---------------------------------------------------------------------------

proc renderConversationApp*[R, E](r: R; vm: ConversationVM): E =
  ## The whole screen: the conversation list beside the transcript.
  result = el[R, E](r, "div", "display:flex;height:100%;min-height:420px;" &
    "background:" & Canvas & ";color:" & TextPrimary & ";font-family:" &
    "-apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', system-ui, sans-serif",
    testId = "conversation-app")
  r.appendChild(result, renderConversationList[R, E](r, vm))
  r.appendChild(result, renderTranscript[R, E](r, vm))
