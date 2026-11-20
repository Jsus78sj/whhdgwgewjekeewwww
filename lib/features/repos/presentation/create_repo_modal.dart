import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/nexus_colors.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/nexus_toast.dart';
import '../domain/github_branch.dart';
import 'repos_controller.dart';

Future<bool?> showCreateRepoModal(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.78),
    builder: (_) => const _CreateRepoDialog(),
  );
}

class _CreateRepoDialog extends ConsumerStatefulWidget {
  const _CreateRepoDialog();

  @override
  ConsumerState<_CreateRepoDialog> createState() => _CreateRepoDialogState();
}

class _CreateRepoDialogState extends ConsumerState<_CreateRepoDialog> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  bool _isPrivate = false;
  bool _initReadme = false;
  String? _inlineError;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final validation = validateRepoName(_nameController.text);
    if (validation != null) {
      setState(() => _inlineError = validation);
      return;
    }

    setState(() => _inlineError = null);

    final result = await ref
        .read(reposControllerProvider.notifier)
        .createRepository(
          name: _nameController.text,
          description: _descController.text,
          isPrivate: _isPrivate,
          autoInit: _initReadme,
        );

    if (!mounted) return;

    if (result.repo != null) {
      Navigator.of(context).pop(true);
      showNexusToast(
        context,
        'تم إنشاء المستودع: ${result.repo!.name}',
        type: NexusToastType.success,
      );
    } else {
      setState(() => _inlineError = result.error ?? 'تعذر إنشاء المستودع');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCreating = ref.watch(
      reposControllerProvider.select((s) => s.isCreatingRepo),
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: GlassPanel(
          strong: true,
          borderRadius: 22,
          padding: const EdgeInsets.all(22),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: NexusColors.success.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: NexusColors.success.withOpacity(0.30),
                        ),
                      ),
                      child: const Icon(
                        Icons.add_circle_outline_rounded,
                        color: NexusColors.successSoft,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'New Repository',
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
                  'Repository Name',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: NexusColors.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  enabled: !isCreating,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13.5,
                    color: NexusColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'my-awesome-project',
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Description (optional)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: NexusColors.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descController,
                  enabled: !isCreating,
                  maxLines: 2,
                  minLines: 1,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: NexusColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'وصف مختصر للمشروع',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _VisibilityOptionCard(
                        icon: Icons.public_rounded,
                        label: 'Public',
                        subtitle: 'متاح للجميع',
                        selected: !_isPrivate,
                        accent: NexusColors.successSoft,
                        onTap: isCreating
                            ? null
                            : () => setState(() => _isPrivate = false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _VisibilityOptionCard(
                        icon: Icons.lock_outline_rounded,
                        label: 'Private',
                        subtitle: 'خاص بك فقط',
                        selected: _isPrivate,
                        accent: NexusColors.roseSoft,
                        onTap: isCreating
                            ? null
                            : () => setState(() => _isPrivate = true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: isCreating
                      ? null
                      : () => setState(() => _initReadme = !_initReadme),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: NexusColors.bgDeep.withOpacity(0.42),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: NexusColors.borderSubtle),
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _initReadme,
                          onChanged: isCreating
                              ? null
                              : (v) =>
                                  setState(() => _initReadme = v ?? false),
                          activeColor: NexusColors.primary,
                          side: const BorderSide(
                            color: NexusColors.textSubtle,
                          ),
                        ),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Initialize with README',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: NexusColors.textPrimary,
                                ),
                              ),
                              Text(
                                'ينشئ الفرع الافتراضي تلقائياً لتتمكن من التفريع فوراً',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: NexusColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
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
                        gradient: NexusColors.successGradient,
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
                                  Icon(Icons.add_rounded, size: 18),
                                  SizedBox(width: 6),
                                  Text('Create'),
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
      ),
    );
  }
}

class _VisibilityOptionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final Color accent;
  final VoidCallback? onTap;

  const _VisibilityOptionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? accent.withOpacity(0.13)
          : NexusColors.bgDeep.withOpacity(0.45),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? accent.withOpacity(0.6)
                  : NexusColors.borderSubtle,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected ? accent : NexusColors.textMuted,
                size: 22,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? accent : NexusColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: NexusColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
