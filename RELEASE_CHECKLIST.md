# GitHub Nexus — Release & Signing Guide

## 1. Local Release Build (Quick Test)
Without a custom keystore, `android/app/build.gradle` automatically applies R8 minification & resource shrinking (`minifyEnabled = true`, `shrinkResources = true`) using debug signing so you can test the optimized APK immediately:

```bash
flutter pub get
flutter test
flutter build apk --release --split-per-abi
```

Output APKs (recommended for smaller download size):
- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (modern 64-bit Android phones)
- `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` (older 32-bit Android phones)
- `build/app/outputs/flutter-apk/app-x86_64-release.apk` (emulators / x86 tablets)

## 2. Production Signing (Play Store / Direct Distribution)
1. Generate a 4096-bit keystore:
   ```bash
   chmod +x scripts/generate_keystore.sh
   ./scripts/generate_keystore.sh
   ```
2. Copy `android/key.properties.example` to `android/key.properties` and enter your keystore credentials.
3. Build signed & obfuscated release APKs:
   ```bash
   chmod +x scripts/build_release.sh
   ./scripts/build_release.sh
   ```

## 3. Automated GitHub Actions Release Pipeline
`.github/workflows/build_release_apk.yml` automatically analyzes, tests, builds, signs, and publishes release APKs.

Add these four **Repository Secrets** (`Settings -> Secrets and variables -> Actions`):
| Secret Name | Value |
| :--- | :--- |
| `ANDROID_KEYSTORE_BASE64` | Output of `base64 -w 0 android/app/github_nexus_release.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | Your keystore store password |
| `ANDROID_KEY_ALIAS` | `githubnexus` |
| `ANDROID_KEY_PASSWORD` | Your key password |

Push a version tag to trigger an automatic GitHub Release with attached APKs and `SHA256SUMS.txt`:
```bash
git tag v1.0.0
git push origin v1.0.0
```
