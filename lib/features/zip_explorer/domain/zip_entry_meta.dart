/// GitHub hard limit per single file is 100 MB; soft recommendation warning is 50 MB.
const int kGitHubHardFileLimitBytes = 100 * 1024 * 1024;
const int kGitHubSoftFileWarningBytes = 50 * 1024 * 1024;
const int kMaxArchiveSizeBytes = 100 * 1024 * 1024;

/// Lightweight metadata parsed strictly from the ZIP Central Directory.
/// Holds ZERO file payload bytes in memory, enabling smooth 100MB archive inspection.
class ZipEntryMeta {
  final String rawPath;
  final String normalizedPath;
  final int compressedSize;
  final int uncompressedSize;
  final int compressionMethod;
  final int localHeaderOffset;
  final int crc32;
  final bool isEncrypted;

  const ZipEntryMeta({
    required this.rawPath,
    required this.normalizedPath,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.compressionMethod,
    required this.localHeaderOffset,
    required this.crc32,
    required this.isEncrypted,
  });

  bool get exceedsGitHubHardLimit =>
      uncompressedSize > kGitHubHardFileLimitBytes;

  bool get exceedsGitHubSoftWarning =>
      uncompressedSize > kGitHubSoftFileWarningBytes &&
      !exceedsGitHubHardLimit;

  bool get isSupportedCompression =>
      compressionMethod == 0 || compressionMethod == 8;

  String get fileName {
    final idx = normalizedPath.lastIndexOf('/');
    return idx >= 0 ? normalizedPath.substring(idx + 1) : normalizedPath;
  }

  String get extension {
    final name = fileName;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }
}

class InspectedZipArchive {
  final String filePath;
  final String fileName;
  final int archiveSizeBytes;
  final List<ZipEntryMeta> entries;
  final String? detectedSingleRootFolder;
  final int skippedUnsafePaths;

  const InspectedZipArchive({
    required this.filePath,
    required this.fileName,
    required this.archiveSizeBytes,
    required this.entries,
    required this.detectedSingleRootFolder,
    this.skippedUnsafePaths = 0,
  });

  int get totalUncompressedBytes =>
      entries.fold(0, (sum, e) => sum + e.uncompressedSize);
}
