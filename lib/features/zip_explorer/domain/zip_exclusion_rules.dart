enum ExclusionPreset {
  gitMetadata(
    label: '.git/',
    description: 'مجلد بيانات Git الداخلية (لا يحذف .gitignore)',
  ),
  nodeModules(
    label: 'node_modules/',
    description: 'حزم Node.js المثبتة',
  ),
  buildOutputs(
    label: 'build / dist',
    description: 'build, dist, out, .dart_tool, .gradle, .next, target',
  ),
  osJunk(
    label: 'OS Junk',
    description: '__MACOSX, .DS_Store, Thumbs.db, desktop.ini',
  ),
  ideAndCache(
    label: 'IDE / Cache',
    description: '.idea, .vscode, __pycache__, *.pyc',
  );

  final String label;
  final String description;

  const ExclusionPreset({
    required this.label,
    required this.description,
  });
}

class ZipExclusionRules {
  final Set<ExclusionPreset> activePresets;
  final List<String> customPatterns;

  const ZipExclusionRules({
    this.activePresets = const {
      ExclusionPreset.gitMetadata,
      ExclusionPreset.nodeModules,
      ExclusionPreset.buildOutputs,
      ExclusionPreset.osJunk,
      ExclusionPreset.ideAndCache,
    },
    this.customPatterns = const [],
  });

  ZipExclusionRules copyWith({
    Set<ExclusionPreset>? activePresets,
    List<String>? customPatterns,
  }) {
    return ZipExclusionRules(
      activePresets: activePresets ?? this.activePresets,
      customPatterns: customPatterns ?? this.customPatterns,
    );
  }

  /// Evaluates whether [effectivePath] matches any active preset or custom rule.
  bool matches(String effectivePath) {
    final lowerPath = effectivePath.toLowerCase();
    final segments = lowerPath.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return true;
    final fileName = segments.last;

    if (activePresets.contains(ExclusionPreset.gitMetadata)) {
      if (segments.contains('.git')) return true;
    }

    if (activePresets.contains(ExclusionPreset.nodeModules)) {
      if (segments.contains('node_modules')) return true;
    }

    if (activePresets.contains(ExclusionPreset.buildOutputs)) {
      const buildDirs = {
        'build',
        'dist',
        'out',
        '.dart_tool',
        '.gradle',
        '.next',
        '.nuxt',
        'target',
        'coverage',
      };
      // Match only directory segments so files like "build.gradle" stay included.
      for (var i = 0; i < segments.length - 1; i++) {
        if (buildDirs.contains(segments[i])) return true;
      }
    }

    if (activePresets.contains(ExclusionPreset.osJunk)) {
      if (segments.contains('__macosx') ||
          fileName == '.ds_store' ||
          fileName == 'thumbs.db' ||
          fileName == 'desktop.ini' ||
          fileName.startsWith('._')) {
        return true;
      }
    }

    if (activePresets.contains(ExclusionPreset.ideAndCache)) {
      const ideDirs = {'.idea', '.vscode', '__pycache__', '.pytest_cache'};
      for (var i = 0; i < segments.length - 1; i++) {
        if (ideDirs.contains(segments[i])) return true;
      }
      if (fileName.endsWith('.pyc') ||
          fileName.endsWith('.pyo') ||
          fileName.endsWith('.iml')) {
        return true;
      }
    }

    for (final rawPattern in customPatterns) {
      final p = rawPattern.trim().toLowerCase();
      if (p.isEmpty) continue;

      if (p.endsWith('/')) {
        final dirName = p.substring(0, p.length - 1);
        if (dirName.isNotEmpty) {
          for (var i = 0; i < segments.length - 1; i++) {
            if (segments[i] == dirName) return true;
          }
        }
      } else if (p.startsWith('*.')) {
        final extSuffix = p.substring(1); // ".log"
        if (fileName.endsWith(extSuffix)) return true;
      } else if (p.contains('*')) {
        final escaped = RegExp.escape(p).replaceAll(r'\*', '.*');
        if (RegExp('^$escaped\$').hasMatch(lowerPath) ||
            RegExp('^$escaped\$').hasMatch(fileName)) {
          return true;
        }
      } else {
        if (lowerPath == p ||
            fileName == p ||
            segments.contains(p)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Checks if a single specific [preset] matches [effectivePath] (used for live badge counts).
  static bool matchesPreset(ExclusionPreset preset, String effectivePath) {
    return ZipExclusionRules(activePresets: {preset}).matches(effectivePath);
  }

  static List<String> parseCustomPatternString(String raw) {
    return raw
        .split(RegExp(r'[,\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
}
