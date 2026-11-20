import 'zip_entry_meta.dart';

class ResolvedZipItem {
  final ZipEntryMeta entry;
  final String effectivePath;
  final bool excludedByRule;
  final bool isSelected;

  const ResolvedZipItem({
    required this.entry,
    required this.effectivePath,
    required this.excludedByRule,
    required this.isSelected,
  });
}

/// Immutable tree node with aggregated directory sizes and tri-state selection counts.
class ZipTreeNode {
  final String name;
  final String fullPath;
  final bool isDirectory;
  final List<ZipTreeNode> children;
  final ResolvedZipItem? item;
  final int totalSizeBytes;
  final int totalFileCount;
  final int selectedFileCount;
  final int oversizedFileCount;

  const ZipTreeNode({
    required this.name,
    required this.fullPath,
    required this.isDirectory,
    required this.children,
    required this.item,
    required this.totalSizeBytes,
    required this.totalFileCount,
    required this.selectedFileCount,
    required this.oversizedFileCount,
  });

  /// Tri-state checkbox value:
  /// - `true`  -> all files in subtree selected
  /// - `false` -> zero files in subtree selected
  /// - `null`  -> partially selected subtree
  bool? get selectionTriState {
    if (!isDirectory) return item?.isSelected ?? false;
    if (totalFileCount == 0 || selectedFileCount == 0) return false;
    if (selectedFileCount == totalFileCount) return true;
    return null;
  }

  List<String> collectRawPaths() {
    if (!isDirectory) {
      return item != null ? [item!.entry.rawPath] : const [];
    }
    final result = <String>[];
    for (final child in children) {
      result.addAll(child.collectRawPaths());
    }
    return result;
  }

  static List<ZipTreeNode> buildForest(
    List<ResolvedZipItem> items, {
    String searchQuery = '',
  }) {
    final query = searchQuery.trim().toLowerCase();
    final filteredItems = query.isEmpty
        ? items
        : items
            .where((i) => i.effectivePath.toLowerCase().contains(query))
            .toList();

    final root = _MutableNode(name: '', fullPath: '', isDirectory: true);

    for (final resolved in filteredItems) {
      final parts = resolved.effectivePath
          .split('/')
          .where((p) => p.isNotEmpty)
          .toList();
      if (parts.isEmpty) continue;

      var cursor = root;
      final pathBuffer = StringBuffer();

      for (var i = 0; i < parts.length; i++) {
        final part = parts[i];
        if (i > 0) pathBuffer.write('/');
        pathBuffer.write(part);
        final currentPath = pathBuffer.toString();
        final isLast = i == parts.length - 1;

        cursor = cursor.children.putIfAbsent(
          part,
          () => _MutableNode(
            name: part,
            fullPath: currentPath,
            isDirectory: !isLast,
            item: isLast ? resolved : null,
          ),
        );

        if (isLast) {
          cursor.isDirectory = false;
          cursor.item = resolved;
        }
      }
    }

    return root.toImmutableChildren();
  }
}

class _MutableNode {
  final String name;
  final String fullPath;
  bool isDirectory;
  ResolvedZipItem? item;
  final Map<String, _MutableNode> children = {};

  _MutableNode({
    required this.name,
    required this.fullPath,
    required this.isDirectory,
    this.item,
  });

  List<ZipTreeNode> toImmutableChildren() {
    final nodes = children.values.map((c) => c.toImmutable()).toList();
    nodes.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return nodes;
  }

  ZipTreeNode toImmutable() {
    if (!isDirectory) {
      final entry = item!.entry;
      return ZipTreeNode(
        name: name,
        fullPath: fullPath,
        isDirectory: false,
        children: const [],
        item: item,
        totalSizeBytes: entry.uncompressedSize,
        totalFileCount: 1,
        selectedFileCount: item!.isSelected ? 1 : 0,
        oversizedFileCount: entry.exceedsGitHubHardLimit ? 1 : 0,
      );
    }

    final builtChildren = toImmutableChildren();
    var sizeSum = 0;
    var fileCount = 0;
    var selectedCount = 0;
    var oversizedCount = 0;

    for (final child in builtChildren) {
      sizeSum += child.totalSizeBytes;
      fileCount += child.totalFileCount;
      selectedCount += child.selectedFileCount;
      oversizedCount += child.oversizedFileCount;
    }

    return ZipTreeNode(
      name: name,
      fullPath: fullPath,
      isDirectory: true,
      children: builtChildren,
      item: null,
      totalSizeBytes: sizeSum,
      totalFileCount: fileCount,
      selectedFileCount: selectedCount,
      oversizedFileCount: oversizedCount,
    );
  }
}

/// Final archive handoff contract passed from Phase 3 (ZIP Explorer)
/// directly to Phase 4 (Atomic Deploy Engine).
class DeployArchiveBundle {
  final String zipFilePath;
  final String archiveName;
  final int archiveSizeBytes;
  final List<ResolvedZipItem> selectedFiles;
  final int totalEntriesCount;
  final int excludedCount;
  final int oversizedSelectedCount;
  final int softWarningSelectedCount;
  final int encryptedSelectedCount;
  final bool stripRootFolder;
  final String? strippedRootFolderName;

  const DeployArchiveBundle({
    required this.zipFilePath,
    required this.archiveName,
    required this.archiveSizeBytes,
    required this.selectedFiles,
    required this.totalEntriesCount,
    required this.excludedCount,
    required this.oversizedSelectedCount,
    required this.softWarningSelectedCount,
    required this.encryptedSelectedCount,
    required this.stripRootFolder,
    required this.strippedRootFolderName,
  });

  int get totalSelectedBytes =>
      selectedFiles.fold(0, (sum, f) => sum + f.entry.uncompressedSize);

  bool get hasBlockingIssues =>
      oversizedSelectedCount > 0 || encryptedSelectedCount > 0;

  bool get isReadyToDeploy =>
      selectedFiles.isNotEmpty && !hasBlockingIssues;
}
