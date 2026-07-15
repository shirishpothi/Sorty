import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import { createServer, loadConfiguration } from './server.mjs';

const temporaryDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'sorty-license-roundtrip-'));
const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const privateKeyPEM = privateKey.export({ type: 'pkcs8', format: 'pem' });
const publicKeyPEM = publicKey.export({ type: 'spki', format: 'pem' });
const licenseKey = 'SORTY-ROUNDTRIP-DEV-LICENSE';

const configuration = loadConfiguration({
  SORTY_LICENSE_SERVICE_HOST: '127.0.0.1',
  SORTY_LICENSE_SERVICE_PORT: '0',
  SORTY_LICENSE_KEY_ID: 'roundtrip-key-v1',
  SORTY_LICENSE_SIGNING_PRIVATE_KEY_PEM: privateKeyPEM,
  SORTY_LICENSE_STORE_PATH: path.join(temporaryDirectory, 'store.json'),
  SORTY_LICENSE_DEVICE_LIMIT: '1',
  SORTY_LICENSE_VALIDATION_HOURS: '2',
  SORTY_LICENSE_GRACE_HOURS: '24',
  GUMROAD_API_URL: 'https://gumroad.test/v2/licenses/verify',
  GUMROAD_PRODUCT_MAP_JSON: JSON.stringify({
    'sorty-deep-scan': {
      productId: 'sorty-dev-product',
      displayName: 'Sorty Deep Scan',
      entitlements: ['deep_scan']
    }
  })
});

const upstreamFetch = async (_url, options) => {
  assert.equal(options.redirect, 'error');
  const body = new URLSearchParams(options.body);
  assert.equal(body.get('product_id'), 'sorty-dev-product');
  assert.equal(body.get('increment_uses_count'), 'false');

  if (body.get('license_key') !== licenseKey) {
    return new Response(JSON.stringify({ success: false }), { status: 404 });
  }

  return Response.json({
    success: true,
    purchase: {
      id: 'roundtrip-sale-1',
      email: 'roundtrip@sorty.test',
      created_at: '2026-01-01T00:00:00.000Z',
      refunded: false,
      disputed: false,
      chargebacked: false
    }
  });
};

const server = createServer(configuration, { fetchImpl: upstreamFetch });

try {
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });

  const address = server.address();
  assert(address && typeof address === 'object');
  const baseURL = `http://127.0.0.1:${address.port}`;
  const firstDevice = {
    deviceID: 'roundtrip-device-1',
    deviceName: 'Roundtrip Mac 1',
    appVersion: '1.0-dev'
  };
  const secondDevice = {
    deviceID: 'roundtrip-device-2',
    deviceName: 'Roundtrip Mac 2',
    appVersion: '1.0-dev'
  };

  const activation = await postJSON(`${baseURL}/v1/activate`, {
    licenseKeys: [licenseKey],
    device: firstDevice,
    reason: 'activate'
  });
  assert.equal(activation.response.status, 200);
  const activatedPayload = verifyEnvelope(activation.body.envelope, publicKeyPEM);
  assert.equal(activatedPayload.status, 'active');
  assert.deepEqual(activatedPayload.entitlements, ['deep_scan']);
  assert.equal(activatedPayload.seatState.activeSeatCount, 1);
  assert.equal(activatedPayload.seatState.currentDeviceID, firstDevice.deviceID);

  const refresh = await postJSON(`${baseURL}/v1/refresh`, {
    licenseKeys: [licenseKey],
    device: firstDevice,
    reason: 'refresh'
  });
  assert.equal(refresh.response.status, 200);
  const refreshedPayload = verifyEnvelope(refresh.body.envelope, publicKeyPEM);
  assert.equal(refreshedPayload.activeLicenses[0].keyHint, 'SORT...ENSE');

  const blockedActivation = await postJSON(`${baseURL}/v1/activate`, {
    licenseKeys: [licenseKey],
    device: secondDevice,
    reason: 'activate'
  });
  assert.equal(blockedActivation.response.status, 409);

  const deactivation = await postJSON(`${baseURL}/v1/deactivate`, {
    licenseKeys: [licenseKey],
    deviceID: firstDevice.deviceID
  });
  assert.equal(deactivation.response.status, 200);
  assert.equal(deactivation.body.ok, true);

  const reactivation = await postJSON(`${baseURL}/v1/activate`, {
    licenseKeys: [licenseKey],
    device: secondDevice,
    reason: 'activate'
  });
  assert.equal(reactivation.response.status, 200);
  const reactivatedPayload = verifyEnvelope(reactivation.body.envelope, publicKeyPEM);
  assert.equal(reactivatedPayload.seatState.currentDeviceID, secondDevice.deviceID);

  const finalDeactivation = await postJSON(`${baseURL}/v1/deactivate`, {
    licenseKeys: [licenseKey],
    deviceID: secondDevice.deviceID
  });
  assert.equal(finalDeactivation.response.status, 200);

  const persistedStore = JSON.parse(await fs.readFile(configuration.storePath, 'utf8'));
  assert.deepEqual(persistedStore, { licenses: {} });
  console.log('Live activation, refresh, seat enforcement, signature verification, and deactivation passed.');
} finally {
  await new Promise((resolve) => server.close(resolve));
  await fs.rm(temporaryDirectory, { recursive: true, force: true });
}

async function postJSON(url, payload) {
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
    redirect: 'error'
  });
  return { response, body: await response.json() };
}

function verifyEnvelope(envelope, verificationKey) {
  assert.equal(envelope.algorithm, 'ES256');
  assert.equal(envelope.keyID, 'roundtrip-key-v1');
  const payload = Buffer.from(envelope.payload, 'base64');
  const signature = Buffer.from(envelope.signature, 'base64');
  assert.equal(crypto.verify('sha256', payload, verificationKey, signature), true);
  return JSON.parse(payload.toString('utf8'));
}
