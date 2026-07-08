import 'dart:convert';
import 'dart:io';

class ReplayDatasetSplitManifest {
  final int schemaVersion;
  final String datasetId;
  final String frozenAt;
  final String splitPolicy;
  final Map<String, List<String>> splits;
  final File sourceFile;

  const ReplayDatasetSplitManifest({
    required this.schemaVersion,
    required this.datasetId,
    required this.frozenAt,
    required this.splitPolicy,
    required this.splits,
    required this.sourceFile,
  });

  factory ReplayDatasetSplitManifest.fromFile(File file) {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final rawSplits = json['splits']! as Map<String, Object?>;
    return ReplayDatasetSplitManifest(
      schemaVersion: json['schemaVersion']! as int,
      datasetId: json['datasetId']! as String,
      frozenAt: json['frozenAt']! as String,
      splitPolicy: json['splitPolicy']! as String,
      splits: rawSplits.map(
        (key, value) => MapEntry(key, (value! as List<Object?>).cast<String>()),
      ),
      sourceFile: file,
    );
  }

  List<File> caseManifestsFor(String splitName) {
    final entries = splits[splitName];
    if (entries == null) {
      throw ArgumentError.value(splitName, 'splitName', 'Unknown split.');
    }
    return entries
        .map((entry) => File.fromUri(sourceFile.parent.uri.resolve(entry)))
        .toList(growable: false);
  }

  Set<String> caseIdsFor(String splitName) {
    return caseManifestsFor(splitName).map(_caseIdFromManifest).toSet();
  }

  bool isInSplit(String caseId, String splitName) {
    return caseIdsFor(splitName).contains(caseId);
  }

  List<String> validate({
    List<File> allowedCaseManifests = const [],
    List<File> benchmarkSuiteManifests = const [],
  }) {
    final issues = <String>[];
    if (schemaVersion != 1) issues.add('unsupported_schema_version');
    if (datasetId.isEmpty) issues.add('missing_dataset_id');
    if (frozenAt.isEmpty) issues.add('missing_frozen_at');
    if (splitPolicy.isEmpty) issues.add('missing_split_policy');

    for (final requiredSplit in const ['train', 'validation', 'test']) {
      final entries = splits[requiredSplit];
      if (entries == null) {
        issues.add('missing_split:$requiredSplit');
      } else if (entries.isEmpty) {
        issues.add('empty_split:$requiredSplit');
      }
    }

    final allowedFileNames = allowedCaseManifests
        .map((file) => _normalizedPath(file.uri.pathSegments.last))
        .toSet();
    final seenCaseIds = <String, String>{};
    for (final split in splits.entries) {
      if (split.value.toSet().length != split.value.length) {
        issues.add('duplicate_case_path_in_split:${split.key}');
      }
      for (final relativePath in split.value) {
        if (!_isSafeRelativePath(relativePath)) {
          issues.add('unsafe_case_path:${split.key}:$relativePath');
          continue;
        }
        final manifest = File.fromUri(
          sourceFile.parent.uri.resolve(relativePath),
        );
        if (allowedFileNames.isNotEmpty &&
            !allowedFileNames.contains(
              _normalizedPath(manifest.uri.pathSegments.last),
            )) {
          issues.add('unknown_case:${split.key}:$relativePath');
        }
        if (!manifest.existsSync()) {
          issues.add('missing_case_file:${split.key}:$relativePath');
          continue;
        }
        final caseId = _caseIdFromManifest(manifest);
        final previousSplit = seenCaseIds[caseId];
        if (previousSplit != null) {
          issues.add(
            'case_in_multiple_splits:$caseId:$previousSplit:${split.key}',
          );
        } else {
          seenCaseIds[caseId] = split.key;
        }
      }
    }

    final testCaseIds = seenCaseIds.entries
        .where((entry) => entry.value == 'test')
        .map((entry) => entry.key)
        .toSet();
    for (final suite in benchmarkSuiteManifests) {
      if (!suite.existsSync()) {
        issues.add('missing_benchmark_suite:${suite.path}');
        continue;
      }
      final suiteJson =
          jsonDecode(suite.readAsStringSync()) as Map<String, Object?>;
      final suiteId = suiteJson['suiteId']! as String;
      final suiteCases = (suiteJson['cases']! as List<Object?>).cast<String>();
      for (final relativePath in suiteCases) {
        final manifest = File.fromUri(suite.parent.uri.resolve(relativePath));
        if (!manifest.existsSync()) continue;
        final caseId = _caseIdFromManifest(manifest);
        if (testCaseIds.contains(caseId)) {
          issues.add('test_case_used_by_suite:$caseId:$suiteId');
        }
      }
    }
    return issues;
  }

  static bool _isSafeRelativePath(String path) {
    final normalized = _normalizedPath(path);
    return normalized.isNotEmpty &&
        !normalized.startsWith('/') &&
        !normalized.contains('../') &&
        !RegExp(r'^[A-Za-z]:').hasMatch(normalized);
  }

  static String _normalizedPath(String path) => path.replaceAll('\\', '/');

  static String _caseIdFromManifest(File manifest) {
    final json =
        jsonDecode(manifest.readAsStringSync()) as Map<String, Object?>;
    return json['caseId']! as String;
  }
}
