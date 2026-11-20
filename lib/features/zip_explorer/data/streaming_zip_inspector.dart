import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../domain/zip_entry_meta.dart';

class ZipInspectionException implements Exception {
  final String message;
  const ZipInspectionException(this.message);

  @override
  String toString() => message;
}

/// Zero-decompression streaming ZIP inspector & on-demand single-entry reader.
///
/// Reads ONLY the End of Central Directory (EOCD) and Central Directory entries
/// using [RandomAccessFile], so inspecting a 100 MB archive allocates only a few
/// megabytes of metadata and never decompresses payloads into RAM.
class StreamingZipInspector {
  static const int _eocdSignature = 0x06054b50;
  static const int _zip64EocdLocatorSignature = 0x07064b50;
  static const int _zip64EocdSignature = 0x06064b50;
  static const int _centralDirSignature = 0x02014b50;
  static const int _localFileHeaderSignature = 0x04034b50;

  /// Inspects [filePath] without decompressing any entry payload.
  /// Safe to call inside `Isolate.run`.
  static Future<InspectedZipArchive> inspectFile(
    String filePath, {
    String? displayName,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const ZipInspectionException('تعذر العثور على ملف ZIP المحدد.');
    }

    final fileLength = await file.length();
    if (fileLength < 22) {
      throw const ZipInspectionException('ملف ZIP تالف أو فارغ تماماً.');
    }
    if (fileLength > kMaxArchiveSizeBytes + (5 * 1024 * 1024)) {
      throw const ZipInspectionException(
        'حجم ملف ZIP يتجاوز الحد الأقصى المسموح (100MB).',
      );
    }

    final raf = await file.open(mode: FileMode.read);
    try {
      final eocd = await _findEndOfCentralDirectory(raf, fileLength);
      if (eocd == null) {
        throw const ZipInspectionException(
          'تعذر قراءة فهرس الأرشيف (EOCD). تأكد أن الملف أرشيف ZIP صالح.',
        );
      }

      var cdOffset = eocd.centralDirOffset;
      var cdSize = eocd.centralDirSize;
      var entryCount = eocd.totalEntries;

      // Support ZIP64 archives if standard fields are saturated (0xFFFFFFFF / 0xFFFF).
      if (cdOffset == 0xFFFFFFFF ||
          cdSize == 0xFFFFFFFF ||
          entryCount == 0xFFFF) {
        final zip64 = await _tryReadZip64Eocd(raf, eocd.eocdAbsoluteOffset);
        if (zip64 != null) {
          cdOffset = zip64.centralDirOffset;
          cdSize = zip64.centralDirSize;
          entryCount = zip64.totalEntries;
        }
      }

      if (cdOffset < 0 || cdSize < 0 || cdOffset + cdSize > fileLength) {
        throw const ZipInspectionException(
          'فهرس الأرشيف غير متطابق مع حجم الملف (ZIP تالف).',
        );
      }

      await raf.setPosition(cdOffset);
      final cdBytes = await raf.read(cdSize);
      if (cdBytes.length < cdSize) {
        throw const ZipInspectionException(
          'تعذر قراءة فهرس الملفات داخل الأرشيف بالكامل.',
        );
      }

      final bd = ByteData.sublistView(cdBytes);
      final entries = <ZipEntryMeta>[];
      var offset = 0;
      var skippedUnsafe = 0;

      while (offset + 46 <= cdBytes.length && entries.length <= entryCount + 1000) {
        final sig = bd.getUint32(offset, Endian.little);
        if (sig != _centralDirSignature) break;

        final flags = bd.getUint16(offset + 8, Endian.little);
        final compressionMethod = bd.getUint16(offset + 10, Endian.little);
        final crc32 = bd.getUint32(offset + 16, Endian.little);
        var compressedSize = bd.getUint32(offset + 20, Endian.little);
        var uncompressedSize = bd.getUint32(offset + 24, Endian.little);
        final fileNameLen = bd.getUint16(offset + 28, Endian.little);
        final extraLen = bd.getUint16(offset + 30, Endian.little);
        final commentLen = bd.getUint16(offset + 32, Endian.little);
        final externalAttrs = bd.getUint32(offset + 38, Endian.little);
        var localHeaderOffset = bd.getUint32(offset + 42, Endian.little);

        final nameStart = offset + 46;
        final extraStart = nameStart + fileNameLen;
        final nextOffset = extraStart + extraLen + commentLen;
        if (nextOffset > cdBytes.length) break;

        final nameBytes = cdBytes.sublist(nameStart, extraStart);
        final isUtf8 = (flags & 0x0800) != 0;
        final rawPath = _decodeEntryName(nameBytes, isUtf8: isUtf8);

        // Parse ZIP64 extra field (0x0001) when any 32-bit field is saturated.
        if (uncompressedSize == 0xFFFFFFFF ||
            compressedSize == 0xFFFFFFFF ||
            localHeaderOffset == 0xFFFFFFFF) {
          final parsed64 = _parseZip64ExtraField(
            cdBytes,
            extraStart,
            extraLen,
            needUncompressed: uncompressedSize == 0xFFFFFFFF,
            needCompressed: compressedSize == 0xFFFFFFFF,
            needLocalOffset: localHeaderOffset == 0xFFFFFFFF,
          );
          if (parsed64.uncompressedSize != null) {
            uncompressedSize = parsed64.uncompressedSize!;
          }
          if (parsed64.compressedSize != null) {
            compressedSize = parsed64.compressedSize!;
          }
          if (parsed64.localHeaderOffset != null) {
            localHeaderOffset = parsed64.localHeaderOffset!;
          }
        }

        final isDosDirectory = (externalAttrs & 0x10) != 0;
        final isDirectory = rawPath.endsWith('/') ||
            rawPath.endsWith('\\') ||
            isDosDirectory;

        if (!isDirectory) {
          final normalized = _sanitizeZipPath(rawPath);
          if (normalized == null) {
            skippedUnsafe++;
          } else {
            entries.add(
              ZipEntryMeta(
                rawPath: rawPath,
                normalizedPath: normalized,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                compressionMethod: compressionMethod,
                localHeaderOffset: localHeaderOffset,
                crc32: crc32,
                isEncrypted: (flags & 0x01) != 0,
              ),
            );
          }
        }

        offset = nextOffset;
      }

      final resolvedName = (displayName != null && displayName.trim().isNotEmpty)
          ? displayName.trim()
          : file.uri.pathSegments.where((s) => s.isNotEmpty).last;

      final singleRoot = detectSingleRootFolder(entries);

      return InspectedZipArchive(
        filePath: filePath,
        fileName: resolvedName,
        archiveSizeBytes: fileLength,
        entries: entries,
        detectedSingleRootFolder: singleRoot,
        skippedUnsafePaths: skippedUnsafe,
      );
    } finally {
      await raf.close();
    }
  }

  /// Streams & decompresses a SINGLE file entry from disk on demand.
  /// Used by Phase 4's Atomic Deploy Engine so only active batch files touch RAM.
  static Future<Uint8List> readEntryBytes(
    String zipFilePath,
    ZipEntryMeta entry,
  ) async {
    if (entry.isEncrypted) {
      throw ZipInspectionException(
        'الملف (${entry.normalizedPath}) محمي بكلمة مرور ولا يمكن رفعه.',
      );
    }
    if (!entry.isSupportedCompression) {
      throw ZipInspectionException(
        'خوارزمية الضغط (${entry.compressionMethod}) غير مدعومة للملف ${entry.normalizedPath}.',
      );
    }

    final raf = await File(zipFilePath).open(mode: FileMode.read);
    try {
      await raf.setPosition(entry.localHeaderOffset);
      final localHeader = await raf.read(30);
      if (localHeader.length < 30) {
        throw ZipInspectionException(
          'تعذر قراءة ترويسة الملف ${entry.normalizedPath}.',
        );
      }
      final bd = ByteData.sublistView(localHeader);
      final sig = bd.getUint32(0, Endian.little);
      if (sig != _localFileHeaderSignature) {
        throw ZipInspectionException(
          'ترويسة محلية غير صالحة للملف ${entry.normalizedPath}.',
        );
      }

      final localNameLen = bd.getUint16(26, Endian.little);
      final localExtraLen = bd.getUint16(28, Endian.little);
      final dataOffset = entry.localHeaderOffset + 30 + localNameLen + localExtraLen;

      await raf.setPosition(dataOffset);
      final rawData = await raf.read(entry.compressedSize);
      if (rawData.length < entry.compressedSize) {
        throw ZipInspectionException(
          'بيانات الملف ${entry.normalizedPath} غير مكتملة داخل الأرشيف.',
        );
      }

      if (entry.compressionMethod == 0) {
        return rawData;
      }

      // Compression method 8: raw DEFLATE stream.
      final decoded = ZLibDecoder(raw: true).convert(rawData);
      return Uint8List.fromList(decoded);
    } finally {
      await raf.close();
    }
  }

  /// Detects if all meaningful entries share a single top-level directory
  /// (ignoring macOS `__MACOSX/` and `.DS_Store` noise).
  static String? detectSingleRootFolder(List<ZipEntryMeta> entries) {
    String? candidateRoot;
    var meaningfulCount = 0;

    for (final entry in entries) {
      final path = entry.normalizedPath;
      final lower = path.toLowerCase();
      if (lower.startsWith('__macosx/') ||
          lower == '.ds_store' ||
          lower.endsWith('/.ds_store')) {
        continue;
      }

      meaningfulCount++;
      final slashIndex = path.indexOf('/');
      if (slashIndex <= 0) {
        // File exists directly at archive root -> no single root folder.
        return null;
      }

      final topSegment = path.substring(0, slashIndex);
      if (candidateRoot == null) {
        candidateRoot = topSegment;
      } else if (candidateRoot != topSegment) {
        return null;
      }
    }

    return meaningfulCount > 0 ? candidateRoot : null;
  }

  /// Applies optional single-root stripping to an entry path.
  static String effectivePathFor(
    ZipEntryMeta entry, {
    required bool stripRootFolder,
    required String? detectedRootFolder,
  }) {
    final path = entry.normalizedPath;
    if (!stripRootFolder ||
        detectedRootFolder == null ||
        detectedRootFolder.isEmpty) {
      return path;
    }
    final prefix = '$detectedRootFolder/';
    if (path.startsWith(prefix) && path.length > prefix.length) {
      return path.substring(prefix.length);
    }
    return path;
  }

  static String _decodeEntryName(Uint8List bytes, {required bool isUtf8}) {
    if (isUtf8) {
      return utf8.decode(bytes, allowMalformed: true);
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  static String? _sanitizeZipPath(String raw) {
    var path = raw.replaceAll('\\', '/').trim();
    while (path.startsWith('/')) {
      path = path.substring(1);
    }
    while (path.startsWith('./')) {
      path = path.substring(2);
    }
    if (path.isEmpty) return null;

    final segments = path.split('/').where((s) => s.isNotEmpty && s != '.').toList();
    if (segments.isEmpty) return null;
    if (segments.any((s) => s == '..')) {
      // Zip Slip path traversal guard.
      return null;
    }
    return segments.join('/');
  }

  static Future<_EocdRecord?> _findEndOfCentralDirectory(
    RandomAccessFile raf,
    int fileLength,
  ) async {
    const maxCommentLen = 65535;
    final windowSize = fileLength < (22 + maxCommentLen)
        ? fileLength
        : (22 + maxCommentLen);
    final windowStart = fileLength - windowSize;

    await raf.setPosition(windowStart);
    final tail = await raf.read(windowSize);
    final bd = ByteData.sublistView(tail);

    for (var i = tail.length - 22; i >= 0; i--) {
      if (bd.getUint32(i, Endian.little) == _eocdSignature) {
        final commentLen = bd.getUint16(i + 20, Endian.little);
        if (i + 22 + commentLen == tail.length) {
          return _EocdRecord(
            eocdAbsoluteOffset: windowStart + i,
            totalEntries: bd.getUint16(i + 10, Endian.little),
            centralDirSize: bd.getUint32(i + 12, Endian.little),
            centralDirOffset: bd.getUint32(i + 16, Endian.little),
          );
        }
      }
    }
    return null;
  }

  static Future<_EocdRecord?> _tryReadZip64Eocd(
    RandomAccessFile raf,
    int eocdAbsoluteOffset,
  ) async {
    final locatorOffset = eocdAbsoluteOffset - 20;
    if (locatorOffset < 0) return null;

    await raf.setPosition(locatorOffset);
    final locator = await raf.read(20);
    if (locator.length < 20) return null;

    final lbd = ByteData.sublistView(locator);
    if (lbd.getUint32(0, Endian.little) != _zip64EocdLocatorSignature) {
      return null;
    }

    final zip64Offset = lbd.getUint64(8, Endian.little);
    await raf.setPosition(zip64Offset);
    final header = await raf.read(56);
    if (header.length < 56) return null;

    final hbd = ByteData.sublistView(header);
    if (hbd.getUint32(0, Endian.little) != _zip64EocdSignature) {
      return null;
    }

    return _EocdRecord(
      eocdAbsoluteOffset: zip64Offset,
      totalEntries: hbd.getUint64(32, Endian.little),
      centralDirSize: hbd.getUint64(40, Endian.little),
      centralDirOffset: hbd.getUint64(48, Endian.little),
    );
  }

  static ({
    int? uncompressedSize,
    int? compressedSize,
    int? localHeaderOffset,
  }) _parseZip64ExtraField(
    Uint8List cdBytes,
    int extraStart,
    int extraLen, {
    required bool needUncompressed,
    required bool needCompressed,
    required bool needLocalOffset,
  }) {
    final bd = ByteData.sublistView(cdBytes);
    var pos = extraStart;
    final end = extraStart + extraLen;

    while (pos + 4 <= end) {
      final headerId = bd.getUint16(pos, Endian.little);
      final dataSize = bd.getUint16(pos + 2, Endian.little);
      pos += 4;
      if (pos + dataSize > end) break;

      if (headerId == 0x0001) {
        var cursor = pos;
        int? uncomp;
        int? comp;
        int? localOff;
        if (needUncompressed && cursor + 8 <= pos + dataSize) {
          uncomp = bd.getUint64(cursor, Endian.little);
          cursor += 8;
        }
        if (needCompressed && cursor + 8 <= pos + dataSize) {
          comp = bd.getUint64(cursor, Endian.little);
          cursor += 8;
        }
        if (needLocalOffset && cursor + 8 <= pos + dataSize) {
          localOff = bd.getUint64(cursor, Endian.little);
        }
        return (
          uncompressedSize: uncomp,
          compressedSize: comp,
          localHeaderOffset: localOff,
        );
      }
      pos += dataSize;
    }

    return (
      uncompressedSize: null,
      compressedSize: null,
      localHeaderOffset: null,
    );
  }
}

class _EocdRecord {
  final int eocdAbsoluteOffset;
  final int totalEntries;
  final int centralDirSize;
  final int centralDirOffset;

  const _EocdRecord({
    required this.eocdAbsoluteOffset,
    required this.totalEntries,
    required this.centralDirSize,
    required this.centralDirOffset,
  });
}
