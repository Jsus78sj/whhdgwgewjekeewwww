import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_nexus/features/zip_explorer/data/streaming_zip_inspector.dart';
import 'package:github_nexus/features/zip_explorer/domain/zip_entry_meta.dart';
import 'package:github_nexus/features/zip_explorer/domain/zip_exclusion_rules.dart';
import 'package:github_nexus/features/zip_explorer/presentation/zip_explorer_controller.dart';

/// Builds a valid binary ZIP archive supporting both Stored (0) and Deflated (8) entries.
Uint8List _buildTestZip(Map<String, ({List<int> data, bool deflate})> files) {
  final localChunks = BytesBuilder();
  final centralChunks = BytesBuilder();
  var entryCount = 0;

  for (final entry in files.entries) {
    final nameBytes = utf8.encode(entry.key);
    final rawData = Uint8List.fromList(entry.value.data);
    final deflate = entry.value.deflate;
    final payload = deflate
        ? Uint8List.fromList(ZLibEncoder(raw: true).convert(rawData))
        : rawData;
    final method = deflate ? 8 : 0;
    final localOffset = localChunks.length;

    // Local File Header (30 bytes)
    final lh = ByteData(30);
    lh.setUint32(0, 0x04034b50, Endian.little);
    lh.setUint16(4, 20, Endian.little);
    lh.setUint16(6, 0x0800, Endian.little); // UTF-8
    lh.setUint16(8, method, Endian.little);
    lh.setUint32(18, payload.length, Endian.little);
    lh.setUint32(22, rawData.length, Endian.little);
    lh.setUint16(26, nameBytes.length, Endian.little);
    lh.setUint16(28, 0, Endian.little);

    localChunks.add(lh.buffer.asUint8List());
    localChunks.add(nameBytes);
    localChunks.add(payload);

    // Central Directory Header (46 bytes)
    final cd = ByteData(46);
    cd.setUint32(0, 0x02014b50, Endian.little);
    cd.setUint16(4, 20, Endian.little);
    cd.setUint16(6, 20, Endian.little);
    cd.setUint16(8, 0x0800, Endian.little); // UTF-8
    cd.setUint16(10, method, Endian.little);
    cd.setUint32(20, payload.length, Endian.little);
    cd.setUint32(24, rawData.length, Endian.little);
    cd.setUint16(28, nameBytes.length, Endian.little);
    cd.setUint32(42, localOffset, Endian.little);

    centralChunks.add(cd.buffer.asUint8List());
    centralChunks.add(nameBytes);
    entryCount++;
  }

  final cdOffset = localChunks.length;
  final cdBytes = centralChunks.toBytes();

  // End of Central Directory (22 bytes)
  final eocd = ByteData(22);
  eocd.setUint32(0, 0x06054b50, Endian.little);
  eocd.setUint16(8, entryCount, Endian.little);
  eocd.setUint16(10, entryCount, Endian.little);
  eocd.setUint32(12, cdBytes.length, Endian.little);
  eocd.setUint32(16, cdOffset, Endian.little);

  final out = BytesBuilder();
  out.add(localChunks.toBytes());
  out.add(cdBytes);
  out.add(eocd.buffer.asUint8List());
  return out.toBytes();
}

void main() {
  group('StreamingZipInspector & Pre-Deploy Filtering', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('github_nexus_zip_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('inspects ZIP central directory, detects single root, and extracts single entries', () async {
      final zipBytes = _buildTestZip({
        'my-app-main/lib/main.dart': (
          data: utf8.encode('void main() => print("Nexus");'),
          deflate: true,
        ),
        'my-app-main/README.md': (
          data: utf8.encode('# My App'),
          deflate: false,
        ),
        'my-app-main/.git/HEAD': (
          data: utf8.encode('ref: refs/heads/main'),
          deflate: false,
        ),
        'my-app-main/node_modules/pkg/index.js': (
          data: utf8.encode('module.exports = 1;'),
          deflate: true,
        ),
        'my-app-main/build/output.bin': (
          data: utf8.encode('binary'),
          deflate: false,
        ),
        '__MACOSX/._README.md': (
          data: utf8.encode('junk'),
          deflate: false,
        ),
      });

      final zipFile = File('${tempDir.path}/sample.zip');
      await zipFile.writeAsBytes(zipBytes);

      final inspected = await StreamingZipInspector.inspectFile(zipFile.path);
      expect(inspected.entries.length, 6);
      expect(inspected.detectedSingleRootFolder, 'my-app-main');

      // Extract a deflated file and a stored file on demand
      final dartEntry = inspected.entries
          .firstWhere((e) => e.normalizedPath == 'my-app-main/lib/main.dart');
      final extractedDart =
          await StreamingZipInspector.readEntryBytes(zipFile.path, dartEntry);
      expect(utf8.decode(extractedDart), 'void main() => print("Nexus");');

      final readmeEntry = inspected.entries
          .firstWhere((e) => e.normalizedPath == 'my-app-main/README.md');
      final extractedReadme =
          await StreamingZipInspector.readEntryBytes(zipFile.path, readmeEntry);
      expect(utf8.decode(extractedReadme), '# My App');

      // Verify state resolution with default exclusion rules + root stripping
      final explorerState = ZipExplorerState(
        archive: inspected,
        stripRootFolder: true,
      );
      final bundle = explorerState.deployBundle!;
      expect(bundle.strippedRootFolderName, 'my-app-main');
      expect(
        bundle.selectedFiles.map((f) => f.effectivePath).toList(),
        ['lib/main.dart', 'README.md'],
      );
      expect(bundle.excludedCount, 4);
      expect(bundle.isReadyToDeploy, isTrue);
    });

    test('flags files exceeding GitHub 100MB limit and computes tri-state tree counts', () {
      final oversized = ZipEntryMeta(
        rawPath: 'assets/huge_video.mp4',
        normalizedPath: 'assets/huge_video.mp4',
        compressedSize: 95 * 1024 * 1024,
        uncompressedSize: 105 * 1024 * 1024,
        compressionMethod: 8,
        localHeaderOffset: 0,
        crc32: 0,
        isEncrypted: false,
      );
      final normal = ZipEntryMeta(
        rawPath: 'assets/logo.png',
        normalizedPath: 'assets/logo.png',
        compressedSize: 1024,
        uncompressedSize: 2048,
        compressionMethod: 0,
        localHeaderOffset: 100,
        crc32: 0,
        isEncrypted: false,
      );

      final archive = InspectedZipArchive(
        filePath: '/tmp/fake.zip',
        fileName: 'fake.zip',
        archiveSizeBytes: 96 * 1024 * 1024,
        entries: [oversized, normal],
        detectedSingleRootFolder: null,
      );

      final state = ZipExplorerState(archive: archive, stripRootFolder: false);
      expect(state.deployBundle!.oversizedSelectedCount, 1);
      expect(state.deployBundle!.isReadyToDeploy, isFalse);

      // Deselect oversized file -> folder becomes indeterminate (null), bundle becomes ready
      final fixedState = state.copyWith(
        manualOverrides: {'assets/huge_video.mp4': false},
      );
      expect(fixedState.deployBundle!.oversizedSelectedCount, 0);
      expect(fixedState.deployBundle!.isReadyToDeploy, isTrue);

      final tree = fixedState.visibleTree;
      expect(tree.length, 1);
      expect(tree.first.name, 'assets');
      expect(tree.first.selectionTriState, isNull);
      expect(tree.first.selectedFileCount, 1);
      expect(tree.first.totalFileCount, 2);
    });

    test('exclusion rules preserve build.gradle while excluding build/ directory', () {
      const rules = ZipExclusionRules();
      expect(rules.matches('android/app/build.gradle'), isFalse);
      expect(rules.matches('android/app/build/outputs/app.apk'), isTrue);
      expect(rules.matches('.gitignore'), isFalse);
      expect(rules.matches('.git/config'), isTrue);
    });
  });
}
