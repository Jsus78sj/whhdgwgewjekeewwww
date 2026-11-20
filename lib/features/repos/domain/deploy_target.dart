import 'github_repo.dart';

/// Immutable target selection passed from Phase 2 (Repos & Branches)
/// into Phase 3 (ZIP Explorer) and Phase 4 (Atomic Deploy Engine).
class DeployTarget {
  final GitHubRepo repo;
  final String branchName;
  final bool isEmptyRepo;
  final String? headCommitSha;

  const DeployTarget({
    required this.repo,
    required this.branchName,
    required this.isEmptyRepo,
    this.headCommitSha,
  });

  String get displayTarget => '${repo.fullName}:$branchName';
}
