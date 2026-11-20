#!/usr/bin/env bash
set -euo pipefail

echo "1/4 Fetching packages..."
flutter pub get

echo "2/4 Running static analysis..."
flutter analyze --no-fatal-infos

echo "3/4 Running all tests..."
flutter test

echo "4/4 Building optimized split-per-abi & universal release APKs..."
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/debug-symbols
flutter build apk --release --obfuscate --split-debug-info=build/debug-symbols

echo ""
echo "Release APKs ready in build/app/outputs/flutter-apk/:"
ls -lh build/app/outputs/flutter-apk/*.apk
