# Local Licensing Setup

This guide wires Sorty's app-side entitlement flow to the reference Gumroad verification service for local development.

## 1. Generate a signing keypair

From the repository root:

```bash
openssl ecparam -name prime256v1 -genkey -noout -out sorty-license-private.pem
openssl ec -in sorty-license-private.pem -pubout -out sorty-license-public.pem
```

The service uses the private key to sign entitlement payloads. The app only needs the public key.

## 2. Configure the verification service

Create a service env file:

```bash
cp services/gumroad-license-service/.env.example services/gumroad-license-service/.env.local
```

Set these values in `services/gumroad-license-service/.env.local`:

- `SORTY_LICENSE_SIGNING_PRIVATE_KEY_PEM`
- `GUMROAD_PRODUCT_MAP_JSON`
- `SORTY_LICENSE_STORE_PATH`

The private key can stay on one line with escaped newlines:

```bash
perl -0pe 's/\n/\\n/g' sorty-license-private.pem
```

## 3. Start the service

```bash
cd services/gumroad-license-service
set -a
source ./.env.local
set +a
node server.mjs
```

Verify it is reachable:

```bash
curl http://127.0.0.1:8787/health
```

## 4. Point the app at the service

### Debug builds via user defaults

This is the fastest path while developing locally:

```bash
defaults write com.sorty.app sortyLicenseServiceURL -string http://127.0.0.1:8787
defaults write com.sorty.app sortyLicensePublicKeyPEM -string "$(perl -0pe 's/\n/\\n/g' sorty-license-public.pem)"
defaults write com.sorty.app sortyLicensePublicKeyID -string sorty-license-key-v1
defaults write com.sorty.app sortyLicenseValidationHours -string 24
defaults write com.sorty.app sortyLicenseGraceHours -string 168
defaults write com.sorty.app sortyLicenseSeatLimit -string 3
```

Sorty normalizes literal `\n` escapes back into PEM newlines at runtime, so this works for both shell commands and one-line config values.

### Release or shared build configuration

Release builds read the same values from `Info.plist`, and the checked-in `BuildConfig.xcconfig` now exposes these build settings:

- `SORTY_LICENSE_SERVICE_URL`
- `SORTY_LICENSE_PUBLIC_KEY_PEM`
- `SORTY_LICENSE_PUBLIC_KEY_ID`
- `SORTY_LICENSE_VALIDATION_HOURS`
- `SORTY_LICENSE_GRACE_HOURS`
- `SORTY_LICENSE_SEAT_LIMIT`

Set them in Xcode, an imported private xcconfig, or CI secrets for signed release builds.

## 5. Verify the app flow

1. Launch Sorty.
2. Open `Settings -> Licensing & Access`.
3. Confirm the page no longer shows the “not configured” warning.
4. Enter a Gumroad license key backed by your `GUMROAD_PRODUCT_MAP_JSON`.
5. Confirm the feature gates update immediately.

Useful checks:

- `Refresh Access` should hit `/v1/refresh`.
- `Release This Mac` should hit `/v1/deactivate`.
- With the service offline, Sorty should fall back to the encrypted cached snapshot during the grace window.

## 6. Reset local overrides

If you want to clear the debug-only app overrides:

```bash
defaults delete com.sorty.app sortyLicenseServiceURL
defaults delete com.sorty.app sortyLicensePublicKeyPEM
defaults delete com.sorty.app sortyLicensePublicKeyID
defaults delete com.sorty.app sortyLicenseValidationHours
defaults delete com.sorty.app sortyLicenseGraceHours
defaults delete com.sorty.app sortyLicenseSeatLimit
```

