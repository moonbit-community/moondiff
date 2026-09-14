import assert from 'node:assert/strict';
import test from 'node:test';
import { readE2EConfig } from './e2e-config.mjs';

test('Playground E2E configuration uses a fixed loopback host', () => {
  assert.deepEqual(readE2EConfig({}), {
    port: 4173,
    origin: 'http://127.0.0.1:4173',
  });
  assert.deepEqual(
    readE2EConfig({ PORT: '4321', MOONDIFF_E2E_HOST: 'localhost' }),
    { port: 4321, origin: 'http://127.0.0.1:4321' },
  );
});

test('Playground E2E origin is canonical', () => {
  assert.equal(readE2EConfig({ PORT: '80' }).origin, 'http://127.0.0.1');
});

test('Playground E2E configuration rejects invalid ports', () => {
  for (const port of ['0', '65536', '1.5', '-1', 'not-a-port']) {
    assert.throws(
      () => readE2EConfig({ PORT: port }),
      /Invalid Playground E2E port/,
    );
  }
});
