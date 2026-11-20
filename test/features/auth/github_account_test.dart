import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/features/auth/domain/github_account.dart';

void main() {
  group('SavedAccount', () {
    test('serializes and restores cleanly with masked token', () {
      final account = SavedAccount(
        user: const GitHubUser(
          id: 42,
          login: 'nexus-dev',
          name: 'Nexus Developer',
          avatarUrl: 'https://avatars.githubusercontent.com/u/42',
          publicRepos: 12,
          totalPrivateRepos: 5,
        ),
        token: 'ghp_1234567890abcdef1234567890',
        scopes: const ['repo', 'read:user'],
        isFineGrainedToken: false,
        addedAt: DateTime.utc(2026, 11, 20),
      );

      final roundTrip = SavedAccount.fromJson(account.toJson());
      expect(roundTrip.id, '42');
      expect(roundTrip.user.totalRepos, 17);
      expect(roundTrip.hasRepoScope, isTrue);
      expect(roundTrip.maskedToken, 'ghp_12••••••7890');
    });

    test('recognizes fine-grained PATs without classic x-oauth-scopes', () {
      final fineGrained = SavedAccount(
        user: const GitHubUser(
          id: 99,
          login: 'fg-user',
          name: 'FG User',
          avatarUrl: '',
          publicRepos: 3,
          totalPrivateRepos: 1,
        ),
        token: 'github_pat_11AAABBBCCC',
        scopes: const [],
        isFineGrainedToken: true,
        addedAt: DateTime.utc(2026, 11, 20),
      );

      expect(fineGrained.hasRepoScope, isTrue);
    });
  });
}
