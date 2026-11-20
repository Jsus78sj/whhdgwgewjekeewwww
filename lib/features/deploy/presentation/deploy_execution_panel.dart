import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/nexus_colors.dart';
import '../../../core/utils/format_bytes.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/nexus_toast.dart';
import '../../repos/domain/deploy_target.dart';
import '../../zip_explorer/domain/zip_tree_node.dart';
import '../domain/deploy_models.dart';
import 'deploy_controller.dart';
import 'full_sync_confirm_modal.dart';

class DeployExecutionPanel extends ConsumerStatefulWidget {
  final DeployTarget? target;
  final DeployArchiveBundle bundle;

  const DeployExecutionPanel({
    super.key,
    required this.target,
    required this.bundle,
  });

  @override
  ConsumerState<DeployExecutionPanel> createState() =>
      _DeployExecutionPanelState();
}

class _DeployExecutionPanelState extends ConsumerState<DeployExecutionPanel> {
  final _commitController = TextEditingController();
  final _logScrollController = ScrollController();

  @override
  void dispose() {
    _commitController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  Future<void> _onDeployPressed() async {
    final target = widget.target;
    if (target == null || !widget.bundle.isReadyToDeploy) return;

    final controller = ref.read(deployControllerProvider.notifier);
    final currentMode = ref.read(deployControllerProvider).mode;

    if (currentMode == DeployMode.fullSync) {
      final analysis = await controller.analyzeDiffForPreview(
        target: target,
        bundle: widget.bundle,
      );
      if (!mounted) return;

      if (analysis.preview == null) {
        showNexusToast(
          context,
          analysis.error ?? 'تعذر تحليل الفروقات قبل النشر',
          type: NexusToastType.error,
        );
        return;
      }

      final confirmed = await showFullSyncConfirmModal(
        context,
        target: target,
        diff: analysis.preview!,
      );
      if (!confirmed || !mounted) return;
    }

    final result = await controller.startDeploy(
      target: target,
      bundle: widget.bundle,
      retryFailedOnly: false,
    );

    if (!mounted || result == null) return;
    _notifyResult(result);
  }

  Future<void> _onRetryFailedOnly() async {
    final target = widget.target;
    if (target == null) return;

    final result = await ref
        .read(deployControllerProvider.notifier)
        .startDeploy(
          target: target,
          bundle: widget.bundle,
          retryFailedOnly: true,
        );

    if (!mounted || result == null) return;
    _notifyResult(result);
  }

  void _notifyResult(AtomicDeployResult result) {
    if (result.isSuccess) {
      showNexusToast(
        context,
        'اكتمل النشر الذري (${result.shortCommitSha}) بنجاح!',
        type: NexusToastType.success,
      );
    } else if (result.finalStage == DeployStage.cancelled) {
      showNexusToast(
        context,
        'تم إلغاء عملية النشر',
        type: NexusToastType.warning,
      );
    } else {
      showNexusToast(
        context,
        result.errorMessage ?? 'تعثر النشر — راجع سجل العمليات',
        type: NexusToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deployControllerProvider);
    final controller = ref.read(deployControllerProvider.notifier);

    ref.listen<int>(
      deployControllerProvider.select((s) => s.logs.length),
      (prev, next) {
        if (next > (prev ?? 0)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_logScrollController.hasClients) {
              _logScrollController.animateTo(
                _logScrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            }
          });
        }
      },
    );

    final canLaunch = widget.target != null &&
        widget.bundle.isReadyToDeploy &&
        !state.isDeploying &&
        !state.isAnalyzingDiff;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Strategy Header
        const Text(
          'DEPLOYMENT STRATEGY',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
            color: NexusColors.textMuted,
          ),
        ),
        const SizedBox(height: 8),

        // Full Sync vs Partial Update Radio Cards
        Row(
          children: [
            Expanded(
              child: _StrategyCard(
                title: 'Full Sync',
                badge: 'Mirror',
                description:
                    'يستبدل كامل الفرع بمحتوى الـ ZIP ويحذف الزائد في Commit واحد.',
                icon: Icons.sync_rounded,
                accent: NexusColors.roseSoft,
                selected: state.mode == DeployMode.fullSync,
                enabled: !state.isDeploying,
                onTap: () => controller.setDeployMode(DeployMode.fullSync),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StrategyCard(
                title: 'Partial Update',
                badge: 'Merge',
                description:
                    'يضيف ويحدّث الملفات المحددة فقط مع الإبقاء على بقية ملفات الفرع.',
                icon: Icons.layers_rounded,
                accent: NexusColors.successSoft,
                selected: state.mode == DeployMode.partialUpdate,
                enabled: !state.isDeploying,
                onTap: () => controller.setDeployMode(DeployMode.partialUpdate),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Custom Commit Message Input + Concurrency Chip
        Row(
          children: [
            const Expanded(
              child: Text(
                'COMMIT MESSAGE',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                  color: NexusColors.textMuted,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: NexusColors.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: NexusColors.primary.withOpacity(0.28),
                ),
              ),
              child: Text(
                'Git Data API · ${state.concurrency}x Parallel',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10.5,
                  color: NexusColors.primarySoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _commitController,
          enabled: !state.isDeploying,
          onChanged: controller.setCommitMessage,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12.8,
            color: NexusColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText:
                'deploy: ${widget.bundle.archiveName} via GitHub Nexus',
            prefixIcon: const Icon(
              Icons.commit_rounded,
              size: 18,
              color: NexusColors.textSubtle,
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Readiness Helper + Main Deploy CTA
        if (widget.target == null || widget.bundle.hasBlockingIssues)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              widget.target == null
                  ? 'اختر مستودعاً وفرعاً من الخطوة 1 لتفعيل زر النشر.'
                  : 'عالج الملفات المخالفة لحد 100MB أو المشفّرة أعلاه قبل النشر.',
              style: const TextStyle(
                fontSize: 12,
                color: NexusColors.warningSoft,
              ),
            ),
          ),

        NexusGradientButton(
          height: 52,
          onPressed: canLaunch ? _onDeployPressed : null,
          child: state.isAnalyzingDiff
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text('جارٍ تحليل الفروقات مع المستودع...'),
                  ],
                )
              : state.isDeploying
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text('النشر الذري قيد التنفيذ...'),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.rocket_launch_rounded, size: 19),
                        const SizedBox(width: 8),
                        Text(
                          'Deploy ${widget.bundle.selectedFiles.length} files (${formatBytes(widget.bundle.totalSelectedBytes)})',
                        ),
                      ],
                    ),
        ),

        // Live Progress & Console Log Card
        if (state.hasProgressCard) ...[
          const SizedBox(height: 18),
          _LiveProgressConsoleCard(
            state: state,
            logScrollController: _logScrollController,
            onCancel: controller.cancelDeploy,
            onRetryFailed: _onRetryFailedOnly,
            onClear: controller.resetProgress,
          ),
        ],
      ],
    );
  }
}

class _StrategyCard extends StatelessWidget {
  final String title;
  final String badge;
  final String description;
  final IconData icon;
  final Color accent;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _StrategyCard({
    required this.title,
    required this.badge,
    required this.description,
    required this.icon,
    required this.accent,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selected
                ? NexusColors.primary.withOpacity(0.12)
                : NexusColors.bgDeep.withOpacity(0.45),
            border: Border.all(
              color: selected
                  ? NexusColors.primary
                  : NexusColors.borderSubtle,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: NexusColors.primary.withOpacity(0.18),
                      blurRadius: 16,
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: NexusColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accent.withOpacity(0.30)),
                ),
                child: Text(
                  badge.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 0.7,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 11.2,
                  color: NexusColors.textMuted,
                  height: 1.38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveProgressConsoleCard extends StatelessWidget {
  final DeployState state;
  final ScrollController logScrollController;
  final VoidCallback onCancel;
  final VoidCallback onRetryFailed;
  final VoidCallback onClear;

  const _LiveProgressConsoleCard({
    required this.state,
    required this.logScrollController,
    required this.onCancel,
    required this.onRetryFailed,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final result = state.lastResult;
    final accent = switch (state.stage) {
      DeployStage.completed => NexusColors.successSoft,
      DeployStage.failed || DeployStage.partialFailure => NexusColors.roseSoft,
      DeployStage.cancelled => NexusColors.warningSoft,
      _ => NexusColors.primarySoft,
    };

    return GlassPanel(
      strong: true,
      borderRadius: 18,
      borderColor: accent.withOpacity(0.35),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Progress Header
          Row(
            children: [
              if (state.isDeploying)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.3,
                    color: NexusColors.primarySoft,
                  ),
                )
              else
                Icon(
                  switch (state.stage) {
                    DeployStage.completed => Icons.check_circle_rounded,
                    DeployStage.cancelled => Icons.cancel_outlined,
                    _ => Icons.error_outline_rounded,
                  },
                  color: accent,
                  size: 24,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.isDeploying
                          ? 'Deployment in Progress'
                          : (state.stage == DeployStage.completed
                              ? 'Atomic Commit Complete'
                              : 'Deployment Status'),
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: NexusColors.textPrimary,
                      ),
                    ),
                    Text(
                      state.progressLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: NexusColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${state.progressPercent}%',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: state.progressPercent / 100.0,
              minHeight: 8,
              backgroundColor: NexusColors.bgElevated,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: Text(
                  state.progressStats.isEmpty
                      ? 'GitHub Git Data API'
                      : state.progressStats,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: NexusColors.textMuted,
                  ),
                ),
              ),
              if (state.isDeploying)
                const Text(
                  'Foreground Service Active',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: NexusColors.successSoft,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),

          // Commit SHA Banner on Success
          if (result != null &&
              result.isSuccess &&
              result.commitSha != null &&
              result.commitSha!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: NexusColors.success.withOpacity(0.11),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: NexusColors.success.withOpacity(0.35),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    size: 16,
                    color: NexusColors.successSoft,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Commit: ${result.shortCommitSha} • ${result.elapsed.inSeconds}s',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: NexusColors.successSoft,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: NexusColors.successSoft,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(
                          text: result.commitUrl ?? result.commitSha!,
                        ),
                      );
                      showNexusToast(
                        context,
                        'تم نسخ رابط الـ Commit',
                        type: NexusToastType.info,
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: const Text('نسخ الرابط', style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
            ),
          ],

          // Action Controls (Cancel / Retry Failed Only / Copy Logs)
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (state.isDeploying)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NexusColors.rose.withOpacity(0.88),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: onCancel,
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                  label: const Text(
                    'إلغاء النشر',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              if (state.canRetryFailedOnly)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NexusColors.warning,
                    foregroundColor: NexusColors.bgDeep,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: onRetryFailed,
                  icon: const Icon(Icons.replay_rounded, size: 16),
                  label: Text(
                    'إعادة محاولة الفاشلة فقط (${state.failedFiles.length})',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (state.logs.isNotEmpty)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: NexusColors.textSecondary,
                    side: const BorderSide(color: NexusColors.borderSubtle),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    final dump = state.logs
                        .map((l) => '[${l.formattedTime}] ${l.message}')
                        .join('\n');
                    Clipboard.setData(ClipboardData(text: dump));
                    showNexusToast(
                      context,
                      'تم نسخ سجل العمليات (${state.logs.length} سطر)',
                      type: NexusToastType.info,
                    );
                  },
                  icon: const Icon(Icons.content_copy_rounded, size: 14),
                  label: const Text('نسخ السجل', style: TextStyle(fontSize: 11.5)),
                ),
              if (!state.isDeploying)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: NexusColors.textMuted,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  onPressed: onClear,
                  icon: const Icon(Icons.clear_all_rounded, size: 15),
                  label: const Text('مسح', style: TextStyle(fontSize: 11.5)),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Live Console Log Box
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.48),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NexusColors.borderSubtle),
            ),
            child: state.logs.isEmpty
                ? const Text(
                    'بانتظار بدء السجل المباشر...',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      color: NexusColors.textSubtle,
                    ),
                  )
                : ListView.builder(
                    controller: logScrollController,
                    shrinkWrap: true,
                    itemCount: state.logs.length,
                    itemBuilder: (_, idx) {
                      final entry = state.logs[idx];
                      final (Color color, String glyph) = switch (entry.level) {
                        DeployLogLevel.success => (NexusColors.successSoft, '✓'),
                        DeployLogLevel.error => (NexusColors.roseSoft, '✗'),
                        DeployLogLevel.warning => (NexusColors.warningSoft, '⚠'),
                        DeployLogLevel.delete => (const Color(0xFFFDA4AF), '−'),
                        DeployLogLevel.info => (NexusColors.textSecondary, '•'),
                      };
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.formattedTime,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                color: NexusColors.textSubtle,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              glyph,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                entry.message,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11.2,
                                  color: color,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
