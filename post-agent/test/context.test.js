import test from 'node:test';
import assert from 'node:assert/strict';

import { buildQueries } from '../src/research.js';
import { DEFAULT_PROVIDER, PROJECT_ROOT } from '../src/config.js';

test('defaults to opencode and points to the sibling snehayog project', () => {
  assert.equal(DEFAULT_PROVIDER, 'opencode');
  assert.match(PROJECT_ROOT, /snehayog$/i);
});

test('builds multiple research queries around the requested topic', () => {
  const queries = buildQueries({ topic: 'creator monetization', projectName: 'Snehayog/Vayug' });
  assert.equal(queries.length, 3);
  assert.ok(queries.every((query) => query.includes('creator monetization')));
});
