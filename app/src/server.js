'use strict';

// notes-api: a deliberately small, dependency-free service used to exercise
// the platform. It has the behaviours a real workload needs on Kubernetes:
//   - separate liveness (/healthz) and readiness (/readyz) signals
//   - graceful shutdown on SIGTERM (stop taking traffic, drain, exit)
//   - state on a PersistentVolume (DATA_DIR), one file per note so that
//     several replicas can write to a shared RWX volume without locking

const http = require('node:http');
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');

const PORT = Number(process.env.PORT || 8080);
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, '..', 'data');
const APP_VERSION = process.env.APP_VERSION || 'dev';
const SHUTDOWN_DRAIN_MS = Number(process.env.SHUTDOWN_DRAIN_MS || 5000);
const MAX_BODY_BYTES = 16 * 1024;

const state = { ready: false, shuttingDown: false };

function log(level, msg, extra = {}) {
  process.stdout.write(
    JSON.stringify({ ts: new Date().toISOString(), level, msg, ...extra }) + '\n'
  );
}

function send(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(payload),
    'cache-control': 'no-store',
  });
  res.end(payload);
}

async function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > MAX_BODY_BYTES) {
        reject(Object.assign(new Error('payload too large'), { status: 413 }));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

async function dataDirWritable() {
  const probe = path.join(DATA_DIR, `.probe-${process.pid}`);
  try {
    await fsp.writeFile(probe, String(Date.now()));
    await fsp.unlink(probe);
    return true;
  } catch {
    return false;
  }
}

async function listNotes() {
  const files = (await fsp.readdir(DATA_DIR)).filter((f) => f.endsWith('.json'));
  const notes = await Promise.all(
    files.map(async (f) => {
      try {
        return JSON.parse(await fsp.readFile(path.join(DATA_DIR, f), 'utf8'));
      } catch {
        return null; // half-written or corrupt file: skip rather than 500
      }
    })
  );
  return notes.filter(Boolean).sort((a, b) => a.createdAt.localeCompare(b.createdAt));
}

async function createNote(text) {
  const note = {
    id: crypto.randomUUID(),
    text,
    createdAt: new Date().toISOString(),
    writtenBy: process.env.POD_NAME || 'local',
  };
  const final = path.join(DATA_DIR, `${note.id}.json`);
  const tmp = `${final}.tmp`;
  await fsp.writeFile(tmp, JSON.stringify(note));
  await fsp.rename(tmp, final); // atomic on the same filesystem
  return note;
}

async function handle(req, res) {
  const url = new URL(req.url, 'http://localhost');

  if (req.method === 'GET' && url.pathname === '/healthz') {
    return send(res, 200, { status: 'ok' });
  }

  if (req.method === 'GET' && url.pathname === '/readyz') {
    if (state.shuttingDown || !state.ready) {
      return send(res, 503, { status: 'not-ready', shuttingDown: state.shuttingDown });
    }
    if (!(await dataDirWritable())) {
      return send(res, 503, { status: 'not-ready', reason: 'data dir not writable' });
    }
    return send(res, 200, { status: 'ready' });
  }

  if (req.method === 'GET' && url.pathname === '/') {
    return send(res, 200, {
      service: 'notes-api',
      version: APP_VERSION,
      pod: process.env.POD_NAME || 'local',
      node: process.env.NODE_NAME || 'local',
    });
  }

  if (url.pathname === '/api/notes') {
    if (req.method === 'GET') return send(res, 200, await listNotes());
    if (req.method === 'POST') {
      let parsed;
      try {
        parsed = JSON.parse(await readBody(req));
      } catch (err) {
        if (err.status) return send(res, err.status, { error: err.message });
        return send(res, 400, { error: 'body must be JSON' });
      }
      const text = typeof parsed?.text === 'string' ? parsed.text.trim() : '';
      if (!text || text.length > 1000) {
        return send(res, 400, { error: 'text is required (1-1000 chars)' });
      }
      return send(res, 201, await createNote(text));
    }
    res.setHeader('allow', 'GET, POST');
    return send(res, 405, { error: 'method not allowed' });
  }

  return send(res, 404, { error: 'not found' });
}

function createServer() {
  return http.createServer((req, res) => {
    const started = Date.now();
    res.on('finish', () => {
      if (req.url !== '/healthz' && req.url !== '/readyz') {
        log('info', 'request', {
          method: req.method,
          path: req.url,
          status: res.statusCode,
          ms: Date.now() - started,
        });
      }
    });
    handle(req, res).catch((err) => {
      log('error', 'unhandled', { err: err.message });
      if (!res.headersSent) send(res, 500, { error: 'internal error' });
    });
  });
}

async function start() {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  const server = createServer();
  server.keepAliveTimeout = 65_000; // longer than typical proxy idle timeouts

  await new Promise((resolve) => server.listen(PORT, resolve));
  state.ready = true;
  log('info', 'listening', { port: PORT, dataDir: DATA_DIR, version: APP_VERSION });

  const shutdown = (signal) => {
    if (state.shuttingDown) return;
    state.shuttingDown = true;
    log('info', 'shutdown requested; draining', { signal, drainMs: SHUTDOWN_DRAIN_MS });
    // Readiness now fails, so endpoints controllers remove this pod. Keep
    // serving in-flight and late-arriving requests for the drain window.
    setTimeout(() => {
      server.close(() => {
        log('info', 'shutdown complete');
        process.exit(0);
      });
      server.closeIdleConnections();
      setTimeout(() => process.exit(1), 10_000).unref();
    }, SHUTDOWN_DRAIN_MS).unref();
  };
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
  return server;
}

module.exports = { createServer, state, start };

if (require.main === module) {
  start().catch((err) => {
    log('error', 'failed to start', { err: err.message });
    process.exit(1);
  });
}