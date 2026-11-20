import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/nexus_colors.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/nexus_toast.dart';
import 'auth_controller.dart';

Future<void> showAccountSwitcherSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AccountSwitcherSheet(),
  );
}

class _AccountSwitcherSheet extends ConsumerStatefulWidget {
  const _AccountSwitcherSheet();

  @override
  ConsumerState<_AccountSwitcherSheet> createState() =>
      _AccountSwitcherSheetState();
}

class _AccountSwitcherSheetState extends ConsumerState<_AccountSwitcherSheet> {
  final _newTokenController = TextEditingController();
  bool _showAddForm = false;

  @override
  void dispose() {
    _newTokenController.dispose();
    super.dispose();
  }

  Future<void> _addToken() async {
    final token = _newTokenController.text.trim();
    if (token.isEmpty) return;

    final ok = await ref
        .read(authControllerProvider.notifier)
        .connectWithToken(token);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      showNexusToast(
        context,
        'تمت إضافة الحساب والتبديل إليه بنجاح',
        type: NexusToastType.success,
      );
    } else {
      final err = ref.read(authControllerProvider).errorMessage;
      showNexusToast(
        context,
        err ?? 'فشل التحقق من التوكن الجديد',
        type: NexusToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isBusy = authState.isBusy;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
      child: GlassPanel(
        strong: true,
        borderRadius: 24,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.manage_accounts_rounded,
                  color: NexusColors.primarySoft,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'إدارة الحسابات المحفوظة',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: NexusColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: NexusColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: authState.savedAccounts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final acc = authState.savedAccounts[index];
                  final isActive = acc.id == authState.activeAccount?.id;
                  return Material(
                    color: isActive
                        ? NexusColors.primary.withOpacity(0.14)
                        : NexusColors.bgElevated.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: (isActive || isBusy)
                          ? null
                          : () async {
                              final ok = await ref
                                  .read(authControllerProvider.notifier)
                                  .switchAccount(acc);
                              if (!context.mounted) return;
                              if (ok) {
                                Navigator.of(context).pop();
                                showNexusToast(
                                  context,
                                  'تم التبديل إلى @${acc.user.login}',
                                  type: NexusToastType.success,
                                );
                              }
                            },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isActive
                                ? NexusColors.primary.withOpacity(0.55)
                                : NexusColors.borderSubtle,
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 19,
                              backgroundColor: NexusColors.bgHover,
                              backgroundImage: acc.user.avatarUrl.isNotEmpty
                                  ? NetworkImage(acc.user.avatarUrl)
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    acc.user.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: NexusColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    '@${acc.user.login} • ${acc.maskedToken}',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontFamily: 'monospace',
                                      color: NexusColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: NexusColors.success.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color:
                                        NexusColors.success.withOpacity(0.35),
                                  ),
                                ),
                                child: const Text(
                                  'نشط',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: NexusColors.successSoft,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            else
                              IconButton(
                                tooltip: 'إزالة الحساب',
                                onPressed: isBusy
                                    ? null
                                    : () => ref
                                        .read(authControllerProvider.notifier)
                                        .removeSavedAccount(acc.id),
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: NexusColors.roseSoft,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            if (_showAddForm) ...[
              TextField(
                controller: _newTokenController,
                obscureText: true,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
                decoration: const InputDecoration(
                  hintText: 'ghp_xxxxxxxxxxxxxx أو github_pat_...',
                ),
              ),
              const SizedBox(height: 10),
              NexusGradientButton(
                height: 46,
                onPressed: isBusy ? null : _addToken,
                child: isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('التحقق وإضافة الحساب'),
              ),
            ] else
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: NexusColors.primarySoft,
                  side: BorderSide(
                    color: NexusColors.primary.withOpacity(0.35),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => setState(() => _showAddForm = true),
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('إضافة حساب GitHub آخر'),
              ),
          ],
        ),
      ),
    );
  }
}
