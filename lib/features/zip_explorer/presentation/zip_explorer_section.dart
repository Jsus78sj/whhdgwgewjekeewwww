import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/nexus_colors.dart';
import '../../../core/utils/format_bytes.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/nexus_toast.dart';
import '../../deploy/presentation/deploy_execution_panel.dart';
import '../../repos/domain/deploy_target.dart';
import '../domain/zip_exclusion_rules.dart';
import '../domain/zip_tree_node.dart';
import 'zip_explorer_controller.dart';

class ZipExplorerSection extends ConsumerStatefulWidget {
  final DeployTarget? target;

  const ZipExplorerSection({super.key, required this.target});

  @override
  ConsumerState<ZipExplorerSection> createState() => _ZipExplorerSectionState();
}

class _ZipExplorerSectionState extends ConsumerState<ZipExplorerSection> {
  final _treeSearchController = TextEditingController();
  final _customPatternController = TextEditingController();
  bool _showCustomPatternInput = false;

  @override
  void dispose() {
    _treeSearchController.dispose();
    _customPatternController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ZipExplorerState>(zipExplorerControllerProvider, (prev, next) {
      if (next.errorMessage != null &&
          next.errorMessage != prev?.errorMessage) {
        showNexusToast(context, next.errorMessage!, type: NexusToastType.error);
      } else if (next.lastEventMessage != null &&
          next.lastEventMessage != prev?.lastEventMessage) {
        showNexusToast(
          context,
          next.lastEventMessage!,
          type: NexusToastType.success,
        );
      }
    });

    final state = ref.watch(zipExplorerControllerProvider);
    final controller = ref.read(zipExplorerControllerProvider.notifier);
    final bundle = state.deployBundle;
    final hasTarget = widget.target != null;

    return GlassPanel(
      padding: const EdgeInsets.all(18),
      borderColor: (hasTarget || state.hasArchive)
          ? NexusColors.primary.withOpacity(0.32)
          : NexusColors.borderSubtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header (Step 2: Deploy Center & Archive Explorer)
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: (hasTarget || state.hasArchive)
                      ? NexusColors.primaryGradient
                      : const LinearGradient(
                          colors: [NexusColors.bgElevated, NexusColors.bgHover],
                        ),
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: (hasTarget || state.hasArchive)
                      ? [
                          BoxShadow(
                            color: NexusColors.primary.withOpacity(0.42),
                            blurRadius: 16,
                          ),
                        ]
                      : null,
                ),
                child: const Center(
                  child: Text(
                    '2',
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
                      'Deploy Center & ZIP Explorer',
                      style: TextStyle(
                        fontSize: 17.5,
                        fontWeight: FontWeight.w700,
                        color: NexusColors.textPrimary,
                      ),
                    ),
                    Text(
                      'اختر أرشيف ZIP وفلتر الملفات قبل النشر الذري',
                      style: TextStyle(
                        fontSize: 12,
                        color: NexusColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Active Target Summary Strip
          _TargetSummaryStrip(target: widget.target),
          const SizedBox(height: 16),

          // Upload / Archive Picker Card
          const Text(
            'UPLOAD ARCHIVE',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: NexusColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          _ArchiveDropZoneCard(
            state: state,
            bundle: bundle,
            onPick: controller.pickZipFile,
            onClear: () {
              _treeSearchController.clear();
              controller.clearArchive();
            },
          ),

          if (state.hasArchive && bundle != null) ...[
            const SizedBox(height: 16),

            // Pre-Deploy Limit / Encryption Warnings
            if (bundle.oversizedSelectedCount > 0 ||
                bundle.encryptedSelectedCount > 0) ...[
              _BlockingWarningBanner(
                oversizedCount: bundle.oversizedSelectedCount,
                encryptedCount: bundle.encryptedSelectedCount,
                onAutoFix: controller.deselectBlockingFiles,
              ),
              const SizedBox(height: 12),
            ] else if (bundle.softWarningSelectedCount > 0) ...[
              _SoftWarningBanner(
                softWarningCount: bundle.softWarningSelectedCount,
              ),
              const SizedBox(height: 12),
            ],

            // Smart Options: Auto-Strip Root + Preset Exclusions
            _PreFilterControlsPanel(
              state: state,
              customPatternController: _customPatternController,
              showCustomInput: _showCustomPatternInput,
              onToggleCustomInput: () => setState(
                () => _showCustomPatternInput = !_showCustomPatternInput,
              ),
            ),
            const SizedBox(height: 16),

            // Interactive Hierarchical File Tree
            _ArchiveTreeViewer(
              state: state,
              bundle: bundle,
              searchController: _treeSearchController,
            ),
            const SizedBox(height: 16),

            // Phase 4: Atomic Deploy Strategy, Commit Message, CTA & Live Console
            DeployExecutionPanel(
              target: widget.target,
              bundle: bundle,
            ),
          ],
        ],
      ),
    );
  }
}

class _TargetSummaryStrip extends StatelessWidget {
  final DeployTarget? target;

  const _TargetSummaryStrip({required this.target});

  @override
  Widget build(BuildContext context) {
    final t = target;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexusColors.bgDeep.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexusColors.borderSubtle),
      ),
      child: t == null
          ? const Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: NexusColors.textSubtle,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'يمكنك فحص ملف ZIP الآن، ثم اختر المستودع والفرع من الخطوة 1 عند الجاهزية.',
                    style: TextStyle(
                      fontSize: 12,
                      color: NexusColors.textMuted,
                    ),
                  ),
                ),
              ],
            )
          : Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                const Icon(
                  Icons.track_changes_rounded,
                  size: 16,
                  color: NexusColors.textSubtle,
                ),
                const Text(
                  'Target:',
                  style: TextStyle(fontSize: 12, color: NexusColors.textMuted),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    t.repo.fullName,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: NexusColors.textPrimary,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 14,
                  color: NexusColors.textSubtle,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: (t.isEmptyRepo
                            ? NexusColors.warning
                            : NexusColors.success)
                        .withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: (t.isEmptyRepo
                              ? NexusColors.warning
                              : NexusColors.success)
                          .withOpacity(0.32),
                    ),
                  ),
                  child: Text(
                    t.isEmptyRepo ? '${t.branchName} (Empty)' : t.branchName,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: t.isEmptyRepo
                          ? NexusColors.warningSoft
                          : NexusColors.successSoft,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ArchiveDropZoneCard extends StatelessWidget {
  final ZipExplorerState state;
  final DeployArchiveBundle? bundle;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _ArchiveDropZoneCard({
    required this.state,
    required this.bundle,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final archive = state.archive;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: state.isInspecting ? null : onPick,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                (archive != null ? NexusColors.success : NexusColors.primary)
                    .withOpacity(0.08),
                NexusColors.bgDeep.withOpacity(0.45),
              ],
            ),
            border: Border.all(
              color: (archive != null
                      ? NexusColors.success
                      : NexusColors.primary)
                  .withOpacity(0.36),
              width: 1.4,
            ),
          ),
          child: state.isInspecting
              ? const Column(
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: NexusColors.primarySoft,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'جارٍ فحص فهرس الأرشيف بالتدفق (Streaming)...',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: NexusColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'لا يتم استهلاك الذاكرة بفك الضغط المسبق',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: NexusColors.textMuted,
                      ),
                    ),
                  ],
                )
              : archive == null
                  ? Column(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: NexusColors.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: NexusColors.primary.withOpacity(0.28),
                            ),
                          ),
                          child: const Icon(
                            Icons.cloud_upload_outlined,
                            size: 30,
                            color: NexusColors.primarySoft,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'اختر ملف ZIP من جهازك',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: NexusColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'يدعم حتى 100MB • أو شارك أي ملف .zip مباشرة عبر Android Share Sheet',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: NexusColors.textMuted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: NexusColors.success.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: NexusColors.success.withOpacity(0.32),
                            ),
                          ),
                          child: const Icon(
                            Icons.folder_zip_outlined,
                            size: 28,
                            color: NexusColors.successSoft,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          archive.fileName,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: NexusColors.successSoft,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'حجم الأرشيف: ${formatBytes(archive.archiveSizeBytes)} • ${bundle?.selectedFiles.length ?? 0} / ${archive.entries.length} ملف محدد (${formatBytes(bundle?.totalSelectedBytes ?? 0)})',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: NexusColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: NexusColors.primarySoft,
                                side: BorderSide(
                                  color: NexusColors.primary.withOpacity(0.35),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: onPick,
                              icon: const Icon(Icons.swap_horiz_rounded, size: 15),
                              label: const Text(
                                'تغيير الأرشيف',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: NexusColors.roseSoft,
                                backgroundColor:
                                    NexusColors.rose.withOpacity(0.11),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: onClear,
                              icon: const Icon(Icons.close_rounded, size: 15),
                              label: const Text(
                                'إزالة الملف',
                                style: TextStyle(fontSize: 12),
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

class _BlockingWarningBanner extends StatelessWidget {
  final int oversizedCount;
  final int encryptedCount;
  final VoidCallback onAutoFix;

  const _BlockingWarningBanner({
    required this.oversizedCount,
    required this.encryptedCount,
    required this.onAutoFix,
  });

  @override
  Widget build(BuildContext context) {
    final reasons = <String>[
      if (oversizedCount > 0)
        '$oversizedCount ملف يتجاوز حد GitHub الصارم (100MB)',
      if (encryptedCount > 0) '$encryptedCount ملف مشفّر بكلمة مرور',
    ];

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: NexusColors.rose.withOpacity(0.12),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: NexusColors.rose.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.report_problem_rounded,
                size: 18,
                color: NexusColors.roseSoft,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ملفات تمنع النشر إلى GitHub',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: NexusColors.roseSoft,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${reasons.join(' • ')}. يرجى إلغاء تحديدها قبل المتابعة.',
            style: const TextStyle(
              fontSize: 12,
              color: NexusColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: NexusColors.rose.withOpacity(0.85),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            onPressed: onAutoFix,
            icon: const Icon(Icons.auto_fix_high_rounded, size: 15),
            label: const Text(
              'استبعاد الملفات المخالفة تلقائياً',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftWarningBanner extends StatelessWidget {
  final int softWarningCount;

  const _SoftWarningBanner({required this.softWarningCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexusColors.warning.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexusColors.warning.withOpacity(0.32)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: NexusColors.warningSoft,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'تنبيه: يوجد $softWarningCount ملف بحجم بين 50MB و100MB (GitHub يوصي بإبقاء الملفات أقل من 50MB).',
              style: const TextStyle(
                fontSize: 12,
                color: NexusColors.warningSoft,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreFilterControlsPanel extends ConsumerWidget {
  final ZipExplorerState state;
  final TextEditingController customPatternController;
  final bool showCustomInput;
  final VoidCallback onToggleCustomInput;

  const _PreFilterControlsPanel({
    required this.state,
    required this.customPatternController,
    required this.showCustomInput,
    required this.onToggleCustomInput,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(zipExplorerControllerProvider.notifier);
    final counts = state.presetMatchCounts;
    final rootFolder = state.archive?.detectedSingleRootFolder;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NexusColors.bgDeep.withOpacity(0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NexusColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Auto-Strip Single Root Folder Toggle
          if (rootFolder != null) ...[
            Row(
              children: [
                const Icon(
                  Icons.drive_file_move_outline,
                  size: 18,
                  color: NexusColors.primarySoft,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'إزالة المجلد الجذري الزائد تلقائياً',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: NexusColors.textPrimary,
                        ),
                      ),
                      Text(
                        'جذر مكتشف: $rootFolder/',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: NexusColors.primarySoft,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: state.stripRootFolder,
                  activeColor: NexusColors.primary,
                  onChanged: controller.setStripRootFolder,
                ),
              ],
            ),
            const Divider(height: 18),
          ],

          // Exclusion Presets Header
          Row(
            children: [
              const Icon(
                Icons.filter_alt_outlined,
                size: 16,
                color: NexusColors.textMuted,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'قواعد الاستبعاد التلقائي',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: NexusColors.textPrimary,
                  ),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onToggleCustomInput,
                child: Text(
                  showCustomInput ? 'إخفاء المخصص' : '+ نمط مخصص',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: NexusColors.primarySoft,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: ExclusionPreset.values.map((preset) {
              final active =
                  state.exclusionRules.activePresets.contains(preset);
              final matchedCount = counts[preset] ?? 0;

              return Tooltip(
                message: preset.description,
                child: InkWell(
                  onTap: () => controller.togglePreset(preset),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? NexusColors.rose.withOpacity(0.14)
                          : Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: active
                            ? NexusColors.rose.withOpacity(0.45)
                            : NexusColors.borderSubtle,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          active
                              ? Icons.block_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 13,
                          color: active
                              ? NexusColors.roseSoft
                              : NexusColors.textMuted,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          preset.label,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: active
                                ? NexusColors.roseSoft
                                : NexusColors.textSecondary,
                          ),
                        ),
                        if (matchedCount > 0) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.28),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$matchedCount',
                              style: const TextStyle(
                                fontSize: 10,
                                fontFamily: 'monospace',
                                color: NexusColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          if (showCustomInput) ...[
            const SizedBox(height: 12),
            TextField(
              controller: customPatternController,
              onChanged: controller.setCustomPatternsRaw,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                color: NexusColors.textPrimary,
              ),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'مثال: *.log, *.apk, temp/, secrets.json',
                helperText: 'افصل بين الأنماط بفاصلة ( , )',
                helperStyle: TextStyle(
                  fontSize: 11,
                  color: NexusColors.textSubtle,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ArchiveTreeViewer extends ConsumerWidget {
  final ZipExplorerState state;
  final DeployArchiveBundle bundle;
  final TextEditingController searchController;

  const _ArchiveTreeViewer({
    required this.state,
    required this.bundle,
    required this.searchController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(zipExplorerControllerProvider.notifier);
    final treeNodes = state.visibleTree;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tree Title + Stats Badge
        Row(
          children: [
            const Icon(
              Icons.account_tree_outlined,
              size: 17,
              color: NexusColors.textMuted,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Archive Contents',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: NexusColors.textPrimary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: NexusColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: NexusColors.primary.withOpacity(0.32),
                ),
              ),
              child: Text(
                '${bundle.selectedFiles.length} محدد • ${formatBytes(bundle.totalSelectedBytes)}',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: NexusColors.primarySoft,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Search inside Archive
        TextField(
          controller: searchController,
          onChanged: controller.setTreeSearchQuery,
          style: const TextStyle(fontSize: 13, color: NexusColors.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'ابحث عن ملف أو مجلد داخل الأرشيف...',
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 18,
              color: NexusColors.textSubtle,
            ),
            suffixIcon: state.treeSearchQuery.isNotEmpty
                ? IconButton(
                    onPressed: () {
                      searchController.clear();
                      controller.setTreeSearchQuery('');
                    },
                    icon: const Icon(Icons.close_rounded, size: 17),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 8),

        // Bulk Actions Toolbar
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _MiniActionButton(
                icon: Icons.select_all_rounded,
                label: 'الكل',
                onTap: controller.selectAllFiles,
              ),
              const SizedBox(width: 6),
              _MiniActionButton(
                icon: Icons.deselect_rounded,
                label: 'لا شيء',
                onTap: controller.deselectAllFiles,
              ),
              const SizedBox(width: 6),
              _MiniActionButton(
                icon: Icons.restore_rounded,
                label: 'حسب القواعد',
                onTap: controller.resetSelectionToRules,
              ),
              const SizedBox(width: 6),
              _MiniActionButton(
                icon: Icons.unfold_more_rounded,
                label: 'توسيع',
                onTap: controller.expandAllFolders,
              ),
              const SizedBox(width: 6),
              _MiniActionButton(
                icon: Icons.unfold_less_rounded,
                label: 'طي',
                onTap: controller.collapseAllFolders,
              ),
              const SizedBox(width: 6),
              _MiniActionButton(
                icon: state.showExcludedFiles
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                label: state.showExcludedFiles ? 'إخفاء المستبعد' : 'إظهار المستبعد',
                onTap: controller.toggleShowExcludedFiles,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Tree Scroll Box
        Container(
          constraints: const BoxConstraints(maxHeight: 360),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: NexusColors.bgDeep.withOpacity(0.65),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: NexusColors.borderSubtle),
          ),
          child: treeNodes.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text(
                      'لا توجد عناصر مطابقة لعرضها',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: NexusColors.textMuted,
                      ),
                    ),
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  children: _flattenVisibleTree(
                    treeNodes,
                    expanded: state.expandedFolders,
                    forceExpand: state.treeSearchQuery.trim().isNotEmpty,
                    depth: 0,
                  )
                      .map(
                        (row) => _TreeRowTile(
                          row: row,
                          onToggleExpand: () =>
                              controller.toggleFolderExpanded(row.node.fullPath),
                          onToggleSelect: () =>
                              controller.toggleNodeSelection(row.node),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }

  List<_FlattenedTreeRow> _flattenVisibleTree(
    List<ZipTreeNode> nodes, {
    required Set<String> expanded,
    required bool forceExpand,
    required int depth,
  }) {
    final result = <_FlattenedTreeRow>[];
    for (final node in nodes) {
      final isOpen =
          node.isDirectory && (forceExpand || expanded.contains(node.fullPath));
      result.add(_FlattenedTreeRow(node: node, depth: depth, isOpen: isOpen));
      if (isOpen && node.children.isNotEmpty) {
        result.addAll(
          _flattenVisibleTree(
            node.children,
            expanded: expanded,
            forceExpand: forceExpand,
            depth: depth + 1,
          ),
        );
      }
    }
    return result;
  }
}

class _FlattenedTreeRow {
  final ZipTreeNode node;
  final int depth;
  final bool isOpen;

  const _FlattenedTreeRow({
    required this.node,
    required this.depth,
    required this.isOpen,
  });
}

class _TreeRowTile extends StatelessWidget {
  final _FlattenedTreeRow row;
  final VoidCallback onToggleExpand;
  final VoidCallback onToggleSelect;

  const _TreeRowTile({
    required this.row,
    required this.onToggleExpand,
    required this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context) {
    final node = row.node;
    final triState = node.selectionTriState;
    final isDeselected = triState == false;
    final isOversized = !node.isDirectory &&
        (node.item?.entry.exceedsGitHubHardLimit ?? false);
    final isEncrypted = !node.isDirectory &&
        (node.item?.entry.isEncrypted ?? false);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: node.isDirectory ? onToggleExpand : onToggleSelect,
      child: Padding(
        padding: EdgeInsets.fromLTRB(4 + (row.depth * 16.0), 3, 6, 3),
        child: Row(
          children: [
            if (node.isDirectory)
              SizedBox(
                width: 22,
                height: 22,
                child: Icon(
                  row.isOpen
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_right_rounded,
                  size: 18,
                  color: row.isOpen
                      ? NexusColors.primarySoft
                      : NexusColors.textSubtle,
                ),
              )
            else
              const SizedBox(width: 22),
            SizedBox(
              width: 26,
              height: 26,
              child: Checkbox(
                tristate: node.isDirectory,
                value: triState,
                onChanged: (_) => onToggleSelect(),
                activeColor: NexusColors.primary,
                side: const BorderSide(color: NexusColors.textSubtle, width: 1.3),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              node.isDirectory
                  ? (row.isOpen
                      ? Icons.folder_open_rounded
                      : Icons.folder_rounded)
                  : _iconForExtension(node.item?.entry.extension ?? ''),
              size: 16,
              color: isDeselected
                  ? NexusColors.textSubtle.withOpacity(0.55)
                  : (node.isDirectory
                      ? NexusColors.primarySoft
                      : _colorForExtension(node.item?.entry.extension ?? '')),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.2,
                  color: isDeselected
                      ? NexusColors.textSubtle
                      : NexusColors.textSecondary,
                  decoration: isDeselected
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                  decorationColor: NexusColors.textSubtle,
                ),
              ),
            ),
            if (isOversized)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: NexusColors.rose.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: NexusColors.rose.withOpacity(0.5)),
                ),
                child: const Text(
                  '>100MB',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: NexusColors.roseSoft,
                  ),
                ),
              ),
            if (isEncrypted)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.lock_rounded,
                  size: 13,
                  color: NexusColors.roseSoft,
                ),
              ),
            if (node.isDirectory && node.oversizedFileCount > 0)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: NexusColors.roseSoft,
                ),
              ),
            const SizedBox(width: 6),
            Text(
              node.isDirectory
                  ? '${node.selectedFileCount}/${node.totalFileCount} · ${formatBytes(node.totalSizeBytes)}'
                  : formatBytes(node.totalSizeBytes),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10.5,
                color: NexusColors.textSubtle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForExtension(String ext) {
    return switch (ext) {
      'dart' || 'kt' || 'java' || 'js' || 'ts' || 'tsx' || 'py' || 'cpp' =>
        Icons.code_rounded,
      'json' || 'yaml' || 'yml' || 'xml' || 'toml' || 'gradle' =>
        Icons.data_object_rounded,
      'html' || 'css' || 'scss' => Icons.web_rounded,
      'png' || 'jpg' || 'jpeg' || 'webp' || 'svg' || 'gif' =>
        Icons.image_outlined,
      'md' || 'txt' => Icons.description_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }

  Color _colorForExtension(String ext) {
    return switch (ext) {
      'dart' || 'ts' || 'tsx' => NexusColors.primarySoft,
      'kt' || 'java' => const Color(0xFFA78BFA),
      'json' || 'yaml' || 'yml' => NexusColors.warningSoft,
      'html' || 'css' => const Color(0xFFFB923C),
      'png' || 'jpg' || 'jpeg' || 'webp' || 'svg' => NexusColors.successSoft,
      _ => NexusColors.textMuted,
    };
  }
}

class _MiniActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MiniActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NexusColors.bgElevated.withOpacity(0.55),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: NexusColors.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13.5, color: NexusColors.textMuted),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: NexusColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
