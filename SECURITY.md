# Security Policy

## Supported Versions

Security updates are provided for the following versions:

| Version | Supported |
|---------|-----------|
| 1.0.x   | Yes       |
| < 1.0   | No        |

## Reporting a Vulnerability

We take security seriously. If you discover a security vulnerability, please follow these steps:

1. **Do not** open a public issue on GitHub
2. Use [GitHub's private vulnerability reporting](https://github.com/shirishpothi/Sorty/security/advisories/new) to submit details
3. Include steps to reproduce, if possible
4. Allow up to 48 hours for acknowledgment
5. We will provide an estimated timeline for the fix

## Security Considerations

### Release Signing

Sorty releases are distributed as pre-built ZIP archives. These releases are **not code-signed** and do not have a Developer ID certificate from Apple. When installing:

- macOS may show a security warning on first launch
- You need to remove the quarantine attribute manually: `xattr -cr /Applications/Sorty.app`
- This is common for open source macOS applications without paid developer accounts
- Build from source if you prefer complete control over the build process

### Sandboxing

Sorty runs within the macOS App Sandbox with the following entitlements:

- User-selected file access (read/write)
- Network access for AI provider APIs
- No system-level access outside the sandbox

### Data Security

#### Local Data Protection

- **The Learnings Profile**: Stored with AES-256 encryption
- **Biometric Protection**: Touch ID/Face ID required to access learning data
- **Organization History**: Stored locally, not encrypted (contains file paths and metadata)
- **Settings**: Stored in standard UserDefaults

#### AI Provider Data

When using cloud-based AI providers (OpenAI, Anthropic, etc.):

- File names and metadata are sent for analysis
- File contents are NOT uploaded unless Deep Scan is explicitly enabled
- API keys are stored in the macOS Keychain
- Traffic occurs over HTTPS

For maximum privacy, use local options:
- **Ollama**: Processes files entirely on your machine
- **Apple Foundation Models**: On-device processing via Apple Intelligence

### Network Security

- All API calls use HTTPS with TLS 1.2+
- API keys are never logged or transmitted outside AI provider endpoints
- Update checks fetch version data from GitHub Releases API over HTTPS
- No telemetry or analytics data is collected

### Supply Chain Security

- Dependencies are pinned in Package.resolved
- GitHub Actions workflows scan for secrets using Gitleaks
- Automated security checks run on every commit
- Build artifacts are reproducible from source

## Security Best Practices for Users

### Protecting Your Data

1. **Use Local AI When Possible**
   - Ollama keeps all processing on your device
   - Apple Foundation Models require macOS 15+

2. **Secure Your API Keys**
   - Store keys in the macOS Keychain, not in plain text
   - Use environment variables for CLI tools
   - Rotate keys periodically
   - Never commit keys to version control

3. **Review Deep Scan Settings**
   - Deep Scan uploads file content excerpts
   - Only enable for files you are comfortable analyzing remotely
   - Disable for sensitive documents

4. **Monitor Watched Folders**
   - Watched folders have persistent file system access
   - Remove folders you no longer want monitored
   - Review permissions periodically

5. **Backup Before Major Operations**
   - Safe Deletion provides a recovery window
   - Consider Time Machine or other backups for important directories
   - Test the rollback feature before relying on it

### Reporting Suspicious Behavior

If you notice:
- Unexpected network connections
- Files being accessed without your action
- Unusual API usage patterns
- Potential data leaks

Report via [GitHub's private vulnerability reporting](https://github.com/shirishpothi/Sorty/security/advisories/new) immediately with details.

## Incident Response

In the event of a security incident:

1. We will acknowledge reports within 48 hours
2. Affected users will be notified via GitHub releases and the in-app update system
3. Fixes will be prioritized based on severity
4. Post-incident reports will be published for transparency
5. CVE identifiers will be requested when applicable

## Security-Related Configuration

### Disabling Network Features

To minimize network exposure:

```swift
// Use local AI only
Settings → AI Provider → Ollama (localhost:11434)

// Disable automatic update checks
Settings → Updates → Manual only
```

### Verifying Releases

While releases are not signed, you can verify integrity:

```bash
# Download release
# Check SHA256 hash (if provided in release notes)
shasum -a 256 Sorty.zip

# Or build from source
git clone https://github.com/shirishpothi/Sorty.git
cd Sorty
make build
```

## Third-Party Security

Sorty integrates with third-party services:

- **Sparkle Framework**: Handles app updates securely
- **Various AI Providers**: Each has their own security policies
- **GitHub**: Hosts releases and update feeds

Review the security policies of your chosen AI provider:
- [OpenAI Security](https://openai.com/security)
- [Anthropic Security](https://www.anthropic.com/security)
- [Groq Security](https://groq.com/security)

## Contact

- **Security Issues**: Use [GitHub's private vulnerability reporting](https://github.com/shirishpothi/Sorty/security/advisories/new)
- **General Questions**: Open a GitHub discussion (not for vulnerabilities)

---

Last updated: January 2026
