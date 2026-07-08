import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _defaultDecisionPath =
    'docs/data/hinet_capture_provenance_review_decisions.json';

void main(List<String> args) {
  final decisionPath = _argument(args, '--decisions') ?? _defaultDecisionPath;
  final inputPath = _argument(args, '--input');
  final dryRun = args.contains('--dry-run');

  if (inputPath == null) {
    stderr.writeln(
      'Usage: dart run tools/import_hinet_capture_repair_candidate.dart '
      '--input repair.json '
      '[--decisions docs/data/hinet_capture_provenance_review_decisions.json] '
      '[--dry-run]',
    );
    exitCode = 64;
    return;
  }

  final result = importHinetCaptureRepairCandidate(
    decisionFile: File(decisionPath),
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
    stdout.writeln('dry-run: capture repair candidate is valid');
  } else {
    stdout.writeln('imported capture repair candidate');
  }
  stdout.writeln('caseId: ${result['caseId']}');
  stdout.writeln('destination: ${result['destinationPath']}');
  stdout.writeln('decisions: ${File(decisionPath).path}');
}

Map<String, Object?> importHinetCaptureRepairCandidate({
  required File decisionFile,
  required File inputFile,
  bool dryRun = false,
}) {
  final errors = <String>[];
  if (!decisionFile.existsSync()) {
    return _failed(['decision_file_not_found:${decisionFile.path}']);
  }
  if (!inputFile.existsSync()) {
    return _failed(['input_repair_file_not_found:${inputFile.path}']);
  }

  final decisionsJson =
      jsonDecode(decisionFile.readAsStringSync()) as Map<String, Object?>;
  final inputJson =
      jsonDecode(inputFile.readAsStringSync()) as Map<String, Object?>;
  errors.addAll(
    validateHinetCaptureRepairCandidateInput(
      decisionsJson: decisionsJson,
      inputJson: inputJson,
    ),
  );
  if (errors.isNotEmpty) return _failed(errors);

  final candidateFile = File(inputJson['candidatePath'].toString());
  final captureDirectory = Directory(inputJson['captureDirectory'].toString());
  final expectedFileName = inputJson['expectedFileName'].toString();
  final destination = File('${captureDirectory.path}/$expectedFileName');
  final bytes = candidateFile.readAsBytesSync();
  final actualSha256 = sha256.convert(bytes).toString();
  final expectedSha256 = inputJson['expectedSha256'].toString();

  if (actualSha256 != expectedSha256) {
    return _failed(['candidate_sha256_mismatch']);
  }
  if (!_isGif(bytes)) {
    return _failed(['candidate_is_not_gif']);
  }
  if (destination.existsSync()) {
    return _failed(['destination_already_exists:${destination.path}']);
  }
  if (!_isWithinDirectory(destination, captureDirectory)) {
    return _failed(['destination_outside_capture_directory']);
  }

  final manifestFile = File('${captureDirectory.path}/manifest.json');
  final captureManifestFile = File(
    '${captureDirectory.path}/capture_manifest.json',
  );
  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
  final captureManifest =
      jsonDecode(captureManifestFile.readAsStringSync())
          as Map<String, Object?>;
  final missingBefore = _list(manifest['missingFrames']).length;
  final repairedMissingFrames = _removeMatchingMissingFrames(
    manifest,
    expectedFileName,
  );
  if (repairedMissingFrames != 1) {
    return _failed(['matching_missing_frame_not_found']);
  }
  final repairedRecordCount = _repairCaptureManifestRecord(
    captureManifest,
    inputJson: inputJson,
    bytes: bytes.length,
    sha256Hex: actualSha256,
  );
  if (repairedRecordCount != 1) {
    return _failed(['matching_capture_manifest_record_not_found']);
  }
  _updateDecision(decisionsJson, inputJson, actualSha256);

  if (!dryRun) {
    destination.writeAsBytesSync(bytes);
    _writeJson(manifestFile, manifest);
    _writeJson(captureManifestFile, captureManifest);
    _writeJson(decisionFile, decisionsJson);
  }

  return {
    'status': 'pass',
    'errors': <String>[],
    'dryRun': dryRun,
    'caseId': inputJson['caseId'],
    'sourcePath': candidateFile.path,
    'destinationPath': destination.path,
    'expectedFileName': expectedFileName,
    'sha256': actualSha256,
    'missingFrameCountBefore': missingBefore,
    'missingFrameCountAfter': _list(manifest['missingFrames']).length,
  };
}

List<String> validateHinetCaptureRepairCandidateInput({
  required Map<String, Object?> decisionsJson,
  required Map<String, Object?> inputJson,
}) {
  final errors = <String>[];
  if (decisionsJson['schemaVersion'] !=
      'hinet_capture_provenance_review_decisions_v1') {
    errors.add('unexpected_capture_decisions_schema');
  }
  if (_containsSensitiveKey(inputJson)) {
    errors.add('input_contains_sensitive_auth_material');
  }
  for (final field in const [
    'caseId',
    'decisionStatus',
    'reviewedAtUtc',
    'reviewer',
    'captureDirectory',
    'candidatePath',
    'expectedFileName',
    'expectedSha256',
    'sourceDescription',
  ]) {
    final value = inputJson[field];
    if (value == null || (value is String && value.trim().isEmpty)) {
      errors.add('missing_required_field:$field');
    } else if (_containsUnresolvedPlaceholder(value)) {
      errors.add('unresolved_placeholder:$field');
    }
  }
  if (inputJson['decisionStatus'] != 'capture_frame_repaired') {
    errors.add('unsupported_decision_status:${inputJson['decisionStatus']}');
  }
  if (DateTime.tryParse(inputJson['reviewedAtUtc']?.toString() ?? '') == null) {
    errors.add('reviewed_at_not_parseable');
  }

  final caseId = inputJson['caseId']?.toString() ?? '';
  final matchingCases = _list(
    decisionsJson['cases'],
  ).map((entry) => _map(entry)).where((entry) => entry['caseId'] == caseId);
  if (caseId.isEmpty) {
    errors.add('missing_case_id');
  } else if (matchingCases.isEmpty) {
    errors.add('case_not_in_capture_decisions:$caseId');
  } else if (matchingCases.first['decisionStatus'] !=
      'pending_capture_repair_or_exclusion') {
    errors.add('case_decision_is_not_pending:$caseId');
  }

  final expectedFileName = inputJson['expectedFileName']?.toString() ?? '';
  if (!expectedFileName.endsWith('.gif') ||
      expectedFileName.contains('/') ||
      expectedFileName.contains('\\')) {
    errors.add('invalid_expected_file_name');
  }
  final expectedSha256 = inputJson['expectedSha256']?.toString() ?? '';
  if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(expectedSha256)) {
    errors.add('invalid_expected_sha256');
  }

  final candidatePath = inputJson['candidatePath']?.toString() ?? '';
  final candidateFile = File(candidatePath);
  if (candidatePath.isNotEmpty && !candidateFile.existsSync()) {
    errors.add('candidate_file_not_found:$candidatePath');
  }
  if (candidatePath.isNotEmpty &&
      _baseName(candidatePath) != expectedFileName) {
    errors.add('candidate_file_name_mismatch');
  }

  final capturePath = inputJson['captureDirectory']?.toString() ?? '';
  final captureDirectory = Directory(capturePath);
  if (capturePath.isNotEmpty && !captureDirectory.existsSync()) {
    errors.add('capture_directory_not_found:$capturePath');
  }
  final manifestFile = File('$capturePath/manifest.json');
  final captureManifestFile = File('$capturePath/capture_manifest.json');
  if (capturePath.isNotEmpty && !manifestFile.existsSync()) {
    errors.add('capture_manifest_json_missing:${manifestFile.path}');
  }
  if (capturePath.isNotEmpty && !captureManifestFile.existsSync()) {
    errors.add(
      'capture_download_manifest_json_missing:${captureManifestFile.path}',
    );
  }
  return errors;
}

int _removeMatchingMissingFrames(
  Map<String, Object?> manifest,
  String expectedFileName,
) {
  final parsed = _ParsedGifName.parse(expectedFileName);
  if (parsed == null) return 0;
  final missingFrames = _list(
    manifest['missingFrames'],
  ).map((entry) => _map(entry)).toList(growable: true);
  final before = missingFrames.length;
  missingFrames.removeWhere((entry) {
    final observedAt = entry['observedAt']?.toString() ?? '';
    return entry['layer'] == parsed.layer &&
        observedAt.startsWith(parsed.observedAtJstPrefix);
  });
  manifest['missingFrames'] = missingFrames;
  final repairs = _list(manifest['repairs']).toList(growable: true)
    ..add({
      'file': expectedFileName,
      'repairedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'method': 'import_hinet_capture_repair_candidate',
    });
  manifest['repairs'] = repairs;
  return before - missingFrames.length;
}

int _repairCaptureManifestRecord(
  Map<String, Object?> captureManifest, {
  required Map<String, Object?> inputJson,
  required int bytes,
  required String sha256Hex,
}) {
  final expectedFileName = inputJson['expectedFileName'].toString();
  var repaired = 0;
  final records = _list(
    captureManifest['records'],
  ).map((entry) => _map(entry)).toList(growable: false);
  for (final record in records) {
    if (record['file'] != expectedFileName) continue;
    repaired += 1;
    record['bytes'] = bytes;
    record['sha256'] = sha256Hex;
    record['ok'] = true;
    record['cacheStatus'] = 'repaired_from_local_candidate';
    record['qualityFlags'] = ['repaired_from_alternate_source'];
    record.remove('error');
    record['repairProvenance'] = {
      'candidatePath': inputJson['candidatePath'],
      'reviewedAtUtc': inputJson['reviewedAtUtc'],
      'reviewer': inputJson['reviewer'],
      'sourceDescription': inputJson['sourceDescription'],
    };
  }
  if (repaired == 1) {
    captureManifest['downloadedGifCount'] =
        (_asInt(captureManifest['downloadedGifCount']) ?? 0) + 1;
    final failedCount = _asInt(captureManifest['failedGifCount']) ?? 0;
    captureManifest['failedGifCount'] = failedCount > 0 ? failedCount - 1 : 0;
  }
  return repaired;
}

void _updateDecision(
  Map<String, Object?> decisionsJson,
  Map<String, Object?> inputJson,
  String sha256Hex,
) {
  final caseId = inputJson['caseId'].toString();
  final cases = _list(
    decisionsJson['cases'],
  ).map((entry) => _map(entry)).toList(growable: true);
  final index = cases.indexWhere((entry) => entry['caseId'] == caseId);
  final existing = cases[index];
  cases[index] = {
    'caseId': caseId,
    'decisionStatus': 'capture_frame_repaired',
    'reviewedAtUtc': inputJson['reviewedAtUtc'],
    'reviewer': inputJson['reviewer'],
    'exclusionApproved': false,
    'excludedFiles': <String>[],
    'exclusionReason': null,
    'repairedFiles': [
      {
        'file': inputJson['expectedFileName'],
        'sha256': sha256Hex,
        'sourceDescription': inputJson['sourceDescription'],
      },
    ],
    'requiredActions': existing['requiredActions'],
    'notes': existing['notes'],
  };
  decisionsJson['cases'] = cases;
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

bool _isGif(List<int> bytes) {
  if (bytes.length < 6) return false;
  final header = String.fromCharCodes(bytes.take(6));
  return header == 'GIF87a' || header == 'GIF89a';
}

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

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String _baseName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  return index < 0 ? normalized : normalized.substring(index + 1);
}

List<Object?> _list(Object? value) => value is List ? value : const [];

List<String> _stringList(Object? value) =>
    _list(value).map((item) => item.toString()).toList(growable: false);

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};

class _ParsedGifName {
  final String layer;
  final String observedAtJstPrefix;

  const _ParsedGifName({
    required this.layer,
    required this.observedAtJstPrefix,
  });

  static _ParsedGifName? parse(String fileName) {
    final match = RegExp(
      r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\.([a-z0-9_]+)\.gif$',
    ).firstMatch(fileName);
    if (match == null) return null;
    return _ParsedGifName(
      layer: match.group(7)!,
      observedAtJstPrefix:
          '${match.group(1)}-${match.group(2)}-${match.group(3)}'
          'T${match.group(4)}:${match.group(5)}:${match.group(6)}',
    );
  }
}
