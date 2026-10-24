import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { startFixtureServer } from './fixture-server.mjs';

function request(origin, route) {
  return new Promise((resolve, reject) => {
    http.get(origin, { path: route, agent: false }, (response) => {
      let body = '';
      response.setEncoding('utf8');
      response.on('data', (chunk) => { body += chunk; });
      response.on('end', () => resolve({ status: response.statusCode, body, type: response.headers['content-type'] }));
    }).on('error', reject);
  });
}

async function withFixtures(run) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'deepk-fixture-server-test-'));
  const modules = path.join(root, 'node_modules');
  fs.mkdirSync(modules);
  fs.mkdirSync(path.join(root, 'node_modules-private'));
  fs.writeFileSync(path.join(modules, 'fixture.css'), 'body { color: navy; }');
  fs.writeFileSync(path.join(root, 'node_modules-private', 'outside.txt'), 'outside fixture');
  fs.symlinkSync(path.join(root, 'node_modules-private'), path.join(modules, 'outside-link'));
  fs.symlinkSync(path.join(modules, 'fixture.css'), path.join(modules, 'inside.css'));
  const fixture = await startFixtureServer({ demo: '<p>synthetic page</p>' }, { modules });
  try {
    await run(fixture);
  } finally {
    await new Promise((resolve, reject) => fixture.server.close((error) => error ? reject(error) : resolve()));
    fs.rmSync(root, { recursive: true, force: true });
  }
}

test('fixture pages and in-root assets remain available only on loopback', async () => {
  await withFixtures(async ({ server, origin }) => {
    assert.equal(server.address().address, '127.0.0.1');
    assert.equal((await request(origin, '/demo.html')).body, '<p>synthetic page</p>');
    const asset = await request(origin, '/modules/fixture.css');
    assert.equal(asset.status, 200);
    assert.equal(asset.type, 'text/css');
    assert.equal(asset.body, 'body { color: navy; }');
    assert.equal((await request(origin, '/modules/inside.css')).status, 200);
  });
});

test('prefix siblings and external symlinks cannot be read as module assets', async () => {
  await withFixtures(async ({ origin }) => {
    for (const route of ['/modules/%2e%2e%2fnode_modules-private/outside.txt', '/modules/outside-link/outside.txt', '/modules/', '/modules/missing.txt']) {
      const response = await request(origin, route);
      assert.equal(response.status, 404, route);
      assert.equal(response.body, '', route);
    }
    assert.equal((await request(origin, '/modules/fixture.css')).status, 200);
  });
});

test('malformed URLs and inherited object names do not terminate the fixture server', async () => {
  await withFixtures(async ({ origin }) => {
    assert.equal((await request(origin, '/%E0%A4%A')).status, 400);
    assert.equal((await request(origin, '/constructor')).status, 404);
    assert.equal((await request(origin, '/demo')).status, 200);
  });
});
