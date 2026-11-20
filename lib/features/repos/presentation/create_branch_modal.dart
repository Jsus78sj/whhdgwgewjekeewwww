import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/nexus_colors.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/nexus_toast.dart';
import '../domain/github_branch.dart';
import 'repos_controller.dart';

Future<bool?> showCreateBranchModal(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.78),
    builder: (_) => const _CreateBranchDialog(),
  );
}

class _CreateBranchDialog extends ConsumerStatefulWidget {
  const _CreateBranchDialog();

  @override
  ConsumerState<_CreateBranchDialog> createState() =>
      _CreateBranchDialogState();
}

class _CreateBranchDialogState extends ConsumerState<_CreateBranchDialog> {
  final _branchController = TextEditingController();
  String? _selectedBaseBranch;
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    final state = ref.read(reposControllerProvider);
    _selectedBaseBranch = state.selectedBranch ??
        (state.branches.isNotEmpty ? state.branches.first.name : null);
  }

  @override
  void dispose() {
    _branchController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final validation = validateGitBranchName(_branchController.text);
    if (validation != null) {
      setState(() => _inlineError = validation);
      return;
    }

    final baseBranch = _selectedBaseBranch;
    if (baseBranch == null || baseBranch.isEmpty) {
      setState(() => _inlineError = 'اختر فرعاً أساسياً أولاً.');
      return;
    }

    setState(() => _inlineError = null);

    final result = await ref
        .read(reposControllerProvider.notifier)
        .createBranch(
          newBranchName: _branchController.text,
          baseBranchName: baseBranch,
        );

    if (!mounted) return;

    if (result.branch != null) {
      Navigator.of(context).pop(true);
      showNexusToast(
        context,
        'تم إنشاء الفرع: ${result.branch!.name}',
        type: NexusToastType.success,
      );
    } else {
      setState(() => _inlineError = result.error ?? 'تعذر إنشاء الفرع.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final reposState = ref.watch(reposControllerProvider);
    final isCreating = reposState.isCreatingBranch;
    final branches = reposState.branches;

    if (_selectedBaseBranch == null && branches.isNotEmpty) {
      _selectedBaseBranch = branches.first.name;
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassPanel(
          strong: true,
          borderRadius: 22,
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: NexusColors.violet.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: NexusColors.violet.withOpacity(0.35),
                      ),
                    ),
                    child: const Icon(
                      Icons.account_tree_rounded,
                      color: Color(0xFFA78BFA),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'New Branch',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: NexusColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: isCreating
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: NexusColors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Branch Name',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: NexusColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _branchController,
                autofocus: true,
                enabled: !isCreating,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13.5,
                  color: NexusColors.textPrimary,
                ),
                decoration: const InputDecoration(
                  hintText: 'feature/new-feature',
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Base Branch',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: NexusColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: branches.any((b) => b.name == _selectedBaseBranch)
                    ? _selectedBaseBranch
                    : (branches.isNotEmpty ? branches.first.name : null),
                dropdownColor: NexusColors.bgSurface,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13.5,
                  color: NexusColors.textPrimary,
                ),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                ),
                items: branches
                    .map(
                      (b) => DropdownMenuItem<String>(
                        value: b.name,
                        child: Text(
                          '${b.name} (${b.shortSha})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: isCreating
                    ? null
                    : (val) => setState(() => _selectedBaseBranch = val),
              ),
              if (_inlineError != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: NexusColors.rose.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: NexusColors.rose.withOpacity(0.35),
                    ),
                  ),
                  child: Text(
                    _inlineError!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: NexusColors.roseSoft,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: NexusColors.textSecondary,
                        side: const BorderSide(
                          color: NexusColors.borderSubtle,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      onPressed: isCreating
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: NexusGradientButton(
                      height: 48,
                      borderRadius: 13,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7C3AED), Color(0xFF6D28D9)],
                      ),
                      onPressed: isCreating ? null : _submit,
                      child: isCreating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.call_split_rounded, size: 17),
                                SizedBox(width: 6),
                                Text('Create Branch'),
                              ],
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
