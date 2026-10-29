import assert from 'node:assert/strict';
import test from 'node:test';
import { release } from '../src/data/release.ts';

test('release links point at the same version in this repository', () => {
  const base = 'https://github.com/Geuni620/deepK';
  assert.equal(release.repositoryUrl, base);
  assert.ok(release.downloadUrl.startsWith(`${base}/releases/download/v${release.version}/`));
  assert.ok(release.downloadUrl.includes(`-${release.version}-arm64-`));
  assert.equal(release.notesUrl, `${base}/releases/tag/v${release.version}`);
  assert.equal(release.noticesUrl, `${base}/blob/main/THIRD-PARTY-NOTICES.txt`);
});

test('install command and checksum use the published cask format', () => {
  assert.equal(release.installCommand, 'brew install --cask Geuni620/tap/deepk');
  assert.match(release.sha256, /^[0-9a-f]{64}$/);
});
