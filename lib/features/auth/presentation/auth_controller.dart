import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/github_api_client.dart';
import '../../../core/network/github_exceptions.dart';
import '../../../core/network/rate_limit_info.dart';
import '../../../core/storage/secure_account_storage.dart';
import '../domain/github_account.dart';

enum AuthStatus { initializing, unauthenticated, authenticating, authenticated }

class AuthState {
  final AuthStatus status;
  final List<SavedAccount> savedAccounts;
  final SavedAccount? activeAccount;
  final RateLimitInfo? rateLimit;
  final String? errorMessage;

  const AuthState({
    this.status = AuthStatus.initializing,
    this.savedAccounts = const [],
    this.activeAccount,
    this.rateLimit,
    this.errorMessage,
  });

  bool get isBusy =>
      status == AuthStatus.initializing || status == AuthStatus.authenticating;

  AuthState copyWith({
    AuthStatus? status,
    List<SavedAccount>? savedAccounts,
    SavedAccount? activeAccount,
    bool clearActiveAccount = false,
    RateLimitInfo? rateLimit,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      savedAccounts: savedAccounts ?? this.savedAccounts,
      activeAccount:
          clearActiveAccount ? null : (activeAccount ?? this.activeAccount),
      rateLimit: rateLimit ?? this.rateLimit,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final rateLimitProvider = StateProvider<RateLimitInfo?>((ref) => null);

final secureAccountStorageProvider = Provider<SecureAccountStorage>(
  (ref) => SecureAccountStorage(),
);

final githubApiClientProvider = Provider<GitHubApiClient>(
  (ref) => GitHubApiClient(
    onRateLimitUpdated: (info) {
      ref.read(rateLimitProvider.notifier).state = info;
    },
  ),
);

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  final api = ref.watch(githubApiClientProvider);
  final storage = ref.watch(secureAccountStorageProvider);
  return AuthController(api: api, storage: storage, ref: ref);
});

class AuthController extends StateNotifier<AuthState> {
  final GitHubApiClient api;
  final SecureAccountStorage storage;
  final Ref ref;

  AuthController({
    required this.api,
    required this.storage,
    required this.ref,
  }) : super(const AuthState()) {
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final snapshot = await storage.loadSnapshot();
    final active = snapshot.activeAccount;

    if (active == null) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        savedAccounts: snapshot.accounts,
      );
      return;
    }

    // Optimistically show authenticated workspace, then refresh profile silently.
    state = AuthState(
      status: AuthStatus.authenticated,
      savedAccounts: snapshot.accounts,
      activeAccount: active,
      rateLimit: ref.read(rateLimitProvider),
    );

    try {
      final refreshed = await api.authenticate(active.token);
      final updatedAccount = active.copyWith(
        user: refreshed.user,
        scopes: refreshed.scopes,
        isFineGrainedToken: refreshed.isFineGrainedToken,
      );
      final nextSnapshot = await storage.upsertAccount(updatedAccount);
      state = state.copyWith(
        savedAccounts: nextSnapshot.accounts,
        activeAccount: updatedAccount,
        rateLimit: refreshed.rateLimit ?? ref.read(rateLimitProvider),
        clearError: true,
      );
    } on InvalidTokenException {
      // Token revoked remotely: fall back cleanly to login screen without losing other accounts.
      await storage.setActiveAccount(null);
      state = AuthState(
        status: AuthStatus.unauthenticated,
        savedAccounts: snapshot.accounts,
        errorMessage: 'انتهت صلاحية الجلسة السابقة. يرجى تحديث التوكن.',
      );
    } catch (_) {
      // Keep cached session active if offline so the user can inspect UI/settings.
    }
  }

  /// Authenticates with a GitHub PAT, verifies `repo` scope, and saves encrypted.
  Future<bool> connectWithToken(String token) async {
    final previousStatus = state.status;
    state = state.copyWith(
      status: AuthStatus.authenticating,
      clearError: true,
    );

    try {
      final result = await api.authenticate(token);
      final account = SavedAccount(
        user: result.user,
        token: token.trim(),
        scopes: result.scopes,
        isFineGrainedToken: result.isFineGrainedToken,
        addedAt: DateTime.now(),
      );

      final snapshot = await storage.upsertAccount(account, setActive: true);
      state = AuthState(
        status: AuthStatus.authenticated,
        savedAccounts: snapshot.accounts,
        activeAccount: account,
        rateLimit: result.rateLimit ?? ref.read(rateLimitProvider),
      );
      return true;
    } on GitHubException catch (e) {
      state = state.copyWith(
        status: previousStatus == AuthStatus.authenticated
            ? AuthStatus.authenticated
            : AuthStatus.unauthenticated,
        errorMessage: e.message,
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        status: previousStatus == AuthStatus.authenticated
            ? AuthStatus.authenticated
            : AuthStatus.unauthenticated,
        errorMessage: 'حدث خطأ غير متوقع أثناء المصادقة.',
      );
      return false;
    }
  }

  Future<bool> switchAccount(SavedAccount account) async {
    state = state.copyWith(
      status: AuthStatus.authenticating,
      clearError: true,
    );
    try {
      final result = await api.authenticate(account.token);
      final updated = account.copyWith(
        user: result.user,
        scopes: result.scopes,
        isFineGrainedToken: result.isFineGrainedToken,
      );
      final snapshot = await storage.upsertAccount(updated, setActive: true);
      state = AuthState(
        status: AuthStatus.authenticated,
        savedAccounts: snapshot.accounts,
        activeAccount: updated,
        rateLimit: result.rateLimit ?? ref.read(rateLimitProvider),
      );
      return true;
    } on GitHubException catch (e) {
      state = state.copyWith(
        status: state.activeAccount != null
            ? AuthStatus.authenticated
            : AuthStatus.unauthenticated,
        errorMessage: e.message,
      );
      return false;
    }
  }

  Future<void> removeSavedAccount(String accountId) async {
    final snapshot = await storage.removeAccount(accountId);
    final nextActive = snapshot.activeAccount;
    state = AuthState(
      status: nextActive != null
          ? AuthStatus.authenticated
          : AuthStatus.unauthenticated,
      savedAccounts: snapshot.accounts,
      activeAccount: nextActive,
      rateLimit: ref.read(rateLimitProvider),
    );
  }

  /// Signs out from the active session while keeping saved accounts encrypted if desired,
  /// or clears active pointer so the user returns to the PAT login screen.
  Future<void> disconnect() async {
    final snapshot = await storage.setActiveAccount(null);
    state = AuthState(
      status: AuthStatus.unauthenticated,
      savedAccounts: snapshot.accounts,
      activeAccount: null,
    );
  }

  Future<void> refreshActiveProfile() async {
    final active = state.activeAccount;
    if (active == null) return;
    try {
      final result = await api.authenticate(active.token);
      final updated = active.copyWith(
        user: result.user,
        scopes: result.scopes,
        isFineGrainedToken: result.isFineGrainedToken,
      );
      final snapshot = await storage.upsertAccount(updated, setActive: true);
      state = state.copyWith(
        savedAccounts: snapshot.accounts,
        activeAccount: updated,
        rateLimit: result.rateLimit ?? ref.read(rateLimitProvider),
      );
    } on GitHubException catch (e) {
      state = state.copyWith(errorMessage: e.message);
    }
  }
}
