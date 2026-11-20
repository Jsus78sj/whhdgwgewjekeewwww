class GitHubUser {
  final int id;
  final String login;
  final String name;
  final String avatarUrl;
  final int publicRepos;
  final int totalPrivateRepos;
  final String? bio;

  const GitHubUser({
    required this.id,
    required this.login,
    required this.name,
    required this.avatarUrl,
    required this.publicRepos,
    required this.totalPrivateRepos,
    this.bio,
  });

  int get totalRepos => publicRepos + totalPrivateRepos;

  factory GitHubUser.fromJson(Map<String, dynamic> json) {
    final login = (json['login'] as String?) ?? '';
    final rawName = json['name'] as String?;
    return GitHubUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      login: login,
      name: (rawName != null && rawName.trim().isNotEmpty) ? rawName : login,
      avatarUrl: (json['avatar_url'] as String?) ?? '',
      publicRepos: (json['public_repos'] as num?)?.toInt() ?? 0,
      totalPrivateRepos: (json['total_private_repos'] as num?)?.toInt() ??
          (json['owned_private_repos'] as num?)?.toInt() ??
          0,
      bio: json['bio'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'login': login,
        'name': name,
        'avatar_url': avatarUrl,
        'public_repos': publicRepos,
        'total_private_repos': totalPrivateRepos,
        'bio': bio,
      };
}

class SavedAccount {
  final GitHubUser user;
  final String token;
  final List<String> scopes;
  final bool isFineGrainedToken;
  final DateTime addedAt;

  const SavedAccount({
    required this.user,
    required this.token,
    required this.scopes,
    required this.isFineGrainedToken,
    required this.addedAt,
  });

  String get id => user.id.toString();

  bool get hasRepoScope => isFineGrainedToken || scopes.contains('repo');

  String get maskedToken {
    if (token.length <= 10) return '••••••••';
    return '${token.substring(0, 6)}••••••${token.substring(token.length - 4)}';
  }

  SavedAccount copyWith({
    GitHubUser? user,
    String? token,
    List<String>? scopes,
    bool? isFineGrainedToken,
    DateTime? addedAt,
  }) {
    return SavedAccount(
      user: user ?? this.user,
      token: token ?? this.token,
      scopes: scopes ?? this.scopes,
      isFineGrainedToken: isFineGrainedToken ?? this.isFineGrainedToken,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  factory SavedAccount.fromJson(Map<String, dynamic> json) {
    return SavedAccount(
      user: GitHubUser.fromJson(
        Map<String, dynamic>.from(json['user'] as Map),
      ),
      token: (json['token'] as String?) ?? '',
      scopes: List<String>.from((json['scopes'] as List?) ?? const []),
      isFineGrainedToken: (json['isFineGrainedToken'] as bool?) ?? false,
      addedAt: DateTime.tryParse((json['addedAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'user': user.toJson(),
        'token': token,
        'scopes': scopes,
        'isFineGrainedToken': isFineGrainedToken,
        'addedAt': addedAt.toIso8601String(),
      };
}
