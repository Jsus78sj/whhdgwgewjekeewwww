import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/app.dart';
import 'package:github_nexus/core/storage/secure_account_storage.dart';
import 'package:github_nexus/features/auth/presentation/auth_controller.dart';

class _InMemoryAccountStorage extends SecureAccountStorage {
  StoredAccountsSnapshot _snapshot = const StoredAccountsSnapshot(
    accounts: [],
    activeAccountId: null,
  );

  @override
  Future<StoredAccountsSnapshot> loadSnapshot() async => _snapshot;

  @override
  Future<StoredAccountsSnapshot> setActiveAccount(String? accountId) async {
    _snapshot = StoredAccountsSnapshot(
      accounts: _snapshot.accounts,
      activeAccountId: accountId,
    );
    return _snapshot;
  }
}

void main() {
  testWidgets('GitHubNexusApp renders AuthScreen and validates empty PAT input',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureAccountStorageProvider.overrideWithValue(
            _InMemoryAccountStorage(),
          ),
        ],
        child: const GitHubNexusApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('GitHub Nexus'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Connect to GitHub'), findsOneWidget);

    await tester.tap(find.text('Connect to GitHub'));
    await tester.pump();

    expect(
      find.textContaining('Personal Access Token'),
      findsWidgets,
    );
  });
}
