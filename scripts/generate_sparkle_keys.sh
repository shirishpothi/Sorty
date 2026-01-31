#!/bin/bash
# Generate Ed25519 signing keys for Sparkle using OpenSSL
# Usage: ./scripts/generate_sparkle_keys.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KEYS_DIR="${SCRIPT_DIR}/../sparkle_keys"

mkdir -p "$KEYS_DIR"

echo "Generating Sparkle Ed25519 signing keys..."

# Generate private key (32 bytes seed for Ed25519)
openssl rand -base64 32 > "$KEYS_DIR/sparkle_private_key.base64"

# Extract raw bytes and create Ed25519 key
PRIVATE_KEY_BASE64=$(cat "$KEYS_DIR/sparkle_private_key.base64")
echo "$PRIVATE_KEY_BASE64" | base64 -d > "$KEYS_DIR/sparkle_private_key.raw"

# Generate the key pair using the seed
# Ed25519 private key is 64 bytes (32 byte seed + 32 byte public key)
# We use a simple approach compatible with Sparkle

# For Sparkle, we need to use the Sparkle CLI tools or generate compatible keys
# Let me create a Swift script instead to use Sparkle's built-in key generation

cat > "$KEYS_DIR/generate_keys.swift" << 'SWIFTEOF'
import Foundation
import CryptoKit

// Generate Ed25519 key pair
let privateKey = Curve25519.Signing.PrivateKey()
let publicKey = privateKey.publicKey

let privateKeyData = privateKey.rawRepresentation
let publicKeyData = publicKey.rawRepresentation

// Sparkle expects base64-encoded keys
let privateKeyBase64 = privateKeyData.base64EncodedString()
let publicKeyBase64 = publicKeyData.base64EncodedString()

// Save to files
let fm = FileManager.default
let keysDir = CommandLine.arguments[1]

try? privateKeyData.write(to: URL(fileURLWithPath: "\(keysDir)/sparkle_keys"))
try? publicKeyData.write(to: URL(fileURLWithPath: "\(keysDir)/sparkle_keys.pub"))

print("=== SPARKLE KEYS GENERATED ===")
print("")
print("Public key (add to Info.plist SUPublicEDKey):")
print(publicKeyBase64)
print("")
print("Private key (save to GitHub Secret SPARKLE_PRIVATE_KEY):")
print(privateKeyBase64)
print("")
print("=== IMPORTANT ===")
print("1. Add the public key to Info.plist SUPublicEDKey")
print("2. Store the private key securely in GitHub Secrets")
print("3. NEVER commit the private key to git")
print("4. Add sparkle_keys/ to .gitignore")
SWIFTEOF

echo "Running Swift key generation script..."
cd "$KEYS_DIR"
swift generate_keys.swift "$KEYS_DIR"

# Clean up
rm -f generate_keys.swift sparkle_private_key.base64 sparkle_private_key.raw

echo ""
echo "Keys saved to $KEYS_DIR/"
