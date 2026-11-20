import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/core/network/github_api_client.dart';
import 'package:github_nexus/features/deploy/data/atomic_deploy_engine.dart';
import 'package:github_nexus/features/deploy/domain/deploy_models.dart';
import 'package:github_nexus/features/repos/domain/deploy_target.dart';
import 'package:github_nexus/features/repos/domain/github_repo.dart';
import 'package:github_nexus/features/zip_explorer/data/streaming_zip_inspector.dart';
import 'package:github_nexus/features/zip_explorer/presentation/zip_explorer_controller.dart';

/// Builds a real binary ZIP file on disk mixing Stored (0) and Deflated (8) files.
Uint8List _createBinaryZip(Map<String, ({String content, bool deflate})> files) {
  final localChunks = BytesBuilder();
  final centralChunks = BytesBuilder();
  var count = 0;

  for (final entry in files.entries) {
    final nameBytes = utf8.encode(entry.key);
    final raw = Uint8List.fromList(utf8.encode(entry.value.content));
    final deflate = entry.value.deflate;
    final payload = deflate
        ? Uint8List.fromList(ZLibEncoder(raw: true).convert(raw))
        : raw;
    final method = deflate ? 8 : 0;
    final localOffset = localChunks.length;

    final lh = ByteData(30);
    lh.setUint32(0, 0x04034b50, Endian.little);
    lh.setUint16(4, 20, Endian.little);
    lh.setUint16(6, 0x0800, Endian.little);
    lh.setUint16(8, method, Endian.little);
    lh.setUint32(18, payload.length, Endian.little);
    lh.setUint32(22, raw.length, Endian.little);
    lh.setUint16(26, nameBytes.length, Endian.little);

    localChunks.add(lh.buffer.asUint8List());
    localChunks.add(nameBytes);
    localChunks.add(payload);

    final cd = ByteData(46);
    cd.setUint32(0, 0x02014b50, Endian.little);
    cd.setUint16(4, 20, Endian.little);
    cd.setUint16(6, 20, Endian.little);
    cd.setUint16(8, 0x0800, Endian.little);
    cd.setUint16(10, method, Endian.little);
    cd.setUint32(20, payload.length, Endian.little);
    cd.setUint32(24, raw.length, Endian.little);
    cd.setUint16(28, nameBytes.length, Endian.little);
    cd.setUint32(42, localOffset, Endian.little);

    centralChunks.add(cd.buffer.asUint8List());
    centralChunks.add(nameBytes);
    count++;
  }

  final cdOffset = localChunks.length;
  final cdBytes = centralChunks.toBytes();

  final eocd = ByteData(22);
  eocd.setUint32(0, 0x06054b50, Endian.little);
  eocd.setUint16(8, count, Endian.little);
  eocd.setUint16(10, count, Endian.little);
  eocd.setUint32(12, cdBytes.length, Endian.little);
  eocd.setUint32(16, cdOffset, Endian.little);

  return (BytesBuilder()
        ..add(localChunks.toBytes())
        ..add(cdBytes)
        ..add(eocd.buffer.asUint8List()))
      .toBytes();
}

/// Stateful in-memory GitHub repository mock that records real decoded payloads
/// uploaded via `createBlob` and verifies tree/commit/ref mutations.
class _InMemoryGitHubServer extends GitHubApiClient {
  BranchHeadRef? headRef;
  final Map<String, String> remoteBlobsByPath;
  final Map<String, String> uploadedBlobsBySha = {};
  final Set<String> failContentOnce;
  int commitCounter = 0;
  int putSingleFileCalls = 0;
  int createBlobCalls = 0;
  String? lastTreeBaseSha;
  List<GitTreeItemInput> lastTreeEntries = const [];

  _InMemoryGitHubServer({
    required this.headRef,
    Map<String, String>? initialRemoteFiles,
    Set<String>? failContentOnce,
  })  : remoteBlobsByPath = Map<String, String>.from(initialRemoteFiles ?? {}),
        failContentOnce = Set<String>.from(failContentOnce ?? {});

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
  }) async {
    return RemoteTreeSnapshot(
      blobs: remoteBlobsByPath.entries
          .map(
            (e) => RemoteTreeBlob(
              path: e.key,
              sha: 'remote_${e.key.hashCode.abs()}',
              mode: '100644',
              size: e.value.length,
            ),
          )
          .toList(),
      truncated: false,
    );
  }

  @override
  Future<String> createBlob({
    required String token,
    required String owner,
    required String repo,
    required Uint8List bytes,
    CancelToken? cancelToken,
  }) async {
    createBlobCalls++;
    final decoded = utf8.decode(bytes);
    if (failContentOnce.remove(decoded)) {
      throw DioException(
        requestOptions: RequestOptions(path: '/repos/$owner/$repo/git/blobs'),
        type: DioExceptionType.connectionError,
        message: 'Simulated connection drop',
      );
    }
    final sha = 'sha_${uploadedBlobsBySha.length + 1}_${decoded.hashCode.abs()}';
    uploadedBlobsBySha[sha] = decoded;
    return sha;
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
    lastTreeBaseSha = baseTreeSha;
    lastTreeEntries = entries;

    if (baseTreeSha == null) {
      remoteBlobsByPath.clear();
    }
    for (final item in entries) {
      remoteBlobsByPath[item.path] = uploadedBlobsBySha[item.blobSha] ?? '';
    }
    return 'tree_${++commitCounter}';
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
    final sha = 'commit_sha_000000$commitCounter';
    return CreatedCommitResult(
      sha: sha,
      htmlUrl: 'https://github.com/$owner/$repo/commit/$sha',
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
    headRef = BranchHeadRef(commitSha: commitSha, treeSha: 'tree_$commitCounter');
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
    remoteBlobsByPath[path] = utf8.decode(bytes);
    headRef = const BranchHeadRef(
      commitSha: 'bootstrap_sha_001',
      treeSha: 'bootstrap_tree_001',
    );
    return CreatedCommitResult(
      sha: 'bootstrap_sha_001',
      htmlUrl: 'https://github.com/$owner/$repo/commit/bootstrap_sha_001',
      message: message,
    );
  }
}

DeployTarget _sampleTarget({bool isEmpty = false}) => DeployTarget(
      repo: const GitHubRepo(
        id: 101,
        name: 'nexus-prod',
        fullName: 'abdullah/nexus-prod',
        ownerLogin: 'abdullah',
        description: 'Production release target',
        isPrivate: true,
        defaultBranch: 'main',
        stargazersCount: 5,
        language: 'Dart',
        sizeKb: 42,
        updatedAt: null,
        htmlUrl: 'https://github.com/abdullah/nexus-prod',
        canPush: true,
      ),
      branchName: 'main',
      isEmptyRepo: isEmpty,
      headCommitSha: isEmpty ? null : 'initial_head_sha',
    );

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nexus_e2e_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Phase 5 End-to-End Integration Scenarios', () {
    test('Scenario 1: Real ZIP -> Auto-Strip + Exclusions -> Full Sync atomic mirror', () async {
      final zipFile = File('${tempDir.path}/project_release.zip');
      await zipFile.writeAsBytes(
        _createBinaryZip({
          'project-v2/lib/main.dart': (content: 'void main() {}', deflate: true),
          'project-v2/pubspec.yaml': (content: 'name: app', deflate: false),
          'project-v2/.git/config': (content: '[core]', deflate: false),
          'project-v2/build/app.apk': (content: 'apk-bin', deflate: true),
          'project-v2/node_modules/a/index.js': (content: 'js', deflate: true),
        }),
      );

      final archive = await StreamingZipInspector.inspectFile(zipFile.path);
      final explorerState = ZipExplorerState(
        archive: archive,
        stripRootFolder: true,
      );
      final bundle = explorerState.deployBundle!;
      expect(bundle.isReadyToDeploy, isTrue);
      expect(bundle.selectedFiles.length, 2);
      expect(bundle.excludedCount, 3);

      final server = _InMemoryGitHubServer(
        headRef: const BranchHeadRef(
          commitSha: 'initial_head_sha',
          treeSha: 'initial_tree_sha',
        ),
        initialRemoteFiles: {
          'pubspec.yaml': 'name: old_app',
          'obsolete/legacy.txt': 'delete me',
        },
      );

      final engine = AtomicDeployEngine(api: server);
      final result = await engine.deploy(
        token: 'ghp_test_token',
        target: _sampleTarget(),
        bundle: bundle,
        mode: DeployMode.fullSync,
        commitMessage: 'release: v2.0 full sync',
        cancelToken: CancelToken(),
        isCancelled: () => false,
        onProgress: ({required stage, required percent, required label, required stats}) {},
        onLog: (_) {},
      );

      expect(result.isSuccess, isTrue);
      expect(result.deletedCount, 1);
      expect(server.lastTreeBaseSha, isNull);
      expect(server.remoteBlobsByPath, {
        'lib/main.dart': 'void main() {}',
        'pubspec.yaml': 'name: app',
      });
    });

    test('Scenario 2: Real ZIP -> Partial Update merges cleanly while keeping remote files', () async {
      final zipFile = File('${tempDir.path}/hotfix.zip');
      await zipFile.writeAsBytes(
        _createBinaryZip({
          'lib/hotfix.dart': (content: 'const fixed = true;', deflate: true),
        }),
      );

      final archive = await StreamingZipInspector.inspectFile(zipFile.path);
      final bundle = ZipExplorerState(archive: archive, stripRootFolder: false).deployBundle!;

      final server = _InMemoryGitHubServer(
        headRef: const BranchHeadRef(
          commitSha: 'head_v1',
          treeSha: 'tree_v1',
        ),
        initialRemoteFiles: {
          'README.md': '# Existing Docs',
          'lib/main.dart': 'void main() {}',
        },
      );

      final engine = AtomicDeployEngine(api: server);
      final result = await engine.deploy(
        token: 'ghp_test_token',
        target: _sampleTarget(),
        bundle: bundle,
        mode: DeployMode.partialUpdate,
        commitMessage: 'fix: hotfix',
        cancelToken: CancelToken(),
        isCancelled: () => false,
        onProgress: ({required stage, required percent, required label, required stats}) {},
        onLog: (_) {},
      );

      expect(result.isSuccess, isTrue);
      expect(result.deletedCount, 0);
      expect(server.lastTreeBaseSha, 'tree_v1');
      expect(
        server.remoteBlobsByPath.keys,
        containsAll(['README.md', 'lib/main.dart', 'lib/hotfix.dart']),
      );
      expect(server.remoteBlobsByPath['lib/hotfix.dart'], 'const fixed = true;');
    });

    test('Scenario 3: Empty repository bootstraps automatically and finishes atomic commit', () async {
      final zipFile = File('${tempDir.path}/fresh_repo.zip');
      await zipFile.writeAsBytes(
        _createBinaryZip({
          'README.md': (content: '# Fresh Project', deflate: false),
          'src/index.dart': (content: 'final version = 1;', deflate: true),
        }),
      );

      final archive = await StreamingZipInspector.inspectFile(zipFile.path);
      final bundle = ZipExplorerState(archive: archive, stripRootFolder: false).deployBundle!;

      final server = _InMemoryGitHubServer(headRef: null);
      final engine = AtomicDeployEngine(api: server);

      final result = await engine.deploy(
        token: 'ghp_test_token',
        target: _sampleTarget(isEmpty: true),
        bundle: bundle,
        mode: DeployMode.fullSync,
        commitMessage: 'chore: initial commit',
        cancelToken: CancelToken(),
        isCancelled: () => false,
        onProgress: ({required stage, required percent, required label, required stats}) {},
        onLog: (_) {},
      );

      expect(result.isSuccess, isTrue);
      expect(result.usedEmptyRepoFallback, isTrue);
      expect(server.putSingleFileCalls, 1);
      expect(server.remoteBlobsByPath, {
        'README.md': '# Fresh Project',
        'src/index.dart': 'final version = 1;',
      });
    });

    test('Scenario 4: Network drop mid-upload keeps branch intact and selective retry recovers', () async {
      final zipFile = File('${tempDir.path}/resilient.zip');
      await zipFile.writeAsBytes(
        _createBinaryZip({
          'a.txt': (content: 'FILE_A', deflate: true),
          'b.txt': (content: 'FILE_B_DROPS_ONCE', deflate: true),
          'c.txt': (content: 'FILE_C', deflate: false),
        }),
      );

      final archive = await StreamingZipInspector.inspectFile(zipFile.path);
      final bundle = ZipExplorerState(archive: archive, stripRootFolder: false).deployBundle!;

      final server = _InMemoryGitHubServer(
        headRef: const BranchHeadRef(commitSha: 'stable_sha', treeSha: 'stable_tree'),
        initialRemoteFiles: {'existing.txt': 'untouched'},
        failContentOnce: {'FILE_B_DROPS_ONCE'},
      );
      final engine = AtomicDeployEngine(api: server);

      final first = await engine.deploy(
        token: 'ghp_test_token',
        target: _sampleTarget(),
        bundle: bundle,
        mode: DeployMode.partialUpdate,
        commitMessage: 'feat: resilient deploy',
        cancelToken: CancelToken(),
        isCancelled: () => false,
        onProgress: ({required stage, required percent, required label, required stats}) {},
        onLog: (_) {},
      );

      expect(first.finalStage, DeployStage.partialFailure);
      expect(first.failedFiles.length, 1);
      expect(first.failedFiles.first.item.effectivePath, 'b.txt');
      expect(server.headRef?.commitSha, 'stable_sha');

      server.createBlobCalls = 0;
      final second = await engine.deploy(
        token: 'ghp_test_token',
        target: _sampleTarget(),
        bundle: bundle,
        mode: DeployMode.partialUpdate,
        commitMessage: 'feat: resilient deploy',
        existingBlobShas: first.uploadedBlobShas,
        cancelToken: CancelToken(),
        isCancelled: () => false,
        onProgress: ({required stage, required percent, required label, required stats}) {},
        onLog: (_) {},
      );

      expect(second.isSuccess, isTrue);
      expect(second.reusedCount, 2);
      expect(server.createBlobCalls, 1);
      expect(server.remoteBlobsByPath['b.txt'], 'FILE_B_DROPS_ONCE');
      expect(server.remoteBlobsByPath['existing.txt'], 'untouched');
    });
  });
}
