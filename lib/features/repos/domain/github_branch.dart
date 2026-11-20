class GitHubBranch {
  final String name;
  final String commitSha;
  final bool isProtected;

  const GitHubBranch({
    required this.name,
    required this.commitSha,
    required this.isProtected,
  });

  String get shortSha =>
      commitSha.length >= 7 ? commitSha.substring(0, 7) : commitSha;

  factory GitHubBranch.fromJson(Map<String, dynamic> json) {
    final commitMap = json['commit'] is Map
        ? Map<String, dynamic>.from(json['commit'] as Map)
        : const <String, dynamic>{};
    return GitHubBranch(
      name: (json['name'] as String?) ?? '',
      commitSha: (commitMap['sha'] as String?) ?? '',
      isProtected: (json['protected'] as bool?) ?? false,
    );
  }
}

/// Validates a GitHub repository name according to GitHub naming rules.
/// Returns an error message in Arabic if invalid, or null when valid.
String? validateRepoName(String raw) {
  final name = raw.trim();
  if (name.isEmpty) {
    return 'اسم المستودع مطلوب.';
  }
  if (name.length > 100) {
    return 'اسم المستودع يجب ألا يتجاوز 100 حرف.';
  }
  if (name == '.' || name == '..') {
    return 'اسم المستودع غير مسموح به.';
  }
  final validPattern = RegExp(r'^[A-Za-z0-9._-]+$');
  if (!validPattern.hasMatch(name)) {
    return 'يُسمح فقط بالحروف الإنجليزية والأرقام والرموز ( . _ - ).';
  }
  return null;
}

/// Validates a Git branch ref name according to `git check-ref-format`.
/// Returns an error message in Arabic if invalid, or null when valid.
String? validateGitBranchName(String raw) {
  final branch = raw.trim();
  if (branch.isEmpty) {
    return 'اسم الفرع مطلوب.';
  }
  if (branch.startsWith('/') ||
      branch.endsWith('/') ||
      branch.startsWith('.') ||
      branch.endsWith('.') ||
      branch.startsWith('-')) {
    return 'لا يمكن أن يبدأ أو ينتهي اسم الفرع بـ ( / ) أو ( . ) أو يبدأ بـ ( - ).';
  }
  if (branch.contains('..') ||
      branch.contains('//') ||
      branch.contains('@{') ||
      branch.endsWith('.lock')) {
    return 'صيغة اسم الفرع غير صالحة في Git (تجنب .. أو // أو @{ أو .lock).';
  }
  final forbiddenChars = RegExp(r'[\s~^:?*\[\]\\]');
  if (forbiddenChars.hasMatch(branch)) {
    return 'يحتوي اسم الفرع على مسافات أو رموز غير مسموحة في Git.';
  }
  return null;
}
