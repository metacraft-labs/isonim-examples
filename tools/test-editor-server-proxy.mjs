// RS-M13: editor-server proxy unit test.
//
// Spawns:
//   1. A tiny WS-upgrade-capture server on an ephemeral port (the
//      mock TUI launcher).
//   2. `tools/editor-server.mjs` on a second ephemeral port, pointed
//      at the mock launcher via `BRIDGE_PORTS=tui-term:<port>`.
//
// Then issues HTTP/1.1 upgrade requests against the editor server
// and asserts:
//   - `/tui-bridge` is proxied to the mock launcher with the `Host`
//     header rewritten to `127.0.0.1:<launcher-port>`.
//   - `/tui-bridge/extra/path` ALSO matches the route (the regex
//     allows trailing path segments, so the launcher receives the
//     same `GET /` it would from a direct client).
//   - `/bridge/nonexistent` returns 404 from the editor server.
//
// Real subprocess + real TCP — no in-process mocks beyond a
// hand-rolled WS-handshake-recording server (which is a real Node
// server, just one that doesn't fully upgrade — it captures the
// HTTP request line and headers and replies with 101 stub).

import { strict as assert } from 'node:assert';
import { spawn } from 'node:child_process';
import { createServer, request as httpRequest } from 'node:http';
import { connect as netConnect } from 'node:net';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Capture-server: replies 101 Switching Protocols, records the GET
// request line + Host header. It does NOT do RFC-6455 framing — the
// proxy test only asserts the upgrade request is forwarded.
function startCaptureServer() {
  return new Promise((resolve) => {
    const captured = [];
    const server = createServer();
    server.on('upgrade', (req, socket /*, head*/) => {
      captured.push({
        url: req.url,
        host: req.headers.host,
        upgrade: req.headers.upgrade,
        connection: req.headers.connection,
      });
      socket.write(
        'HTTP/1.1 101 Switching Protocols\r\n' +
          'Upgrade: websocket\r\n' +
          'Connection: Upgrade\r\n' +
          'Sec-WebSocket-Accept: ZmFrZWtleQ==\r\n\r\n',
      );
    });
    server.listen(0, '127.0.0.1', () => {
      resolve({ server, port: server.address().port, captured });
    });
  });
}

function startEditorServer(staticRoot, port, captureLauncherPort) {
  // Patch BRIDGE_PORTS by setting env-overrides — but editor-server
  // reads them from a constant in the module today. The simplest
  // robust shim: copy the module to a temp dir, replace the
  // BRIDGE_PORTS literal so `tui-term` points to the capture port,
  // then spawn the patched copy.
  const srcPath = join(__dirname, 'editor-server.mjs');
  const fsMod = import('node:fs').then((m) => m);
  return fsMod.then(async (fs) => {
    const src = fs.readFileSync(srcPath, 'utf8');
    const patched = src.replace(
      /'tui-term': 8112/,
      `'tui-term': ${captureLauncherPort}`,
    );
    const td = mkdtempSync(join(tmpdir(), 'editor-server-test-'));
    const patchedPath = join(td, 'editor-server.mjs');
    writeFileSync(patchedPath, patched, 'utf8');
    const proc = spawn(process.execPath, [patchedPath], {
      env: {
        ...process.env,
        PORT: String(port),
        EDITOR_STATIC_ROOT: staticRoot,
      },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    // Wait until the editor server prints "[editor-server] serving".
    await new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error('editor-server did not start within 5s')),
        5000,
      );
      proc.stdout.on('data', (chunk) => {
        const s = chunk.toString();
        if (s.includes('[editor-server] serving')) {
          clearTimeout(timer);
          resolve();
        }
      });
    });
    return proc;
  });
}

function makeUpgradeRequest(host, port, path) {
  return new Promise((resolve, reject) => {
    const sock = netConnect({ host, port }, () => {
      sock.write(
        `GET ${path} HTTP/1.1\r\n` +
          `Host: ${host}:${port}\r\n` +
          `Upgrade: websocket\r\n` +
          `Connection: Upgrade\r\n` +
          `Sec-WebSocket-Key: ZmFrZWtleQ==\r\n` +
          `Sec-WebSocket-Version: 13\r\n\r\n`,
      );
    });
    let buf = '';
    sock.on('data', (chunk) => {
      buf += chunk.toString();
      if (buf.includes('\r\n\r\n')) {
        sock.end();
        resolve(buf);
      }
    });
    sock.on('error', reject);
    sock.on('end', () => resolve(buf));
    sock.on('close', () => resolve(buf));
  });
}

function makeHttpRequest(host, port, path) {
  return new Promise((resolve, reject) => {
    const req = httpRequest({ host, port, path, method: 'GET' }, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () =>
        resolve({
          status: res.statusCode,
          body: Buffer.concat(chunks).toString('utf8'),
        }),
      );
    });
    req.on('error', reject);
    req.end();
  });
}

async function main() {
  // Set up a tmp static root so the editor server has something to
  // serve on GET / (avoids 404 on the liveness GET).
  const staticRoot = mkdtempSync(join(tmpdir(), 'editor-server-static-'));
  writeFileSync(join(staticRoot, 'index.html'), 'ok\n', 'utf8');

  const capture = await startCaptureServer();
  const editorPort = await new Promise((resolve) => {
    const sock = createServer();
    sock.listen(0, '127.0.0.1', () => {
      const p = sock.address().port;
      sock.close(() => resolve(p));
    });
  });
  const editorProc = await startEditorServer(
    staticRoot,
    editorPort,
    capture.port,
  );
  try {
    // 1. /tui-bridge → upgraded to the capture server.
    const resp1 = await makeUpgradeRequest('127.0.0.1', editorPort,
      '/tui-bridge');
    assert.match(
      resp1,
      /^HTTP\/1\.1 101/,
      'tui-bridge upgrade should yield 101: ' + resp1,
    );
    // Allow microtasks to deliver the capture event.
    await new Promise((r) => setTimeout(r, 50));
    assert.equal(capture.captured.length, 1,
      'expected one capture');
    const c1 = capture.captured[0];
    assert.equal(c1.url, '/',
      'tui-bridge proxy must rewrite path to /: ' + c1.url);
    assert.equal(c1.host, `127.0.0.1:${capture.port}`,
      'Host header must be rewritten: ' + c1.host);

    // 2. /tui-bridge/extra/path → also matched (regex allows tail).
    const resp2 = await makeUpgradeRequest('127.0.0.1', editorPort,
      '/tui-bridge/extra/path');
    assert.match(
      resp2,
      /^HTTP\/1\.1 101/,
      'tui-bridge/extra upgrade should yield 101: ' + resp2,
    );
    await new Promise((r) => setTimeout(r, 50));
    assert.equal(capture.captured.length, 2,
      'expected two captures');

    // 3. /bridge/nonexistent → 404 (no port mapping).
    const resp3 = await makeUpgradeRequest('127.0.0.1', editorPort,
      '/bridge/nonexistent');
    assert.match(
      resp3,
      /^HTTP\/1\.1 404/,
      'unknown backend should yield 404: ' + resp3,
    );

    // 4. Regular GET / serves the static root.
    const resp4 = await makeHttpRequest('127.0.0.1', editorPort, '/');
    assert.equal(resp4.status, 200);
    assert.ok(resp4.body.includes('ok'),
      'static GET should return index.html body');

    console.log('OK: /tui-bridge proxied; tail path matched; ' +
      'unknown backend 404; static GET 200.');
  } finally {
    editorProc.kill('SIGTERM');
    capture.server.close();
  }
}

main().catch((err) => {
  console.error('FAIL:', err);
  process.exit(1);
});
