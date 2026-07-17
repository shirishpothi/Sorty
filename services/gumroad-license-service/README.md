# Sorty Gumroad License Service

This is the reference verification service for Sorty's paid unlocks.

It does four things:

1. Verifies Gumroad license keys with Gumroad's official verification endpoint.
2. Resolves Gumroad products into Sorty SKUs and entitlements.
3. Enforces a 3-device seat policy on the server side.
4. Signs the resulting entitlement payload so the app can verify it locally and cache it offline.

## Why this exists

Sorty is source-available. That means any client-only Gumroad secret would be recoverable. The app therefore never talks to Gumroad directly with a seller secret. Instead, it talks to this minimal service, which returns a signed entitlement envelope.

The app then:

- Verifies the signature locally.
- Caches the signed envelope in encrypted local storage.
- Keeps the last known good state during the grace window if refresh fails.

## Environment

Copy `.env.example` and set:

- `SORTY_LICENSE_SIGNING_PRIVATE_KEY_PEM`: P-256 private key in PEM format.
- `GUMROAD_PRODUCT_MAP_JSON`: JSON map from Sorty SKU to Gumroad `product_id`.
- `SORTY_LICENSE_STORE_PATH`: persistent path for seat assignments.

Example product map:

```json
{
  "sorty-deep-scan": {
    "productId": "gumroad_product_id",
    "displayName": "Deep Scan",
    "bundle": false,
    "entitlements": ["deep_scan"]
  },
  "sorty-pro-bundle": {
    "productId": "gumroad_bundle_product_id",
    "displayName": "Sorty Pro",
    "bundle": true,
    "entitlements": [
      "watched_folders_plus",
      "batch_organization",
      "deep_scan",
      "duplicate_detection",
      "file_tagging",
      "learnings",
      "workspace_health",
      "storage_locations",
      "history_plus",
      "premium_providers"
    ]
  }
}
```

## Endpoints

- `GET /health`
- `POST /v1/activate`
- `POST /v1/refresh`
- `POST /v1/deactivate`

`/v1/activate` and `/v1/refresh` accept:

```json
{
  "licenseKeys": ["ABCD-1234-EFGH-5678"],
  "device": {
    "deviceID": "stable-device-id",
    "deviceName": "Shirish's MacBook Pro",
    "appVersion": "1.2.0"
  },
  "reason": "activate"
}
```

Successful activation/refresh returns:

```json
{
  "envelope": {
    "algorithm": "ES256",
    "keyID": "sorty-license-key-v1",
    "payload": "<base64-json>",
    "signature": "<base64-der-signature>"
  }
}
```

## Key generation

Generate a signing key pair with OpenSSL:

```bash
openssl ecparam -name prime256v1 -genkey -noout -out sorty-license-private.pem
openssl ec -in sorty-license-private.pem -pubout -out sorty-license-public.pem
```

Ship `sorty-license-public.pem` to the app via `SORTY_LICENSE_PUBLIC_KEY_PEM` or the `sortyLicensePublicKeyPEM` user-defaults override.

## Connecting the macOS app

Sorty now reads license-service configuration in this order:

1. runtime environment variables such as `SORTY_LICENSE_SERVICE_URL`
2. debug-only `defaults write com.sorty.app ...` overrides
3. bundled `Info.plist` values wired from `BuildConfig.xcconfig`

For local development, the easiest wiring path is:

```bash
defaults write com.sorty.app sortyLicenseServiceURL -string http://127.0.0.1:8787
defaults write com.sorty.app sortyLicensePublicKeyPEM -string "$(perl -0pe 's/\n/\\n/g' sorty-license-public.pem)"
defaults write com.sorty.app sortyLicensePublicKeyID -string sorty-license-key-v1
```

The app accepts PEM values with literal `\n` escapes, which keeps them manageable in shell commands and xcconfig files.

For release builds, set these build settings in Xcode or an imported xcconfig:

- `SORTY_LICENSE_SERVICE_URL`
- `SORTY_LICENSE_PUBLIC_KEY_PEM`
- `SORTY_LICENSE_PUBLIC_KEY_ID`
- `SORTY_LICENSE_VALIDATION_HOURS`
- `SORTY_LICENSE_GRACE_HOURS`
- `SORTY_LICENSE_SEAT_LIMIT`

The checked-in [local setup guide](../../docs/licensing/local-development.md) walks through the full app + service flow.

## Running locally

```bash
cd services/gumroad-license-service
node server.mjs
```

## Tests

```bash
cd services/gumroad-license-service
node --test server.test.mjs
```

