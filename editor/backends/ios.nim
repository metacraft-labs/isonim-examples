## editor/backends/ios.nim — iOS-backend launcher for the demo editor.
##
## Host-side binary that talks to a UIKit app running on a paired
## iPhone over Wi-Fi. The on-device counterpart is owned by another
## sub-agent; this launcher only consumes the F-packet stream the
## device produces.
##
## Transport:
##
##   1. Discover the device's TCP endpoint. The device advertises
##      itself via Apple's Bonjour DNS-SD as `_isonim-stream._tcp`.
##      Implementing a full Bonjour browser in Nim (via the `dnssd`
##      FFI) is a yak; for the prototype we accept an explicit
##      endpoint via the `ISONIM_IOS_DEVICE_ENDPOINT=<host>:<port>`
##      env var OR the `--device-host <host>:<port>` CLI flag. When
##      neither is set we fail with a clear error so users know how
##      to point us at the device.
##
##   2. Open a TCP socket to the device. The device then sends F
##      packet bytes continuously (the same 14-byte header + payload
##      layout `isonim_render_serve/packet.nim` defines).
##
##   3. For each decoded F packet we hand a `Frame` to the bridge via
##      an `AnyFrameSource`. `renderFrameImpl` blocks on the next
##      packet — the bridge calls it once per `frameIntervalMs`.
##
## Gated `when defined(macosx):` — iOS dev tooling (Bonjour, Wi-Fi
## pairing, the Xcode-side recorder) is Mac-only. Linux iOS-on-
## network is theoretically possible but out-of-scope for the
## prototype.
##
## No `-d:mockJni`-style host-side mock tree (mirrors the android.nim
## `else` branch at line 211-213): the device owns its VM lifecycle
## and the launcher has no FFI / IPC channel into it. Story-dispatch
## I packets land in a buffered sink and are echoed to the device
## once the dispatcher path lands in a follow-up.

when defined(macosx):
  import std/[net, os, strutils]

  import isonim_render_serve

  import editor/backends/common

  const
    DefaultWidth = 390   ## iPhone 14 portrait logical width
    DefaultHeight = 844  ## iPhone 14 portrait logical height
    BridgePort = 8107
      ## Host launcher's bridge port for the editor's WebSocket
      ## (matches `bridgePortForBackend(pbIos)` in
      ## `isonim/src/isonim/editor/streaming_preview.nim` and the
      ## `ios: 8107` entry in `tools/editor-server.mjs`).
    EndpointEnvVar = "ISONIM_IOS_DEVICE_ENDPOINT"
      ## Fallback endpoint when Bonjour discovery is not wired.
      ## Format: `<host>:<port>`, e.g. `192.168.1.42:8200`.
    ReadChunk = 64 * 1024

  type
    IosTcpFrameSource* = ref object
      ## Frame source wrapping a TCP connection to the device. The
      ## socket is opened lazily on the first `captureFrame` call so
      ## construction-time failures don't blow up the launcher before
      ## the bridge has a chance to bind its port.
      width*, height*: int
      deviceHost*: string
      devicePort*: int
      socket: Socket
      buffer: string

  proc newIosTcpFrameSource*(width = DefaultWidth;
                             height = DefaultHeight;
                             deviceHost = "";
                             devicePort = 0): IosTcpFrameSource =
    IosTcpFrameSource(width: width, height: height,
                      deviceHost: deviceHost,
                      devicePort: devicePort,
                      socket: nil,
                      buffer: "")

  proc parseEndpoint(s: string): tuple[host: string, port: int] =
    let i = s.rfind(':')
    if i < 0:
      raise newException(ValueError,
        "endpoint must be `<host>:<port>`, got: " & s)
    result.host = s[0 ..< i]
    result.port = parseInt(s[i + 1 .. ^1])

  proc readU32LE(s: string; off: int): uint32 =
    uint32(s[off].byte) or
      (uint32(s[off + 1].byte) shl 8) or
      (uint32(s[off + 2].byte) shl 16) or
      (uint32(s[off + 3].byte) shl 24)

  proc ensureBuffer(src: IosTcpFrameSource; minLen: int) =
    ## Read from the socket into `src.buffer` until it has at least
    ## `minLen` bytes (or the peer closes — in which case we raise).
    while src.buffer.len < minLen:
      var chunk = newString(ReadChunk)
      let n = src.socket.recv(addr chunk[0], chunk.len)
      if n <= 0:
        raise newException(IOError,
          "iOS launcher: device closed the TCP stream while waiting " &
          "for " & $minLen & " bytes (have " & $src.buffer.len & ").")
      chunk.setLen(n)
      src.buffer.add chunk

  proc connectIfNeeded(src: IosTcpFrameSource) =
    if src.socket != nil:
      return
    if src.deviceHost.len == 0 or src.devicePort <= 0:
      raise newException(IOError,
        "iOS launcher: no device endpoint configured. Pass " &
        "--device-host <host>:<port> or set " & EndpointEnvVar &
        "=<host>:<port>. Bonjour discovery for `_isonim-stream._tcp` " &
        "is a planned follow-up.")
    let s = newSocket(buffered = false)
    s.connect(src.deviceHost, Port(src.devicePort))
    src.socket = s

  proc captureFrame*(src: IosTcpFrameSource): Frame =
    ## Block on the next F packet from the device, decode it, and
    ## return the resulting `Frame`. Diff packets are passed through
    ## as-is; full frames are returned in their native dimensions
    ## (the launcher does not rescale).
    src.connectIfNeeded()
    src.ensureBuffer(14)
    if src.buffer[0] != 'F':
      raise newException(IOError,
        "iOS launcher: expected F packet tag, got 0x" &
        toHex(src.buffer[0].byte.int, 2) &
        " (the device may be sending a different protocol).")
    let flags = src.buffer[1].byte
    let w = int(readU32LE(src.buffer, 2))
    let h = int(readU32LE(src.buffer, 6))
    let length = int(readU32LE(src.buffer, 10))
    src.ensureBuffer(14 + length)
    let isDiff = (flags and 0x01'u8) != 0
    let pixels = block:
      var raw = newSeq[byte](length)
      for i in 0 ..< length:
        raw[i] = byte(src.buffer[14 + i])
      raw
    # Trim the consumed bytes off the head of the buffer.
    src.buffer = src.buffer[14 + length .. ^1]
    if isDiff:
      # Full diff-rect decoding is deferred. For the prototype the
      # device only sends full frames; if we ever see a diff packet
      # we surface a clear error so the contract is explicit.
      raise newException(IOError,
        "iOS launcher: diff F packets not yet supported by the host " &
        "decoder. Reconfigure the device app to send full frames.")
    # Sanity-check the payload length against the header dimensions.
    if length != w * h * 4:
      raise newException(IOError,
        "iOS launcher: F payload length " & $length & " != w*h*4 (" &
        $(w * h * 4) & ") for " & $w & "x" & $h & ".")
    # Keep the source's width/height in sync with what the device
    # advertised. The bridge reads these on the next `hello` rebuild
    # (or a launcher-side resize follow-up).
    src.width = w
    src.height = h
    Frame(kind: fkFull,
          flags: FrameFlags(isDiff: false, isVideo: false),
          width: w, height: h, pixels: pixels)

  proc closeSource(src: IosTcpFrameSource) =
    if src.socket != nil:
      try: src.socket.close()
      except CatchableError: discard
      src.socket = nil

  proc toAny*(src: IosTcpFrameSource): AnyFrameSource =
    let captured = src
    newAnyFrameSource(src.width, src.height,
      renderFrameImpl = proc(): Frame {.gcsafe.} =
        {.cast(gcsafe).}: captured.captureFrame(),
      closeImpl = proc() {.gcsafe.} =
        {.cast(gcsafe).}: captured.closeSource())

  proc resolveDeviceEndpoint(cfgFromArgv: string):
      tuple[host: string, port: int] =
    ## Endpoint resolution order:
    ##   1. `--device-host <host>:<port>` CLI flag (preferred for
    ##      tests and explicit debugging).
    ##   2. `ISONIM_IOS_DEVICE_ENDPOINT=<host>:<port>` env var.
    ##   3. (Future) Bonjour DNS-SD browse for `_isonim-stream._tcp`.
    ## Returns `("", 0)` if none is set; the source then raises a
    ## clear error on the first capture attempt.
    if cfgFromArgv.len > 0:
      return parseEndpoint(cfgFromArgv)
    let envVal = getEnv(EndpointEnvVar)
    if envVal.len > 0:
      return parseEndpoint(envVal)
    ("", 0)

  proc parseExtraIosArgs(): string =
    ## Walk argv looking for `--device-host <value>` /
    ## `--device-host=<value>`. The shared `parseLauncherArgs` helper
    ## ignores unknown flags by design, so we make a second pass here
    ## without disturbing its CLI contract.
    var i = 1
    while i <= paramCount():
      let arg = paramStr(i)
      if arg.startsWith("--device-host="):
        return arg.substr(len("--device-host="))
      if arg == "--device-host":
        if i + 1 <= paramCount():
          return paramStr(i + 1)
      inc i
    ""

  proc runIosDemo(cfg: LauncherConfig) =
    let w = if cfg.width > 0: cfg.width else: DefaultWidth
    let h = if cfg.height > 0: cfg.height else: DefaultHeight
    let extra = parseExtraIosArgs()
    let (host, port) = resolveDeviceEndpoint(extra)
    let src = newIosTcpFrameSource(width = w, height = h,
                                   deviceHost = host,
                                   devicePort = port)
    var bridgeCfg = cfg
    if bridgeCfg.port == 0:
      bridgeCfg.port = BridgePort
    runDemoBridgeWith(bridgeCfg, src.toAny())

  proc runDemoBridge*(backend: string) =
    let cfg = parseLauncherArgs(backend)
    runIosDemo(cfg)

  when isMainModule:
    runDemoBridge("ios")
