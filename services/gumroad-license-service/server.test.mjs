import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';

import {
  createService,
  hashLicenseKey,
  loadConfiguration,
  loadStore,
  maskLicenseKey,
  normalizePurchaseState,
  signPayload,
  stableStringify
} from './server.mjs';

const { privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });

function configuration(storePath) {
  return {
    keyId: 'test-key',
    privateKeyPEM: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(),
    gumroadApiURL: 'https://gumroad.example.test/verify',
    validationHours: 24,
    graceHours: 168,
    deviceLimit: 3,
    storePath,
    productMap: {
      'sorty-deep-scan': {
        productId: 'prod_deep',
        displayName: 'Deep Scan',
        bundle: false,
        entitlements: ['deep_scan']
      },
      'sorty-pro-bundle': {
        productId: 'prod_bundle',
        displayName: 'Sorty Pro',
        bundle: true,
        entitlements: []
      }
    }
  };
}

function fakeFetch(responseByProductId) {
  return async (_url, options) => {
    const body = new URLSearchParams(options.body);
    const productId = body.get('product_id');
    const response = responseByProductId[productId];

    if (!response) {
      return new Response('not found', { status: 404 });
    }

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
  };
}

test('stableStringify sorts nested object keys', () => {
  const json = stableStringify({ b: 2, a: { d: 4, c: 3 } });
  assert.equal(json, '{"a":{"c":3,"d":4},"b":2}');
});

test('configuration defaults to loopback and normalizes escaped signing keys', () => {
  const loaded = loadConfiguration({
    SORTY_LICENSE_SIGNING_PRIVATE_KEY_PEM: 'line-one\\nline-two'
  });

  assert.equal(loaded.host, '127.0.0.1');
  assert.equal(loaded.privateKeyPEM, 'line-one\nline-two');
});

test('short license keys are never reflected in errors', () => {
  assert.equal(maskLicenseKey('short'), '****');
  assert.equal(maskLicenseKey('long-license-key'), 'long...-key');
});

test('cancelled subscriptions are expired after their cancellation timestamp', () => {
  const normalized = normalizePurchaseState({
    purchase: {
      subscription_cancelled_at: '2026-01-01T00:00:00.000Z'
    }
  });

  assert.equal(normalized.status, 'expired');
});

test('successful HTTP responses without a verified purchase cannot activate', async () => {
  const tempDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'sorty-license-service-'));
  const service = createService(configuration(path.join(tempDirectory, 'store.json')), {
    fetchImpl: fakeFetch({ prod_deep: { success: false } })
  });

  const result = await service.route('POST', '/v1/activate', {
    licenseKeys: ['invalid-key'],
    device: { deviceID: 'device-1', deviceName: 'Mac 1', appVersion: '1.0' }
  });

  assert.equal(result.statusCode, 404);
});

test('signPayload returns an ES256 envelope', () => {
  const envelope = signPayload(
    { status: 'active', entitlements: ['deep_scan'] },
    {
      keyId: 'test-key',
      privateKeyPEM: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString()
    }
  );

  assert.equal(envelope.algorithm, 'ES256');
  assert.equal(envelope.keyID, 'test-key');
  assert.ok(envelope.payload.length > 10);
  assert.ok(envelope.signature.length > 10);
});

test('activation merges licenses and persists seat assignments', async () => {
  const tempDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'sorty-license-service-'));
  const storePath = path.join(tempDirectory, 'store.json');
  const service = createService(configuration(storePath), {
    fetchImpl: fakeFetch({
      prod_deep: {
        success: true,
        purchase: {
          id: 'sale_deep',
          email: 'user@example.com',
          created_at: '2026-04-06T00:00:00Z'
        }
      },
      prod_bundle: {
        success: true,
        purchase: {
          id: 'sale_bundle',
          email: 'user@example.com',
          created_at: '2026-04-06T00:00:00Z'
        }
      }
    })
  });

  const result = await service.route('POST', '/v1/activate', {
    licenseKeys: ['deep-key', 'bundle-key'],
    device: {
      deviceID: 'device-1',
      deviceName: 'Test Mac',
      appVersion: '1.0'
    }
  });

  assert.equal(result.statusCode, 200);
  assert.equal(result.payload.envelope.algorithm, 'ES256');

  const store = await loadStore(storePath);
  assert.equal(store.licenses[hashLicenseKey('deep-key')].devices.length, 1);
  assert.equal(store.licenses[hashLicenseKey('bundle-key')].devices.length, 1);
});

test('seat limit violations return 409', async () => {
  const tempDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'sorty-license-service-'));
  const storePath = path.join(tempDirectory, 'store.json');
  const baseConfiguration = configuration(storePath);
  baseConfiguration.deviceLimit = 1;

  const service = createService(baseConfiguration, {
    fetchImpl: fakeFetch({
      prod_deep: {
        success: true,
        purchase: {
          id: 'sale_deep',
          email: 'user@example.com',
          created_at: '2026-04-06T00:00:00Z'
        }
      }
    })
  });

  const first = await service.route('POST', '/v1/activate', {
    licenseKeys: ['deep-key'],
    device: { deviceID: 'device-1', deviceName: 'Mac 1', appVersion: '1.0' }
  });
  assert.equal(first.statusCode, 200);

  await assert.rejects(
    async () => {
      await service.route('POST', '/v1/activate', {
        licenseKeys: ['deep-key'],
        device: { deviceID: 'device-2', deviceName: 'Mac 2', appVersion: '1.0' }
      });
    },
    /Seat limit exceeded/
  );
});

test('concurrent activations cannot race past the seat limit', async () => {
  const tempDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'sorty-license-service-'));
  const storePath = path.join(tempDirectory, 'store.json');
  const baseConfiguration = configuration(storePath);
  baseConfiguration.deviceLimit = 1;
  const service = createService(baseConfiguration, {
    fetchImpl: fakeFetch({
      prod_deep: {
        success: true,
        purchase: { id: 'sale_deep', email: 'user@example.com' }
      }
    })
  });

  const results = await Promise.allSettled([
    service.route('POST', '/v1/activate', {
      licenseKeys: ['deep-key'],
      device: { deviceID: 'device-1', deviceName: 'Mac 1', appVersion: '1.0' }
    }),
    service.route('POST', '/v1/activate', {
      licenseKeys: ['deep-key'],
      device: { deviceID: 'device-2', deviceName: 'Mac 2', appVersion: '1.0' }
    })
  ]);

  assert.equal(results.filter((result) => result.status === 'fulfilled').length, 1);
  assert.equal(results.filter((result) => result.status === 'rejected').length, 1);
  const store = await loadStore(storePath);
  assert.equal(store.licenses[hashLicenseKey('deep-key')].devices.length, 1);
});

test('deactivation releases the current device seat', async () => {
  const tempDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'sorty-license-service-'));
  const storePath = path.join(tempDirectory, 'store.json');
  const service = createService(configuration(storePath), {
    fetchImpl: fakeFetch({
      prod_deep: {
        success: true,
        purchase: { id: 'sale_deep', email: 'user@example.com' }
      }
    })
  });

  await service.route('POST', '/v1/activate', {
    licenseKeys: ['deep-key'],
    device: { deviceID: 'device-1', deviceName: 'Mac 1', appVersion: '1.0' }
  });
  const response = await service.route('POST', '/v1/deactivate', {
    licenseKeys: ['deep-key'],
    deviceID: 'device-1'
  });

  assert.equal(response.statusCode, 200);
  const store = await loadStore(storePath);
  assert.equal(store.licenses[hashLicenseKey('deep-key')], undefined);
});
