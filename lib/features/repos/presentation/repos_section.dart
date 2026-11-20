import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/nexus_colors.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/nexus_toast.dart';
import '../domain/github_repo.dart';
import 'create_branch_modal.dart';
import 'create_repo_modal.dart';
import 'repos_controller.dart';

enum _RepoSectionTab { existing, createNew }

class ReposSection extends ConsumerStatefulWidget {
  const ReposSection({super.key});

  @override
  ConsumerState<ReposSection> createState() => _ReposSectionState();
}

class _ReposSectionState extends ConsumerState<ReposSection> {
  final _searchController = TextEditingController();
  _RepoSectionTab _activeTab = _RepoSectionTab.existing;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openCreateRepo() async {
    final created = await showCreateRepoModal(context);
    if (created == true && mounted && _activeTab == _RepoSectionTab.createNew) {
      setState(() => _activeTab = _RepoSectionTab.existing);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reposControllerProvider);
    final controller = ref.read(reposControllerProvider.notifier);
    final filtered = state.filteredRepos;

    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section Header
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: NexusColors.primaryGradient,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(
                      color: NexusColors.primary.withOpacity(0.45),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    '1',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Repository',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: NexusColors.textPrimary,
                      ),
                    ),
                    Text(
                      'اختر المستودع والفرع المستهدف للنشر',
                      style: TextStyle(
                        fontSize: 12,
                        color: NexusColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: NexusColors.borderSubtle),
                ),
                child: Text(
                  '${filtered.length} repos',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: NexusColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'تحديث المستودعات',
                onPressed: state.isLoadingRepos
                    ? null
                    : () async {
                        await controller.loadRepositories();
                        if (!context.mounted) return;
                        showNexusToast(
                          context,
                          'تم تحديث قائمة المستودعات',
                          type: NexusToastType.info,
                        );
                      },
                icon: state.isLoadingRepos
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: NexusColors.primarySoft,
                        ),
                      )
                    : const Icon(
                        Icons.refresh_rounded,
                        size: 20,
                        color: NexusColors.textMuted,
                      ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Segmented Tabs: Existing Repos | Create New
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: NexusColors.bgDeep.withOpacity(0.55),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: NexusColors.borderSubtle),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _TabPill(
                    icon: Icons.folder_open_rounded,
                    label: 'Existing Repos',
                    active: _activeTab == _RepoSectionTab.existing,
                    onTap: () =>
                        setState(() => _activeTab = _RepoSectionTab.existing),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _TabPill(
                    icon: Icons.add_circle_outline_rounded,
                    label: 'Create New',
                    active: _activeTab == _RepoSectionTab.createNew,
                    onTap: () =>
                        setState(() => _activeTab = _RepoSectionTab.createNew),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_activeTab == _RepoSectionTab.createNew)
            _CreateNewRepoPlaceholder(onTap: _openCreateRepo)
          else ...[
            // Search & Filter Controls
            TextField(
              controller: _searchController,
              onChanged: controller.setSearchQuery,
              style: const TextStyle(
                fontSize: 13.5,
                color: NexusColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'ابحث باسم المستودع أو الوصف أو اللغة...',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 19,
                  color: NexusColors.textSubtle,
                ),
                suffixIcon: state.searchQuery.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _searchController.clear();
                          controller.setSearchQuery('');
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: NexusColors.textMuted,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterChipPill(
                          label: 'All',
                          selected:
                              state.visibilityFilter == RepoVisibilityFilter.all,
                          onTap: () => controller
                              .setVisibilityFilter(RepoVisibilityFilter.all),
                        ),
                        const SizedBox(width: 6),
                        _FilterChipPill(
                          label: 'Public',
                          selected: state.visibilityFilter ==
                              RepoVisibilityFilter.publicOnly,
                          accent: NexusColors.successSoft,
                          onTap: () => controller.setVisibilityFilter(
                            RepoVisibilityFilter.publicOnly,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _FilterChipPill(
                          label: 'Private',
                          selected: state.visibilityFilter ==
                              RepoVisibilityFilter.privateOnly,
                          accent: NexusColors.roseSoft,
                          onTap: () => controller.setVisibilityFilter(
                            RepoVisibilityFilter.privateOnly,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<RepoSortOption>(
                  tooltip: 'ترتيب المستودعات',
                  color: NexusColors.bgSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: NexusColors.borderSubtle),
                  ),
                  initialValue: state.sortOption,
                  onSelected: controller.setSortOption,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: RepoSortOption.updated,
                      child: Text('الأحدث تحديثاً'),
                    ),
                    PopupMenuItem(
                      value: RepoSortOption.name,
                      child: Text('الاسم (A-Z)'),
                    ),
                    PopupMenuItem(
                      value: RepoSortOption.stars,
                      child: Text('الأكثر نجوماً'),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: NexusColors.bgDeep.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: NexusColors.borderSubtle),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.sort_rounded,
                          size: 15,
                          color: NexusColors.textMuted,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          switch (state.sortOption) {
                            RepoSortOption.updated => 'Updated',
                            RepoSortOption.name => 'Name',
                            RepoSortOption.stars => 'Stars',
                          },
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: NexusColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Error Banner
            if (state.errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(13),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: NexusColors.rose.withOpacity(0.11),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: NexusColors.rose.withOpacity(0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 19,
                      color: NexusColors.roseSoft,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        state.errorMessage!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: NexusColors.roseSoft,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: controller.loadRepositories,
                      child: const Text('إعادة'),
                    ),
                  ],
                ),
              ),
            ],

            // Repository List / Grid
            if (state.isLoadingRepos && state.allRepos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 38),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: NexusColors.primarySoft,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'جارٍ تحميل المستودعات من GitHub...',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: NexusColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    Icon(
                      Icons.inbox_outlined,
                      size: 42,
                      color: NexusColors.textSubtle.withOpacity(0.6),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      state.allRepos.isEmpty
                          ? 'لا توجد مستودعات في هذا الحساب بعد'
                          : 'لا توجد مستودعات تطابق البحث أو الفلتر الحالي',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: NexusColors.textMuted,
                      ),
                    ),
                  ],
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = constraints.maxWidth >= 680 ? 2 : 1;
                    if (crossAxisCount == 1) {
                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, index) {
                          final repo = filtered[index];
                          return _RepoCard(
                            repo: repo,
                            selected: state.selectedRepo?.id == repo.id,
                            onTap: () => controller.selectRepository(repo),
                          );
                        },
                      );
                    }
                    return GridView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        mainAxisExtent: 126,
                      ),
                      itemBuilder: (_, index) {
                        final repo = filtered[index];
                        return _RepoCard(
                          repo: repo,
                          selected: state.selectedRepo?.id == repo.id,
                          onTap: () => controller.selectRepository(repo),
                        );
                      },
                    );
                  },
                ),
              ),
          ],

          // Selected Repository & Branch Controls
          if (state.selectedRepo != null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Divider(height: 1),
            ),
            _SelectedRepoBranchPanel(state: state),
          ],
        ],
      ),
    );
  }
}

class _SelectedRepoBranchPanel extends ConsumerWidget {
  final ReposState state;

  const _SelectedRepoBranchPanel({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = state.selectedRepo!;
    final controller = ref.read(reposControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: NexusColors.primary.withOpacity(0.14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: NexusColors.primary.withOpacity(0.3)),
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                size: 19,
                color: NexusColors.primarySoft,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SELECTED TARGET',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                      color: NexusColors.textMuted,
                    ),
                  ),
                  Text(
                    repo.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: NexusColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Branch Selector + New Branch Button
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: NexusColors.bgDeep.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: NexusColors.borderSubtle),
                ),
                child: state.isLoadingBranches
                    ? const SizedBox(
                        height: 46,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: NexusColors.primarySoft,
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'جارٍ جلب الفروع...',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: NexusColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Row(
                        children: [
                          const Text(
                            'Branch:',
                            style: TextStyle(
                              fontSize: 12,
                              color: NexusColors.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: state.isSelectedRepoEmpty
                                ? Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13,
                                    ),
                                    child: Text(
                                      '${state.selectedBranch ?? repo.defaultBranch} (جديد عند أول رفع)',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12.5,
                                        color: NexusColors.warningSoft,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                : DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      isExpanded: true,
                                      dropdownColor: NexusColors.bgSurface,
                                      value: state.branches.any(
                                        (b) => b.name == state.selectedBranch,
                                      )
                                          ? state.selectedBranch
                                          : (state.branches.isNotEmpty
                                              ? state.branches.first.name
                                              : null),
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 13,
                                        color: NexusColors.textPrimary,
                                      ),
                                      items: state.branches
                                          .map(
                                            (b) => DropdownMenuItem<String>(
                                              value: b.name,
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      b.name,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (b.isProtected)
                                                    const Padding(
                                                      padding: EdgeInsets.only(
                                                        left: 6,
                                                      ),
                                                      child: Icon(
                                                        Icons.shield_outlined,
                                                        size: 14,
                                                        color: NexusColors
                                                            .warningSoft,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          controller.selectBranch(val);
                                        }
                                      },
                                    ),
                                  ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              width: 48,
              child: Tooltip(
                message: state.isSelectedRepoEmpty
                    ? 'قم بتهيئة المستودع الفارغ قبل إنشاء فرع جديد'
                    : 'إنشاء فرع جديد',
                child: Material(
                  color: state.isSelectedRepoEmpty
                      ? NexusColors.bgElevated.withOpacity(0.35)
                      : NexusColors.bgElevated,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: (state.isLoadingBranches ||
                            state.isSelectedRepoEmpty ||
                            state.branches.isEmpty)
                        ? null
                        : () => showCreateBranchModal(context),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: NexusColors.borderSubtle),
                      ),
                      child: Icon(
                        Icons.call_split_rounded,
                        size: 20,
                        color: state.isSelectedRepoEmpty
                            ? NexusColors.textSubtle
                            : NexusColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        // Branch Error Banner
        if (state.branchErrorMessage != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: NexusColors.rose.withOpacity(0.11),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NexusColors.rose.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 17,
                  color: NexusColors.roseSoft,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.branchErrorMessage!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: NexusColors.roseSoft,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: controller.reloadBranchesForSelected,
                  child: const Text('إعادة'),
                ),
              ],
            ),
          ),
        ],

        // Empty Repo Auto-Detection & Handling Banner
        if (state.isSelectedRepoEmpty && !state.isLoadingBranches) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: NexusColors.warning.withOpacity(0.10),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: NexusColors.warning.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: NexusColors.warningSoft,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'مستودع فارغ (بدون Commits بعد)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: NexusColors.warningSoft,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'سيستخدم التطبيق مسار التهيئة الآمن تلقائياً على الفرع (${repo.defaultBranch}) عند النشر، أو يمكنك تهيئته الآن بملف README.md لإنشاء فروع إضافية فوراً.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: NexusColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NexusColors.warningSoft,
                      side: BorderSide(
                        color: NexusColors.warningSoft.withOpacity(0.5),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: state.isInitializingEmptyRepo
                        ? null
                        : () async {
                            final err =
                                await controller.initializeSelectedEmptyRepo();
                            if (!context.mounted) return;
                            if (err == null) {
                              showNexusToast(
                                context,
                                'تمت تهيئة ${repo.name} بملف README.md بنجاح',
                                type: NexusToastType.success,
                              );
                            } else {
                              showNexusToast(
                                context,
                                err,
                                type: NexusToastType.error,
                              );
                            }
                          },
                    icon: state.isInitializingEmptyRepo
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: NexusColors.warningSoft,
                            ),
                          )
                        : const Icon(Icons.auto_fix_high_rounded, size: 16),
                    label: Text(
                      state.isInitializingEmptyRepo
                          ? 'جارٍ التهيئة...'
                          : 'تهيئة الآن بملف README.md',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _RepoCard extends StatelessWidget {
  final GitHubRepo repo;
  final bool selected;
  final VoidCallback onTap;

  const _RepoCard({
    required this.repo,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      NexusColors.primary.withOpacity(0.18),
                      NexusColors.primary.withOpacity(0.04),
                    ],
                  )
                : null,
            color: selected ? null : NexusColors.bgElevated.withOpacity(0.42),
            border: Border.all(
              color: selected
                  ? NexusColors.primary.withOpacity(0.65)
                  : NexusColors.borderSubtle,
              width: selected ? 1.4 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: NexusColors.primary.withOpacity(0.18),
                      blurRadius: 18,
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (selected)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: const BoxDecoration(
                        color: NexusColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: NexusColors.primary,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Text(
                      repo.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? NexusColors.primarySoft
                            : NexusColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: (repo.isPrivate
                              ? NexusColors.rose
                              : NexusColors.success)
                          .withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: (repo.isPrivate
                                ? NexusColors.rose
                                : NexusColors.success)
                            .withOpacity(0.32),
                      ),
                    ),
                    child: Text(
                      repo.isPrivate ? 'Private' : 'Public',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: repo.isPrivate
                            ? NexusColors.roseSoft
                            : NexusColors.successSoft,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                repo.description.isNotEmpty
                    ? repo.description
                    : 'No description',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: NexusColors.textMuted,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.call_split_rounded,
                    size: 13,
                    color: NexusColors.textSubtle,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      repo.defaultBranch,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: NexusColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(
                    Icons.star_border_rounded,
                    size: 14,
                    color: NexusColors.textSubtle,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${repo.stargazersCount}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: NexusColors.textMuted,
                    ),
                  ),
                  if (repo.likelyEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: NexusColors.warning.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Empty',
                        style: TextStyle(
                          fontSize: 10,
                          color: NexusColors.warningSoft,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (repo.language != null && repo.language!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        repo.language!,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: NexusColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabPill({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? NexusColors.primary.withOpacity(0.16) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: active
                ? const Border(
                    bottom: BorderSide(color: NexusColors.primary, width: 2),
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: active ? NexusColors.primarySoft : NexusColors.textMuted,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color:
                      active ? NexusColors.primarySoft : NexusColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChipPill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _FilterChipPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent = NexusColors.primarySoft,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? accent.withOpacity(0.15)
          : NexusColors.bgDeep.withOpacity(0.45),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? accent.withOpacity(0.55)
                  : NexusColors.borderSubtle,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? accent : NexusColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateNewRepoPlaceholder extends StatelessWidget {
  final VoidCallback onTap;

  const _CreateNewRepoPlaceholder({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Material(
        color: NexusColors.success.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: NexusColors.success.withOpacity(0.35),
                width: 1.3,
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: NexusColors.success.withOpacity(0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    size: 30,
                    color: NexusColors.successSoft,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Create New Repository',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: NexusColors.successSoft,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'أنشئ مستودعاً جديداً وحدد خصوصيته وخيار README للنشر المباشر',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: NexusColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
