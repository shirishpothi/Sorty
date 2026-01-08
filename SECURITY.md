# Security Policy

## Supported Versions

The following versions of the Sorty project are currently being supported with security updates:

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

We take the security of Sorty strictly. If you have discovered a security vulnerability, please follow these steps:

1.  **Do not** open a public issue on GitHub.
2.  Send an email to [security@sorty.app](mailto:security@sorty.app) (or your designated security contact).
3.  Include as much detail as possible to help us reproduce the issue.

We will acknowledge your email within 48 hours and provide an estimated timeline for the fix.

## Security Features

Sorty implements the following security measures:
- **Sandboxing**: Runs within the macOS App Sandbox.
- **Harden Runner**: GitHub Actions are monitored for tamper attempts.
- **Secret Scanning**: All commits are scanned for exposed credentials.
- **Code Signing**: Releases are signed with a Developer ID.
