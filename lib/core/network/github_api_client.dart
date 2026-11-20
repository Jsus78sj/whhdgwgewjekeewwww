import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../features/auth/domain/github_account.dart';
import '../../features/repos/domain/github_branch.dart';
import '../../features/repos/domain/github_repo.dart';
import 'github_exceptions.dart';
import 'rate_limit_info.dart';

class AuthenticatedUserResult {
  final GitHubUser user;
  final List<String> scopes;
  final bool isFineGrainedToken;
  final RateLimitInfo? rateLimit;

  const AuthenticatedUserResult({
    required this.user,
    required this.scopes,
    required this.isFineGrainedToken,
    required this.rateLimit,
  });

  bool get hasRepoScope =>
      isFineGrainedToken || scopes.contains('repo');
}

class BranchHeadRef {
  final String commitSha;
  final String treeSha;

  const BranchHeadRef({
    required this.commitSha,
    required this.treeSha,
  });
}

class RemoteTreeBlob {
  final String path;
  final String sha;
  final String mode;
  final int size;

  const RemoteTreeBlob({
    required this.path,
    required this.sha,
    required this.mode,
    required this.size,
  });
}

class RemoteTreeSnapshot {
  final List<RemoteTreeBlob> blobs;
  final bool truncated;

  const RemoteTreeSnapshot({
    required this.blobs,
    required this.truncated,
  });
}

class GitTreeItemInput {
  final String path;
  final String blobSha;
  final String mode;

  const GitTreeItemInput({
    required this.path,
    required this.blobSha,
    this.mode = '100644',
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'mode': mode,
        'type': 'blob',
        'sha': blobSha,
      };
}

class CreatedCommitResult {
  final String sha;
  final String htmlUrl;
  final String message;

  const CreatedCommitResult({
    required this.sha,
    required this.htmlUrl,
    required this.message,
  });
}

/// Core GitHub REST & Git Data API client with:
/// - Exponential backoff retry for transient 5xx / timeout / secondary rate limits
/// - Automatic rate-limit header tracking
/// - Standardized GitHub API version headers
class GitHubApiClient {
  static const String baseUrl = 'https://api.github.com';
  static const String apiVersion = '2022-11-28';

  final Dio _dio;
  final void Function(RateLimitInfo info)? onRateLimitUpdated;

  GitHubApiClient({
    Dio? dio,
    this.onRateLimitUpdated,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 25),
                receiveTimeout: const Duration(seconds: 60),
                sendTimeout: const Duration(seconds: 60),
                headers: const {
                  'Accept': 'application/vnd.github+json',
                  'X-GitHub-Api-Version': apiVersion,
                  'User-Agent': 'GitHub-Nexus-Android/1.0',
                },
                validateStatus: (status) =>
                    status != null && status < 500 && status != 429,
              ),
            ) {
    _dio.interceptors.add(_RateLimitTrackingInterceptor(onRateLimitUpdated));
    _dio.interceptors.add(_ExponentialBackoffRetryInterceptor(_dio, maxRetries: 3));
  }

  Options _authOptions(String token) => Options(
        headers: {'Authorization': 'Bearer $token'},
      );

  String _encodeBranchPath(String branchName) =>
      branchName.trim().split('/').map(Uri.encodeComponent).join('/');

  String _encodeFilePath(String path) =>
      path.split('/').map(Uri.encodeComponent).join('/');

  // ---------------------------------------------------------------------------
  // Phase 1: Auth
  // ---------------------------------------------------------------------------

  Future<AuthenticatedUserResult> authenticate(
    String rawToken, {
    bool enforceRepoScope = true,
  }) async {
    final token = rawToken.trim();
    if (token.isEmpty) {
      throw const InvalidTokenException('يرجى إدخال Personal Access Token أولاً.');
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/user',
        options: _authOptions(token),
      );

      final status = response.statusCode ?? 0;
      _throwIfErrorStatus(response);

      if (response.data == null) {
        throw GitHubApiException(
          'فشل التحقق من الحساب (استجابة فارغة: $status).',
          statusCode: status,
        );
      }

      final scopesHeader = response.headers.value('x-oauth-scopes') ?? '';
      final scopes = scopesHeader
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final isFineGrained = token.startsWith('github_pat_');
      final hasRepo = isFineGrained || scopes.contains('repo');

      if (enforceRepoScope && !hasRepo) {
        throw InsufficientScopeException(grantedScopes: scopes);
      }

      final rateLimit = RateLimitInfo.fromHeaders(response.headers.map);
      if (rateLimit != null) {
        onRateLimitUpdated?.call(rateLimit);
      }

      return AuthenticatedUserResult(
        user: GitHubUser.fromJson(response.data!),
        scopes: scopes,
        isFineGrainedToken: isFineGrained,
        rateLimit: rateLimit,
      );
    } on GitHubException {
      rethrow;
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  // ---------------------------------------------------------------------------
  // Phase 2: Repositories & Branches
  // ---------------------------------------------------------------------------

  Future<List<GitHubRepo>> fetchUserRepositories(
    String token, {
    int maxPages = 10,
  }) async {
    final allRepos = <GitHubRepo>[];
    try {
      for (var page = 1; page <= maxPages; page++) {
        final response = await _dio.get<List<dynamic>>(
          '/user/repos',
          queryParameters: {
            'per_page': 100,
            'page': page,
            'sort': 'updated',
            'direction': 'desc',
            'affiliation': 'owner,collaborator,organization_member',
          },
          options: _authOptions(token),
        );

        _throwIfErrorStatus(response);

        final data = response.data ?? const <dynamic>[];
        if (data.isEmpty) break;

        for (final item in data) {
          if (item is Map) {
            allRepos.add(
              GitHubRepo.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        }

        if (data.length < 100) break;
      }

      return allRepos;
    } on GitHubException {
      rethrow;
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  Future<GitHubRepo> createRepository({
    required String token,
    required String name,
    String description = '',
    bool isPrivate = false,
    bool autoInit = false,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/user/repos',
        data: {
          'name': name.trim(),
          if (description.trim().isNotEmpty) 'description': description.trim(),
          'private': isPrivate,
          'auto_init': autoInit,
        },
        options: _authOptions(token),
      );

      final status = response.statusCode ?? 0;
      if (status == 422) {
        final detail = _extractValidationDetail(response.data);
        throw GitHubApiException(
          detail ?? 'اسم المستودع مستخدم بالفعل أو غير صالح.',
          statusCode: 422,
        );
      }

      _throwIfErrorStatus(response);

      if (response.data == null) {
        throw const GitHubApiException('تم إنشاء المستودع لكن الاستجابة فارغة.');
      }
      return GitHubRepo.fromJson(response.data!);
    } on GitHubException {
      rethrow;
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  Future<List<GitHubBranch>> fetchBranches({
    required String token,
    required String owner,
    required String repo,
    int maxPages = 5,
  }) async {
    final branches = <GitHubBranch>[];
    try {
      for (var page = 1; page <= maxPages; page++) {
        final response = await _dio.get<dynamic>(
          '/repos/$owner/$repo/branches',
          queryParameters: {
            'per_page': 100,
            'page': page,
          },
          options: _authOptions(token),
        );

        if (response.statusCode == 409) {
          return const <GitHubBranch>[];
        }

        _throwIfErrorStatus(response);

        final data = response.data;
        if (data is! List || data.isEmpty) break;

        for (final item in data) {
          if (item is Map) {
            branches.add(
              GitHubBranch.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        }

        if (data.length < 100) break;
      }

      return branches;
    } on GitHubException {
      rethrow;
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  Future<GitHubBranch> createBranch({
    required String token,
    required String owner,
    required String repo,
    required String newBranchName,
    required String baseBranchName,
  }) async {
    final cleanNew = newBranchName.trim();
    final cleanBase = baseBranchName.trim();

    try {
      final encodedBase = _encodeBranchPath(cleanBase);
      final baseRefRes = await _dio.get<Map<String, dynamic>>(
        '/repos/$owner/$repo/git/ref/heads/$encodedBase',
        options: _authOptions(token),
      );

      if (baseRefRes.statusCode == 409) {
        throw const GitHubApiException(
          'المستودع فارغ ولا يحتوي على أي Commit بعد. قم بتهيئته بملف README أولاً.',
          statusCode: 409,
        );
      }

      _throwIfErrorStatus(baseRefRes);

      final objectMap = baseRefRes.data?['object'];
      final baseSha = objectMap is Map ? objectMap['sha'] as String? : null;
      if (baseSha == null || baseSha.isEmpty) {
        throw const GitHubApiException(
          'تعذر قراءة SHA الخاص بالفرع الأساسي.',
        );
      }

      final createRes = await _dio.post<Map<String, dynamic>>(
        '/repos/$owner/$repo/git/refs',
        data: {
          'ref': 'refs/heads/$cleanNew',
          'sha': baseSha,
        },
        options: _authOptions(token),
      );

      if (createRes.statusCode == 422) {
        final detail = _extractValidationDetail(createRes.data);
        throw GitHubApiException(
          detail ?? 'اسم الفرع موجود بالفعل أو غير صالح.',
          statusCode: 422,
        );
      }

      _throwIfErrorStatus(createRes);

      return GitHubBranch(
        name: cleanNew,
        commitSha: baseSha,
        isProtected: false,
      );
    } on GitHubException {
      rethrow;
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  Future<void> initializeEmptyRepository({
    required String token,
    required String owner,
    required String repo,
    required String branchName,
  }) async {
    await putSingleFileContent(
      token: token,
      owner: owner,
      repo: repo,
      path: 'README.md',
      bytes: Uint8List.fromList(
        utf8.encode('# $repo\n\nInitialized with GitHub Nexus.\n'),
      ),
      message: 'chore: initialize repository with README.md',
      branchName: branchName,
    );
  }

  // ---------------------------------------------------------------------------
  // Phase 4: Git Data API (Atomic Single-Commit Deploy Engine)
  // ---------------------------------------------------------------------------

  /// Resolves the current HEAD commit SHA and root tree SHA for [branchName].
  /// Returns `null` if the repository is completely empty (409) or branch does not exist yet (404).
  Future<BranchHeadRef?> fetchBranchHead({
    required String token,
    required String owner,
    required String repo,
    required String branchName,
    CancelToken? cancelToken,
  }) async {
    try {
      final encoded = _encodeBranchPath(branchName);
      final refRes = await _dio.get<Map<String, dynamic>>(
        '/repos/$owner/$repo/git/ref/heads/$encoded',
        options: _authOptions(token),
        cancelToken: cancelToken,
      );

      if (refRes.statusCode == 409 || refRes.statusCode == 404) {
        return null;
      }
      _throwIfErrorStatus(refRes);

      final objectMap = refRes.data?['object'];
      final commitSha = objectMap is Map ? objectMap['sha'] as String? : null;
      if (commitSha == null || commitSha.isEmpty) return null;

      final commitRes = await _dio.get<Map<String, dynamic>>(
        '/repos/$owner/$repo/git/commits/$commitSha',
        options: _authOptions(token),
        cancelToken: cancelToken,
      );
      _throwIfErrorStatus(commitRes);

      final treeMap = commitRes.data?['tree'];
      final treeSha = treeMap is Map ? treeMap['sha'] as String? : null;
      if (treeSha == null || treeSha.isEmpty) {
        throw const GitHubApiException('تعذر قراءة Tree SHA للـ Commit الحالي.');
      }

      return BranchHeadRef(commitSha: commitSha, treeSha: treeSha);
    } on GitHubException {
      rethrow;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw _mapDioException(e);
    }
  }

  /// Fetches the entire recursive file tree snapshot for diff preview & sync analysis.
  Future<RemoteTreeSnapshot> fetchRecursiveTree({
    required String token,
    required String owner,
    required String repo,
    required String treeSha,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/repos/$owner/$repo/git/trees/$treeSha',
        queryParameters: const {'recursive': 1},
        options: _authOptions(token),
        cancelToken: cancelToken,
      );

      if (response.statusCode == 409 || response.statusCode == 404) {
        return const RemoteTreeSnapshot(blobs: [], truncated: false);
      }
      _throwIfErrorStatus(response);

      final rawTree = response.data?['tree'];
      final truncated = (response.data?['truncated'] as bool?) ?? false;
      final blobs = <RemoteTreeBlob>[];

      if (rawTree is List) {
        for (final item in rawTree) {
          if (item is Map && item['type'] == 'blob') {
            blobs.add(
              RemoteTreeBlob(
                path: (item['path'] as String?) ?? '',
                sha: (item['sha'] as String?) ?? '',
                mode: (item['mode'] as String?) ?? '100644',
                size: (item['size'] as num?)?.toInt() ?? 0,
              ),
            );
          }
        }
      }

      return RemoteTreeSnapshot(blobs: blobs, truncated: truncated);
    } on GitHubException {
      rethrow;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw _mapDioException(e);
    }
  }

  /// Uploads raw file bytes as a Git Blob object and returns its SHA-1.
  Future<String> createBlob({
    required String token,
    required String owner,
    required String repo,
    required Uint8List bytes,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/repos/$owner/$repo/git/blobs',
        data: {
          'content': base64Encode(bytes),
          'encoding': 'base64',
        },
        options: _authOptions(token),
        cancelToken: cancelToken,
      );

      _throwIfErrorStatus(response);
      final sha = response.data?['sha'] as String?;
      if (sha == null || sha.isEmpty) {
        throw const GitHubApiException('استجابة GitHub لم تحتوِ على Blob SHA.');
      }
      return sha;
    } on GitHubException {
      rethrow;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw _mapDioException(e);
    }
  }

  /// Creates a Git Tree object.
  /// - Omit [baseTreeSha] for **Full Sync** (atomically drops any remote files not in [entries]).
  /// - Pass [baseTreeSha] for **Partial Update** (merges [entries] over the existing tree).
  Future<String> createTree({
    required String token,
    required String owner,
    required String repo,
    required List<GitTreeItemInput> entries,
    String? baseTreeSha,
    CancelToken? cancelToken,
  }) async {
    try {
      final payload = <String, dynamic>{
        'tree': entries.map((e) => e.toJson()).toList(),
        if (baseTreeSha != null && baseTreeSha.isNotEmpty)
          'base_tree': baseTreeSha,
      };

      final response = await _dio.post<Map<String, dynamic>>(
        '/repos/$owner/$repo/git/trees',
        data: payload,
        options: _authOptions(token),
        cancelToken: cancelToken,
      );

      _throwIfErrorStatus(response);
      final sha = response.data?['sha'] as String?;
      if (sha == null || sha.isEmpty) {
        throw const GitHubApiException('فشل إنشاء شجرة الملفات (Tree SHA مفقود).');
      }
      return sha;
    } on GitHubException {
      rethrow;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw _mapDioException(e);
    }
  }

  /// Creates a single atomic Git Commit pointing to [treeSha].
  Future<CreatedCommitResult> createCommit({
    required String token,
    required String owner,
    required String repo,
    required String message,
    required String treeSha,
    required List<String> parentShas,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/repos/$owner/$repo/git/commits',
        data: {
          'message': message.trim(),
          'tree': treeSha,
          'parents': parentShas,
        },
        options: _authOptions(token),
        cancelToken: cancelToken,
      );

      _throwIfErrorStatus(response);
      final sha = response.data?['sha'] as String?;
      if (sha == null || sha.isEmpty) {
        throw const GitHubApiException('فشل إنشاء الـ Commit (SHA مفقود).');
      }
      final htmlUrl = (response.data?['html_url'] as String?) ??
          'https://github.com/$owner/$repo/commit/$sha';

      return CreatedCommitResult(
        sha: sha,
        htmlUrl: htmlUrl,
        message: message.trim(),
      );
    } on GitHubException {
      rethrow;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw _mapDioException(e);
    }
  }

  /// Updates the branch reference pointer atomically to [commitSha].
  Future<void> updateBranchRef({
    required String token,
    required String owner,
    required String repo,
    required String branchName,
    required String commitSha,
    bool force = false,
    CancelToken? cancelToken,
  }) async {
    try {
      final encoded = _encodeBranchPath(branchName);
      final response = await _dio.patch<Map<String, dynamic>>(
        '/repos/$owner/$repo/git/refs/heads/$encoded',
        data: {
          'sha': commitSha,
          'force': force,
        },
        options: _authOptions(token),
        cancelToken: cancelToken,
      );

      _throwIfErrorStatus(response);
    } on GitHubException {
      rethrow;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw _mapDioException(e);
    }
  }

  /// Fallback endpoint for bootstrapping completely empty repositories
  /// (where Git Data API rejects blob creation with 409 until 1 commit exists).
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
    try {
      final encodedPath = _encodeFilePath(path);
      final response = await _dio.put<Map<String, dynamic>>(
        '/repos/$owner/$repo/contents/$encodedPath',
        data: {
          'message': message.trim(),
          'content': base64Encode(bytes),
          'branch': branchName,
        },
        options: _authOptions(token),
        cancelToken: cancelToken,
      );

      _throwIfErrorStatus(response);
      final commitMap = response.data?['commit'];
      final sha = commitMap is Map ? (commitMap['sha'] as String?) ?? '' : '';
      final htmlUrl = commitMap is Map
          ? (commitMap['html_url'] as String?) ??
              'https://github.com/$owner/$repo/commit/$sha'
          : 'https://github.com/$owner/$repo';

      return CreatedCommitResult(
        sha: sha,
        htmlUrl: htmlUrl,
        message: message.trim(),
      );
    } on GitHubException {
      rethrow;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw _mapDioException(e);
    }
  }

  Dio get rawClient => _dio;

  Options authorizedOptions(String token) => _authOptions(token);

  void _throwIfErrorStatus(Response<dynamic> response) {
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) return;

    if (status == 401) {
      throw const InvalidTokenException();
    }
    if (status == 403 || status == 429) {
      throw _parseForbiddenError(response);
    }
    if (status == 404) {
      throw GitHubApiException(
        _extractApiMessage(response.data) ??
            'العنصر المطلوب غير موجود أو لا تملك صلاحية الوصول إليه.',
        statusCode: 404,
      );
    }
    if (status == 409) {
      throw GitHubApiException(
        _extractApiMessage(response.data) ??
            'تعارض في حالة المستودع (409).',
        statusCode: 409,
      );
    }
    throw GitHubApiException(
      _extractApiMessage(response.data) ??
          'فشل الطلب من GitHub API (رمز الحالة: $status).',
      statusCode: status,
    );
  }

  GitHubException _parseForbiddenError(Response<dynamic> response) {
    final rateLimit = RateLimitInfo.fromHeaders(response.headers.map);
    final apiMsg = _extractApiMessage(response.data)?.toLowerCase() ?? '';
    if ((rateLimit != null && rateLimit.isExhausted) ||
        apiMsg.contains('rate limit')) {
      return RateLimitException(resetAt: rateLimit?.resetAt);
    }
    return GitHubApiException(
      _extractApiMessage(response.data) ?? 'لا تملك صلاحية كافية لتنفيذ هذا الطلب.',
      statusCode: response.statusCode,
    );
  }

  GitHubException _mapDioException(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.connectionError) {
      return const NetworkConnectionException();
    }
    final status = e.response?.statusCode;
    if (status == 401) {
      return const InvalidTokenException();
    }
    if (status == 403 || status == 429) {
      if (e.response != null) {
        return _parseForbiddenError(e.response!);
      }
      return const RateLimitException();
    }
    return GitHubApiException(
      _extractApiMessage(e.response?.data) ??
          'حدث خطأ غير متوقع في الاتصال بـ GitHub.',
      statusCode: status,
    );
  }

  String? _extractApiMessage(dynamic data) {
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    return null;
  }

  String? _extractValidationDetail(dynamic data) {
    if (data is! Map) return null;
    final errors = data['errors'];
    if (errors is List && errors.isNotEmpty) {
      final first = errors.first;
      if (first is Map && first['message'] is String) {
        return first['message'] as String;
      }
    }
    return _extractApiMessage(data);
  }
}

class _RateLimitTrackingInterceptor extends Interceptor {
  final void Function(RateLimitInfo info)? onUpdated;

  _RateLimitTrackingInterceptor(this.onUpdated);

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final info = RateLimitInfo.fromHeaders(response.headers.map);
    if (info != null) {
      onUpdated?.call(info);
    }
    super.onResponse(response, handler);
  }
}

class _ExponentialBackoffRetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;

  _ExponentialBackoffRetryInterceptor(this.dio, {this.maxRetries = 3});

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (CancelToken.isCancel(err)) {
      return handler.next(err);
    }

    final attempt = (err.requestOptions.extra['retry_attempt'] as int?) ?? 0;
    final shouldRetry = attempt < maxRetries && _isRetryable(err);

    if (!shouldRetry) {
      return handler.next(err);
    }

    final retryAfterHeader = err.response?.headers.value('retry-after');
    final retryAfterSec = int.tryParse(retryAfterHeader ?? '');
    final delayMs = retryAfterSec != null
        ? retryAfterSec * 1000
        : (math.pow(2, attempt) * 600).toInt();

    await Future<void>.delayed(Duration(milliseconds: delayMs));

    final nextOptions = err.requestOptions;
    nextOptions.extra['retry_attempt'] = attempt + 1;

    try {
      final response = await dio.fetch<dynamic>(nextOptions);
      return handler.resolve(response);
    } on DioException catch (retryErr) {
      return handler.next(retryErr);
    }
  }

  bool _isRetryable(DioException err) {
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.connectionError) {
      return true;
    }
    final status = err.response?.statusCode;
    return status == 429 || (status != null && status >= 500);
  }
}
