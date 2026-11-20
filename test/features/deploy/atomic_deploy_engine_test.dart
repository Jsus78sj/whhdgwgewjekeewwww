import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/core/network/github_api_client.dart';
import 'package:github_nexus/features/deploy/data/atomic_deploy_engine.dart';
import 'package:github_nexus/features/deploy/domain/deploy_models.dart';
import 'package:github_nexus/features/repos/domain/deploy_target.dart';
import 'package:github_nexus/features/repos/domain/github_repo.dart';
import 'package:github_nexus/features/zip_explorer/domain/zip_entry_meta.dart';
import 'package:github_nexus/features/zip_explorer/domain/zip_tree_node.dart';

class _FakeGitHubApiClient extends GitHubApiClient {
  BranchHeadRef? headRef;
  RemoteTreeSnapshot remoteTree;
  final Set<String> failBlobPathsOnce;

  int createBlobCalls = 0;
  int createTreeCalls = 0;
  String? lastTreeBaseSha;
  List<GitTreeItemInput> lastTreeItems = const [];
  String? lastCommitMessage;
  String? lastUpdatedRefSha;
  int putSingleFileCalls = 0;

  _FakeGitHubApiClient({
    required this.headRef,
    required this.remoteTree,
    Set<String>? failBlobPathsOnce,
  }) : failBlobPathsOnce = failBlobPathsOnce ?? <String>{};

  @override
  Future<BranchHeadRef?> fetchBranchHead({
    required String token,
    required String owner,
    required String repo,
    required String branchName,
    CancelToken? cancelToken,
  }) async =>
      headRef;

  @override
  Future<RemoteTreeSnapshot> fetchRecursiveTree({
    required String token,
    required String owner,
    required String repo,
    required String treeSha,
    CancelToken? cancelToken,
  }) async =>
      remoteTree;

  @override
  Future<String> createBlob({
    required String token,
    required String owner,
    required String repo,
    required Uint8List bytes,
    CancelToken? cancelToken,
  }) async {
    createBlobCalls++;
    final text = utf8.decode(bytes);
    if (failBlobPathsOnce.remove(text)) {
      throw Exception('Simulated network drop for $text');
    }
    return 'blob_sha_${text.hashCode.abs()}';
  }

  @override
  Future<String> createTree({
    required String token,
    required String owner,
    required String repo,
    required List<GitTreeItemInput> entries,
    String? baseTreeSha,
    CancelToken? cancelToken,
  }) async {
    createTreeCalls++;
    lastTreeBaseSha = baseTreeSha;
    lastTreeItems = entries;
    return 'tree_sha_new_001';
  }

  @override
  Future<CreatedCommitResult> createCommit({
    required String token,
    required String owner,
    required String repo,
    required String message,
    required String treeSha,
    required List<String> parentShas,
    CancelToken? cancelToken,
  }) async {
    lastCommitMessage = message;
    return CreatedCommitResult(
      sha: 'abcdef1234567890',
      htmlUrl: 'https://github.com/$owner/$repo/commit/abcdef1234567890',
      message: message,
    );
  }

  @override
  Future<void> updateBranchRef({
    required String token,
    required String owner,
    required String repo,
    required String branchName,
    required String commitSha,
    bool force = false,
    CancelToken? cancelToken,
  }) async {
    lastUpdatedRefSha = commitSha;
  }

  @override
  Future<CreatedCommitResult> putSingleFileContent({
    required String token,
    required String owner,
    required String repo,
    required String path,
    required Uint8List bytes,
    required String message,
    required String branchName,
    CancelToken? cancelToken,
  }) async {
    putSingleFileCalls++;
    // Simulate branch now existing after bootstrap commit
    headRef = const BranchHeadRef(
      commitSha: 'bootstrap_commit_sha',
      treeSha: 'bootstrap_tree_sha',
    );
    return CreatedCommitResult(
      sha: 'bootstrap_commit_sha',
      htmlUrl: 'https://github.com/$owner/$repo/commit/bootstrap_commit_sha',
      message: message,
    );
  }
}

ResolvedZipItem _makeItem(String path) {
  return ResolvedZipItem(
    entry: ZipEntryMeta(
      rawPath: path,
      normalizedPath: path,
      compressedSize: path.length,
      uncompressedSize: path.length,
      compressionMethod: 0,
      localHeaderOffset: 0,
      crc32: 0,
      isEncrypted: false,
    ),
    effectivePath: path,
    excludedByRule: false,
    isSelected: true,
  );
}

DeployArchiveBundle _makeBundle(List<String> paths) {
  final items = paths.map(_makeItem).toList();
  return DeployArchiveBundle(
    zipFilePath: '/tmp/test.zip',
    archiveName: 'release.zip',
    archiveSizeBytes: 1024,
    selectedFiles: items,
    totalEntriesCount: items.length,
    excludedCount: 0,
    oversizedSelectedCount: 0,
    softWarningSelectedCount: 0,
    encryptedSelectedCount: 0,
    stripRootFolder: false,
    strippedRootFolderName: null,
  );
}

DeployTarget _makeTarget({bool isEmpty = false}) {
  return DeployTarget(
    repo: const GitHubRepo(
      id: 10,
      name: 'nexus-demo',
      fullName: 'abdullah/nexus-demo',
      ownerLogin: 'abdullah',
      description: '',
      isPrivate: true,
      defaultBranch: 'main',
      stargazersCount: 0,
      language: 'Dart',
      sizeKb: 100,
      updatedAt: null,
      htmlUrl: 'https://github.com/abdullah/nexus-demo',
      canPush: true,
    ),
    branchName: 'main',
    isEmptyRepo: isEmpty,
    headCommitSha: isEmpty ? null : 'old_commit_sha',
  );
}

void main() {
  Future<Uint8List> fakeReader(String _, ZipEntryMeta entry) async =>
      Uint8List.fromList(utf8.encode(entry.normalizedPath));

  group('AtomicDeployEngine', () {
    test('Full Sync computes exact diff and builds tree WITHOUT base_tree in 1 commit', () async {
      final api = _FakeGitHubApiClient(
        headRef: const BranchHeadRef(
          commitSha: 'old_commit_sha',
          treeSha: 'old_tree_sha',
        ),
        remoteTree: const RemoteTreeSnapshot(
          blobs: [
            RemoteTreeBlob(path: 'README.md', sha: 's1', mode: '100644', size: 10),
            RemoteTreeBlob(path: 'legacy/old.dart', sha: 's2', mode: '100644', size: 20),
          ],
          truncated: false,
        ),
      );
      final engine = AtomicDeployEngine(api: api, readEntryBytes: fakeReader);
      final target = _makeTarget();
      final bundle = _makeBundle(['README.md', 'lib/main.dart']);

      final diff = await engine.computeDiffPreview(
        token: 'tok',
        target: target,
        bundle: bundle,
        mode: DeployMode.fullSync,
      );
      expect(diff.addedPaths, ['lib/main.dart']);
      expect(diff.updatedPaths, ['README.md']);
      expect(diff.deletedPaths, ['legacy/old.dart']);

      final result = await engine.deploy(
        token: 'tok',
        target: target,
        bundle: bundle,
        mode: DeployMode.fullSync,
        commitMessage: 'release: full sync v1',
        cancelToken: CancelToken(),
        isCancelled: () => false,
        onProgress: ({required stage, required percent, required label, required stats}) {},
        onLog: (_) {},
      );

      expect(result.isSuccess, isTrue);
      expect(result.deletedCount, 1);
      expect(api.createBlobCalls, 2);
      expect(api.createTreeCalls, 1);
      expect(api.lastTreeBaseSha, isNull); // Critical: Full Sync omits base_tree
      expect(api.lastUpdatedRefSha, 'abcdef1234567890');
    });

    test('Partial Update passes base_tree and preserves untouched remote files', () async {
      final api = _FakeGitHubApiClient(
        headRef: const BranchHeadRef(
          commitSha: 'old_commit_sha',
          treeSha: 'old_tree_sha',
        ),
        remoteTree: const RemoteTreeSnapshot(
          blobs: [
            RemoteTreeBlob(path: 'keep_me.txt', sha: 's1', mode: '100644', size: 10),
          ],
          truncated: false,
        ),
      );
      final engine = AtomicDeployEngine(api: api, readEntryBytes: fakeReader);

      final result = await engine.deploy(
        token: 'tok',
        target: _makeTarget(),
        bundle: _makeBundle(['lib/feature.dart']),
        mode: DeployMode.partialUpdate,
        commitMessage: 'feat: partial merge',
        cancelToken: CancelToken(),
        isCancelled: () => false,
        onProgress: ({required stage, required percent, required label, required stats}) {},
        onLog: (_) {},
      );

      expect(result.isSuccess, isTrue);
      expect(result.deletedCount, 0);
      expect(api.lastTreeBaseSha, 'old_tree_sha');
      expect(api.lastTreeItems.map((e) => e.path), ['lib/feature.dart']);
    });

    test('Partial blob failure preserves branch and retries ONLY failed files', () async {
      final api = _FakeGitHubApiClient(
        headRef: const BranchHeadRef(
          commitSha: 'old_commit_sha',
          treeSha: 'old_tree_sha',
        ),
        remoteTree: const RemoteTreeSnapshot(blobs: [], truncated: false),
        failBlobPathsOnce: {'lib/b.dart'},
      );
      final engine = AtomicDeployEngine(api: api, readEntryBytes: fakeReader);
      final bundle = _makeBundle(['lib/a.dart', 'lib/b.dart', 'lib/c.dart']);

      final firstRun = await engine.deploy(
        token: 'tok',
        target: _makeTarget(),
        bundle: bundle,
        mode: DeployMode.partialUpdate,
        commitMessage: 'retry test',
        cancelToken: CancelToken(),
        isCancelled: () => false,
        onProgress: ({required stage, required percent, required label, required stats}) {},
        onLog: (_) {},
      );

      expect(firstRun.finalStage, DeployStage.partialFailure);
      expect(firstRun.failedFiles.map((f) => f.item.effectivePath), ['lib/b.dart']);
      expect(firstRun.uploadedBlobShas.keys, containsAll(['lib/a.dart', 'lib/c.dart']));
      expect(api.createTreeCalls, 0); // Branch untouched!

      // Retry only failed files using cached blob SHAs
      api.createBlobCalls = 0;
      final retryRun = await engine.deploy(
        token: 'tok',
        target: _makeTarget(),
        bundle: bundle,
        mode: DeployMode.partialUpdate,
        commitMessage: 'retry test',
        existingBlobShas: firstRun.uploadedBlobShas,
        cancelToken: CancelToken(),
        isCancelled: () => false,
        onProgress: ({required stage, required percent, required label, required stats}) {},
        onLog: (_) {},
      );

      expect(retryRun.isSuccess, isTrue);
      expect(retryRun.reusedCount, 2);
      expect(api.createBlobCalls, 1); // Only lib/b.dart was uploaded!
      expect(api.createTreeCalls, 1);
    });

    test('Empty repository automatically bootstraps and completes atomic deploy', () async {
      final api = _FakeGitHubApiClient(
        headRef: null,
        remoteTree: const RemoteTreeSnapshot(blobs: [], truncated: false),
      );
      final engine = AtomicDeployEngine(api: api, readEntryBytes: fakeReader);

      final result = await engine.deploy(
        token: 'tok',
        target: _makeTarget(isEmpty: true),
        bundle: _makeBundle(['README.md', 'lib/app.dart']),
        mode: DeployMode.fullSync,
        commitMessage: 'initial release',
        cancelToken: CancelToken(),
        isCancelled: () => false,
        onProgress: ({required stage, required percent, required label, required stats}) {},
        onLog: (_) {},
      );

      expect(result.isSuccess, isTrue);
      expect(result.usedEmptyRepoFallback, isTrue);
      expect(api.putSingleFileCalls, 1);
      expect(api.createTreeCalls, 1);
      expect(api.lastUpdatedRefSha, 'abcdef1234567890');
    });
  });
}
