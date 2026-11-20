import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../repos/domain/deploy_target.dart';
import '../../repos/presentation/repos_controller.dart';
import '../../zip_explorer/domain/zip_tree_node.dart';
import '../data/atomic_deploy_engine.dart';
import '../data/deploy_foreground_bridge.dart';
import '../domain/deploy_models.dart';

class DeployState {
  final DeployMode mode;
  final String commitMessage;
  final int concurrency;
  final DeployStage stage;
  final bool isAnalyzingDiff;
  final int progressPercent;
  final String progressLabel;
  final String progressStats;
  final List<DeployLogEntry> logs;
  final List<FailedFileUpload> failedFiles;
  final Map<String, String> cachedBlobShas;
  final String? cachedSessionKey;
  final AtomicDeployResult? lastResult;
  final String? errorMessage;

  const DeployState({
    this.mode = DeployMode.fullSync,
    this.commitMessage = '',
    this.concurrency = 6,
    this.stage = DeployStage.idle,
    this.isAnalyzingDiff = false,
    this.progressPercent = 0,
    this.progressLabel = 'جاهز للنشر',
    this.progressStats = '',
    this.logs = const [],
    this.failedFiles = const [],
    this.cachedBlobShas = const {},
    this.cachedSessionKey,
    this.lastResult,
    this.errorMessage,
  });

  bool get isDeploying =>
      stage == DeployStage.analyzing ||
      stage == DeployStage.bootstrappingEmptyRepo ||
      stage == DeployStage.uploadingBlobs ||
      stage == DeployStage.creatingTree ||
      stage == DeployStage.creatingCommit ||
      stage == DeployStage.updatingRef;

  bool get hasProgressCard => stage != DeployStage.idle || logs.isNotEmpty;

  bool get canRetryFailedOnly =>
      !isDeploying && failedFiles.isNotEmpty && cachedBlobShas.isNotEmpty;

  DeployState copyWith({
    DeployMode? mode,
    String? commitMessage,
    int? concurrency,
    DeployStage? stage,
    bool? isAnalyzingDiff,
    int? progressPercent,
    String? progressLabel,
    String? progressStats,
    List<DeployLogEntry>? logs,
    List<FailedFileUpload>? failedFiles,
    Map<String, String>? cachedBlobShas,
    String? cachedSessionKey,
    bool clearSessionCache = false,
    AtomicDeployResult? lastResult,
    bool clearLastResult = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DeployState(
      mode: mode ?? this.mode,
      commitMessage: commitMessage ?? this.commitMessage,
      concurrency: concurrency ?? this.concurrency,
      stage: stage ?? this.stage,
      isAnalyzingDiff: isAnalyzingDiff ?? this.isAnalyzingDiff,
      progressPercent: progressPercent ?? this.progressPercent,
      progressLabel: progressLabel ?? this.progressLabel,
      progressStats: progressStats ?? this.progressStats,
      logs: logs ?? this.logs,
      failedFiles: failedFiles ?? this.failedFiles,
      cachedBlobShas: clearSessionCache
          ? const {}
          : (cachedBlobShas ?? this.cachedBlobShas),
      cachedSessionKey: clearSessionCache
          ? null
          : (cachedSessionKey ?? this.cachedSessionKey),
      lastResult: clearLastResult ? null : (lastResult ?? this.lastResult),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final deployForegroundBridgeProvider = Provider<DeployForegroundBridge>(
  (ref) => DeployForegroundBridge(),
);

final atomicDeployEngineProvider = Provider<AtomicDeployEngine>(
  (ref) => AtomicDeployEngine(
    api: ref.watch(githubApiClientProvider),
  ),
);

final deployControllerProvider =
    StateNotifierProvider<DeployController, DeployState>((ref) {
  return DeployController(
    engine: ref.watch(atomicDeployEngineProvider),
    foregroundBridge: ref.watch(deployForegroundBridgeProvider),
    ref: ref,
  );
});

class DeployController extends StateNotifier<DeployState> {
  final AtomicDeployEngine engine;
  final DeployForegroundBridge foregroundBridge;
  final Ref ref;

  CancelToken? _activeCancelToken;
  bool _cancelFlag = false;
  StreamSubscription<void>? _notifCancelSub;
  DateTime _lastNotifUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  DeployController({
    required this.engine,
    required this.foregroundBridge,
    required this.ref,
  }) : super(const DeployState()) {
    _notifCancelSub =
        foregroundBridge.cancelRequestedStream().listen((_) => cancelDeploy());
  }

  void setDeployMode(DeployMode mode) {
    if (state.isDeploying) return;
    state = state.copyWith(mode: mode);
  }

  void setCommitMessage(String message) {
    state = state.copyWith(commitMessage: message);
  }

  void setConcurrency(int value) {
    if (state.isDeploying) return;
    state = state.copyWith(concurrency: value.clamp(2, 8));
  }

  void resetProgress() {
    if (state.isDeploying) return;
    state = state.copyWith(
      stage: DeployStage.idle,
      progressPercent: 0,
      progressLabel: 'جاهز للنشر',
      progressStats: '',
      logs: const [],
      failedFiles: const [],
      clearSessionCache: true,
      clearLastResult: true,
      clearError: true,
    );
  }

  /// Fetches live Added / Updated / Deleted counts prior to showing the Full Sync modal.
  Future<({DeployDiffPreview? preview, String? error})> analyzeDiffForPreview({
    required DeployTarget target,
    required DeployArchiveBundle bundle,
  }) async {
    final token = ref.read(authControllerProvider).activeAccount?.token;
    if (token == null || token.isEmpty) {
      return (preview: null, error: 'الجلسة غير نشطة. سجل الدخول أولاً.');
    }

    state = state.copyWith(isAnalyzingDiff: true, clearError: true);
    try {
      final preview = await engine.computeDiffPreview(
        token: token,
        target: target,
        bundle: bundle,
        mode: state.mode,
      );
      state = state.copyWith(isAnalyzingDiff: false);
      return (preview: preview, error: null);
    } catch (e) {
      state = state.copyWith(isAnalyzingDiff: false);
      return (preview: null, error: e.toString());
    }
  }

  /// Launches a fresh deployment or selectively retries failed files.
  Future<AtomicDeployResult?> startDeploy({
    required DeployTarget target,
    required DeployArchiveBundle bundle,
    bool retryFailedOnly = false,
  }) async {
    if (state.isDeploying) return null;

    final token = ref.read(authControllerProvider).activeAccount?.token;
    if (token == null || token.isEmpty) {
      state = state.copyWith(errorMessage: 'يرجى تسجيل الدخول بحساب GitHub أولاً.');
      return null;
    }

    final sessionKey =
        '${target.displayTarget}|${bundle.zipFilePath}|${bundle.archiveSizeBytes}';
    final existingShas = (retryFailedOnly && state.cachedSessionKey == sessionKey)
        ? Map<String, String>.from(state.cachedBlobShas)
        : <String, String>{};

    final effectiveMessage = state.commitMessage.trim().isNotEmpty
        ? state.commitMessage.trim()
        : 'deploy: ${bundle.archiveName} (${state.mode == DeployMode.fullSync ? 'full sync' : 'partial update'})';

    _cancelFlag = false;
    _activeCancelToken = CancelToken();

    state = state.copyWith(
      stage: DeployStage.analyzing,
      progressPercent: 1,
      progressLabel: retryFailedOnly
          ? 'إعادة محاولة الملفات الفاشلة فقط...'
          : 'بدء النشر الذري...',
      progressStats: '0/${bundle.selectedFiles.length} ملف',
      logs: retryFailedOnly ? state.logs : const [],
      failedFiles: const [],
      clearLastResult: true,
      clearError: true,
    );

    final notifTitle = 'GitHub Nexus · ${target.repo.name}:${target.branchName}';
    await foregroundBridge.start(
      title: notifTitle,
      subtitle: 'جارٍ تجهيز النشر الذري...',
    );

    final result = await engine.deploy(
      token: token,
      target: target,
      bundle: bundle,
      mode: state.mode,
      commitMessage: effectiveMessage,
      concurrency: state.concurrency,
      existingBlobShas: existingShas,
      cancelToken: _activeCancelToken!,
      isCancelled: () => _cancelFlag,
      onProgress: ({
        required stage,
        required percent,
        required label,
        required stats,
      }) {
        state = state.copyWith(
          stage: stage,
          progressPercent: percent,
          progressLabel: label,
          progressStats: stats,
        );

        final now = DateTime.now();
        if (percent == 100 ||
            now.difference(_lastNotifUpdate).inMilliseconds >= 450) {
          _lastNotifUpdate = now;
          unawaited(
            foregroundBridge.updateProgress(
              title: notifTitle,
              subtitle: '$label ($stats)',
              progress: percent,
            ),
          );
        }
      },
      onLog: (entry) {
        final nextLogs = [...state.logs, entry];
        // Cap console ring buffer to 600 lines for smooth scrolling on massive repos.
        final trimmed = nextLogs.length > 600
            ? nextLogs.sublist(nextLogs.length - 600)
            : nextLogs;
        state = state.copyWith(logs: trimmed);
      },
    );

    _activeCancelToken = null;

    state = state.copyWith(
      stage: result.finalStage,
      progressPercent: result.isSuccess ? 100 : state.progressPercent,
      progressLabel: switch (result.finalStage) {
        DeployStage.completed =>
          'اكتمل النشر الذري (${result.shortCommitSha})',
        DeployStage.partialFailure =>
          'فشل ${result.failedFiles.length} ملف — يمكنك إعادة المحاولة',
        DeployStage.cancelled => 'تم إلغاء النشر',
        _ => 'فشل النشر',
      },
      failedFiles: result.failedFiles,
      cachedBlobShas: result.isSuccess ? const {} : result.uploadedBlobShas,
      cachedSessionKey: result.isSuccess ? null : sessionKey,
      lastResult: result,
      errorMessage: result.errorMessage,
    );

    await foregroundBridge.finish(
      title: result.isSuccess
          ? 'اكتمل النشر إلى ${target.repo.name}'
          : (result.finalStage == DeployStage.cancelled
              ? 'تم إلغاء النشر'
              : 'تعثر النشر إلى ${target.repo.name}'),
      subtitle: result.isSuccess
          ? 'Commit ${result.shortCommitSha} • ${bundle.selectedFiles.length} ملف (${result.deletedCount} محذوف)'
          : (result.errorMessage ?? 'راجع سجل العمليات داخل التطبيق'),
      success: result.isSuccess,
    );

    // Refresh branches in Phase 2 controller so newly bootstrapped empty repos update immediately.
    if (result.isSuccess) {
      unawaited(
        ref.read(reposControllerProvider.notifier).reloadBranchesForSelected(),
      );
    }

    return result;
  }

  void cancelDeploy() {
    if (!state.isDeploying || _cancelFlag) return;
    _cancelFlag = true;
    _activeCancelToken?.cancel('Cancelled by user');
    state = state.copyWith(
      progressLabel: 'جارٍ إيقاف العمليات النشطة...',
    );
  }

  @override
  void dispose() {
    _notifCancelSub?.cancel();
    _activeCancelToken?.cancel('Controller disposed');
    super.dispose();
  }
}
