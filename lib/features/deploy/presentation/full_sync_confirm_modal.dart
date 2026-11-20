import 'package:flutter/material.dart';
import '../../../core/theme/nexus_colors.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../repos/domain/deploy_target.dart';
import '../domain/deploy_models.dart';

Future<bool> showFullSyncConfirmModal(
  BuildContext context, {
  required DeployTarget target,
  required DeployDiffPreview diff,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.84),
    builder: (_) => _FullSyncConfirmDialog(target: target, diff: diff),
  );
  return result == true;
}

class _FullSyncConfirmDialog extends StatefulWidget {
  final DeployTarget target;
  final DeployDiffPreview diff;

  const _FullSyncConfirmDialog({
    required this.target,
    required this.diff,
  });

  @override
  State<_FullSyncConfirmDialog> createState() => _FullSyncConfirmDialogState();
}

class _FullSyncConfirmDialogState extends State<_FullSyncConfirmDialog> {
  bool _showDeletedList = false;

  @override
  Widget build(BuildContext context) {
    final diff = widget.diff;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: GlassPanel(
          strong: true,
          borderRadius: 22,
          borderColor: NexusColors.rose.withOpacity(0.42),
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
                        color: NexusColors.rose.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: NexusColors.rose.withOpacity(0.38),
                        ),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: NexusColors.roseSoft,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تأكيد وضع Full Sync',
                            style: TextStyle(
                              fontSize: 17.5,
                              fontWeight: FontWeight.w700,
                              color: NexusColors.roseSoft,
                            ),
                          ),
                          Text(
                            'مزامنة كاملة بـ Commit ذري واحد',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: NexusColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 13,
                      color: NexusColors.textSecondary,
                      height: 1.5,
                    ),
                    children: [
                      const TextSpan(
                        text: 'سيتم استبدال محتوى الفرع ',
                      ),
                      TextSpan(
                        text: widget.target.displayTarget,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          color: NexusColors.textPrimary,
                        ),
                      ),
                      const TextSpan(
                        text: ' بالكامل بالملفات المحددة من الأرشيف.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Diff Counters Summary
                Row(
                  children: [
                    Expanded(
                      child: _DiffCounterBox(
                        label: 'إضافة',
                        count: '+${diff.addedCount}',
                        color: NexusColors.successSoft,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DiffCounterBox(
                        label: 'تحديث',
                        count: '~${diff.updatedCount}',
                        color: NexusColors.primarySoft,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DiffCounterBox(
                        label: 'حذف',
                        count: '-${diff.deletedCount}',
                        color: NexusColors.roseSoft,
                      ),
                    ),
                  ],
                ),

                if (diff.deletedCount > 0) ...[
                  const SizedBox(height: 12),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(
                      () => _showDeletedList = !_showDeletedList,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: NexusColors.rose.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: NexusColors.rose.withOpacity(0.30),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.delete_sweep_outlined,
                            size: 16,
                            color: NexusColors.roseSoft,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'سيتم حذف ${diff.deletedCount} ملف غير موجود في الـ ZIP',
                              style: const TextStyle(
                                fontSize: 12,
                                color: NexusColors.roseSoft,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            _showDeletedList
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: NexusColors.roseSoft,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_showDeletedList) ...[
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 140),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: NexusColors.bgDeep.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: NexusColors.borderSubtle),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: diff.deletedPaths.length.clamp(0, 50),
                        itemBuilder: (_, idx) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '− ${diff.deletedPaths[idx]}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: NexusColors.roseSoft,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],

                if (diff.remoteTreeTruncated) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'ملاحظة: شجرة المستودع كبيرة جداً وتم اختصار المعاينة؛ ستُستبدل كامل الشجرة ذرياً عند التنفيذ.',
                    style: TextStyle(
                      fontSize: 11,
                      color: NexusColors.warningSoft,
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
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('إلغاء'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: NexusGradientButton(
                        height: 48,
                        borderRadius: 13,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFDC2626), Color(0xFFB91C1C)],
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('نعم، نفّذ المزامنة'),
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

class _DiffCounterBox extends StatelessWidget {
  final String label;
  final String count;
  final Color color;

  const _DiffCounterBox({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.32)),
      ),
      child: Column(
        children: [
          Text(
            count,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: NexusColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
