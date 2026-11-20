import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../features/auth/domain/github_account.dart';

class StoredAccountsSnapshot {
  final List<SavedAccount> accounts;
  final String? activeAccountId;

  const StoredAccountsSnapshot({
    required this.accounts,
    required this.activeAccountId,
  });

  SavedAccount? get activeAccount {
    if (activeAccountId == null) return null;
    for (final account in accounts) {
      if (account.id == activeAccountId) return account;
    }
    return null;
  }
}

/// Persists GitHub PATs and account metadata inside Android Keystore
/// via EncryptedSharedPreferences.
class SecureAccountStorage {
  static const String _accountsKey = 'github_nexus_accounts_v1';
  static const String _activeAccountKey = 'github_nexus_active_account_v1';

  final FlutterSecureStorage _storage;

  SecureAccountStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
            );

  Future<StoredAccountsSnapshot> loadSnapshot() async {
    try {
      final rawAccounts = await _storage.read(key: _accountsKey);
      final activeId = await _storage.read(key: _activeAccountKey);

      if (rawAccounts == null || rawAccounts.isEmpty) {
        return const StoredAccountsSnapshot(
          accounts: [],
          activeAccountId: null,
        );
      }

      final decoded = jsonDecode(rawAccounts) as List<dynamic>;
      final accounts = decoded
          .whereType<Map>()
          .map((e) => SavedAccount.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      return StoredAccountsSnapshot(
        accounts: accounts,
        activeAccountId: activeId,
      );
    } catch (_) {
      return const StoredAccountsSnapshot(
        accounts: [],
        activeAccountId: null,
      );
    }
  }

  Future<StoredAccountsSnapshot> upsertAccount(
    SavedAccount account, {
    bool setActive = true,
  }) async {
    final current = await loadSnapshot();
    final updated = List<SavedAccount>.from(current.accounts);
    final idx = updated.indexWhere((a) => a.id == account.id);
    if (idx >= 0) {
      updated[idx] = account;
    } else {
      updated.insert(0, account);
    }

    final nextActiveId = setActive ? account.id : current.activeAccountId;
    await _persist(updated, nextActiveId);
    return StoredAccountsSnapshot(
      accounts: updated,
      activeAccountId: nextActiveId,
    );
  }

  Future<StoredAccountsSnapshot> setActiveAccount(String? accountId) async {
    final current = await loadSnapshot();
    await _persist(current.accounts, accountId);
    return StoredAccountsSnapshot(
      accounts: current.accounts,
      activeAccountId: accountId,
    );
  }

  Future<StoredAccountsSnapshot> removeAccount(String accountId) async {
    final current = await loadSnapshot();
    final updated =
        current.accounts.where((a) => a.id != accountId).toList();
    final nextActive = current.activeAccountId == accountId
        ? (updated.isNotEmpty ? updated.first.id : null)
        : current.activeAccountId;

    await _persist(updated, nextActive);
    return StoredAccountsSnapshot(
      accounts: updated,
      activeAccountId: nextActive,
    );
  }

  Future<void> _persist(
    List<SavedAccount> accounts,
    String? activeAccountId,
  ) async {
    final serialized = jsonEncode(accounts.map((a) => a.toJson()).toList());
    await _storage.write(key: _accountsKey, value: serialized);
    if (activeAccountId == null) {
      await _storage.delete(key: _activeAccountKey);
    } else {
      await _storage.write(key: _activeAccountKey, value: activeAccountId);
    }
  }
}
