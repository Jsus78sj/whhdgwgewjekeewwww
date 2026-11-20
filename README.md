# GitHub Nexus — Repo Manager Pro (Final Release v1.0.0)

Production-ready Flutter Android APK application converted and upgraded from **GitHub Nexus** across all 5 engineering phases.

## Architecture & Completed Phases

### Phase 1 — Core Architecture & Secure Auth
- Offline Dark Glassmorphism UI (`NexusColors`, `NexusTheme`, `GlassPanel`, `NexusAmbientBackground`, `NexusGradientButton`, `showNexusToast`).
- `GitHubApiClient` (Dio) with `2022-11-28` headers, exponential backoff retry (5xx / 429 / timeouts), and live `X-RateLimit-*` monitoring.
- Multi-account encrypted PAT storage via **Android Keystore (`EncryptedSharedPreferences`)** supporting both Classic (`ghp_`) and Fine-Grained (`github_pat_`) tokens.

### Phase 2 — Repositories & Branches Manager
- Paginated repository fetching with Pull-to-Refresh, instant search, visibility filters (`All` / `Public` / `Private`), and sorting (`Updated` / `Name` / `Stars`).
- Create Repository modal, Branch Switcher & Creator (with Git ref validation), and automatic Empty Repository detection with 1-tap `README.md` initialization.

### Phase 3 — Streaming ZIP Explorer & Pre-Deploy Filtering
- Zero-decompression `StreamingZipInspector` (ZIP64 + Zip-Slip guard) executed inside `Isolate.run` for smooth inspection of archives up to 100 MB.
- System File Picker + native Android Share Sheet (`ACTION_SEND` / `ACTION_VIEW`) with 64 KB buffered copy.
- Hierarchical Tree View with tri-state selection, automatic single-root folder stripping, preset & custom exclusion rules, and 100 MB limit auto-remediation.

### Phase 4 — Atomic Deploy Engine & Background Foreground Service
- **Git Data API Single-Commit Engine (`AtomicDeployEngine`)** with 6x parallel streaming blob uploads.
- **Full Sync (Mirror)** with live Added / Updated / Deleted confirmation modal and atomic tree replacement (zero individual `DELETE` requests).
- **Partial Update (Merge)** preserving untouched remote files via `base_tree`.
- Automatic empty-repo bootstrap fallback, selective **Retry Failed Files Only** reusing uploaded Blob SHAs, and native Android `DeployForegroundService` (`dataSync` + `WakeLock` + Cancel notification button) with Live Console Log.

### Phase 5 — QA Integration Tests, Release Optimization & CI/CD
- End-to-end integration tests (`test/integration/end_to_end_deploy_flow_test.dart`) & widget smoke tests (`test/widget/app_smoke_test.dart`).
- Adaptive Android Launcher Icons (vector + legacy densities + round icons) and Android 12+ native Splash Screen (`values-v31/styles.xml`).
- R8 code shrinking, resource shrinking, and tailored `proguard-rules.pro` protecting Keystore/Tink/ForegroundService.
- Signing config (`android/key.properties.example`), helper scripts (`scripts/`), and GitHub Actions workflow (`.github/workflows/build_release_apk.yml`) producing split-per-ABI + universal release APKs with SHA-256 checksums.

## Quick Commands
```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

See `RELEASE_CHECKLIST.md` for keystore generation and GitHub Actions Secrets setup.
