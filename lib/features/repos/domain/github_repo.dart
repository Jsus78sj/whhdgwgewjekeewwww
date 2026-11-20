enum RepoVisibilityFilter {
  all,
  publicOnly,
  privateOnly,
}

enum RepoSortOption {
  updated,
  name,
  stars,
}

class GitHubRepo {
  final int id;
  final String name;
  final String fullName;
  final String ownerLogin;
  final String description;
  final bool isPrivate;
  final String defaultBranch;
  final int stargazersCount;
  final String? language;
  final int sizeKb;
  final DateTime? updatedAt;
  final String htmlUrl;
  final bool canPush;

  const GitHubRepo({
    required this.id,
    required this.name,
    required this.fullName,
    required this.ownerLogin,
    required this.description,
    required this.isPrivate,
    required this.defaultBranch,
    required this.stargazersCount,
    required this.language,
    required this.sizeKb,
    required this.updatedAt,
    required this.htmlUrl,
    required this.canPush,
  });

  /// Heuristic hint before branches are queried; authoritative check happens
  /// when `/branches` returns an empty list or 409 conflict.
  bool get likelyEmpty => sizeKb == 0;

  factory GitHubRepo.fromJson(Map<String, dynamic> json) {
    final ownerMap = json['owner'] is Map
        ? Map<String, dynamic>.from(json['owner'] as Map)
        : const <String, dynamic>{};
    final permissionsMap = json['permissions'] is Map
        ? Map<String, dynamic>.from(json['permissions'] as Map)
        : const <String, dynamic>{};

    final name = (json['name'] as String?) ?? '';
    final ownerLogin = (ownerMap['login'] as String?) ?? '';
    final fullName = (json['full_name'] as String?) ??
        (ownerLogin.isNotEmpty ? '$ownerLogin/$name' : name);

    final rawDefaultBranch = json['default_branch'] as String?;
    final defaultBranch =
        (rawDefaultBranch != null && rawDefaultBranch.trim().isNotEmpty)
            ? rawDefaultBranch.trim()
            : 'main';

    return GitHubRepo(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: name,
      fullName: fullName,
      ownerLogin: ownerLogin,
      description: (json['description'] as String?)?.trim() ?? '',
      isPrivate: (json['private'] as bool?) ?? false,
      defaultBranch: defaultBranch,
      stargazersCount: (json['stargazers_count'] as num?)?.toInt() ?? 0,
      language: json['language'] as String?,
      sizeKb: (json['size'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.tryParse((json['updated_at'] as String?) ?? '') ??
          DateTime.tryParse((json['pushed_at'] as String?) ?? ''),
      htmlUrl: (json['html_url'] as String?) ?? '',
      canPush: (permissionsMap['push'] as bool?) ?? true,
    );
  }
}
