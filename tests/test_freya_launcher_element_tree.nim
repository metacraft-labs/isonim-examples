## test_freya_launcher_element_tree — RS-M11b / EX-M23b headline test
## for the Freya launcher. Mirror of ``test_gpui_launcher_element_tree``;
## drives the real ``build/backends/isonim-examples-freya`` binary.

import std/[asyncdispatch, asyncnet, base64, json, nativesockets, net,
            os, osproc, random, strutils, times, unittest]

import isonim_render_serve

const
  ManifestDeadlineMs = 1500
  StateChangeDeadlineMs = 1500
  IdleFrameCount = 10

# ---------------------------------------------------------------------------
# WS client helpers (mirror of test_gpui_launcher_element_tree.nim).
# ---------------------------------------------------------------------------

proc recvSome(fd: AsyncFD; size: int): Future[string] {.async.} =
  var buf = newString(size)
  let n = await asyncdispatch.recvInto(fd, addr buf[0], size)
  if n <= 0: return ""
  buf.setLen(n)
  result = buf

proc handshake(s: AsyncSocket; host: string; port: int) {.async.} =
  let key = encode("0123456789abcdef0123")
  let req = "GET / HTTP/1.1\r\n" &
            "Host: " & host & ":" & $port & "\r\n" &
            "Upgrade: websocket\r\n" &
            "Connection: Upgrade\r\n" &
            "Sec-WebSocket-Key: " & key & "\r\n" &
            "Sec-WebSocket-Version: 13\r\n\r\n"
  await s.send(req)
  let fd = AsyncFD(getFd(s))
  var resp = ""
  while not resp.contains("\r\n\r\n"):
    let chunk = await recvSome(fd, 4096)
    if chunk.len == 0: break
    resp.add(chunk)
  doAssert resp.startsWith("HTTP/1.1 101"),
    "handshake failed: " & resp

proc connectWs(port: int): Future[AsyncSocket] {.async.} =
  let sock = newAsyncSocket()
  await sock.connect("127.0.0.1", Port(port))
  await handshake(sock, "127.0.0.1", port)
  result = sock

type DecState = ref object
  dec: WsFrameDecoder

proc newDecState(): DecState =
  DecState(dec: initWsFrameDecoder())

proc recvOnePacket(sock: AsyncSocket; state: DecState):
                   Future[string] {.async.} =
  let fd = AsyncFD(getFd(sock))
  var msg = state.dec.popMessage()
  while not msg.complete:
    let chunk = await recvSome(fd, 16384)
    if chunk.len == 0: break
    state.dec.feed(chunk)
    msg = state.dec.popMessage()
  if msg.complete: return msg.payload
  result = ""

proc randMaskKey(): array[4, byte] =
  for i in 0 ..< 4: result[i] = byte(rand(0 .. 255))

proc sendInputPacket(sock: AsyncSocket; ipkt: InputPacket) {.async.} =
  let payload = bytesToString(encodeInput(ipkt))
  let mask = randMaskKey()
  let frame = encodeWsClientFrame(wsOpBinary, payload, mask)
  await sock.send(frame)

# ---------------------------------------------------------------------------
# Binary resolution
# ---------------------------------------------------------------------------

proc resolveLauncherBinary(): string =
  let envPath = getEnv("ISONIM_EXAMPLES_FREYA_BIN")
  if envPath.len > 0:
    if fileExists(envPath): return envPath
    raise newException(IOError,
      "$ISONIM_EXAMPLES_FREYA_BIN points at non-existent file: " & envPath)
  let repoRoot = currentSourcePath().parentDir().parentDir()
  let local = repoRoot / "build" / "backends" / "isonim-examples-freya"
  if fileExists(local): return local
  raise newException(IOError,
    "isonim-examples-freya binary not found at " & local & "\n" &
    "Run `just build-backends` in isonim-examples first, or set " &
    "$ISONIM_EXAMPLES_FREYA_BIN to a built binary.")

proc pickPort(): int =
  let s = newSocket()
  s.bindAddr(Port(0))
  let p = s.getLocalAddr()[1]
  s.close()
  int(p)

proc waitForListen(port: int; deadlineMs: int): bool =
  let deadline = epochTime() + (deadlineMs.float / 1000.0)
  while epochTime() < deadline:
    try:
      let s = newSocket()
      defer: s.close()
      s.connect("127.0.0.1", Port(port), timeout = 50)
      return true
    except CatchableError:
      sleep(25)
  false

type
  Launcher = ref object
    process: Process
    port: int

proc launch(): Launcher =
  let bin = resolveLauncherBinary()
  let port = pickPort()
  let args = @["--demo=tasks", "--port", $port, "--fps", "60"]
  let p = startProcess(bin, args = args,
                       options = {poStdErrToStdOut, poUsePath})
  if not waitForListen(port, deadlineMs = 4000):
    p.terminate()
    discard p.waitForExit(timeout = 1000)
    raise newException(IOError,
      "launcher " & bin & " did not bind to 127.0.0.1:" & $port &
      " within 4s")
  Launcher(process: p, port: port)

proc stop(l: Launcher) =
  if l.process != nil and l.process.running:
    l.process.terminate()
    discard l.process.waitForExit(timeout = 2000)

# ---------------------------------------------------------------------------
# Suite
# ---------------------------------------------------------------------------

suite "EX-M23b / RS-M11b: Freya launcher element-tree":

  setup:
    randomize()

  test "manifest arrives within deadline with task / filter / summary entries":
    when defined(windows):
      skip()
    else:
      let l = launch()
      defer: l.stop()
      proc flow(): Future[ElementTreeManifest] {.async.} =
        let sock = await connectWs(l.port)
        let dec = newDecState()
        let start = epochTime()
        var helloSeen = false
        while epochTime() - start < (ManifestDeadlineMs.float / 1000.0):
          let payload = await recvOnePacket(sock, dec)
          if payload.len == 0: continue
          case payload[0]
          of 'M':
            let meta = decodeMeta(stringToBytes(payload))
            if isElementTreeBody(meta.json):
              sock.close()
              return decodeElementTreeJson(meta.json)
            else:
              if not helloSeen:
                let helloJson = parseJson(meta.json)
                doAssert helloJson["type"].getStr == "hello"
                doAssert helloJson["capabilities"][
                  "elementTree"].getBool == true,
                  "Freya launcher must advertise capabilities.elementTree=true"
                helloSeen = true
          of 'F':
            doAssert false,
              "F packet arrived before the first element-tree manifest"
          else: discard
        sock.close()
        raise newException(IOError, "no manifest arrived within deadline")
      let manifest = waitFor flow()
      check manifest.surfaceWidth > 0
      check manifest.surfaceHeight > 0
      var taskRowCount = 0
      var filterBarCount = 0
      var summaryCount = 0
      for e in manifest.elements:
        if e.componentPath.startsWith("task_app/views/TaskRow#"):
          inc taskRowCount
        if e.componentPath == "task_app/views/FilterBar":
          inc filterBarCount
        if e.componentPath == "task_app/views/SummaryBar":
          inc summaryCount
      check taskRowCount >= 3
      check filterBarCount >= 1
      check summaryCount >= 1
      for e in manifest.elements:
        check e.bounds.x >= 0
        check e.bounds.y >= 0
        check e.bounds.x + e.bounds.w <= manifest.surfaceWidth
        check e.bounds.y + e.bounds.h <= manifest.surfaceHeight

  test "idle frames do NOT trigger a new element-tree manifest":
    when defined(windows):
      skip()
    else:
      let l = launch()
      defer: l.stop()
      proc flow(): Future[tuple[initialManifests, postManifests,
                                framesObserved: int]] {.async.} =
        let sock = await connectWs(l.port)
        let dec = newDecState()
        var manifestsBeforeFirstFrame = 0
        var manifestsAfterFirstFrame = 0
        var framesObserved = 0
        let start = epochTime()
        while framesObserved < IdleFrameCount and
            (epochTime() - start) < 5.0:
          let payload = await recvOnePacket(sock, dec)
          if payload.len == 0: continue
          case payload[0]
          of 'M':
            let meta = decodeMeta(stringToBytes(payload))
            if isElementTreeBody(meta.json):
              if framesObserved == 0:
                inc manifestsBeforeFirstFrame
              else:
                inc manifestsAfterFirstFrame
          of 'F':
            inc framesObserved
          else: discard
        sock.close()
        return (initialManifests: manifestsBeforeFirstFrame,
                postManifests: manifestsAfterFirstFrame,
                framesObserved: framesObserved)
      let r = waitFor flow()
      check r.framesObserved >= IdleFrameCount
      check r.initialManifests == 1
      check r.postManifests == 0

  test "state change (I packet) re-emits the manifest":
    when defined(windows):
      skip()
    else:
      let l = launch()
      defer: l.stop()
      proc flow(): Future[tuple[seenBefore, seenAfter: int]] {.async.} =
        let sock = await connectWs(l.port)
        let dec = newDecState()
        var manifestsBefore = 0
        var manifestsAfter = 0
        var framesObserved = 0
        var changeSent = false
        let start = epochTime()
        let resizePkt = encodeInputEvent(InputEvent(
          kind: iekResize, width: 1024, height: 480))
        var phase: int = 0
        let postDeadline = StateChangeDeadlineMs.float / 1000.0
        var changeAt = 0.0
        while (epochTime() - start) < 6.0:
          let payload = await recvOnePacket(sock, dec)
          if payload.len == 0: continue
          case payload[0]
          of 'M':
            let meta = decodeMeta(stringToBytes(payload))
            if isElementTreeBody(meta.json):
              if phase == 0:
                inc manifestsBefore
              else:
                inc manifestsAfter
                if epochTime() - changeAt < postDeadline:
                  break
          of 'F':
            inc framesObserved
            if not changeSent and manifestsBefore >= 1 and framesObserved >= 2:
              await sendInputPacket(sock, resizePkt)
              changeSent = true
              changeAt = epochTime()
              phase = 1
          else: discard
          if changeSent and (epochTime() - changeAt) > postDeadline + 1.0:
            break
        sock.close()
        return (seenBefore: manifestsBefore, seenAfter: manifestsAfter)
      let r = waitFor flow()
      check r.seenBefore >= 1
      check r.seenAfter >= 1
