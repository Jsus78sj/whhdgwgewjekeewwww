import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/github_api_client.dart';
import '../../../core/network/github_exceptions.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/deploy_target.dart';
import '../domain/github_branch.dart';
import '../domain/github_repo.dart';

class ReposState {
  final bool isLoadingRepos;
  final bool isLoadingBranches;
  final bool isCreatingRepo;
  final bool isCreatingBranch;
  final bool isInitializingEmptyRepo;
  final List<GitHubRepo> allRepos;
  final String searchQuery;
  final RepoVisibilityFilter visibilityFilter;
  final RepoSortOption sortOption;
  final GitHubRepo? selectedRepo;
  final List<GitHubBranch> branches;
  final String? selectedBranch;
  final bool isSelectedRepoEmpty;
  final String? errorMessage;
  final String? branchErrorMessage;

  const ReposState({
    this.isLoadingRepos = false,
    this.isLoadingBranches = false,
    this.isCreatingRepo = false,
    this.isCreatingBranch = false,
    this.isInitializingEmptyRepo = false,
    this.allRepos = const [],
    this.searchQuery = '',
    this.visibilityFilter = RepoVisibilityFilter.all,
    this.sortOption = RepoSortOption.updated,
    this.selectedRepo,
    this.branches = const [],
    this.selectedBranch,
    this.isSelectedRepoEmpty = false,
    this.errorMessage,
    this.branchErrorMessage,
  });

  List<GitHubRepo> get filteredRepos {
    final query = searchQuery.trim().toLowerCase();
    final filtered = allRepos.where((repo) {
      final matchesVisibility = switch (visibilityFilter) {
        RepoVisibilityFilter.all => true,
        RepoVisibilityFilter.publicOnly => !repo.isPrivate,
        RepoVisibilityFilter.privateOnly => repo.isPrivate,
      };
      if (!matchesVisibility) return false;
      if (query.isEmpty) return true;
      return repo.name.toLowerCase().contains(query) ||
          repo.fullName.toLowerCase().contains(query) ||
          repo.description.toLowerCase().contains(query) ||
          (repo.language?.toLowerCase().contains(query) ?? false);
    }).toList();

    switch (sortOption) {
      case RepoSortOption.updated:
        filtered.sort((a, b) {
          final da = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });
      case RepoSortOption.name:
        filtered.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case RepoSortOption.stars:
        filtered.sort((a, b) {
          final cmp = b.stargazersCount.compareTo(a.stargazersCount);
          if (cmp != 0) return cmp;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
    }

    return filtered;
  }

  /// Returns the ready-to-use deployment target for Phases 3 & 4.
  DeployTarget? get activeTarget {
    final repo = selectedRepo;
    final branch = selectedBranch;
    if (repo == null || branch == null || branch.isEmpty) return null;

    String? sha;
    for (final b in branches) {
      if (b.name == branch) {
        sha = b.commitSha;
        break;
      }
    }

    return DeployTarget(
      repo: repo,
      branchName: branch,
      isEmptyRepo: isSelectedRepoEmpty,
      headCommitSha: sha,
    );
  }

  ReposState copyWith({
    bool? isLoadingRepos,
    bool? isLoadingBranches,
    bool? isCreatingRepo,
    bool? isCreatingBranch,
    bool? isInitializingEmptyRepo,
    List<GitHubRepo>? allRepos,
    String? searchQuery,
    RepoVisibilityFilter? visibilityFilter,
    RepoSortOption? sortOption,
    GitHubRepo? selectedRepo,
    bool clearSelectedRepo = false,
    List<GitHubBranch>? branches,
    String? selectedBranch,
    bool clearSelectedBranch = false,
    bool? isSelectedRepoEmpty,
    String? errorMessage,
    bool clearError = false,
    String? branchErrorMessage,
    bool clearBranchError = false,
  }) {
    return ReposState(
      isLoadingRepos: isLoadingRepos ?? this.isLoadingRepos,
      isLoadingBranches: isLoadingBranches ?? this.isLoadingBranches,
      isCreatingRepo: isCreatingRepo ?? this.isCreatingRepo,
      isCreatingBranch: isCreatingBranch ?? this.isCreatingBranch,
      isInitializingEmptyRepo:
          isInitializingEmptyRepo ?? this.isInitializingEmptyRepo,
      allRepos: allRepos ?? this.allRepos,
      searchQuery: searchQuery ?? this.searchQuery,
      visibilityFilter: visibilityFilter ?? this.visibilityFilter,
      sortOption: sortOption ?? this.sortOption,
      selectedRepo:
          clearSelectedRepo ? null : (selectedRepo ?? this.selectedRepo),
      branches: branches ?? this.branches,
      selectedBranch:
          clearSelectedBranch ? null : (selectedBranch ?? this.selectedBranch),
      isSelectedRepoEmpty: isSelectedRepoEmpty ?? this.isSelectedRepoEmpty,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      branchErrorMessage: clearBranchError
          ? null
          : (branchErrorMessage ?? this.branchErrorMessage),
    );
  }
}

final reposControllerProvider =
    StateNotifierProvider<ReposController, ReposState>((ref) {
  final api = ref.watch(githubApiClientProvider);
  final activeAccount = ref.watch(
    authControllerProvider.select((s) => s.activeAccount),
  );
  return ReposController(
    api: api,
    token: activeAccount?.token,
  );
});

class ReposController extends StateNotifier<ReposState> {
  final GitHubApiClient api;
  final String? token;

  ReposController({
    required this.api,
    required this.token,
  }) : super(const ReposState()) {
    if (token != null && token!.isNotEmpty) {
      loadRepositories();
    }
  }

  Future<void> loadRepositories({bool silent = false}) async {
    final activeToken = token;
    if (activeToken == null || activeToken.isEmpty) return;

    if (!silent) {
      state = state.copyWith(isLoadingRepos: true, clearError: true);
    }

    try {
      final repos = await api.fetchUserRepositories(activeToken);

      // Keep selected repo reference fresh if it still exists in the list.
      GitHubRepo? refreshedSelected = state.selectedRepo;
      if (refreshedSelected != null) {
        final match = repos.where((r) => r.id == refreshedSelected!.id);
        refreshedSelected = match.isNotEmpty ? match.first : null;
      }

      state = state.copyWith(
        isLoadingRepos: false,
        allRepos: repos,
        selectedRepo: refreshedSelected,
        clearSelectedRepo: refreshedSelected == null,
        clearSelectedBranch: refreshedSelected == null,
        branches: refreshedSelected == null ? const [] : state.branches,
        isSelectedRepoEmpty:
            refreshedSelected == null ? false : state.isSelectedRepoEmpty,
        clearError: true,
      );
    } on GitHubException catch (e) {
      state = state.copyWith(
        isLoadingRepos: false,
        errorMessage: e.message,
      );
    } catch (_) {
      state = state.copyWith(
        isLoadingRepos: false,
        errorMessage: 'تعذر تحميل قائمة المستودعات. حاول مجدداً.',
      );
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setVisibilityFilter(RepoVisibilityFilter filter) {
    state = state.copyWith(visibilityFilter: filter);
  }

  void setSortOption(RepoSortOption option) {
    state = state.copyWith(sortOption: option);
  }

  Future<void> selectRepository(GitHubRepo repo) async {
    final activeToken = token;
    if (activeToken == null || activeToken.isEmpty) return;

    state = state.copyWith(
      selectedRepo: repo,
      selectedBranch: repo.defaultBranch,
      branches: const [],
      isLoadingBranches: true,
      isSelectedRepoEmpty: false,
      clearBranchError: true,
    );

    await _loadBranchesForSelected(repo, activeToken);
  }

  Future<void> reloadBranchesForSelected() async {
    final repo = state.selectedRepo;
    final activeToken = token;
    if (repo == null || activeToken == null || activeToken.isEmpty) return;

    state = state.copyWith(isLoadingBranches: true, clearBranchError: true);
    await _loadBranchesForSelected(repo, activeToken);
  }

  Future<void> _loadBranchesForSelected(
    GitHubRepo repo,
    String activeToken, {
    String? preferredBranch,
  }) async {
    try {
      final branches = await api.fetchBranches(
        token: activeToken,
        owner: repo.ownerLogin,
        repo: repo.name,
      );

      // Guard against stale async completion if user switched repos quickly.
      if (state.selectedRepo?.id != repo.id) return;

      if (branches.isEmpty) {
        state = state.copyWith(
          isLoadingBranches: false,
          branches: const [],
          selectedBranch: repo.defaultBranch,
          isSelectedRepoEmpty: true,
          clearBranchError: true,
        );
        return;
      }

      final names = branches.map((b) => b.name).toSet();
      final nextBranch = (preferredBranch != null && names.contains(preferredBranch))
          ? preferredBranch
          : (names.contains(repo.defaultBranch)
              ? repo.defaultBranch
              : branches.first.name);

      state = state.copyWith(
        isLoadingBranches: false,
        branches: branches,
        selectedBranch: nextBranch,
        isSelectedRepoEmpty: false,
        clearBranchError: true,
      );
    } on GitHubException catch (e) {
      if (state.selectedRepo?.id != repo.id) return;
      state = state.copyWith(
        isLoadingBranches: false,
        branchErrorMessage: e.message,
      );
    } catch (_) {
      if (state.selectedRepo?.id != repo.id) return;
      state = state.copyWith(
        isLoadingBranches: false,
        branchErrorMessage: 'تعذر جلب فروع هذا المستودع.',
      );
    }
  }

  void selectBranch(String branchName) {
    state = state.copyWith(selectedBranch: branchName);
  }

  Future<({GitHubRepo? repo, String? error})> createRepository({
    required String name,
    required String description,
    required bool isPrivate,
    required bool autoInit,
  }) async {
    final activeToken = token;
    if (activeToken == null || activeToken.isEmpty) {
      return (repo: null, error: 'لا توجد جلسة نشطة.');
    }

    final validation = validateRepoName(name);
    if (validation != null) {
      return (repo: null, error: validation);
    }

    state = state.copyWith(isCreatingRepo: true);

    try {
      final created = await api.createRepository(
        token: activeToken,
        name: name.trim(),
        description: description.trim(),
        isPrivate: isPrivate,
        autoInit: autoInit,
      );

      final updatedList = [
        created,
        ...state.allRepos.where((r) => r.id != created.id),
      ];

      state = state.copyWith(
        isCreatingRepo: false,
        allRepos: updatedList,
      );

      // Immediately select the new repo and load its branch state
      await selectRepository(created);
      return (repo: created, error: null);
    } on GitHubException catch (e) {
      state = state.copyWith(isCreatingRepo: false);
      return (repo: null, error: e.message);
    } catch (_) {
      state = state.copyWith(isCreatingRepo: false);
      return (repo: null, error: 'فشل إنشاء المستودع الجديد.');
    }
  }

  Future<({GitHubBranch? branch, String? error})> createBranch({
    required String newBranchName,
    required String baseBranchName,
  }) async {
    final activeToken = token;
    final repo = state.selectedRepo;
    if (activeToken == null || repo == null) {
      return (branch: null, error: 'اختر مستودعاً أولاً.');
    }

    if (state.isSelectedRepoEmpty) {
      return (
        branch: null,
        error: 'لا يمكن تفريع مستودع فارغ قبل إنشاء أول Commit أو تهيئة README.'
      );
    }

    final validation = validateGitBranchName(newBranchName);
    if (validation != null) {
      return (branch: null, error: validation);
    }

    state = state.copyWith(isCreatingBranch: true);

    try {
      final created = await api.createBranch(
        token: activeToken,
        owner: repo.ownerLogin,
        repo: repo.name,
        newBranchName: newBranchName.trim(),
        baseBranchName: baseBranchName.trim(),
      );

      state = state.copyWith(isCreatingBranch: false);
      await _loadBranchesForSelected(
        repo,
        activeToken,
        preferredBranch: created.name,
      );
      return (branch: created, error: null);
    } on GitHubException catch (e) {
      state = state.copyWith(isCreatingBranch: false);
      return (branch: null, error: e.message);
    } catch (_) {
      state = state.copyWith(isCreatingBranch: false);
      return (branch: null, error: 'فشل إنشاء الفرع الجديد.');
    }
  }

  Future<String?> initializeSelectedEmptyRepo() async {
    final activeToken = token;
    final repo = state.selectedRepo;
    if (activeToken == null || repo == null) {
      return 'اختر مستودعاً أولاً.';
    }

    state = state.copyWith(isInitializingEmptyRepo: true);

    try {
      final targetBranch = state.selectedBranch ?? repo.defaultBranch;
      await api.initializeEmptyRepository(
        token: activeToken,
        owner: repo.ownerLogin,
        repo: repo.name,
        branchName: targetBranch,
      );

      state = state.copyWith(isInitializingEmptyRepo: false);
      await _loadBranchesForSelected(
        repo,
        activeToken,
        preferredBranch: targetBranch,
      );
      return null;
    } on GitHubException catch (e) {
      state = state.copyWith(isInitializingEmptyRepo: false);
      return e.message;
    } catch (_) {
      state = state.copyWith(isInitializingEmptyRepo: false);
      return 'تعذر تهيئة المستودع الفارغ.';
    }
  }
}
