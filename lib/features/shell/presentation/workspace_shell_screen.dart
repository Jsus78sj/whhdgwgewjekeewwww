import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/rate_limit_info.dart';
import '../../../core/theme/nexus_colors.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/nexus_toast.dart';
import '../../auth/domain/github_account.dart';
import '../../auth/presentation/account_switcher_sheet.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../repos/presentation/create_repo_modal.dart';
import '../../repos/presentation/repos_controller.dart';
import '../../repos/presentation/repos_section.dart';
import '../../zip_explorer/presentation/zip_explorer_section.dart';

class WorkspaceShellScreen extends ConsumerWidget {
  const WorkspaceShellScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final rateLimit = ref.watch(rateLimitProvider) ?? authState.rateLimit;
    final activeTarget = ref.watch(
      reposControllerProvider.select((s) => s.activeTarget),
    );
    final account = authState.activeAccount;

    if (account == null) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      body: NexusAmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              _TopWorkspaceHeader(
                onSwitchAccount: () => showAccountSwitcherSheet(context),
                onDisconnect: () async {
                  await ref.read(authControllerProvider.notifier).disconnect();
                  if (!context.mounted) return;
                  showNexusToast(
                    context,
                    'تم تسجيل الخروج من الجلسة النشطة',
                    type: NexusToastType.info,
                  );
                },
              ),
              Expanded(
                child: RefreshIndicator(
                  color: NexusColors.primarySoft,
                  backgroundColor: NexusColors.bgSurface,
                  onRefresh: () async {
                    await Future.wait([
                      ref
                          .read(authControllerProvider.notifier)
                          .refreshActiveProfile(),
                      ref
                          .read(reposControllerProvider.notifier)
                          .loadRepositories(silent: true),
                    ]);
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      _UserProfileBar(
                        account: account,
                        rateLimit: rateLimit,
                        onSwitchAccount: () =>
                            showAccountSwitcherSheet(context),
                        onNewRepo: () => showCreateRepoModal(context),
                      ),
                      const SizedBox(height: 16),
                      const ReposSection(),
                      const SizedBox(height: 16),
                      ZipExplorerSection(target: activeTarget),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopWorkspaceHeader extends StatelessWidget {
  final VoidCallback onSwitchAccount;
  final VoidCallback onDisconnect;

  const _TopWorkspaceHeader({
    required this.onSwitchAccount,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: NexusColors.bgDeep.withOpacity(0.55),
        border: const Border(
          bottom: BorderSide(color: NexusColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: NexusColors.brandLogoGradient,
              borderRadius: BorderRadius.circular(11),
              boxShadow: [
                BoxShadow(
                  color: NexusColors.primary.withOpacity(0.35),
                  blurRadius: 14,
                ),
              ],
            ),
            child: const Icon(Icons.hub_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GitHub Nexus',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: NexusColors.textPrimary,
                  ),
                ),
                Text(
                  'REPO MANAGER PRO',
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w600,
                    color: NexusColors.textSubtle,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: NexusColors.borderSubtle),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 8, color: NexusColors.successSoft),
                SizedBox(width: 6),
                Text(
                  'Connected',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: NexusColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'تبديل الحساب',
            onPressed: onSwitchAccount,
            icon: const Icon(
              Icons.switch_account_rounded,
              color: NexusColors.textMuted,
              size: 21,
            ),
          ),
          IconButton(
            tooltip: 'تسجيل الخروج',
            onPressed: onDisconnect,
            icon: const Icon(
              Icons.logout_rounded,
              color: NexusColors.textMuted,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserProfileBar extends StatelessWidget {
  final SavedAccount account;
  final RateLimitInfo? rateLimit;
  final VoidCallback onSwitchAccount;
  final VoidCallback onNewRepo;

  const _UserProfileBar({
    required this.account,
    required this.rateLimit,
    required this.onSwitchAccount,
    required this.onNewRepo,
  });

  @override
  Widget build(BuildContext context) {
    final user = account.user;
    final quotaText = rateLimit != null
        ? 'API ${rateLimit!.remaining}/${rateLimit!.limit}'
        : 'Keystore Active';
    final quotaColor = rateLimit != null && rateLimit!.isLow
        ? NexusColors.warningSoft
        : NexusColors.successSoft;

    return GlassPanel(
      padding: const EdgeInsets.all(15),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onSwitchAccount,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: NexusColors.bgHover, width: 2),
                      ),
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: NexusColors.bgElevated,
                        backgroundImage: user.avatarUrl.isNotEmpty
                            ? NetworkImage(user.avatarUrl)
                            : null,
                        child: user.avatarUrl.isEmpty
                            ? const Icon(Icons.person_rounded, size: 22)
                            : null,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: NexusColors.successSoft,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: NexusColors.bgSurface,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: NexusColors.textPrimary,
                      ),
                    ),
                    Text(
                      '@${user.login}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: NexusColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 124,
                child: NexusGradientButton(
                  height: 38,
                  borderRadius: 11,
                  gradient: NexusColors.successGradient,
                  onPressed: onNewRepo,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'New Repo',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MiniBadge(
                icon: Icons.verified_user_outlined,
                label: account.isFineGrainedToken
                    ? 'Fine-Grained'
                    : 'scope: repo',
                color: NexusColors.primarySoft,
              ),
              const SizedBox(width: 8),
              _MiniBadge(
                icon: Icons.speed_rounded,
                label: quotaText,
                color: quotaColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MiniBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
