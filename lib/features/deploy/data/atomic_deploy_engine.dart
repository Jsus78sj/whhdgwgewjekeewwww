import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../../core/network/github_api_client.dart';
import '../../../core/network/github_exceptions.dart';
import '../../repos/domain/deploy_target.dart';
import '../../zip_explorer/data/streaming_zip_inspector.dart';
import '../../zip_explorer/domain/zip_entry_meta.dart';
import '../../zip_explorer/domain/zip_tree_node.dart';
import '../domain/deploy_models.dart';

typedef ZipBytesReader = Future<Uint8List> Function(
  String zipFilePath,
  ZipEntryMeta entry,
);

typedef DeployProgressCallback = void Function({
  required DeployStage stage,
  required int percent,
  required String label,
  required String stats,
});

typedef DeployLogCallback = void Function(DeployLogEntry entry);

/// High-throughput atomic deployment engine powered by GitHub's Git Data API:
/// 1. Streams & uploads selected ZIP files in bounded parallel batches (`concurrency`).
/// 2. Builds a single Git Tree (omitting `base_tree` for Full Sync auto-deletion,
///    or attaching `base_tree` for Partial Update merge).
/// 3. Creates ONE clean Git Commit and atomically moves the branch ref.
/// 4. Handles completely empty repositories transparently via a bootstrap commit fallback.
/// 5. Supports selective retry of failed files by reusing already-uploaded blob SHAs.
class AtomicDeployEngine {
  final GitHubApiClient api;
  final ZipBytesReader readEntryBytes;

  AtomicDeployEngine({
    required this.api,
    ZipBytesReader? readEntryBytes,
  }) : readEntryBytes = readEntryBytes ?? StreamingZipInspector.readEntryBytes;

  /// Computes Added / Updated / Deleted counts against the remote branch tree
  /// before running a destructive Full Sync confirmation dialog.
  Future<DeployDiffPreview> computeDiffPreview({
    required String token,
    required DeployTarget target,
    required DeployArchiveBundle bundle,
    required DeployMode mode,
    CancelToken? cancelToken,
  }) async {
    final localPaths =
        bundle.selectedFiles.map((f) => f.effectivePath).toList();
    final localSet = localPaths.toSet();

    if (target.isEmptyRepo) {
      return DeployDiffPreview(
        addedPaths: localPaths,
        updatedPaths: const [],
        deletedPaths: const [],
        remoteTotalFiles: 0,
        isEmptyRemote: true,
      );
    }

    final head = await api.fetchBranchHead(
      token: token,
      owner: target.repo.ownerLogin,
      repo: target.repo.name,
      branchName: target.branchName,
      cancelToken: cancelToken,
    );

    if (head == null) {
      return DeployDiffPreview(
        addedPaths: localPaths,
        updatedPaths: const [],
        deletedPaths: const [],
        remoteTotalFiles: 0,
        isEmptyRemote: true,
      );
    }

    final remoteTree = await api.fetchRecursiveTree(
      token: token,
      owner: target.repo.ownerLogin,
      repo: target.repo.name,
      treeSha: head.treeSha,
      cancelToken: cancelToken,
    );

    final remoteSet = remoteTree.blobs.map((b) => b.path).toSet();
    final added = <String>[];
    final updated = <String>[];

    for (final path in localPaths) {
      if (remoteSet.contains(path)) {
        updated.add(path);
      } else {
        added.add(path);
      }
    }

    final deleted = mode == DeployMode.fullSync
        ? remoteTree.blobs
            .map((b) => b.path)
            .where((p) => !localSet.contains(p))
            .toList()
        : const <String>[];

    return DeployDiffPreview(
      addedPaths: added,
      updatedPaths: updated,
      deletedPaths: deleted,
      remoteTotalFiles: remoteTree.blobs.length,
      remoteTreeTruncated: remoteTree.truncated,
      isEmptyRemote: false,
    );
  }

  /// Executes an atomic deployment (or retries only failed items reusing [existingBlobShas]).
  Future<AtomicDeployResult> deploy({
    required String token,
    required DeployTarget target,
    required DeployArchiveBundle bundle,
    required DeployMode mode,
    required String commitMessage,
    int concurrency = 6,
    Map<String, String> existingBlobShas = const {},
    required CancelToken cancelToken,
    required bool Function() isCancelled,
    required DeployProgressCallback onProgress,
    required DeployLogCallback onLog,
  }) async {
    final stopwatch = Stopwatch()..start();
    final owner = target.repo.ownerLogin;
    final repo = target.repo.name;
    final branch = target.branchName;
    final selectedFiles = bundle.selectedFiles;

    if (selectedFiles.isEmpty) {
      return AtomicDeployResult(
        finalStage: DeployStage.failed,
        uploadedCount: 0,
        deletedCount: 0,
        failedFiles: const [],
        uploadedBlobShas: existingBlobShas,
        usedEmptyRepoFallback: false,
        elapsed: stopwatch.elapsed,
        errorMessage: 'لا توجد ملفات محددة للنشر.',
      );
    }

    final blobShas = Map<String, String>.from(existingBlobShas);
    var usedEmptyFallback = false;
    var deletedCount = 0;

    void emitLog(String msg, [DeployLogLevel level = DeployLogLevel.info]) {
      onLog(
        DeployLogEntry(
          timestamp: DateTime.now(),
          message: msg,
          level: level,
        ),
      );
    }

    try {
      emitLog(
        'بدء النشر الذري إلى $owner/$repo:$branch '
        '[${mode == DeployMode.fullSync ? 'FULL SYNC' : 'PARTIAL UPDATE'}]',
      );

      onProgress(
        stage: DeployStage.analyzing,
        percent: 2,
        label: 'تحليل حالة الفرع المستهدف...',
        stats: '0/${selectedFiles.length} ملف',
      );

      BranchHeadRef? head = await api.fetchBranchHead(
        token: token,
        owner: owner,
        repo: repo,
        branchName: branch,
        cancelToken: cancelToken,
      );

      if (isCancelled()) {
        return _cancelledResult(blobShas, usedEmptyFallback, stopwatch.elapsed);
      }

      // -----------------------------------------------------------------------
      // Empty Repository Automatic Fallback
      // -----------------------------------------------------------------------
      if (head == null) {
        usedEmptyFallback = true;
        final firstFile = selectedFiles.first;
        emitLog(
          'تم اكتشاف مستودع فارغ — تفعيل مسار التهيئة التلقائي عبر ${firstFile.effectivePath}',
          DeployLogLevel.warning,
        );

        onProgress(
          stage: DeployStage.bootstrappingEmptyRepo,
          percent: 6,
          label: 'تهيئة المستودع الفارغ بأول ملف...',
          stats: '0/${selectedFiles.length} ملف',
        );

        final firstBytes =
            await readEntryBytes(bundle.zipFilePath, firstFile.entry);
        final bootstrapCommit = await api.putSingleFileContent(
          token: token,
          owner: owner,
          repo: repo,
          path: firstFile.effectivePath,
          bytes: firstBytes,
          message: selectedFiles.length == 1
              ? commitMessage
              : 'chore: bootstrap empty repository (${firstFile.effectivePath})',
          branchName: branch,
          cancelToken: cancelToken,
        );

        // If the ZIP only contained 1 file, the bootstrap commit IS the complete deployment!
        if (selectedFiles.length == 1) {
          emitLog(
            'تم رفع الملف الوحيد وإنشاء الـ Commit الأول بنجاح (${bootstrapCommit.sha.substring(0, bootstrapCommit.sha.length.clamp(0, 7))})',
            DeployLogLevel.success,
          );
          onProgress(
            stage: DeployStage.completed,
            percent: 100,
            label: 'اكتمل النشر بنجاح',
            stats: '1↑ · 0🗑 · 0✗',
          );
          return AtomicDeployResult(
            finalStage: DeployStage.completed,
            commitSha: bootstrapCommit.sha,
            commitUrl: bootstrapCommit.htmlUrl,
            uploadedCount: 1,
            deletedCount: 0,
            failedFiles: const [],
            uploadedBlobShas: blobShas,
            usedEmptyRepoFallback: true,
            elapsed: stopwatch.elapsed,
          );
        }

        // Re-fetch newly initialized branch HEAD so Git Data API works for the atomic commit.
        head = await api.fetchBranchHead(
          token: token,
          owner: owner,
          repo: repo,
          branchName: branch,
          cancelToken: cancelToken,
        );
        if (head == null) {
          throw const GitHubApiException(
            'تعذر قراءة الفرع بعد تهيئة المستودع الفارغ.',
          );
        }
        emitLog(
          'تمت تهيئة الفرع ($branch) بنجاح — المتابعة عبر Git Data API...',
          DeployLogLevel.success,
        );
      } else if (mode == DeployMode.fullSync) {
        // Compute exact deleted file count for accurate logging & stats.
        final remoteSnapshot = await api.fetchRecursiveTree(
          token: token,
          owner: owner,
          repo: repo,
          treeSha: head.treeSha,
          cancelToken: cancelToken,
        );
        final localPaths = selectedFiles.map((f) => f.effectivePath).toSet();
        final toDelete = remoteSnapshot.blobs
            .map((b) => b.path)
            .where((p) => !localPaths.contains(p))
            .toList();
        deletedCount = toDelete.length;
        if (deletedCount > 0) {
          emitLog(
            'وضع Full Sync: سيتم حذف $deletedCount ملف قديم تلقائياً داخل نفس الـ Commit دون طلبات DELETE منفصلة.',
            DeployLogLevel.delete,
          );
        }
      }

      if (isCancelled()) {
        return _cancelledResult(blobShas, usedEmptyFallback, stopwatch.elapsed);
      }

      // -----------------------------------------------------------------------
      // Step 1: Parallel Batched Blob Uploads (Streaming 1 entry per worker)
      // -----------------------------------------------------------------------
      final filesToUpload = <ResolvedZipItem>[];
      var reusedCount = 0;

      for (final item in selectedFiles) {
        if (blobShas.containsKey(item.effectivePath)) {
          reusedCount++;
        } else {
          filesToUpload.add(item);
        }
      }

      if (reusedCount > 0) {
        emitLog(
          'إعادة استخدام $reusedCount ملف مرفوع مسبقاً — سيتم رفع ${filesToUpload.length} ملف فقط.',
          DeployLogLevel.info,
        );
      } else {
        emitLog(
          'رفع ${filesToUpload.length} ملف كـ Git Blobs بدفعات متوازية ($concurrency ملفات معاً)...',
          DeployLogLevel.info,
        );
      }

      final failedFiles = <FailedFileUpload>[];
      var uploadedInThisRun = 0;
      var processed = reusedCount;
      final totalFiles = selectedFiles.length;
      final effectiveWorkers = concurrency.clamp(1, 8);

      var cursor = 0;

      Future<void> worker() async {
        while (true) {
          if (isCancelled()) return;
          final idx = cursor++;
          if (idx >= filesToUpload.length) return;

          final item = filesToUpload[idx];
          try {
            final bytes = await readEntryBytes(bundle.zipFilePath, item.entry);
            if (isCancelled()) return;

            final blobSha = await api.createBlob(
              token: token,
              owner: owner,
              repo: repo,
              bytes: bytes,
              cancelToken: cancelToken,
            );
            blobShas[item.effectivePath] = blobSha;
            uploadedInThisRun++;
            emitLog(
              'Uploaded blob: ${item.effectivePath}',
              DeployLogLevel.success,
            );
          } on DioException catch (e) {
            if (CancelToken.isCancel(e) || isCancelled()) return;
            final msg = e.message ?? 'خطأ شبكة أثناء رفع الملف';
            failedFiles.add(FailedFileUpload(item: item, errorMessage: msg));
            emitLog('فشل رفع ${item.effectivePath}: $msg', DeployLogLevel.error);
          } catch (e) {
            if (isCancelled()) return;
            final msg = e.toString();
            failedFiles.add(FailedFileUpload(item: item, errorMessage: msg));
            emitLog('فشل رفع ${item.effectivePath}: $msg', DeployLogLevel.error);
          } finally {
            processed++;
            // Allocate 8% -> 84% of progress bar to blob uploads
            final pct = 8 + ((processed / totalFiles) * 76).round();
            onProgress(
              stage: DeployStage.uploadingBlobs,
              percent: pct.clamp(8, 84),
              label: 'رفع الملفات ($processed / $totalFiles)...',
              stats:
                  '${uploadedInThisRun + reusedCount}↑ · $deletedCount🗑 · ${failedFiles.length}✗',
            );
          }
        }
      }

      if (filesToUpload.isNotEmpty) {
        final workerCount = filesToUpload.length < effectiveWorkers
            ? filesToUpload.length
            : effectiveWorkers;
        await Future.wait(List.generate(workerCount, (_) => worker()));
      }

      if (isCancelled()) {
        emitLog('تم إلغاء النشر بواسطة المستخدم.', DeployLogLevel.warning);
        return _cancelledResult(blobShas, usedEmptyFallback, stopwatch.elapsed);
      }

      // If any blobs failed, abort BEFORE mutating the branch ref so the repo remains 100% clean,
      // and allow the user to retry ONLY the failed files while keeping all uploaded blob SHAs!
      if (failedFiles.isNotEmpty) {
        emitLog(
          'توقف النشر قبل تعديل الفرع بسبب فشل ${failedFiles.length} ملف. يمكنك إعادة محاولة الملفات الفاشلة فقط دون إعادة رفع البقية.',
          DeployLogLevel.warning,
        );
        onProgress(
          stage: DeployStage.partialFailure,
          percent: 84,
          label: 'فشل رفع ${failedFiles.length} ملف — لم يتغير الفرع بعد',
          stats:
              '${uploadedInThisRun + reusedCount}↑ · $deletedCount🗑 · ${failedFiles.length}✗',
        );
        return AtomicDeployResult(
          finalStage: DeployStage.partialFailure,
          uploadedCount: uploadedInThisRun,
          reusedCount: reusedCount,
          deletedCount: 0,
          failedFiles: failedFiles,
          uploadedBlobShas: blobShas,
          usedEmptyRepoFallback: usedEmptyFallback,
          elapsed: stopwatch.elapsed,
          errorMessage:
              'فشل رفع ${failedFiles.length} ملف. اضغط "إعادة محاولة الفاشلة فقط" لإكمال الـ Commit.',
        );
      }

      // -----------------------------------------------------------------------
      // Step 2: Build Single Git Tree (Full Sync omits base_tree; Partial sets base_tree)
      // -----------------------------------------------------------------------
      onProgress(
        stage: DeployStage.creatingTree,
        percent: 88,
        label: 'بناء شجرة Git الذرية (Tree)...',
        stats: '$totalFiles↑ · $deletedCount🗑 · 0✗',
      );
      emitLog(
        mode == DeployMode.fullSync
            ? 'إنشاء شجرة كاملة جديدة (${selectedFiles.length} ملف، بدون base_tree)...'
            : 'دمج ${selectedFiles.length} ملف فوق الشجرة الحالية (base_tree)...',
      );

      final treeItems = selectedFiles.map((item) {
        final sha = blobShas[item.effectivePath]!;
        return GitTreeItemInput(path: item.effectivePath, blobSha: sha);
      }).toList();

      final newTreeSha = await api.createTree(
        token: token,
        owner: owner,
        repo: repo,
        entries: treeItems,
        baseTreeSha: mode == DeployMode.partialUpdate ? head.treeSha : null,
        cancelToken: cancelToken,
      );

      if (isCancelled()) {
        return _cancelledResult(blobShas, usedEmptyFallback, stopwatch.elapsed);
      }

      // -----------------------------------------------------------------------
      // Step 3: Create Single Atomic Commit
      // -----------------------------------------------------------------------
      onProgress(
        stage: DeployStage.creatingCommit,
        percent: 94,
        label: 'إنشاء Commit واحد نظيف...',
        stats: '$totalFiles↑ · $deletedCount🗑 · 0✗',
      );

      final createdCommit = await api.createCommit(
        token: token,
        owner: owner,
        repo: repo,
        message: commitMessage.trim().isEmpty
            ? 'deploy: ${bundle.archiveName} via GitHub Nexus'
            : commitMessage.trim(),
        treeSha: newTreeSha,
        parentShas: [head.commitSha],
        cancelToken: cancelToken,
      );

      if (isCancelled()) {
        return _cancelledResult(blobShas, usedEmptyFallback, stopwatch.elapsed);
      }

      // -----------------------------------------------------------------------
      // Step 4: Fast-Forward Branch Ref
      // -----------------------------------------------------------------------
      onProgress(
        stage: DeployStage.updatingRef,
        percent: 98,
        label: 'تحديث مؤشر الفرع ($branch)...',
        stats: '$totalFiles↑ · $deletedCount🗑 · 0✗',
      );

      await api.updateBranchRef(
        token: token,
        owner: owner,
        repo: repo,
        branchName: branch,
        commitSha: createdCommit.sha,
        cancelToken: cancelToken,
      );

      final shortSha = createdCommit.sha.length >= 7
          ? createdCommit.sha.substring(0, 7)
          : createdCommit.sha;

      emitLog(
        'اكتمل النشر بنجاح في Commit واحد ($shortSha) خلال ${stopwatch.elapsed.inSeconds} ثانية!',
        DeployLogLevel.success,
      );

      onProgress(
        stage: DeployStage.completed,
        percent: 100,
        label: 'اكتمل النشر الذري ($shortSha)',
        stats: '$totalFiles↑ · $deletedCount🗑 · 0✗',
      );

      return AtomicDeployResult(
        finalStage: DeployStage.completed,
        commitSha: createdCommit.sha,
        commitUrl: createdCommit.htmlUrl,
        uploadedCount: uploadedInThisRun,
        reusedCount: reusedCount,
        deletedCount: deletedCount,
        failedFiles: const [],
        uploadedBlobShas: blobShas,
        usedEmptyRepoFallback: usedEmptyFallback,
        elapsed: stopwatch.elapsed,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e) || isCancelled()) {
        emitLog('تم إلغاء عملية النشر.', DeployLogLevel.warning);
        return _cancelledResult(blobShas, usedEmptyFallback, stopwatch.elapsed);
      }
      final msg = e.message ?? 'انقطع الاتصال أثناء النشر.';
      emitLog('خطأ اتصال: $msg', DeployLogLevel.error);
      return _failedResult(blobShas, usedEmptyFallback, stopwatch.elapsed, msg);
    } on GitHubException catch (e) {
      emitLog('خطأ GitHub API: ${e.message}', DeployLogLevel.error);
      return _failedResult(
        blobShas,
        usedEmptyFallback,
        stopwatch.elapsed,
        e.message,
      );
    } catch (e) {
      emitLog('خطأ غير متوقع: $e', DeployLogLevel.error);
      return _failedResult(
        blobShas,
        usedEmptyFallback,
        stopwatch.elapsed,
        e.toString(),
      );
    }
  }

  AtomicDeployResult _cancelledResult(
    Map<String, String> blobShas,
    bool usedEmptyFallback,
    Duration elapsed,
  ) {
    return AtomicDeployResult(
      finalStage: DeployStage.cancelled,
      uploadedCount: 0,
      deletedCount: 0,
      failedFiles: const [],
      uploadedBlobShas: blobShas,
      usedEmptyRepoFallback: usedEmptyFallback,
      elapsed: elapsed,
      errorMessage: 'تم إلغاء النشر بواسطة المستخدم.',
    );
  }

  AtomicDeployResult _failedResult(
    Map<String, String> blobShas,
    bool usedEmptyFallback,
    Duration elapsed,
    String message,
  ) {
    return AtomicDeployResult(
      finalStage: DeployStage.failed,
      uploadedCount: 0,
      deletedCount: 0,
      failedFiles: const [],
      uploadedBlobShas: blobShas,
      usedEmptyRepoFallback: usedEmptyFallback,
      elapsed: elapsed,
      errorMessage: message,
    );
  }
}
