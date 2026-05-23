# Nightly Updates

Sorty publishes a moving nightly prerelease from `main` through `.github/workflows/nightly.yml`.

The workflow runs every day at midnight Singapore time and can also be triggered manually from GitHub Actions. It builds the universal macOS app, stamps the built bundle with a monotonically increasing `CFBundleVersion`, points that bundle at the nightly Sparkle feed, packages `Sorty-nightly.zip`, signs `appcast-nightly.xml`, and replaces the GitHub `nightly` prerelease.

Nightly update feed:

```text
https://github.com/sorty-organizer/Sorty/releases/download/nightly/appcast-nightly.xml
```

Nightly download:

```text
https://github.com/sorty-organizer/Sorty/releases/download/nightly/Sorty-nightly.zip
```

Stable releases continue to use the existing `release.yml` workflow and `appcast.xml`. The nightly workflow only mutates the moving `nightly` tag and prerelease assets, so it does not create version tags or update the stable appcast.

Required secret:

```text
SPARKLE_PRIVATE_KEY
```

If this secret is missing or does not match `SUPublicEDKey`, appcast validation fails and the nightly release is not published.
