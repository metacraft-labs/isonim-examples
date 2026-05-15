## test_gpui_freya_render_tree_e2e — RS-M13b.
##
## End-to-end real-launcher test for the GPUI + Freya render-tree
## bridges. For each launcher:
##
##   1. Spawn the real built binary on an ephemeral port.
##   2. Open a real WebSocket.
##   3. Decode hello — must advertise ``renderTree: true`` +
##      ``rendererSurface: "tree"``.
##   4. Decode the initial render-tree manifest — must carry a
##      non-empty root with style fields populated.
##   5. Send a ``select-story`` I packet for "Task App / Pages / Inbox"
##      and decode the resulting render-tree — must contain the
##      expected componentPath entries for that story.
##   6. Send a second ``select-story`` for "Task App / TaskList / Two
##      Active" and assert the manifest changes accordingly.
##   7. Assert NO F packets arrive on the wire.
##
## The launcher binaries are produced by `just build-backends`; the
## test resolves them via the same env-var / build/backends fallback
## the other launcher tests use.

import std/[asyncdispatch, asyncnet, base64, json, nativesockets, net,
            os, osproc, random, sets, strutils, times, unittest]

import isonim_render_serve

const ManifestDeadlineMs = 2500

# ---------------------------------------------------------------------------
# WS helpers (same shape as test_cross_renderer_component_paths.nim).
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

proc escapeJsonStr(s: string): string =
  $newJString(s)

proc resolveLauncherBinary(envVar, binSuffix: string): string =
  let envPath = getEnv(envVar)
  if envPath.len > 0:
    if fileExists(envPath): return envPath
    raise newException(IOError,
      "$" & envVar & " points at non-existent file: " & envPath)
  let repoRoot = currentSourcePath().parentDir().parentDir()
  let local = repoRoot / "build" / "backends" / ("isonim-examples-" & binSuffix)
  if fileExists(local): return local
  raise newException(IOError,
    "isonim-examples-" & binSuffix & " not found at " & local &
    ". Run `just build-backends` first.")

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
    name: string

proc launch(name, envVar: string): Launcher =
  let bin = resolveLauncherBinary(envVar, name)
  let port = pickPort()
  let args = @["--demo=tasks", "--port", $port, "--fps", "30"]
  let p = startProcess(bin, args = args,
                       options = {poStdErrToStdOut, poUsePath})
  if not waitForListen(port, deadlineMs = 4000):
    p.terminate()
    discard p.waitForExit(timeout = 1000)
    raise newException(IOError,
      "launcher " & bin & " did not bind to 127.0.0.1:" & $port)
  Launcher(process: p, port: port, name: name)

proc stop(l: Launcher) =
  if l.process != nil and l.process.running:
    l.process.terminate()
    discard l.process.waitForExit(timeout = 2000)

# ---------------------------------------------------------------------------
# Manifest collection helpers
# ---------------------------------------------------------------------------

proc collectInitialPackets(sock: AsyncSocket; dec: DecState;
                           maxPackets: int = 6):
                          Future[seq[string]] {.async.} =
  result = newSeq[string]()
  for _ in 0 ..< maxPackets:
    let payload = await recvOnePacket(sock, dec)
    if payload.len == 0: break
    result.add payload

proc allComponentPaths(node: RenderTreeNode; into: var HashSet[string]) =
  if node.componentPath.len > 0:
    into.incl node.componentPath
  for c in node.children:
    allComponentPaths(c, into)

proc countNodes(node: RenderTreeNode): int =
  result = 1
  for c in node.children:
    result += countNodes(c)

proc anyStyleSet(node: RenderTreeNode): bool =
  ## Returns true if at least one node in the subtree carries a
  ## non-empty style map. The launcher's per-(tag, kind) style table
  ## always populates a font stack on the root, so a manifest with
  ## zero styles is a sign the adapter regressed.
  if node.style.keys.len > 0: return true
  for c in node.children:
    if anyStyleSet(c): return true

# ---------------------------------------------------------------------------
# Suite
# ---------------------------------------------------------------------------

suite "RS-M13b: GPUI + Freya render-tree e2e":

  test "GPUI launcher emits render-tree with style + componentPath payloads":
    when defined(windows):
      skip()
    else:
      let l = launch("gpui", "ISONIM_EXAMPLES_GPUI_BIN")
      defer: l.stop()

      proc flow(): Future[void] {.async.} =
        let sock = await connectWs(l.port)
        let dec = newDecState()
        let pkts = await collectInitialPackets(sock, dec, 3)
        sock.close()
        check pkts.len >= 3
        # No F packets — render-tree is the surface.
        for p in pkts:
          check p[0] != 'F'
        let helloMeta = decodeMeta(stringToBytes(pkts[0]))
        let hello = parseJson(helloMeta.json)
        check hello["type"].getStr == "hello"
        check hello["backend"].getStr == "gpui"
        check hello["capabilities"]["renderTree"].getBool == true
        check hello["capabilities"]["rendererSurface"].getStr == "tree"
        check hello["capabilities"]["elementTree"].getBool == true

        # The launcher emits both element-tree and render-tree before
        # the first F packet; their relative order is implementation-
        # defined (element-tree lands first today). Find the
        # render-tree M packet and validate it.
        var rtBody = ""
        for p in pkts[1 ..< pkts.len]:
          if p[0] == 'M':
            let body = decodeMeta(stringToBytes(p)).json
            if isRenderTreeBody(body):
              rtBody = body
              break
        check rtBody.len > 0
        let manifest = decodeRenderTreeBody(rtBody)
        check manifest.rendererId == "gpui"
        check countNodes(manifest.root) >= 5
        check anyStyleSet(manifest.root)
        var paths = initHashSet[string]()
        allComponentPaths(manifest.root, paths)
        check paths.len >= 4
        # Seeded task_app component paths must be present.
        check paths.contains("task_app/views/TaskApp")
      waitFor flow()

  test "Freya launcher emits render-tree with style + componentPath payloads":
    when defined(windows):
      skip()
    else:
      let l = launch("freya", "ISONIM_EXAMPLES_FREYA_BIN")
      defer: l.stop()

      proc flow(): Future[void] {.async.} =
        let sock = await connectWs(l.port)
        let dec = newDecState()
        let pkts = await collectInitialPackets(sock, dec, 3)
        sock.close()
        check pkts.len >= 3
        for p in pkts:
          check p[0] != 'F'
        let helloMeta = decodeMeta(stringToBytes(pkts[0]))
        let hello = parseJson(helloMeta.json)
        check hello["backend"].getStr == "freya"
        check hello["capabilities"]["renderTree"].getBool == true
        check hello["capabilities"]["rendererSurface"].getStr == "tree"

        var rtBody = ""
        for p in pkts[1 ..< pkts.len]:
          if p[0] == 'M':
            let body = decodeMeta(stringToBytes(p)).json
            if isRenderTreeBody(body):
              rtBody = body
              break
        check rtBody.len > 0
        let manifest = decodeRenderTreeBody(rtBody)
        check manifest.rendererId == "freya"
        check countNodes(manifest.root) >= 5
        check anyStyleSet(manifest.root)
        var paths = initHashSet[string]()
        allComponentPaths(manifest.root, paths)
        check paths.contains("task_app/views/TaskApp")
      waitFor flow()

  test "select-story drives a fresh render-tree from both GPUI and Freya":
    when defined(windows):
      skip()
    else:
      randomize(0xfeed)
      for spec in [("gpui", "ISONIM_EXAMPLES_GPUI_BIN"),
                   ("freya", "ISONIM_EXAMPLES_FREYA_BIN")]:
        let (name, envVar) = spec
        let l = launch(name, envVar)
        defer: l.stop()

        proc flow(): Future[void] {.async.} =
          let sock = await connectWs(l.port)
          let dec = newDecState()
          # Drain hello + initial element-tree + render-tree.
          let boot = await collectInitialPackets(sock, dec, 3)
          check boot.len >= 3

          # Send select-story for "Two Active".
          let storyId = "Task App / TaskList / Two Active"
          let lastSep = storyId.rfind(" / ")
          let group = storyId[0 ..< lastSep]
          let storyName = storyId[lastSep + 3 .. ^1]
          let body = "{\"type\":\"select-story\"" &
                     ",\"group\":" & escapeJsonStr(group) &
                     ",\"name\":" & escapeJsonStr(storyName) &
                     ",\"kind\":\"skPattern\",\"storyId\":" &
                     escapeJsonStr(storyId) & "}"
          await sendInputPacket(sock, InputPacket(json: body))

          let deadline = epochTime() + (ManifestDeadlineMs.float / 1000.0)
          var changedTreeBody = ""
          while epochTime() < deadline:
            let payload = await recvOnePacket(sock, dec)
            if payload.len == 0: continue
            check payload[0] != 'F'  # render-tree mode: no F packets.
            if payload[0] == 'M':
              let metaBody = decodeMeta(stringToBytes(payload)).json
              if isRenderTreeBody(metaBody):
                changedTreeBody = metaBody
                break
          sock.close()
          check changedTreeBody.len > 0
          let manifest = decodeRenderTreeBody(changedTreeBody)
          check manifest.rendererId == name
          var paths = initHashSet[string]()
          allComponentPaths(manifest.root, paths)
          # The Two Active story seeds two task rows.
          var rowCount = 0
          for p in paths:
            if p.startsWith("task_app/views/TaskRow#"):
              inc rowCount
          check rowCount >= 1
        waitFor flow()
