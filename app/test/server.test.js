'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const os = require('node:os');
const fs = require('node:fs');
const path = require('node:path');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'notes-'));
process.env.DATA_DIR = tmp;

const { createServer, state } = require('../src/server');

let server;
let base;

test.before(async () => {
  server = createServer();
  await new Promise((r) => server.listen(0, r));
  base = `http://127.0.0.1:${server.address().port}`;
  state.ready = true;
});

test.after(() => {
  server.close();
  fs.rmSync(tmp, { recursive: true, force: true });
});

test('liveness is always ok', async () => {
  const res = await fetch(`${base}/healthz`);
  assert.equal(res.status, 200);
});

test('readiness is ok when ready and data dir writable', async () => {
  const res = await fetch(`${base}/readyz`);
  assert.equal(res.status, 200);
});

test('create and list notes', async () => {
  const created = await fetch(`${base}/api/notes`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ text: 'hello cluster' }),
  });
  assert.equal(created.status, 201);
  const list = await (await fetch(`${base}/api/notes`)).json();
  assert.equal(list.length, 1);
  assert.equal(list[0].text, 'hello cluster');
});

test('rejects invalid input', async () => {
  const res = await fetch(`${base}/api/notes`, { method: 'POST', body: 'not json' });
  assert.equal(res.status, 400);
});

test('readiness fails while shutting down', async () => {
  state.shuttingDown = true;
  const res = await fetch(`${base}/readyz`);
  assert.equal(res.status, 503);
  state.shuttingDown = false;
});