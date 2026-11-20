import '../../zip_explorer/domain/zip_tree_node.dart';

enum DeployMode {
  fullSync,
  partialUpdate,
}

enum DeployStage {
  idle,
  analyzing,
  bootstrappingEmptyRepo,
  uploadingBlobs,
  creatingTree,
  creatingCommit,
  updatingRef,
  completed,
  partialFailure,
  cancelled,
  failed,
}

enum DeployLogLevel {
  info,
  success,
  warning,
  error,
  delete,
}

class DeployLogEntry {
  final DateTime timestamp;
  final String message;
  final DeployLogLevel level;

  const DeployLogEntry({
    required this.timestamp,
    required this.message,
    this.level = DeployLogLevel.info,
  });

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

/// Pre-deploy diff summary shown in the Full Sync confirmation modal.
class DeployDiffPreview {
  final List<String> addedPaths;
  final List<String> updatedPaths;
  final List<String> deletedPaths;
  final int remoteTotalFiles;
  final bool remoteTreeTruncated;
  final bool isEmptyRemote;

  const DeployDiffPreview({
    required this.addedPaths,
    required this.updatedPaths,
    required this.deletedPaths,
    required this.remoteTotalFiles,
    this.remoteTreeTruncated = false,
    this.isEmptyRemote = false,
  });

  int get addedCount => addedPaths.length;
  int get updatedCount => updatedPaths.length;
  int get deletedCount => deletedPaths.length;
}

class FailedFileUpload {
  final ResolvedZipItem item;
  final String errorMessage;

  const FailedFileUpload({
    required this.item,
    required this.errorMessage,
  });
}

class AtomicDeployResult {
  final DeployStage finalStage;
  final String? commitSha;
  final String? commitUrl;
  final int uploadedCount;
  final int reusedCount;
  final int deletedCount;
  final List<FailedFileUpload> failedFiles;
  final Map<String, String> uploadedBlobShas;
  final bool usedEmptyRepoFallback;
  final Duration elapsed;
  final String? errorMessage;

  const AtomicDeployResult({
    required this.finalStage,
    this.commitSha,
    this.commitUrl,
    required this.uploadedCount,
    this.reusedCount = 0,
    required this.deletedCount,
    required this.failedFiles,
    required this.uploadedBlobShas,
    required this.usedEmptyRepoFallback,
    required this.elapsed,
    this.errorMessage,
  });

  bool get isSuccess => finalStage == DeployStage.completed;

  String get shortCommitSha {
    final sha = commitSha ?? '';
    return sha.length >= 7 ? sha.substring(0, 7) : sha;
  }
}
