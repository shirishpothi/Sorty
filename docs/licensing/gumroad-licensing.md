# Gumroad Licensing

Sorty Pro uses Gumroad's license-key API directly. The production identifiers are pinned in `LicenseServiceConfiguration`:

- Product URL: `https://shirishpothi.gumroad.com/l/Sorty`
- Product ID: `w0WiZtzKwIjM7_xdOTSi2g==`
- Verification endpoint: `https://api.gumroad.com/v2/licenses/verify`

The app sends `product_id`, `license_key`, and `increment_uses_count=false` as a form-encoded HTTPS request. It rejects responses for any other product and treats refunded, disputed, chargebacked, ended, or failed purchases as inactive.

After verification, Sorty stores the license key in Keychain and encrypts the last verified entitlement payload with AES-GCM. Access is refreshed every 24 hours and remains available for up to seven days while Gumroad is unreachable. Removing the license clears both the Keychain entry and encrypted cache.

## Gumroad product setup

1. Open the Sorty product's Content editor in Gumroad.
2. Insert a **License key** block and publish the content update. Gumroad generates the key shown in the customer's receipt and library.
3. Keep the product ID above unchanged. New products created after January 9, 2023 must be verified with `product_id`, not the public permalink.
4. Make a Gumroad test purchase, copy its generated key, and activate it in **Settings > Licensing & Access**.

The current Sorty product is a one-time digital product rather than a multi-seat membership. Sorty does not claim device-seat enforcement or increment Gumroad's usage counter.
