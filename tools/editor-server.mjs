// Editor server with same-origin WebSocket proxying.
//
// Replaces `python3 -m http.server 8091` so the editor can be served to a
// remote browser. The browser's hardcoded `ws://127.0.0.1:<port>` would
// resolve to the browser's own loopback (no launchers there), which fails for
// any reviewer not running locally on the editor host.
//
// This server:
//  * Serves the static editor bundle from `build/editor/` on the configured
//    port (default 8091).
//  * Proxies WS upgrades on `/bridge/<backend>` to the matching launcher
//    listening on 127.0.0.1:<port>. The path-based URL means the browser
//    always connects to the same origin as the page; we tunnel inside.
//
// The editor JS bundle is responsible for producing `ws://<location.host>/bridge/<backend>`
// URLs (see `bridgeUrlForBackend` in src/isonim/editor/streaming_preview.nim).

import { createServer, request as httpRequest } from 'node:http';
import { connect as tcpConnect } from 'node:net';
import { readFile, stat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join, normalize, sep } from 'node:path';

const PORT = Number.parseInt(process.env.PORT || '8091', 10);
const ROOT = process.env.EDITOR_STATIC_ROOT
  ? process.env.EDITOR_STATIC_ROOT
  : join(dirname(fileURLToPath(import.meta.url)), '..', 'build', 'editor');

// Daemon HTTP API proxy — forwards /api/* to the local isonim-review
// daemon (default 127.0.0.1:8113). Lets the editor JS bundle call
// /api/design-review/*, /api/agent/*, /api/campaign/* via the SAME
// origin as the editor, so:
//   * cross-machine access works (the daemon stays bound to loopback,
//     this server is the only listener exposed to the LAN);
//   * the browser never makes a cross-port fetch (no CORS headers
//     required on the daemon).
const DAEMON_HOST = process.env.ISONIM_DAEMON_HOST || '127.0.0.1';
const DAEMON_PORT = Number.parseInt(
  process.env.ISONIM_DAEMON_PORT || '8113',
  10,
);

// Per-backend launcher port table — must match
// `bridgePortForBackend` in src/isonim/editor/streaming_preview.nim.
//
// RS-M13: the TUI launcher moved to a separate transport (D/M/P via
// `isonim-tui-serve`) on a new port (8112) and a new proxy route
// (`/tui-bridge`). The historical `tui: 8102` entry stays here for
// one release cycle so the deprecated pixel TUI launcher (built via
// `just build-backends-dev-pixel-tui`) is still proxied if someone
// boots it; new traffic should target `tui-term`.
const BRIDGE_PORTS = {
  tui: 8102,
  'tui-term': 8112,
  gpui: 8103,
  freya: 8104,
  cocoa: 8105,
  android: 8106,
  ios: 8107,
};

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
};

function mimeFor(path) {
  const dot = path.lastIndexOf('.');
  if (dot < 0) return 'application/octet-stream';
  return MIME[path.substring(dot)] || 'application/octet-stream';
}

async function safePath(reqUrl) {
  let p = decodeURIComponent(reqUrl.split('?')[0]);
  if (p === '/' || p === '') p = '/index.html';
  // Strip any leading slashes then resolve to prevent escape.
  p = normalize(p).replace(/^[/\\]+/, '');
  const full = join(ROOT, p);
  // Ensure resolved path is still inside ROOT.
  if (!full.startsWith(ROOT + sep) && full !== ROOT) {
    return null;
  }
  try {
    const s = await stat(full);
    if (s.isDirectory()) {
      // Serve index.html from directories.
      return safePath('/' + p.replace(/\/+$/, '') + '/index.html');
    }
    return full;
  } catch {
    return null;
  }
}

// Proxy /api/* HTTP requests to the daemon. Streams request and
// response bodies bidirectionally; preserves headers verbatim except
// for `host`, which we rewrite to the daemon's address so the daemon
// sees the request as local.
function proxyToDaemon(req, res) {
  const headers = { ...req.headers };
  delete headers.host;
  headers.host = `${DAEMON_HOST}:${DAEMON_PORT}`;

  const upstream = httpRequest(
    {
      host: DAEMON_HOST,
      port: DAEMON_PORT,
      method: req.method,
      path: req.url,
      headers,
    },
    (upRes) => {
      res.writeHead(upRes.statusCode || 502, upRes.headers);
      upRes.pipe(res);
    },
  );
  upstream.on('error', (e) => {
    if (!res.headersSent) {
      res.writeHead(502, { 'content-type': 'text/plain' });
    }
    res.end(`daemon proxy error: ${e.message}`);
  });
  req.pipe(upstream);
}

// Rewrite `index.html` on the fly to inject a `<meta
// name="isonim-review-api">` tag pointing at this same-origin server,
// so the editor's `daemon_discovery` resolves to the proxy rather than
// to `<location.host-without-port>:8113` (the latter only works when
// the daemon is bound to the LAN, which it isn't by default).
//
// CHRM-M6 opt-in: when `ISONIM_REVIEW_API_FOR_SCREENSHOTS` is set
// (the editor-screenshot.mjs daemon path), the meta tag content is
// REPLACED with that env var's value rather than `http://<host>`. The
// daemon spawned by editor-screenshot.mjs binds to a per-run ephemeral
// port (parsed via the READY handshake) — pointing the editor at it
// directly means the editor's `daemon_discovery` fetches go straight
// to that daemon (not through the proxy on this server). The daemon
// already handles CORS preflight for /api/design-review/* so a cross-
// port fetch works.
const REVIEW_API_OVERRIDE_FOR_SCREENSHOTS =
  process.env.ISONIM_REVIEW_API_FOR_SCREENSHOTS || "";

function injectDaemonMeta(html, host) {
  const apiBase =
    REVIEW_API_OVERRIDE_FOR_SCREENSHOTS.length > 0
      ? REVIEW_API_OVERRIDE_FOR_SCREENSHOTS
      : `http://${host}`;
  const tag = `<meta name="isonim-review-api" content="${apiBase}">`;
  return html.replace(/<head>/i, `<head>\n    ${tag}`);
}

const server = createServer(async (req, res) => {
  const url = req.url || '/';
  // Daemon HTTP API proxy — anything under /api/* goes to the daemon.
  if (url.startsWith('/api/')) {
    proxyToDaemon(req, res);
    return;
  }

  const full = await safePath(url);
  if (!full) {
    res.writeHead(404, { 'content-type': 'text/plain' });
    res.end('not found');
    return;
  }
  try {
    let body = await readFile(full);
    const contentType = mimeFor(full);
    // Inject the daemon meta tag into the index page so the editor
    // bundle's daemon discovery resolves to this same-origin server.
    if (full.endsWith('index.html')) {
      const host = req.headers.host || `${DAEMON_HOST}:${PORT}`;
      body = Buffer.from(injectDaemonMeta(body.toString('utf-8'), host), 'utf-8');
    }
    res.writeHead(200, {
      'content-type': contentType,
      'cache-control': 'no-store',
    });
    res.end(body);
  } catch (e) {
    res.writeHead(500, { 'content-type': 'text/plain' });
    res.end('read error');
  }
});

server.on('upgrade', (req, clientSocket, head) => {
  // Path-based bridge routing: /bridge/tui -> 127.0.0.1:8102, etc.
  //
  // RS-M13 adds a parallel `/tui-bridge` route (the new D/M/P
  // terminal transport on port 8112). Same proxy mechanics — the path
  // is rewritten to `/` before forwarding so the launcher sees a
  // direct-client request.
  const url = req.url || '';
  let backend = null;
  const tuiBridgeMatch = url.match(/^\/tui-bridge(?:\/.*)?$/);
  if (tuiBridgeMatch) {
    backend = 'tui-term';
  } else {
    const bridgeMatch = url.match(/^\/bridge\/([a-z]+)(?:\/.*)?$/);
    if (bridgeMatch) {
      backend = bridgeMatch[1];
    }
  }
  if (!backend) {
    clientSocket.write('HTTP/1.1 404 Not Found\r\n\r\n');
    clientSocket.destroy();
    return;
  }
  const port = BRIDGE_PORTS[backend];
  if (!port) {
    clientSocket.write('HTTP/1.1 404 Not Found\r\n\r\n');
    clientSocket.destroy();
    return;
  }
  // Open a TCP socket to the launcher and forward the upgrade request
  // verbatim. After the launcher's 101 response, both sides just pipe
  // raw bytes (RFC 6455 framing is opaque to us).
  const upstream = tcpConnect({ host: '127.0.0.1', port }, () => {
    // Rebuild the HTTP/1.1 request preserving headers but rewriting Host
    // and the path (strip the /bridge/<backend> prefix so the launcher
    // sees `/` like a direct client would).
    const lines = [];
    lines.push(`GET / HTTP/1.1`);
    for (const [k, v] of Object.entries(req.headers)) {
      if (k.toLowerCase() === 'host') {
        lines.push(`Host: 127.0.0.1:${port}`);
      } else {
        const values = Array.isArray(v) ? v : [v];
        for (const vv of values) lines.push(`${k}: ${vv}`);
      }
    }
    lines.push('\r\n');
    upstream.write(lines.join('\r\n'));
    if (head && head.length) upstream.write(head);
    upstream.pipe(clientSocket);
    clientSocket.pipe(upstream);
  });
  upstream.on('error', (e) => {
    try {
      clientSocket.write(
        `HTTP/1.1 502 Bad Gateway\r\nContent-Type: text/plain\r\n\r\n` +
          `launcher ${backend} unreachable: ${e.message}`,
      );
    } catch {}
    clientSocket.destroy();
  });
  clientSocket.on('error', () => upstream.destroy());
  clientSocket.on('close', () => upstream.destroy());
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[editor-server] serving ${ROOT} on http://0.0.0.0:${PORT}`);
  console.log(`[editor-server] /api/* -> ${DAEMON_HOST}:${DAEMON_PORT}  (isonim-review daemon)`);
  console.log(`[editor-server] bridge routes:`);
  for (const [k, v] of Object.entries(BRIDGE_PORTS)) {
    if (k === 'tui-term') {
      console.log(`  /tui-bridge -> 127.0.0.1:${v}  (RS-M13 D/M/P xterm.js)`);
    } else {
      console.log(`  /bridge/${k} -> 127.0.0.1:${v}`);
    }
  }
});
