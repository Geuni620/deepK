import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { examples, getExample, parseCandidates } from '../src/data/examples.ts';
import { getVariant } from '../src/data/variants.ts';
import { samples, exampleTranslation } from '../src/data/samples.ts';

test('every selected Pencil frame is represented once with an existing original preview', () => {
  const expected = [
    'S7wmDG',
    'fpJiT',
    'A4Bdm',
    'FJV7P',
    'X3Qzu',
    'm6SVH',
    'DJTfM',
    'ybUDM',
    'ZhjQf',
    'LI9te',
    'cw9VP',
    'kX1RX',
    'vgY2V',
    'mNu6p',
    'qvd1Z',
    'h8bwSA',
    'K6vGz',
    'kiGM2',
  ];
  assert.deepEqual(examples.map((example) => example.nodeId).sort(), expected.sort());
  assert.equal(new Set(examples.map((example) => example.slug)).size, expected.length);
  for (const example of examples) {
    assert.ok(
      fs.statSync(new URL(`../public/thumbnails/${example.nodeId}.webp`, import.meta.url)).size > 0,
    );
    if ('variant' in example) assert.ok(getVariant(example.variant));
  }
});

test('responsive examples reuse one implementation at three actual viewport widths', () => {
  const responsive = examples.filter((example) => example.kind === 'responsive');
  assert.deepEqual(
    responsive.map((example) => example.width),
    [1440, 768, 390],
  );
  assert.deepEqual([...new Set(responsive.map((example) => example.variant))], ['final']);
});

test('candidate restore rejects malformed or unknown data without retaining duplicates', () => {
  assert.deepEqual(parseCandidates('{broken'), []);
  assert.deepEqual(parseCandidates('{"slug":"desktop"}'), []);
  assert.deepEqual(parseCandidates('["desktop","desktop","not-a-case",3,"mobile"]'), [
    'desktop',
    'mobile',
  ]);
  assert.equal(getExample('../../outside'), undefined);
});

test('example translation only returns the supplied fixture results', () => {
  for (const sample of samples)
    assert.equal(exampleTranslation(`  ${sample.source.replace(/\n/g, '   ')}  `), sample.result);
  assert.equal(exampleTranslation('A new sentence which was never translated.'), undefined);
  assert.equal(exampleTranslation('<img src=x onerror=alert(1)>'), undefined);
  assert.equal(exampleTranslation(''), undefined);
});
