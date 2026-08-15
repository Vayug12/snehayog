import test from 'node:test';
import assert from 'node:assert/strict';
import { fingerprintFor, parseJUnit, redact } from './triage-results.mjs';

test('parseJUnit extracts failed Maestro cases only', () => {
  const xml = `<testsuite tests="2" failures="1"><testcase classname="navigation" name="opens Upload" /><testcase classname="navigation" name="opens Account"><failure message="Element &quot;Account&quot; not found">at flow.yaml:42</failure></testcase></testsuite>`;
  assert.deepEqual(parseJUnit(xml), [{ name: 'navigation — opens Account', message: 'Element "Account" not found', details: 'at flow.yaml:42' }]);
});

test('fingerprints ignore volatile line numbers and large ids', () => {
  const first = fingerprintFor({ name: 'flow', message: 'failed at app.dart:123 id 987654' });
  const second = fingerprintFor({ name: 'flow', message: 'failed at app.dart:991 id 123456' });
  assert.equal(first, second);
});

test('redact removes common credentials and personal data', () => {
  const result = redact('Authorization: Bearer abc123 email me@example.com card 4111 1111 1111 1111');
  assert.doesNotMatch(result, /abc123|me@example\.com|4111/);
  assert.match(result, /REDACTED/);
});

