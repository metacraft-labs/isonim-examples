## RS-M13: D/M/P terminal bridge for the new TUI launcher.
##
## A minimal in-process WS bridge purpose-built for the
## ``isonim-examples-tui-term`` launcher. It differs from
## ``isonim-tui-serve``'s shipping bridge in one key respect: the
## bridge here OWNS the harness — there's no child process and no
## stdio plumbing. Each WS connection drives one launcher composition
## root in-process via the supplied closures:
##
##   * ``displaySource``: ``proc(): string`` — pull the latest ANSI
##     escape-sequence bytes from the harness (typically
##     ``harness.bytesEmitted`` after ``harness.flush()``).
##   * ``manifestSource``: ``proc(): TuiElementTreeManifest`` — build
##     the current element-tree manifest with cell coordinates.
##   * ``storyDispatch``: ``TuiStoryDispatchSink`` — receives decoded
##     ``select-story`` / ``apply-mutation`` events from the editor.
##
## Cadence rules (preserved from RS-M11 / RS-M12):
##
##   * On WS connect: emit exactly one element-tree M packet BEFORE
##     the first D packet. The editor's canvas hit-test needs the
##     manifest before any output bytes paint, so this ordering is a
##     hard invariant the launcher test asserts.
##   * Every frame tick: re-flush the harness, compare the manifest
##     key against the per-connection cache, emit a fresh M packet
##     only on (id, bounds)-change; emit D packets from the bytes
##     produced since the last flush.

import std/[asyncdispatch, asynchttpserver, asyncnet, base64, httpcore,
            nativesockets, strutils]
import std/sha1 as sha1Mod

import isonim_tui_serve

const
  WebSocketGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    ## RFC 6455 §1.3 magic GUID.
  CloseProtocolError = 1002'u16
    ## RFC 6455 §7.4.1 status code for protocol error.

type
  DisplaySource* = proc(): string {.closure, gcsafe.}
  ManifestSource* = proc(): TuiElementTreeManifest {.closure, gcsafe.}
  InitialDisplaySource* = proc(): string {.closure, gcsafe.}
    ## RS-M13 fix-cycle 1: per-connection full-repaint hook.
    ##
    ## ``displaySource`` returns the *delta* bytes emitted since the
    ## last drain (the harness's ``bytesEmitted`` accumulator is
    ## cleared each call). That model breaks for the *second* WS
    ## connection: the harness already has its full state painted
    ## into ``compositor.lastBuffer`` (drained by the first
    ## connection), so a fresh drain yields the empty string and
    ## xterm.js renders nothing until the next state change.
    ##
    ## ``initialDisplaySource`` (optional) is invoked instead of
    ## ``displaySource`` for the very first D emission per
    ## connection. The launcher implements it to invalidate the
    ## compositor's last-paint cache (``c.initialPainted = false``)
    ## and re-flush, producing a full ANSI repaint covering the
    ## current screen state.

  TerminalBridgeConfig* = object
    port*: Port
    frameIntervalMs*: int
    displaySource*: DisplaySource
    initialDisplaySource*: InitialDisplaySource
    manifestSource*: ManifestSource
    storyDispatch*: TuiStoryDispatchSink

  TerminalBridgeServer* = ref object
    cfg: TerminalBridgeConfig
    httpServer: AsyncHttpServer

  ConnectionState = ref object
    closed: bool
    lastManifestKey: string

proc computeAcceptKey(clientKey: string): string =
  let combined = clientKey & WebSocketGuid
  {.push warning[Deprecated]: off.}
  let digest = sha1Mod.secureHash(combined)
  let bytes = sha1Mod.Sha1Digest(digest)
  {.pop.}
  var raw = newString(20)
  for i in 0 ..< 20: raw[i] = char(bytes[i])
  encode(raw)

proc readHeader(headers: HttpHeaders; key: string): string =
  if headers.hasKey(key):
    result = $headers[key]
  else:
    result = ""

proc sendWsBinary(client: AsyncSocket; payload: string) {.async.} =
  let frame = encodeWsBinaryFrame(payload)
  await client.send(frame)

proc sendWsClose(client: AsyncSocket; code: uint16;
                 reason: string = "") {.async.} =
  ## Best-effort close. The bridge always tries to write a close frame
  ## before tearing down the socket so spec-conformant clients see the
  ## protocol-violation status code.
  let n = 2 + reason.len
  var payload = newString(n)
  payload[0] = char((code shr 8) and 0xFF)
  payload[1] = char(code and 0xFF)
  for i, ch in reason: payload[2 + i] = ch
  try:
    await client.send(encodeWsFrame(wsOpClose, payload))
  except CatchableError:
    discard
  try: client.close() except CatchableError: discard

proc sendElementTreeIfChanged(client: AsyncSocket;
                              cfg: TerminalBridgeConfig;
                              state: ConnectionState;
                              force: bool = false) {.async.} =
  ## Emit an ``element-tree`` M packet when the manifest key has
  ## changed (or on the first emission). Idle frames produce identical
  ## keys and therefore NO emission — the RS-M11 cadence rule carried
  ## forward into RS-M13.
  if cfg.manifestSource == nil: return
  let manifest = cfg.manifestSource()
  let key = manifestKey(manifest)
  if not force and key == state.lastManifestKey: return
  let body = encodeElementTreeBody(manifest)
  let pkt = encodePacket(PacketTypeMeta, body)
  try:
    await sendWsBinary(client, pkt)
    state.lastManifestKey = key
  except OSError, IOError:
    discard

proc emitDisplay(client: AsyncSocket; cfg: TerminalBridgeConfig;
                 initial: bool = false) {.async.} =
  ## Pull whatever ANSI bytes the harness has accumulated since the
  ## last call and forward as a single D packet. An empty string is
  ## the idle case — we skip the packet entirely so an xterm.js
  ## consumer doesn't see no-op writes.
  ##
  ## When ``initial`` is true AND the config supplies an
  ## ``initialDisplaySource`` callable, we route through it instead.
  ## The hook produces a full ANSI repaint covering the harness's
  ## current screen state so a fresh connection (one that arrives
  ## after a prior connection has already drained the incremental
  ## byte log) still sees real content.
  var bytes = ""
  if initial and cfg.initialDisplaySource != nil:
    bytes = cfg.initialDisplaySource()
  elif cfg.displaySource != nil:
    bytes = cfg.displaySource()
  if bytes.len == 0: return
  let pkt = encodePacket(PacketTypeDisplay, bytes)
  try:
    await sendWsBinary(client, pkt)
  except OSError, IOError:
    discard

proc frameLoop(client: AsyncSocket; cfg: TerminalBridgeConfig;
               state: ConnectionState) {.async.} =
  while not state.closed and not client.isClosed:
    await sendElementTreeIfChanged(client, cfg, state)
    await emitDisplay(client, cfg)
    await sleepAsync(cfg.frameIntervalMs)

proc handleInbound(client: AsyncSocket; cfg: TerminalBridgeConfig;
                   state: ConnectionState) {.async.} =
  ## Read WS frames from the client; dispatch P packets through the
  ## story-dispatch sink. M packets from the client are accepted and
  ## ignored (parity with the render-serve bridge's I-direction
  ## ``M`` handling). D packets from the client are a protocol
  ## violation; we close with 1002.
  var dec = initWsFrameDecoder()
  var parser = initPacketParser()
  let fd = AsyncFD(getFd(client))
  while not client.isClosed:
    var buf = newString(4096)
    var n = 0
    try:
      n = await asyncdispatch.recvInto(fd, addr buf[0], buf.len)
    except CatchableError:
      break
    if n <= 0: break
    dec.feed(buf[0 ..< n])
    while true:
      let msg = dec.popMessage()
      if not msg.complete: break
      if msg.opcode == wsOpClose:
        state.closed = true
        try: client.close() except CatchableError: discard
        return
      if msg.opcode == wsOpPing:
        try:
          await client.send(encodeWsFrame(wsOpPong, msg.payload))
        except CatchableError:
          discard
        continue
      if msg.opcode != wsOpBinary and msg.opcode != wsOpText:
        continue
      parser.feedString(msg.payload)
      while parser.pendingPackets() > 0:
        let (ok, kind, payload) = parser.pop()
        if not ok: break
        case kind
        of PacketTypeInput:
          var ev: TuiStoryEvent
          try:
            ev = decodeTuiStoryEvent(payload)
          except TuiPacketProtocolError as e:
            state.closed = true
            await sendWsClose(client, CloseProtocolError, e.msg)
            return
          if cfg.storyDispatch != nil:
            cfg.storyDispatch.submit(ev)
        of PacketTypeMeta:
          # Client M packets are accepted but unused.
          discard
        of PacketTypeDisplay:
          state.closed = true
          await sendWsClose(client, CloseProtocolError,
                            "client D packet")
          return
        else:
          state.closed = true
          await sendWsClose(client, CloseProtocolError,
                            "unknown packet tag 0x" &
                            toHex(uint8(kind), 2))
          return

proc bridgeOnce(client: AsyncSocket;
                cfg: TerminalBridgeConfig) {.async.} =
  let state = ConnectionState(closed: false, lastManifestKey: "")
  # RS-M13 invariant: manifest BEFORE the first D packet.
  await sendElementTreeIfChanged(client, cfg, state, force = true)
  # Per-connection full repaint (RS-M13 fix-cycle 1): the first D
  # packet of every connection carries a complete ANSI snapshot of
  # the harness's current screen state, not just bytes accumulated
  # since the previous drain. Without this, the second + Nth WS
  # connections see only deltas (typically empty) and xterm.js
  # renders nothing until the next state change.
  await emitDisplay(client, cfg, initial = true)
  let outFut = frameLoop(client, cfg, state)
  let inFut = handleInbound(client, cfg, state)
  await outFut or inFut
  state.closed = true
  try: client.close() except CatchableError: discard

proc handleWebSocketUpgrade(req: Request;
                            cfg: TerminalBridgeConfig) {.async.} =
  let key = readHeader(req.headers, "Sec-WebSocket-Key")
  if key.len == 0:
    await req.respond(Http400, "missing Sec-WebSocket-Key")
    return
  let accept = computeAcceptKey(key.strip())
  let resp = "HTTP/1.1 101 Switching Protocols\r\n" &
             "Upgrade: websocket\r\n" &
             "Connection: Upgrade\r\n" &
             "Sec-WebSocket-Accept: " & accept & "\r\n\r\n"
  await req.client.send(resp)
  await bridgeOnce(req.client, cfg)

proc handler(req: Request; cfg: TerminalBridgeConfig) {.async.} =
  let upgrade = readHeader(req.headers, "Upgrade")
  if upgrade.toLowerAscii == "websocket":
    await handleWebSocketUpgrade(req, cfg)
  else:
    # No static directory served by the new TUI launcher — the editor
    # vendors xterm.js itself and the WS proxy is the only surface the
    # browser uses. Returning a tiny 200 page is sufficient for
    # liveness probes.
    let body = "isonim-examples-tui-term: WS-only bridge.\n"
    var headers = newHttpHeaders([("Content-Type", "text/plain; charset=utf-8")])
    await req.respond(Http200, body, headers)

proc newTerminalBridgeServer*(cfg: TerminalBridgeConfig):
                              TerminalBridgeServer =
  TerminalBridgeServer(cfg: cfg, httpServer: newAsyncHttpServer())

proc serve*(s: TerminalBridgeServer) {.async.} =
  proc cb(req: Request) {.async.} =
    await handler(req, s.cfg)
  await s.httpServer.serve(s.cfg.port, cb)

proc port*(s: TerminalBridgeServer): Port = s.cfg.port
