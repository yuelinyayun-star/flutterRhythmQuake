import 'dart:convert';
import 'dart:io';

const _defaultManifestPath = 'docs/data/jma_reference_event_candidates.json';

void main(List<String> args) {
  final manifestPath = _argument(args, '--manifest') ?? _defaultManifestPath;
  final inputPath = _argument(args, '--input');
  final dryRun = args.contains('--dry-run');

  if (inputPath == null) {
    stderr.writeln(
      'Usage: dart run tools/import_jma_reference_capture_package.dart '
      '--input capture_association.json '
      '[--manifest docs/data/jma_reference_event_candidates.json] '
      '[--dry-run]',
    );
    exitCode = 64;
    return;
  }

  final result = importJmaReferenceCapturePackage(
    manifestFile: File(manifestPath),
    inputFile: File(inputPath),
    dryRun: dryRun,
  );
  final errors = _stringList(result['errors']);
  if (errors.isNotEmpty) {
    for (final error in errors) {
      stderr.writeln(error);
    }
    exitCode = 65;
    return;
  }

  if (dryRun) {
    stdout.writeln('dry-run: JMA reference capture package is valid');
  } else {
    stdout.writeln('imported JMA reference capture package');
  }
  stdout.writeln('eventId: ${result['eventId']}');
  stdout.writeln('captureDirectory: ${result['captureDirectory']}');
  stdout.writeln('manifest: ${File(manifestPath).path}');
}

Map<String, Object?> importJmaReferenceCapturePackage({
  required File manifestFile,
  required File inputFile,
  bool dryRun = false,
}) {
  if (!manifestFile.existsSync()) {
    return _failed(['jma_reference_candidate_manifest_missing']);
  }
  if (!inputFile.existsSync()) {
    return _failed(['capture_association_input_missing:${inputFile.path}']);
  }

  final manifestJson =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
  final inputJson =
      jsonDecode(inputFile.readAsStringSync()) as Map<String, Object?>;

  final errors = validateJmaReferenceCapturePackageInput(
    manifestJson: manifestJson,
    inputJson: inputJson,
  );
  if (errors.isNotEmpty) return _failed(errors);

  final eventId = inputJson['eventId'].toString();
  final events = _list(
    manifestJson['events'],
  ).map((entry) => _map(entry)).toList(growable: true);
  final index = events.indexWhere((entry) => entry['eventId'] == eventId);
  if (index < 0) {
    return _failed(['event_not_found:$eventId']);
  }

  final existing = events[index];
  events[index] = {
    ...existing,
    'status': 'capture_associated_pending_final_catalog',
    'captureDirectory': _normalizePath(inputJson['captureDirectory']),
    'captureAssociation': {
      'reviewedAtUtc': inputJson['reviewedAtUtc'],
      'reviewer': inputJson['reviewer'],
      'manifestPath': _normalizePath(inputJson['manifestPath']),
      'packageSource': inputJson['packageSource'],
      'associationReason': inputJson['associationReason'],
      'importedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'importer': 'tools/import_jma_reference_capture_package.dart',
      'finalCatalogTruth': false,
      'splitAssignmentAllowed': false,
    },
  };
  manifestJson['events'] = events;

  if (!dryRun) {
    _writeJson(manifestFile, manifestJson);
  }

  return {
    'status': 'pass',
    'errors': <String>[],
    'dryRun': dryRun,
    'eventId': eventId,
    'captureDirectory': _normalizePath(inputJson['captureDirectory']),
    'manifestPath': _normalizePath(inputJson['manifestPath']),
    'finalCatalogTruth': false,
    'splitAssignmentAllowed': false,
  };
}

List<String> validateJmaReferenceCapturePackageInput({
  required Map<String, Object?> manifestJson,
  required Map<String, Object?> inputJson,
}) {
  final errors = <String>[];
  if (manifestJson['datasetId'] != 'jma_reference_event_candidates_v1') {
    errors.add('unexpected_jma_reference_candidate_dataset_id');
  }
  if (_containsSensitiveKey(inputJson)) {
    errors.add('input_contains_sensitive_auth_material');
  }

  for (final field in const [
    'eventId',
    'status',
    'reviewedAtUtc',
    'reviewer',
    'captureDirectory',
    'manifestPath',
    'packageSource',
    'associationReason',
  ]) {
    final value = inputJson[field];
    if (value == null || (value is String && value.trim().isEmpty)) {
      errors.add('missing_required_field:$field');
    } else if (_containsUnresolvedPlaceholder(value)) {
      errors.add('unresolved_placeholder:$field');
    }
  }

  if (inputJson['status'] != 'capture_associated_pending_final_catalog') {
    errors.add('unsupported_capture_association_status:${inputJson['status']}');
  }
  if (DateTime.tryParse(inputJson['reviewedAtUtc']?.toString() ?? '') == null) {
    errors.add('reviewed_at_not_parseable');
  }

  final eventId = inputJson['eventId']?.toString() ?? '';
  final events = _list(manifestJson['events']).map((entry) => _map(entry));
  final matches = events.where((entry) => entry['eventId'] == eventId);
  if (eventId.isEmpty) {
    errors.add('missing_event_id');
  } else if (matches.isEmpty) {
    errors.add('event_not_in_jma_reference_candidates:$eventId');
  } else {
    final event = matches.first;
    if (event['status'] != 'pending_capture_association') {
      errors.add('event_is_not_pending_capture_association:$eventId');
    }
    if (event['captureDirectory'] != null) {
      errors.add('event_already_has_capture_directory:$eventId');
    }
    if (event['truthQuality']?.toString().contains('pending_final_catalog') !=
        true) {
      errors.add('event_truth_quality_not_pending_final_catalog:$eventId');
    }
  }

  final captureDirectoryPath = inputJson['captureDirectory']?.toString() ?? '';
  final manifestPath = inputJson['manifestPath']?.toString() ?? '';
  final captureDirectory = Directory(captureDirectoryPath);
  final packageManifest = File(manifestPath);
  if (captureDirectoryPath.isNotEmpty && !captureDirectory.existsSync()) {
    errors.add('capture_directory_not_found:$captureDirectoryPath');
  }
  if (manifestPath.isNotEmpty && !packageManifest.existsSync()) {
    errors.add('capture_manifest_not_found:$manifestPath');
  }
  if (captureDirectoryPath.isNotEmpty &&
      manifestPath.isNotEmpty &&
      packageManifest.existsSync() &&
      !_isWithinDirectory(packageManifest, captureDirectory)) {
    errors.add('capture_manifest_outside_capture_directory');
  }
  if (manifestPath.isNotEmpty &&
      !const {
        'manifest.json',
        'capture_manifest.json',
        'replay_manifest.json',
      }.contains(_baseName(manifestPath))) {
    errors.add('unsupported_capture_manifest_name');
  }
  if (captureDirectory.existsSync() &&
      packageManifest.existsSync() &&
      !_capturePackageHasFrameData(captureDirectory, packageManifest)) {
    errors.add('capture_package_has_no_frame_data');
  }

  return errors;
}

bool _capturePackageHasFrameData(Directory directory, File manifestFile) {
  final manifest = jsonDecode(manifestFile.readAsStringSync());
  if (manifest is Map) {
    final records = manifest['records'];
    if (records is List && records.isNotEmpty) return true;
    final frameIndexPath = manifest['frameIndexPath'];
    if (frameIndexPath is String &&
        File('${directory.path}/$frameIndexPath').existsSync()) {
      return true;
    }
  }
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .any((file) => file.path.toLowerCase().endsWith('.gif'));
}

Map<String, Object?> _failed(List<String> errors) => {
  'status': 'fail',
  'errors': errors,
};

void _writeJson(File file, Map<String, Object?> json) {
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(json)}\n',
  );
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

bool _isWithinDirectory(File file, Directory directory) {
  final directoryPath = directory.absolute.path.replaceAll('\\', '/');
  final filePath = file.absolute.path.replaceAll('\\', '/');
  return filePath.startsWith('$directoryPath/');
}

String _baseName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  return index < 0 ? normalized : normalized.substring(index + 1);
}

String _normalizePath(Object? value) => value.toString().replaceAll('\\', '/');

bool _containsSensitiveKey(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString().toLowerCase();
      if (key.contains('password') ||
          key.contains('cookie') ||
          key.contains('authorization') ||
          key.contains('session') ||
          key.contains('token') ||
          key == 'username' ||
          key == 'user') {
        return true;
      }
      if (_containsSensitiveKey(entry.value)) return true;
    }
  } else if (value is List) {
    return value.any(_containsSensitiveKey);
  }
  return false;
}

bool _containsUnresolvedPlaceholder(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.startsWith('<') && trimmed.endsWith('>');
  }
  if (value is List) return value.any(_containsUnresolvedPlaceholder);
  if (value is Map) return value.values.any(_containsUnresolvedPlaceholder);
  return false;
}

List<Object?> _list(Object? value) => value is List ? value : const [];

List<String> _stringList(Object? value) =>
    _list(value).map((item) => item.toString()).toList(growable: false);

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};
