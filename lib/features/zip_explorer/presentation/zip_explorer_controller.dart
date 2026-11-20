import 'dart:async';
import 'dart:isolate';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/share_intent_service.dart';
import '../data/streaming_zip_inspector.dart';
import '../domain/zip_entry_meta.dart';
import '../domain/zip_exclusion_rules.dart';
import '../domain/zip_tree_node.dart';

class ZipExplorerState {
  final bool isInspecting;
  final InspectedZipArchive? archive;
  final bool stripRootFolder;
  final ZipExclusionRules exclusionRules;
  final String customPatternsRaw;

  /// Manual user overrides keyed by `entry.rawPath`.
  /// Overrides rule-based exclusion (lets user force-include or force-exclude any file).
  final Map<String, bool> manualOverrides;

  final String treeSearchQuery;
  final Set<String> expandedFolders;
  final bool showExcludedFiles;
  final String? errorMessage;
  final String? lastEventMessage;

  const ZipExplorerState({
    this.isInspecting = false,
    this.archive,
    this.stripRootFolder = true,
    this.exclusionRules = const ZipExclusionRules(),
    this.customPatternsRaw = '',
    this.manualOverrides = const {},
    this.treeSearchQuery = '',
    this.expandedFolders = const {},
    this.showExcludedFiles = true,
    this.errorMessage,
    this.lastEventMessage,
  });

  bool get hasArchive => archive != null;

  bool get canStripRootFolder =>
      archive?.detectedSingleRootFolder != null;

  /// Resolves every entry's effective path, rule exclusion state, and selection state.
  List<ResolvedZipItem> get resolvedItems {
    final currentArchive = archive;
    if (currentArchive == null) return const [];

    return currentArchive.entries.map((entry) {
      final effectivePath = StreamingZipInspector.effectivePathFor(
        entry,
        stripRootFolder: stripRootFolder,
        detectedRootFolder: currentArchive.detectedSingleRootFolder,
      );
      final excluded = exclusionRules.matches(effectivePath);
      final manual = manualOverrides[entry.rawPath];
      final isSelected = manual ?? !excluded;

      return ResolvedZipItem(
        entry: entry,
        effectivePath: effectivePath,
        excludedByRule: excluded,
        isSelected: isSelected,
      );
    }).toList();
  }

  /// Counts how many files in the current archive match each preset (for chip badges).
  Map<ExclusionPreset, int> get presetMatchCounts {
    final currentArchive = archive;
    if (currentArchive == null) return const {};

    final counts = <ExclusionPreset, int>{
      for (final p in ExclusionPreset.values) p: 0,
    };

    for (final entry in currentArchive.entries) {
      final effectivePath = StreamingZipInspector.effectivePathFor(
        entry,
        stripRootFolder: stripRootFolder,
        detectedRootFolder: currentArchive.detectedSingleRootFolder,
      );
      for (final preset in ExclusionPreset.values) {
        if (ZipExclusionRules.matchesPreset(preset, effectivePath)) {
          counts[preset] = (counts[preset] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  List<ZipTreeNode> get visibleTree {
    final items = resolvedItems;
    final filteredByVisibility = showExcludedFiles
        ? items
        : items.where((i) => i.isSelected || !i.excludedByRule).toList();
    return ZipTreeNode.buildForest(
      filteredByVisibility,
      searchQuery: treeSearchQuery,
    );
  }

  DeployArchiveBundle? get deployBundle {
    final currentArchive = archive;
    if (currentArchive == null) return null;

    final all = resolvedItems;
    final selected = <ResolvedZipItem>[];
    var excludedCount = 0;
    var oversizedSelected = 0;
    var softWarningSelected = 0;
    var encryptedSelected = 0;

    for (final item in all) {
      if (item.isSelected) {
        selected.add(item);
        if (item.entry.exceedsGitHubHardLimit) oversizedSelected++;
        if (item.entry.exceedsGitHubSoftWarning) softWarningSelected++;
        if (item.entry.isEncrypted) encryptedSelected++;
      } else {
        excludedCount++;
      }
    }

    return DeployArchiveBundle(
      zipFilePath: currentArchive.filePath,
      archiveName: currentArchive.fileName,
      archiveSizeBytes: currentArchive.archiveSizeBytes,
      selectedFiles: selected,
      totalEntriesCount: all.length,
      excludedCount: excludedCount,
      oversizedSelectedCount: oversizedSelected,
      softWarningSelectedCount: softWarningSelected,
      encryptedSelectedCount: encryptedSelected,
      stripRootFolder: stripRootFolder && canStripRootFolder,
      strippedRootFolderName: stripRootFolder
          ? currentArchive.detectedSingleRootFolder
          : null,
    );
  }

  ZipExplorerState copyWith({
    bool? isInspecting,
    InspectedZipArchive? archive,
    bool clearArchive = false,
    bool? stripRootFolder,
    ZipExclusionRules? exclusionRules,
    String? customPatternsRaw,
    Map<String, bool>? manualOverrides,
    String? treeSearchQuery,
    Set<String>? expandedFolders,
    bool? showExcludedFiles,
    String? errorMessage,
    bool clearError = false,
    String? lastEventMessage,
    bool clearEvent = false,
  }) {
    return ZipExplorerState(
      isInspecting: isInspecting ?? this.isInspecting,
      archive: clearArchive ? null : (archive ?? this.archive),
      stripRootFolder: stripRootFolder ?? this.stripRootFolder,
      exclusionRules: exclusionRules ?? this.exclusionRules,
      customPatternsRaw: customPatternsRaw ?? this.customPatternsRaw,
      manualOverrides: manualOverrides ?? this.manualOverrides,
      treeSearchQuery: treeSearchQuery ?? this.treeSearchQuery,
      expandedFolders: expandedFolders ?? this.expandedFolders,
      showExcludedFiles: showExcludedFiles ?? this.showExcludedFiles,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      lastEventMessage:
          clearEvent ? null : (lastEventMessage ?? this.lastEventMessage),
    );
  }
}

final shareIntentServiceProvider = Provider<ShareIntentService>(
  (ref) => ShareIntentService(),
);

final zipExplorerControllerProvider =
    StateNotifierProvider<ZipExplorerController, ZipExplorerState>((ref) {
  final shareService = ref.watch(shareIntentServiceProvider);
  return ZipExplorerController(shareService: shareService);
});

class ZipExplorerController extends StateNotifier<ZipExplorerState> {
  final ShareIntentService shareService;
  StreamSubscription<IncomingSharedZip>? _shareSub;

  ZipExplorerController({required this.shareService})
      : super(const ZipExplorerState()) {
    _initShareListeners();
  }

  Future<void> _initShareListeners() async {
    _shareSub = shareService.sharedZipStream().listen(_handleSharedZip);
    final initial = await shareService.consumeInitialSharedZip();
    if (initial != null) {
      await _handleSharedZip(initial);
    }
  }

  Future<void> _handleSharedZip(IncomingSharedZip shared) async {
    if (shared.error != null) {
      state = state.copyWith(errorMessage: shared.error);
      return;
    }
    if (shared.hasFile) {
      await loadZipFromPath(
        shared.path!,
        displayName: shared.name,
        sourceHint: 'تم استلام ملف ZIP عبر المشاركة',
      );
    }
  }

  /// Opens the Android system file picker restricted to `.zip` archives.
  Future<void> pickZipFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        allowMultiple: false,
        withData: false, // Critical: stream from disk path, never load bytes into RAM.
      );

      if (result == null || result.files.isEmpty) return;
      final picked = result.files.first;
      final path = picked.path;
      if (path == null || path.isEmpty) {
        state = state.copyWith(
          errorMessage: 'تعذر الحصول على مسار ملف ZIP من مدير الملفات.',
        );
        return;
      }

      await loadZipFromPath(path, displayName: picked.name);
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'فشل فتح مدير الملفات: $e',
      );
    }
  }

  /// Inspects a ZIP file off the UI thread using `Isolate.run` without decompressing payloads.
  Future<void> loadZipFromPath(
    String filePath, {
    String? displayName,
    String? sourceHint,
  }) async {
    state = state.copyWith(
      isInspecting: true,
      clearError: true,
      clearEvent: true,
    );

    try {
      final archive = await Isolate.run(
        () => StreamingZipInspector.inspectFile(
          filePath,
          displayName: displayName,
        ),
      );

      final defaultStrip = archive.detectedSingleRootFolder != null;

      // Expand top-level folders automatically for quick visual orientation.
      final initialExpanded = <String>{};
      final previewNodes = ZipTreeNode.buildForest(
        archive.entries.map((e) {
          final eff = StreamingZipInspector.effectivePathFor(
            e,
            stripRootFolder: defaultStrip,
            detectedRootFolder: archive.detectedSingleRootFolder,
          );
          return ResolvedZipItem(
            entry: e,
            effectivePath: eff,
            excludedByRule: false,
            isSelected: true,
          );
        }).toList(),
      );
      for (final node in previewNodes.take(6)) {
        if (node.isDirectory) {
          initialExpanded.add(node.fullPath);
        }
      }

      state = state.copyWith(
        isInspecting: false,
        archive: archive,
        stripRootFolder: defaultStrip,
        manualOverrides: const {},
        treeSearchQuery: '',
        expandedFolders: initialExpanded,
        clearError: true,
        lastEventMessage: sourceHint ??
            'تم فحص الأرشيف بنجاح (${archive.entries.length} ملف)',
      );
    } on ZipInspectionException catch (e) {
      state = state.copyWith(
        isInspecting: false,
        errorMessage: e.message,
      );
    } catch (_) {
      state = state.copyWith(
        isInspecting: false,
        errorMessage: 'تعذر فحص ملف ZIP. تأكد أنه غير تالف وحاول مجدداً.',
      );
    }
  }

  void clearArchive() {
    state = ZipExplorerState(
      exclusionRules: state.exclusionRules,
      customPatternsRaw: state.customPatternsRaw,
      showExcludedFiles: state.showExcludedFiles,
    );
  }

  void clearNotifications() {
    state = state.copyWith(clearError: true, clearEvent: true);
  }

  void setStripRootFolder(bool value) {
    state = state.copyWith(
      stripRootFolder: value,
      expandedFolders: const {},
    );
  }

  void togglePreset(ExclusionPreset preset) {
    final next = Set<ExclusionPreset>.from(state.exclusionRules.activePresets);
    if (next.contains(preset)) {
      next.remove(preset);
    } else {
      next.add(preset);
    }
    state = state.copyWith(
      exclusionRules: state.exclusionRules.copyWith(activePresets: next),
      manualOverrides: const {},
    );
  }

  void setCustomPatternsRaw(String raw) {
    final parsed = ZipExclusionRules.parseCustomPatternString(raw);
    state = state.copyWith(
      customPatternsRaw: raw,
      exclusionRules: state.exclusionRules.copyWith(customPatterns: parsed),
      manualOverrides: const {},
    );
  }

  void setTreeSearchQuery(String query) {
    state = state.copyWith(treeSearchQuery: query);
  }

  void toggleShowExcludedFiles() {
    state = state.copyWith(showExcludedFiles: !state.showExcludedFiles);
  }

  void toggleFolderExpanded(String folderPath) {
    final next = Set<String>.from(state.expandedFolders);
    if (next.contains(folderPath)) {
      next.remove(folderPath);
    } else {
      next.add(folderPath);
    }
    state = state.copyWith(expandedFolders: next);
  }

  void expandAllFolders() {
    final allDirs = <String>{};
    void walk(List<ZipTreeNode> nodes) {
      for (final node in nodes) {
        if (node.isDirectory) {
          allDirs.add(node.fullPath);
          walk(node.children);
        }
      }
    }

    walk(state.visibleTree);
    state = state.copyWith(expandedFolders: allDirs);
  }

  void collapseAllFolders() {
    state = state.copyWith(expandedFolders: const {});
  }

  void toggleNodeSelection(ZipTreeNode node) {
    final nextOverrides = Map<String, bool>.from(state.manualOverrides);
    final rawPaths = node.collectRawPaths();
    if (rawPaths.isEmpty) return;

    // If fully selected -> deselect all; if unchecked or indeterminate -> select all.
    final nextValue = node.selectionTriState != true;
    for (final rawPath in rawPaths) {
      nextOverrides[rawPath] = nextValue;
    }

    state = state.copyWith(manualOverrides: nextOverrides);
  }

  void selectAllFiles() {
    final currentArchive = state.archive;
    if (currentArchive == null) return;
    final overrides = <String, bool>{
      for (final e in currentArchive.entries) e.rawPath: true,
    };
    state = state.copyWith(manualOverrides: overrides);
  }

  void deselectAllFiles() {
    final currentArchive = state.archive;
    if (currentArchive == null) return;
    final overrides = <String, bool>{
      for (final e in currentArchive.entries) e.rawPath: false,
    };
    state = state.copyWith(manualOverrides: overrides);
  }

  void resetSelectionToRules() {
    state = state.copyWith(manualOverrides: const {});
  }

  /// One-tap remediation for files exceeding GitHub's 100MB hard limit or encrypted entries.
  void deselectBlockingFiles() {
    final currentArchive = state.archive;
    if (currentArchive == null) return;
    final nextOverrides = Map<String, bool>.from(state.manualOverrides);
    for (final e in currentArchive.entries) {
      if (e.exceedsGitHubHardLimit || e.isEncrypted) {
        nextOverrides[e.rawPath] = false;
      }
    }
    state = state.copyWith(
      manualOverrides: nextOverrides,
      lastEventMessage: 'تم استبعاد الملفات المخالفة لحدود GitHub تلقائياً',
    );
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }
}
