#!/usr/bin/env bash
set -euo pipefail

KEYSTORE_PATH="android/app/github_nexus_release.jks"
ALIAS="githubnexus"

if [ -f "$KEYSTORE_PATH" ]; then
  echo "Keystore already exists at $KEYSTORE_PATH"
  exit 1
fi

echo "Generating RSA 4096-bit Android release keystore at $KEYSTORE_PATH ..."
keytool -genkey -v \
  -keystore "$KEYSTORE_PATH" \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000 \
  -alias "$ALIAS"

echo ""
echo "Done! Next steps:"
echo "1. Copy android/key.properties.example to android/key.properties and fill in your passwords."
echo "2. For GitHub Actions CI, base64-encode the keystore:"
echo "   base64 -w 0 $KEYSTORE_PATH"
echo "   and save it in repository Secrets as ANDROID_KEYSTORE_BASE64."
