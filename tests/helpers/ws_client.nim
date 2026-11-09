## helpers/ws_client.nim — the client half of the WebSocket opening
## handshake, shared by every test that drives a demo launcher's bridge
## over a real socket.
##
## The launcher bridges write their first frames (the ``hello`` meta
## packet, then the first element-tree manifest) immediately after the
## ``101 Switching Protocols`` response, so those frames regularly share
## a TCP segment with the response headers. A probe against the Freya
## launcher saw frame bytes in the same ``recv`` as the headers on 13 of
## 20 connections, and on 20 of 20 when the client paused 50 ms before
## reading. A handshake that reads "until ``\r\n\r\n``" and then throws
## the whole buffer away therefore loses the start of the frame stream:
## the first manifest goes missing, and when the cut lands inside a frame
## the decoder resynchronises on payload bytes and reports garbage
## (an out-of-range opcode, a frame packet "before" the manifest).
##
## ``wsClientHandshake`` returns those early bytes instead, and
## ``connectWsRaw`` hands them back to the caller, which must feed them to
## its frame decoder before reading anything else from the socket.
##
## The opening handshake is RFC 6455 §4.1 (client requirements) and §4.2.2
## (the server's response):
## https://www.rfc-editor.org/rfc/rfc6455#section-4

import std/[asyncdispatch, asyncnet, base64, net, strutils]

const HeaderTerminator = "\r\n\r\n"

proc recvSome*(fd: AsyncFD; size: int): Future[string] {.async.} =
  ## Read at most ``size`` bytes; an empty string means the peer closed.
  var buf = newString(size)
  let n = await asyncdispatch.recvInto(fd, addr buf[0], size)
  if n <= 0: return ""
  buf.setLen(n)
  result = buf

proc wsClientHandshake*(s: AsyncSocket; host: string;
                        port: int): Future[string] {.async.} =
  ## Send the upgrade request on the connected socket ``s``, wait for the
  ## complete response header and require ``101``. Returns every byte the
  ## server sent after the header terminator — the beginning of the frame
  ## stream, possibly empty, possibly ending inside a frame.
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
  while not resp.contains(HeaderTerminator):
    let chunk = await recvSome(fd, 4096)
    if chunk.len == 0: break
    resp.add(chunk)
  let terminatorAt = resp.find(HeaderTerminator)
  doAssert terminatorAt >= 0 and resp.startsWith("HTTP/1.1 101"),
    "handshake failed: " & resp
  result = resp[terminatorAt + HeaderTerminator.len .. ^1]

proc connectWsRaw*(port: int): Future[tuple[sock: AsyncSocket;
                                            early: string]] {.async.} =
  ## Connect to ``127.0.0.1:port`` and complete the opening handshake.
  ## ``early`` holds the frame bytes that arrived with the response; the
  ## caller feeds them to its decoder first.
  let sock = newAsyncSocket()
  await sock.connect("127.0.0.1", Port(port))
  let early = await wsClientHandshake(sock, "127.0.0.1", port)
  result = (sock: sock, early: early)
