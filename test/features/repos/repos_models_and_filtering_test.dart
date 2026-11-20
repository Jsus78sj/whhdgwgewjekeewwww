import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/features/repos/domain/github_branch.dart';
import 'package:github_nexus/features/repos/domain/github_repo.dart';
import 'package:github_nexus/features/repos/presentation/repos_controller.dart';

void main() {
  final sampleRepos = [
    GitHubRepo.fromJson({
      'id': 1,
      'name': 'nexus-core',
      'full_name': 'abdullah/nexus-core',
      'owner': {'login': 'abdullah'},
      'description': 'Flutter GitHub deployment engine',
      'private': true,
      'default_branch': 'main',
      'stargazers_count': 12,
      'language': 'Dart',
      'size': 250,
      'updated_at': '2026-11-20T10:00:00Z',
    }),
    GitHubRepo.fromJson({
      'id': 2,
      'name': 'alpha-web',
      'full_name': 'abdullah/alpha-web',
      'owner': {'login': 'abdullah'},
      'description': 'Static portfolio site',
      'private': false,
      'default_branch': 'master',
      'stargazers_count': 45,
      'language': 'HTML',
      'size': 0,
      'updated_at': '2026-11-18T10:00:00Z',
    }),
    GitHubRepo.fromJson({
      'id': 3,
      'name': 'civil-toolkit',
      'full_name': 'abdullah/civil-toolkit',
      'owner': {'login': 'abdullah'},
      'description': 'BS8110 structural utilities',
      'private': false,
      'default_branch': 'main',
      'stargazers_count': 8,
      'language': 'Kotlin',
      'size': 120,
      'updated_at': '2026-11-19T10:00:00Z',
    }),
  ];

  group('ReposState filtering and sorting', () {
    test('filters by visibility and instant search query', () {
      final base = ReposState(allRepos: sampleRepos);

      final onlyPrivate =
          base.copyWith(visibilityFilter: RepoVisibilityFilter.privateOnly);
      expect(onlyPrivate.filteredRepos.map((r) => r.name), ['nexus-core']);

      final byLanguage = base.copyWith(searchQuery: 'kotlin');
      expect(byLanguage.filteredRepos.map((r) => r.name), ['civil-toolkit']);

      final publicSortedByStars = base.copyWith(
        visibilityFilter: RepoVisibilityFilter.publicOnly,
        sortOption: RepoSortOption.stars,
      );
      expect(
        publicSortedByStars.filteredRepos.map((r) => r.name),
        ['alpha-web', 'civil-toolkit'],
      );
    });

    test('builds DeployTarget cleanly for empty and non-empty repos', () {
      final emptyState = ReposState(
        allRepos: sampleRepos,
        selectedRepo: sampleRepos[1],
        selectedBranch: 'master',
        isSelectedRepoEmpty: true,
      );
      expect(emptyState.activeTarget?.displayTarget, 'abdullah/alpha-web:master');
      expect(emptyState.activeTarget?.isEmptyRepo, isTrue);
      expect(emptyState.activeTarget?.headCommitSha, isNull);

      final populatedState = ReposState(
        allRepos: sampleRepos,
        selectedRepo: sampleRepos[0],
        branches: const [
          GitHubBranch(
            name: 'main',
            commitSha: '1234567890abcdef',
            isProtected: false,
          ),
        ],
        selectedBranch: 'main',
        isSelectedRepoEmpty: false,
      );
      expect(populatedState.activeTarget?.isEmptyRepo, isFalse);
      expect(populatedState.activeTarget?.headCommitSha, '1234567890abcdef');
    });
  });

  group('Git naming validators', () {
    test('validates repository names', () {
      expect(validateRepoName('my-repo_2.0'), isNull);
      expect(validateRepoName(''), isNotNull);
      expect(validateRepoName('bad repo name'), isNotNull);
      expect(validateRepoName('..'), isNotNull);
    });

    test('validates git branch ref names', () {
      expect(validateGitBranchName('feature/atomic-deploy'), isNull);
      expect(validateGitBranchName('release/v1.2.0'), isNull);
      expect(validateGitBranchName('has space'), isNotNull);
      expect(validateGitBranchName('bad..name'), isNotNull);
      expect(validateGitBranchName('/leading-slash'), isNotNull);
      expect(validateGitBranchName('branch.lock'), isNotNull);
    });
  });
}
