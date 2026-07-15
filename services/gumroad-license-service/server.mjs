import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ALL_ENTITLEMENTS = [
  'watched_folders_plus',
  'batch_organization',
  'deep_scan',
  'duplicate_detection',
  'file_tagging',
  'learnings',
  'workspace_health',
  'storage_locations',
  'history_plus',
  'premium_providers'
];

export function loadConfiguration(env = process.env) {
  const productMap = JSON.parse(env.GUMROAD_PRODUCT_MAP_JSON ?? '{}');

  return {
    port: Number(env.SORTY_LICENSE_SERVICE_PORT ?? 8787),
    host: env.SORTY_LICENSE_SERVICE_HOST ?? '127.0.0.1',
    keyId: env.SORTY_LICENSE_KEY_ID ?? 'sorty-license-key-v1',
    privateKeyPEM: (env.SORTY_LICENSE_SIGNING_PRIVATE_KEY_PEM ?? '').replaceAll('\\n', '\n'),
    gumroadApiURL: env.GUMROAD_API_URL ?? 'https://api.gumroad.com/v2/licenses/verify',
    validationHours: Number(env.SORTY_LICENSE_VALIDATION_HOURS ?? 24),
    graceHours: Number(env.SORTY_LICENSE_GRACE_HOURS ?? 168),
    deviceLimit: Number(env.SORTY_LICENSE_DEVICE_LIMIT ?? 3),
    storePath: env.SORTY_LICENSE_STORE_PATH ?? path.join(path.dirname(fileURLToPath(import.meta.url)), 'data', 'store.json'),
    productMap
  };
}

export function stableStringify(value) {
  if (Array.isArray(value)) {
    return `[${value.map(stableStringify).join(',')}]`;
  }

  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`).join(',')}}`;
  }

  return JSON.stringify(value);
}

export function maskLicenseKey(licenseKey) {
  const trimmed = licenseKey.trim();
  if (trimmed.length <= 8) {
    return '****';
  }
  return `${trimmed.slice(0, 4)}...${trimmed.slice(-4)}`;
}

export function hashLicenseKey(licenseKey) {
  return crypto.createHash('sha256').update(licenseKey.trim()).digest('hex');
}

export async function loadStore(storePath) {
  try {
    const raw = await fs.readFile(storePath, 'utf8');
    return JSON.parse(raw);
  } catch (error) {
    if (error.code === 'ENOENT') {
      return { licenses: {} };
    }
    throw error;
  }
}

export async function saveStore(storePath, store) {
  const directory = path.dirname(storePath);
  const temporaryPath = `${storePath}.${process.pid}.${crypto.randomUUID()}.tmp`;
  await fs.mkdir(directory, { recursive: true, mode: 0o700 });
  await fs.writeFile(
    temporaryPath,
    `${JSON.stringify(store, null, 2)}\n`,
    { encoding: 'utf8', mode: 0o600 }
  );
  await fs.rename(temporaryPath, storePath);
  await fs.chmod(storePath, 0o600);
}

export async function verifyLicenseWithGumroad({ gumroadApiURL, productId, licenseKey, fetchImpl = fetch }) {
  const verificationURL = new URL(gumroadApiURL);
  const isLoopback = verificationURL.hostname === 'localhost'
    || verificationURL.hostname === '127.0.0.1'
    || verificationURL.hostname === '::1';
  if (verificationURL.protocol !== 'https:' && !(verificationURL.protocol === 'http:' && isLoopback)) {
    throw new Error('The Gumroad verification endpoint must use HTTPS unless it is local loopback.');
  }

  const body = new URLSearchParams({
    product_id: productId,
    license_key: licenseKey,
    increment_uses_count: 'false'
  });

  const response = await fetchImpl(gumroadApiURL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
    redirect: 'error',
    signal: AbortSignal.timeout(15_000)
  });

  if (response.status === 404) {
    return null;
  }

  if (!response.ok) {
    const message = await response.text();
    throw new Error(`Gumroad verification failed: ${message || response.status}`);
  }

  const payload = await response.json();
  if (payload.success === false || !payload.purchase) {
    return null;
  }

  const purchase = payload.purchase;
  if (purchase.product_id && String(purchase.product_id) !== String(productId)) {
    return null;
  }

  return purchase;
}

export async function verifyLicenseAgainstCatalog(configuration, licenseKey, fetchImpl = fetch) {
  for (const [sku, entry] of Object.entries(configuration.productMap)) {
    const purchase = await verifyLicenseWithGumroad({
      gumroadApiURL: configuration.gumroadApiURL,
      productId: entry.productId,
      licenseKey,
      fetchImpl
    });

    if (purchase) {
      return {
        sku,
        productId: entry.productId,
        displayName: entry.displayName ?? sku,
        bundle: Boolean(entry.bundle),
        entitlements: Array.isArray(entry.entitlements) ? entry.entitlements : [],
        purchase
      };
    }
  }

  return null;
}

export function normalizePurchaseState(verifiedLicense) {
  const purchase = verifiedLicense.purchase;
  const refunded = Boolean(purchase.refunded || purchase.disputed || purchase.chargebacked);
  const endedAt = purchase.subscription_ended_at ? new Date(purchase.subscription_ended_at) : null;
  const cancelledAt = purchase.subscription_cancelled_at ? new Date(purchase.subscription_cancelled_at) : null;
  const failedAt = purchase.subscription_failed_at ? new Date(purchase.subscription_failed_at) : null;
  const now = new Date();
  const expiredSubscription = endedAt instanceof Date && !Number.isNaN(endedAt.valueOf()) && endedAt <= now;
  const cancelledSubscription = cancelledAt instanceof Date && !Number.isNaN(cancelledAt.valueOf()) && cancelledAt <= now;
  const failedSubscription = failedAt instanceof Date && !Number.isNaN(failedAt.valueOf()) && failedAt <= now;

  return {
    ...verifiedLicense,
    status: refunded || expiredSubscription || cancelledSubscription || failedSubscription ? 'expired' : 'active',
    purchaseDate: purchase.created_at ? new Date(purchase.created_at) : null
  };
}

export function assignSeat(store, licenseHash, device, licenseMeta, seatLimit) {
  const licenseEntry = store.licenses[licenseHash] ?? {
    saleId: licenseMeta.saleId,
    sku: licenseMeta.sku,
    email: licenseMeta.email ?? null,
    productId: licenseMeta.productId,
    devices: []
  };

  const existingDevice = licenseEntry.devices.find((entry) => entry.deviceId === device.deviceID);
  const nowISO = new Date().toISOString();

  if (existingDevice) {
    existingDevice.deviceName = device.deviceName;
    existingDevice.lastSeenAt = nowISO;
    existingDevice.appVersion = device.appVersion;
  } else if (licenseEntry.devices.length >= seatLimit) {
    const error = new Error(`Seat limit exceeded for ${licenseMeta.sku}. Release a device seat before activating another Mac.`);
    error.statusCode = 409;
    throw error;
  } else {
    licenseEntry.devices.push({
      deviceId: device.deviceID,
      deviceName: device.deviceName,
      registeredAt: nowISO,
      lastSeenAt: nowISO,
      appVersion: device.appVersion
    });
  }

  store.licenses[licenseHash] = licenseEntry;
  return licenseEntry;
}

export function releaseSeat(store, licenseHash, deviceID) {
  const licenseEntry = store.licenses[licenseHash];
  if (!licenseEntry) {
    return;
  }

  licenseEntry.devices = licenseEntry.devices.filter((entry) => entry.deviceId !== deviceID);
  if (licenseEntry.devices.length === 0) {
    delete store.licenses[licenseHash];
  }
}

export function buildEntitlementPayload(configuration, licenses, device) {
  const now = new Date();
  const nextValidationAt = new Date(now.getTime() + configuration.validationHours * 3600 * 1000);
  const graceExpiresAt = new Date(now.getTime() + configuration.graceHours * 3600 * 1000);

  const bundleUnlocked = licenses.some((license) => license.bundle);
  const entitlements = bundleUnlocked
    ? ALL_ENTITLEMENTS.slice()
    : Array.from(new Set(licenses.flatMap((license) => license.entitlements))).sort();

  const seatCounts = licenses.map((license) => license.assignedSeatCount);
  const activeSeatCount = seatCounts.length === 0 ? 0 : Math.max(...seatCounts);

  return {
    status: licenses.some((license) => license.status !== 'active') ? 'expired' : 'active',
    issuedAt: now.toISOString(),
    validatedAt: now.toISOString(),
    nextValidationAt: nextValidationAt.toISOString(),
    graceExpiresAt: graceExpiresAt.toISOString(),
    bundleUnlocked,
    entitlements,
    customerEmail: licenses.find((license) => license.email)?.email ?? null,
    warningMessage: null,
    seatState: {
      currentDeviceID: device.deviceID,
      currentDeviceName: device.deviceName,
      currentDeviceRegisteredAt: licenses.find((license) => license.currentDeviceRegisteredAt)?.currentDeviceRegisteredAt ?? null,
      activeSeatCount,
      seatLimit: configuration.deviceLimit
    },
    activeLicenses: licenses.map((license) => ({
      id: `${license.saleId}:${license.sku}`,
      saleID: license.saleId,
      keyHint: license.keyHint,
      sku: license.sku,
      productName: license.productName,
      email: license.email ?? null,
      purchasedAt: license.purchaseDate instanceof Date && !Number.isNaN(license.purchaseDate.valueOf())
        ? license.purchaseDate.toISOString()
        : null
    }))
  };
}

export function signPayload(payload, { keyId, privateKeyPEM }) {
  const canonicalPayload = stableStringify(payload);
  const payloadBuffer = Buffer.from(canonicalPayload, 'utf8');
  const signature = crypto.sign('sha256', payloadBuffer, privateKeyPEM);

  return {
    algorithm: 'ES256',
    keyID: keyId,
    payload: payloadBuffer.toString('base64'),
    signature: signature.toString('base64')
  };
}

export function createService(configuration, options = {}) {
  const fetchImpl = options.fetchImpl ?? fetch;
  let mutationQueue = Promise.resolve();

  function serializeMutation(operation) {
    const result = mutationQueue.then(operation, operation);
    mutationQueue = result.then(() => undefined, () => undefined);
    return result;
  }

  async function handleEntitlementRequest(body) {
    const licenseKeys = Array.from(new Set((body.licenseKeys ?? []).map((value) => String(value).trim()).filter(Boolean)));
    if (licenseKeys.length === 0) {
      return { statusCode: 400, payload: { error: 'No license keys were provided.' } };
    }

    if (!body.device?.deviceID || !body.device?.deviceName) {
      return { statusCode: 400, payload: { error: 'Device identity is required.' } };
    }

    const store = await loadStore(configuration.storePath);
    const verifiedLicenses = [];

    for (const licenseKey of licenseKeys) {
      const verified = await verifyLicenseAgainstCatalog(configuration, licenseKey, fetchImpl);
      if (!verified) {
        return {
          statusCode: 404,
          payload: {
            error: `No matching Gumroad product was found for ${maskLicenseKey(licenseKey)}.`
          }
        };
      }

      const normalized = normalizePurchaseState(verified);
      if (normalized.status !== 'active') {
        return {
          statusCode: 403,
          payload: {
            error: `${normalized.displayName} is no longer active on Gumroad.`
          }
        };
      }

      const saleId = String(normalized.purchase.id ?? normalized.purchase.sale_id ?? normalized.purchase.saleId ?? normalized.productId);
      const email = normalized.purchase.email ?? null;
      const licenseHash = hashLicenseKey(licenseKey);
      const seatEntry = assignSeat(
        store,
        licenseHash,
        body.device,
        {
          saleId,
          sku: normalized.sku,
          email,
          productId: normalized.productId
        },
        configuration.deviceLimit
      );

      const currentSeat = seatEntry.devices.find((entry) => entry.deviceId === body.device.deviceID) ?? null;

      verifiedLicenses.push({
        saleId,
        sku: normalized.sku,
        productName: normalized.displayName,
        productId: normalized.productId,
        email,
        keyHint: maskLicenseKey(licenseKey),
        bundle: normalized.bundle,
        entitlements: normalized.bundle ? ALL_ENTITLEMENTS : normalized.entitlements,
        purchaseDate: normalized.purchaseDate,
        assignedSeatCount: seatEntry.devices.length,
        currentDeviceRegisteredAt: currentSeat?.registeredAt ?? null,
        status: normalized.status
      });
    }

    await saveStore(configuration.storePath, store);

    const payload = buildEntitlementPayload(configuration, verifiedLicenses, body.device);
    return {
      statusCode: 200,
      payload: {
        envelope: signPayload(payload, configuration)
      }
    };
  }

  async function handleDeactivation(body) {
    const licenseKeys = Array.from(new Set((body.licenseKeys ?? []).map((value) => String(value).trim()).filter(Boolean)));
    if (!body.deviceID || licenseKeys.length === 0) {
      return { statusCode: 400, payload: { error: 'Device ID and license keys are required.' } };
    }

    const store = await loadStore(configuration.storePath);
    for (const licenseKey of licenseKeys) {
      releaseSeat(store, hashLicenseKey(licenseKey), body.deviceID);
    }
    await saveStore(configuration.storePath, store);

    return { statusCode: 200, payload: { ok: true } };
  }

  return {
    async route(method, pathname, body = null) {
      if (method === 'GET' && pathname === '/health') {
        return {
          statusCode: 200,
          payload: {
            status: 'ok',
            products: Object.keys(configuration.productMap).length,
            validationHours: configuration.validationHours,
            graceHours: configuration.graceHours,
            deviceLimit: configuration.deviceLimit
          }
        };
      }

      if (!configuration.privateKeyPEM.trim()) {
        return { statusCode: 500, payload: { error: 'Signing key is not configured.' } };
      }

      if (method === 'POST' && pathname === '/v1/activate') {
        return serializeMutation(() => handleEntitlementRequest(body ?? {}));
      }

      if (method === 'POST' && pathname === '/v1/refresh') {
        return serializeMutation(() => handleEntitlementRequest(body ?? {}));
      }

      if (method === 'POST' && pathname === '/v1/deactivate') {
        return serializeMutation(() => handleDeactivation(body ?? {}));
      }

      return { statusCode: 404, payload: { error: 'Not found.' } };
    }
  };
}

export function createServer(configuration = loadConfiguration(), options = {}) {
  const service = createService(configuration, options);

  return http.createServer(async (request, response) => {
    try {
      const url = new URL(request.url ?? '/', `http://${request.headers.host ?? 'localhost'}`);
      const body = await readJSONBody(request);
      const result = await service.route(request.method ?? 'GET', url.pathname, body);
      response.writeHead(result.statusCode, { 'Content-Type': 'application/json' });
      response.end(`${JSON.stringify(result.payload)}\n`);
    } catch (error) {
      response.writeHead(error.statusCode ?? 500, { 'Content-Type': 'application/json' });
      response.end(`${JSON.stringify({ error: error.message ?? 'Unexpected server error.' })}\n`);
    }
  });
}

async function readJSONBody(request) {
  if ((request.method ?? 'GET') === 'GET') {
    return null;
  }

  const chunks = [];
  let byteCount = 0;
  for await (const chunk of request) {
    byteCount += chunk.length;
    if (byteCount > 64 * 1024) {
      const error = new Error('Request body is too large.');
      error.statusCode = 413;
      throw error;
    }
    chunks.push(chunk);
  }

  if (chunks.length === 0) {
    return null;
  }

  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const configuration = loadConfiguration();
  const server = createServer(configuration);
  server.listen(configuration.port, configuration.host, () => {
    console.log(`Sorty Gumroad license service listening on http://${configuration.host}:${configuration.port}`);
  });
}
