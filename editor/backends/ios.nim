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
  import std/[net, options, os, osproc, posix, streams, strutils, times]

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
    SourceInterfaceEnvVar = "ISONIM_IOS_SOURCE_INTERFACE"
      ## Optional Wi-Fi interface name (e.g. `en0`) used to scope
      ## outbound TCP connect()s onto a specific local route. On this
      ## host VPN tunnel interfaces (`utun111-113` with Tailscale-style
      ## 100.x.x.x addresses) interfere with the BSD socket layer's
      ## default route selection: `nc -v 192.168.100.156 8200` works,
      ## but `connect()` from Nim/Python returns ENOENT/EHOSTUNREACH.
      ## Setting `IP_BOUND_IF` via setsockopt forces the kernel to use
      ## the Wi-Fi interface and bypasses the VPN-induced quirk. If
      ## this env var is set to the empty string, the binding is
      ## skipped (preserves the previous default behaviour for any
      ## host where binding would itself be a regression).
    DefaultSourceInterface = "en0"
      ## macOS Wi-Fi interface name on standard Apple hardware. Used
      ## when `ISONIM_IOS_SOURCE_INTERFACE` is unset.
    IpBoundIf = cint(25)
      ## Numeric value of macOS's `IP_BOUND_IF` socket option (from
      ## `<netinet/in.h>`). We hard-code the integer rather than
      ## `importc`-ing it so this file still compiles under non-Apple
      ## SDKs that don't ship the header constant.
    EndpointEnvVar = "ISONIM_IOS_DEVICE_ENDPOINT"
      ## Preferred endpoint when explicitly configured. Format
      ## `<host>:<port>`, e.g. `192.168.1.42:8200`. When the configured
      ## endpoint refuses (device asleep, IP rotated by DHCP, …) we
      ## fall back to Bonjour discovery for `_isonim-stream._tcp` so
      ## the screenshot tool can still recover without manual handoff.
    ReadChunk = 64 * 1024
    BonjourServiceType = "_isonim-stream._tcp"
    BonjourBudgetSeconds = 5
      ## Total wall-clock budget for the Bonjour browse + resolve
      ## fallback. Tight on purpose: the screenshot tool's per-cell
      ## probe is bounded too; we want a fast fail when nothing is
      ## reachable so the user gets a clear "tap the icon" signal.
    ConnectTimeoutMs = 2_000
      ## TCP connect attempt timeout. Long enough to forgive a busy
      ## Wi-Fi network, short enough that the screenshot tool's 5 s
      ## probe budget can still cover one configured-endpoint attempt
      ## plus a Bonjour fallback round-trip.

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
      ncProc: Process
        ## When non-nil, we read the device's F-packet stream from
        ## this `/usr/bin/nc <host> <port>` subprocess instead of a
        ## direct TCP socket. macOS' `nc` links Network.framework and
        ## successfully connects to hosts that the BSD socket layer
        ## refuses with `EHOSTUNREACH` on tunnel-heavy machines (see
        ## `bindToWifiInterface` doc). The subprocess is the
        ## last-resort fallback when direct connect + interface-bound
        ## connect both fail.
      ncStream: Stream
      buffer: string

  proc newIosTcpFrameSource*(width = DefaultWidth;
                             height = DefaultHeight;
                             deviceHost = "";
                             devicePort = 0): IosTcpFrameSource =
    IosTcpFrameSource(width: width, height: height,
                      deviceHost: deviceHost,
                      devicePort: devicePort,
                      socket: nil,
                      ncProc: nil,
                      ncStream: nil,
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
    ## Read from the active transport (direct socket or `nc` relay
    ## subprocess) into `src.buffer` until it has at least `minLen`
    ## bytes. Raises if the peer closes mid-read.
    while src.buffer.len < minLen:
      var chunk = newString(ReadChunk)
      var n: int
      if src.socket != nil:
        n = src.socket.recv(addr chunk[0], chunk.len)
      elif src.ncStream != nil:
        n = src.ncStream.readData(addr chunk[0], chunk.len)
      else:
        raise newException(IOError,
          "iOS launcher: no active transport when reading from device.")
      if n <= 0:
        raise newException(IOError,
          "iOS launcher: device closed the TCP stream while waiting " &
          "for " & $minLen & " bytes (have " & $src.buffer.len & ").")
      chunk.setLen(n)
      src.buffer.add chunk

  proc bindToWifiInterface(sock: Socket) =
    ## Pin the outbound socket to the macOS Wi-Fi interface via
    ## `IP_BOUND_IF` before `connect()`. This works around a routing
    ## quirk that hits hosts with active VPN tunnel interfaces
    ## (`utun*`, Tailscale 100.x.x.x): the BSD socket layer's default
    ## route-selection can end up choosing the tunnel for a destination
    ## that is actually reachable on Wi-Fi, returning `EHOSTUNREACH`
    ## from `connect()` even though `nc <host> <port>` from the same
    ## shell succeeds. Binding to `en0` (or whatever interface the
    ## `ISONIM_IOS_SOURCE_INTERFACE` env var names) forces the kernel
    ## to source the connection from that interface and resolves the
    ## routing failure.
    ##
    ## No-op on non-macOS. No-op when the env var is explicitly set to
    ## the empty string (escape hatch for hosts where binding itself
    ## would be a regression). No-op if `if_nametoindex` returns 0
    ## (the interface doesn't exist on this host): the original
    ## connect() then runs unconstrained — preserving the previous
    ## behaviour for non-Apple hardware.
    let envVal = getEnv(SourceInterfaceEnvVar)
    let ifname =
      if existsEnv(SourceInterfaceEnvVar): envVal
      else: DefaultSourceInterface
    if ifname.len == 0:
      return
    let ifindex = if_nametoindex(cstring(ifname))
    if ifindex == 0:
      return
    var idx = ifindex
    discard setsockopt(sock.getFd(), IPPROTO_IP, IpBoundIf,
                       addr idx, SockLen(sizeof(idx)))

  proc tryConnectViaNc(host: string; port: int):
      Option[tuple[p: Process, s: Stream]] =
    ## Fall back to `/usr/bin/nc <host> <port>` as the byte transport.
    ## Apple's `nc` links Network.framework, whose route selection
    ## handles VPN-tunnel interference that the BSD socket layer
    ## cannot (Tailscale-style `utun*` interfaces on the same host
    ## cause direct `connect()` to return `EHOSTUNREACH` for hosts
    ## that are actually reachable via Wi-Fi). The launcher then
    ## reads F-packet bytes from `nc`'s stdout exactly as if it had
    ## opened the socket itself. We verify the subprocess is still
    ## alive after a short settle window before returning so a
    ## fast-failed `nc` (wrong host, etc.) doesn't masquerade as a
    ## live transport.
    if host.len == 0 or port <= 0:
      return none((Process, Stream))
    var p: Process
    try:
      p = startProcess("/usr/bin/nc",
        args = [host, $port],
        options = {poUsePath})
    except OSError:
      return none((Process, Stream))
    # Give `nc` ~250 ms to either fail fast (e.g. "No route to host")
    # or settle into the connected state. The screenshot tool's outer
    # 30 s frame-paint budget swallows this comfortably.
    sleep(250)
    if not p.running:
      try: p.close() except OSError: discard
      return none((Process, Stream))
    return some((p, p.outputStream()))

  proc tryConnect(host: string; port: int;
                  timeoutMs: int): Option[Socket] =
    ## Open a TCP connection to `host:port` with a hard wall-clock
    ## timeout. Returns `none` on connect failure / timeout so the
    ## caller can decide whether to retry via Bonjour. We deliberately
    ## use `connect(..., timeout)` instead of the default blocking
    ## variant — without a timeout an unreachable iPhone (asleep,
    ## off-network) leaves the launcher hanging until the screenshot
    ## tool's outer 30 s budget fires, masking the real diagnosis.
    if host.len == 0 or port <= 0:
      return none(Socket)
    let s = newSocket(buffered = false)
    bindToWifiInterface(s)
    try:
      s.connect(host, Port(port), timeout = timeoutMs)
      return some(s)
    except CatchableError:
      try: s.close()
      except CatchableError: discard
      return none(Socket)

  proc discoverViaBonjour(budgetSeconds: int):
      Option[tuple[host: string, port: int]] =
    ## Browse + resolve the `_isonim-stream._tcp` Bonjour service via
    ## macOS's `dns-sd` CLI (built into the OS — no Nix-managed
    ## dependency, no `dns_sd.h` FFI to maintain). The output is text
    ## and the parsing is fragile by nature; we lean on three
    ## conventions that have been stable across recent macOS releases:
    ##
    ##   * `dns-sd -B <type> local.` lists candidates one per line
    ##     after a 4-column header. The instance name is the
    ##     concatenation of all tokens after the 6th column.
    ##   * `dns-sd -L <instance> <type> local.` echoes a "can be
    ##     reached at <host>:<port>" line once it resolves the
    ##     SRV/TXT pair.
    ##
    ## Both invocations stay running until killed; we read for at
    ## most `budgetSeconds` total, then send SIGTERM. On any parse
    ## failure or timeout we return `none` so the caller surfaces the
    ## standard "device unreachable" error.
    if budgetSeconds <= 0: return none((string, int))
    let deadline = epochTime() + float(budgetSeconds)

    # --- Browse: find the first instance name on the local domain ---
    var browseProc: Process
    try:
      browseProc = startProcess("/usr/bin/dns-sd",
        args = ["-B", BonjourServiceType, "local."],
        options = {poStdErrToStdOut, poUsePath})
    except OSError:
      return none((string, int))
    defer:
      try: browseProc.terminate()
      except OSError: discard
      try: browseProc.close()
      except OSError: discard

    var instanceName = ""
    let browseStream = browseProc.outputStream()
    while epochTime() < deadline:
      if browseStream.atEnd: break
      let line = browseStream.readLine()
      # Sample line:
      #   timestamp Add 3 4 local. _isonim-stream._tcp. <name…>
      if line.len == 0: continue
      let tokens = line.splitWhitespace()
      if tokens.len < 7: continue
      if tokens[1] != "Add": continue
      if not tokens[5].startsWith(BonjourServiceType): continue
      instanceName = tokens[6 .. ^1].join(" ")
      break
    try: browseProc.terminate()
    except OSError: discard
    if instanceName.len == 0:
      return none((string, int))

    # --- Resolve: ask `dns-sd -L` for the SRV record ---
    let remaining = deadline - epochTime()
    if remaining <= 0: return none((string, int))
    var resolveProc: Process
    try:
      resolveProc = startProcess("/usr/bin/dns-sd",
        args = ["-L", instanceName, BonjourServiceType, "local."],
        options = {poStdErrToStdOut, poUsePath})
    except OSError:
      return none((string, int))
    defer:
      try: resolveProc.terminate()
      except OSError: discard
      try: resolveProc.close()
      except OSError: discard

    let resolveStream = resolveProc.outputStream()
    while epochTime() < deadline:
      if resolveStream.atEnd: break
      let line = resolveStream.readLine()
      # Sample line:
      #   timestamp <instance>._isonim-stream._tcp.local. can be reached
      #     at iPhone.local.:8200 (interface 12)
      let idx = line.find("can be reached at ")
      if idx < 0: continue
      let tail = line[idx + len("can be reached at ") .. ^1].strip()
      let endpoint = tail.split(' ')[0]
      let colon = endpoint.rfind(':')
      if colon <= 0: continue
      var host = endpoint[0 ..< colon]
      let portStr = endpoint[colon + 1 .. ^1]
      var port: int
      try: port = parseInt(portStr)
      except ValueError: continue
      # Strip the trailing `.` Bonjour appends to fully-qualified names.
      if host.endsWith('.'): host = host[0 ..< host.len - 1]
      return some((host: host, port: port))
    none((string, int))

  proc connectIfNeeded(src: IosTcpFrameSource) =
    if src.socket != nil or src.ncProc != nil:
      return
    # Step 1: try the explicitly-configured endpoint (CLI flag / env
    # var). This is the fast path when the iPhone is awake and on the
    # same Wi-Fi address it had last time. `tryConnect` first sets
    # `IP_BOUND_IF` to scope the connect to the Wi-Fi interface; that
    # is enough on stock macOS hosts.
    var sockOpt = tryConnect(src.deviceHost, src.devicePort,
                             ConnectTimeoutMs)
    if sockOpt.isSome:
      src.socket = sockOpt.get()
      return
    # Step 2: fall back to Bonjour. If DHCP rotated the iPhone's IP
    # we need a fresh address; if the device just woke up the
    # NWListener may have re-published with a different port number.
    let discovered = discoverViaBonjour(BonjourBudgetSeconds)
    if discovered.isSome:
      let (host, port) = discovered.get()
      sockOpt = tryConnect(host, port, ConnectTimeoutMs)
      if sockOpt.isSome:
        # Cache the discovered endpoint so subsequent reconnects in the
        # same session don't pay the Bonjour cost again.
        src.deviceHost = host
        src.devicePort = port
        src.socket = sockOpt.get()
        return
    # Step 3: last-resort, spawn `/usr/bin/nc <host> <port>` as a
    # transport. Apple's `nc` links Network.framework, which handles
    # VPN-tunnel-induced route confusion that BSD `connect()` cannot
    # (even with `IP_BOUND_IF`). On hosts where steps 1+2 fail with
    # `EHOSTUNREACH` despite the device being reachable from the
    # shell via `nc`, this fallback wins.
    let ncOpt = tryConnectViaNc(src.deviceHost, src.devicePort)
    if ncOpt.isSome:
      let (p, s) = ncOpt.get()
      src.ncProc = p
      src.ncStream = s
      return
    # All recovery paths exhausted — surface the clearest possible
    # message so the screenshot tool can pattern-match it (and the
    # user knows what to do).
    raise newException(IOError,
      "iOS launcher: device unreachable. Tap the IsoNim Stream icon " &
      "on the iPhone to wake the device, then re-run. (Tried " &
      "configured endpoint `" & src.deviceHost & ":" & $src.devicePort &
      "`, Bonjour `" & BonjourServiceType & "` browse/resolve, and " &
      "`/usr/bin/nc` relay.)")

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
    if src.ncProc != nil:
      try: src.ncProc.terminate()
      except OSError: discard
      try: src.ncProc.close()
      except OSError: discard
      src.ncProc = nil
      src.ncStream = nil

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
    ##   3. Bonjour DNS-SD browse for `_isonim-stream._tcp` — handled
    ##      lazily inside `connectIfNeeded` so the launcher boots even
    ##      when no endpoint is configured (the device may just need a
    ##      moment to publish itself).
    ## Returns `("", 0)` if neither (1) nor (2) is set; the connect
    ## path then goes straight to Bonjour discovery.
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
    # Minimal element-tree provider so the editor's
    # `waitForCanvasManifest` gate (which insists on a populated
    # `window.__isonimManifest`) passes for iOS cells. The device app
    # owns its own UIKit element tree and the launcher has no FFI to
    # introspect it; we emit a single root entry covering the whole
    # surface so the editor can render the iframe + canvas overlay
    # without a per-element story. Real per-element manifests come
    # in a later iOS milestone alongside an on-device tree probe.
    let capturedSrc = src
    let provider = ElementTreeProvider(
      buildImpl: proc(): ElementTreeManifest {.gcsafe.} =
        {.cast(gcsafe).}:
          let sw = max(1, capturedSrc.width)
          let sh = max(1, capturedSrc.height)
          ElementTreeManifest(
            frameSeq: 0,
            surfaceWidth: sw,
            surfaceHeight: sh,
            boundsUnit: "pixels",
            elements: @[
              ElementEntry(
                id: "ios-root",
                componentPath: "ios/root",
                kind: "root",
                bounds: ElementBounds(x: 0, y: 0, w: sw, h: sh))]))
    var bridgeCfg = cfg
    if bridgeCfg.port == 0:
      bridgeCfg.port = BridgePort
    runDemoBridgeWith(bridgeCfg, src.toAny(), provider)

  proc runDemoBridge*(backend: string) =
    let cfg = parseLauncherArgs(backend)
    runIosDemo(cfg)

  when isMainModule:
    runDemoBridge("ios")
