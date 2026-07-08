import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _defaultReviewPath =
    '.dart_tool/hinet_capture_provenance_review/report.json';
const _defaultOutput = '.dart_tool/hinet_capture_repair_probe/report.json';
const _defaultMarkdown =
    'docs/baselines/hinet_capture_repair_probe.generated.md';
const _defaultTemplateDirectory = '.dart_tool/hinet_capture_repair_probe/files';
const _defaultRoots = [
  'tmp/captures',
  'tmp/quarantine',
  'test/fixtures/source_estimation',
];

void main(List<String> args) {
  final reviewPath = _argument(args, '--review') ?? _defaultReviewPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;
  final templateDirectoryPath =
      _argument(args, '--template-directory') ?? _defaultTemplateDirectory;
  final roots = _arguments(args, '--root');
  final scanRoots = roots.isEmpty ? _defaultRoots : roots;

  final report = _CaptureRepairProbeReport.build(
    reviewFile: File(reviewPath),
    scanRoots: scanRoots,
    templateDirectory: Directory(templateDirectoryPath),
  );

  final templateDirectory = Directory(templateDirectoryPath);
  templateDirectory.createSync(recursive: true);
  for (final template in report.repairInputTemplates) {
    final templateFile = File(template.outputFile);
    templateFile.parent.createSync(recursive: true);
    templateFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(template.filePayload)}\n',
    );
  }

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote Hi-net capture repair probe report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');
  stdout.writeln('templates: ${templateDirectory.path}');

  if (report.errors.isNotEmpty) {
    exitCode = 1;
  }
}

Map<String, Object?> buildHinetCaptureRepairProbeJson({
  String reviewPath = _defaultReviewPath,
  List<String> scanRoots = _defaultRoots,
  String templateDirectory = _defaultTemplateDirectory,
}) {
  return _CaptureRepairProbeReport.build(
    reviewFile: File(reviewPath),
    scanRoots: scanRoots,
    templateDirectory: Directory(templateDirectory),
  ).toJson();
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

List<String> _arguments(List<String> args, String name) {
  final values = <String>[];
  for (var index = 0; index < args.length; index += 1) {
    if (args[index] == name && index + 1 < args.length) {
      values.add(args[index + 1]);
      index += 1;
    }
  }
  return values;
}

class _CaptureRepairProbeReport {
  final String reviewPath;
  final List<String> scanRoots;
  final String templateDirectoryPath;
  final List<_RepairProbeCase> cases;
  final List<String> errors;
  final List<String> warnings;

  const _CaptureRepairProbeReport({
    required this.reviewPath,
    required this.scanRoots,
    required this.templateDirectoryPath,
    required this.cases,
    required this.errors,
    required this.warnings,
  });

  factory _CaptureRepairProbeReport.build({
    required File reviewFile,
    required List<String> scanRoots,
    required Directory templateDirectory,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    final normalizedRoots = scanRoots.toSet().toList(growable: false)..sort();
    final candidateIndex = _LocalCandidateIndex.build(
      normalizedRoots,
      warnings,
    );
    final cases = <_RepairProbeCase>[];

    if (!reviewFile.existsSync()) {
      errors.add('hinet_capture_provenance_review_missing:${reviewFile.path}');
    } else {
      final review =
          jsonDecode(reviewFile.readAsStringSync()) as Map<String, Object?>;
      if (review['schemaVersion'] != 'hinet_capture_provenance_review_v1') {
        errors.add('unexpected_hinet_capture_provenance_review_schema');
      }
      if (review['status'] != 'pass') {
        errors.add('hinet_capture_provenance_review_not_pass');
      }
      for (final rawCase in _list(review['cases'])) {
        final item = _map(rawCase);
        if (item['readyAfterExclusion'] == true) continue;
        final caseId = item['caseId']?.toString() ?? '';
        final affectedFiles = _affectedFiles(item);
        if (affectedFiles.isEmpty) {
          warnings.add('capture_repair_probe_no_affected_file:$caseId');
        }
        cases.add(
          _RepairProbeCase(
            caseId: caseId,
            captureDirectory: item['captureDirectory']?.toString() ?? '',
            decisionStatus: item['decisionStatus']?.toString() ?? '',
            affectedFiles: affectedFiles
                .map(
                  (fileName) => _RepairProbeAffectedFile(
                    caseId: caseId,
                    captureDirectory:
                        item['captureDirectory']?.toString() ?? '',
                    fileName: fileName,
                    candidates: candidateIndex.candidatesFor(fileName),
                    remoteHints: _RemoteRepairHint.forFileName(fileName),
                    templateDirectoryPath: templateDirectory.path,
                  ),
                )
                .toList(growable: false),
          ),
        );
      }
    }

    return _CaptureRepairProbeReport(
      reviewPath: reviewFile.path,
      scanRoots: normalizedRoots,
      templateDirectoryPath: templateDirectory.path,
      cases: cases,
      errors: errors,
      warnings: warnings,
    );
  }

  List<_RepairInputTemplate> get repairInputTemplates => cases
      .expand((item) => item.affectedFiles)
      .map((item) => item.repairInputTemplate)
      .toList(growable: false);

  Map<String, Object?> toJson() {
    final affectedFiles = cases.expand((item) => item.affectedFiles).toList();
    final candidates = affectedFiles.expand((item) => item.candidates).toList();
    final remoteHints = affectedFiles
        .expand((item) => item.remoteHints)
        .toList();
    return {
      'schemaVersion': 'hinet_capture_repair_probe_v1',
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'status': errors.isEmpty ? 'pass' : 'fail',
      'reviewPath': reviewPath,
      'scanRoots': scanRoots,
      'templateDirectory': templateDirectoryPath,
      'summary': {
        'caseCount': cases.length,
        'affectedFileCount': affectedFiles.length,
        'repairInputTemplateCount': repairInputTemplates.length,
        'manualReviewRequiredCount': repairInputTemplates.length,
        'automaticClearanceCount': 0,
        'localCandidateCount': candidates.length,
        'validGifCandidateCount': candidates
            .where((candidate) => candidate.isGif)
            .length,
        'remoteHintCount': remoteHints.length,
        'invalidCandidateCount': candidates
            .where((candidate) => !candidate.isGif)
            .length,
        'repairCandidateReadyCount': cases
            .where((item) => item.repairCandidateReady)
            .length,
        'unresolvedRepairCaseCount': cases
            .where((item) => !item.repairCandidateReady)
            .length,
      },
      'errors': errors,
      'warnings': warnings,
      'cases': cases.map((item) => item.toJson()).toList(),
      'repairInputTemplates': repairInputTemplates
          .map((template) => template.toJson())
          .toList(),
    };
  }

  String toMarkdown() {
    final json = toJson();
    final summary = (json['summary'] as Map).cast<String, Object?>();
    final buffer = StringBuffer()
      ..writeln('# Hi-net Capture Repair Probe')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Review report: `$reviewPath`')
      ..writeln('- Scan roots: `${scanRoots.join('`, `')}`')
      ..writeln('- Repair input template directory: `$templateDirectoryPath`')
      ..writeln('- Cases: `${summary['caseCount']}`')
      ..writeln('- Affected files: `${summary['affectedFileCount']}`')
      ..writeln(
        '- Repair input templates: `${summary['repairInputTemplateCount']}`',
      )
      ..writeln(
        '- Manual-review required: '
        '`${summary['manualReviewRequiredCount']}`',
      )
      ..writeln('- Automatic clearances: `0`')
      ..writeln('- Local candidates: `${summary['localCandidateCount']}`')
      ..writeln(
        '- Valid GIF candidates: `${summary['validGifCandidateCount']}`',
      )
      ..writeln('- Remote retrieval hints: `${summary['remoteHintCount']}`')
      ..writeln(
        '- Repair-candidate ready cases: `${summary['repairCandidateReadyCount']}`',
      )
      ..writeln(
        '- Unresolved repair cases: `${summary['unresolvedRepairCaseCount']}`',
      )
      ..writeln()
      ..writeln('## Validation')
      ..writeln()
      ..writeln(
        errors.isEmpty
            ? '- Errors: none'
            : '- Errors: `${errors.join('`, `')}`',
      )
      ..writeln(
        warnings.isEmpty
            ? '- Warnings: none'
            : '- Warnings: `${warnings.join('`, `')}`',
      )
      ..writeln()
      ..writeln('## Cases')
      ..writeln()
      ..writeln(
        '| Case | Decision | Affected file | Candidates | Valid GIFs | Remote hints | Ready |',
      )
      ..writeln('| --- | --- | --- | ---: | ---: | ---: | --- |');
    for (final item in cases) {
      for (final affectedFile in item.affectedFiles) {
        buffer.writeln(
          '| `${item.caseId}` | `${item.decisionStatus}` | '
          '`${affectedFile.fileName}` | ${affectedFile.candidates.length} | '
          '${affectedFile.validGifCandidates.length} | '
          '${affectedFile.remoteHints.length} | '
          '${item.repairCandidateReady ? 'yes' : 'no'} |',
        );
      }
    }
    buffer
      ..writeln()
      ..writeln('## Remote Retrieval Hints')
      ..writeln()
      ..writeln('| Affected file | Source | URL | Notes |')
      ..writeln('| --- | --- | --- | --- |');
    for (final item in cases) {
      for (final affectedFile in item.affectedFiles) {
        if (affectedFile.remoteHints.isEmpty) {
          buffer.writeln(
            '| `${affectedFile.fileName}` | - | - | no deterministic URL hint |',
          );
          continue;
        }
        for (final hint in affectedFile.remoteHints) {
          buffer.writeln(
            '| `${affectedFile.fileName}` | `${hint.source}` | '
            '<${hint.url}> | ${hint.notes} |',
          );
        }
      }
    }
    buffer
      ..writeln()
      ..writeln('## Repair Import Templates')
      ..writeln()
      ..writeln(
        '| Case | Affected file | Template | Candidate status | Dry-run |',
      )
      ..writeln('| --- | --- | --- | --- | --- |');
    for (final template in repairInputTemplates) {
      buffer.writeln(
        '| `${template.caseId}` | `${template.expectedFileName}` | '
        '`${template.outputFile}` | `${template.candidateStatus}` | '
        '`${template.dryRunCommand}` |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Decision')
      ..writeln()
      ..writeln(
        '- This probe does not copy files into a capture package and does not '
        'approve exclusions.',
      )
      ..writeln(
        '- A found GIF is only a repair candidate. A reviewer still needs to '
        'inspect provenance before clearing the capture blocker.',
      )
      ..writeln(
        '- Filling a repair import template and running the importer only '
        'repairs the capture package after explicit review; it does not change '
        'source truth, split assignment or production behavior.',
      );
    return buffer.toString();
  }
}

class _RepairProbeCase {
  final String caseId;
  final String captureDirectory;
  final String decisionStatus;
  final List<_RepairProbeAffectedFile> affectedFiles;

  const _RepairProbeCase({
    required this.caseId,
    required this.captureDirectory,
    required this.decisionStatus,
    required this.affectedFiles,
  });

  bool get repairCandidateReady =>
      affectedFiles.isNotEmpty &&
      affectedFiles.every((item) => item.validGifCandidates.isNotEmpty);

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'captureDirectory': captureDirectory,
    'decisionStatus': decisionStatus,
    'repairCandidateReady': repairCandidateReady,
    'affectedFiles': affectedFiles.map((item) => item.toJson()).toList(),
  };
}

class _RepairProbeAffectedFile {
  final String caseId;
  final String captureDirectory;
  final String fileName;
  final List<_LocalRepairCandidate> candidates;
  final List<_RemoteRepairHint> remoteHints;
  final String templateDirectoryPath;

  const _RepairProbeAffectedFile({
    required this.caseId,
    required this.captureDirectory,
    required this.fileName,
    required this.candidates,
    required this.remoteHints,
    required this.templateDirectoryPath,
  });

  List<_LocalRepairCandidate> get validGifCandidates =>
      candidates.where((item) => item.isGif).toList(growable: false);

  _RepairInputTemplate get repairInputTemplate =>
      _RepairInputTemplate.fromAffectedFile(this);

  Map<String, Object?> toJson() => {
    'fileName': fileName,
    'candidateCount': candidates.length,
    'validGifCandidateCount': validGifCandidates.length,
    'repairInputTemplate': repairInputTemplate.toJson(),
    'candidates': candidates.map((item) => item.toJson()).toList(),
    'remoteHints': remoteHints.map((item) => item.toJson()).toList(),
  };
}

class _RepairInputTemplate {
  final String caseId;
  final String expectedFileName;
  final String outputFile;
  final String dryRunCommand;
  final String candidateStatus;
  final Map<String, Object?> filePayload;

  const _RepairInputTemplate({
    required this.caseId,
    required this.expectedFileName,
    required this.outputFile,
    required this.dryRunCommand,
    required this.candidateStatus,
    required this.filePayload,
  });

  factory _RepairInputTemplate.fromAffectedFile(
    _RepairProbeAffectedFile affectedFile,
  ) {
    final validCandidates = affectedFile.validGifCandidates;
    final selectedCandidate = validCandidates.length == 1
        ? validCandidates.single
        : null;
    final outputFile =
        '${affectedFile.templateDirectoryPath}/'
                '${affectedFile.caseId}.${affectedFile.fileName}.repair.json'
            .replaceAll('\\', '/');
    final candidateStatus = selectedCandidate == null
        ? validCandidates.isEmpty
              ? 'awaiting_local_gif_candidate'
              : 'multiple_candidates_need_review'
        : 'prefilled_from_single_valid_candidate';
    return _RepairInputTemplate(
      caseId: affectedFile.caseId,
      expectedFileName: affectedFile.fileName,
      outputFile: outputFile,
      dryRunCommand:
          'dart run tools\\import_hinet_capture_repair_candidate.dart '
          '--input $outputFile --dry-run',
      candidateStatus: candidateStatus,
      filePayload: {
        '_instructions': [
          'Copy a reviewed local GIF candidate path into candidatePath.',
          'Set expectedSha256 to the SHA-256 printed by the repair probe for that exact file.',
          'Replace every <fill-...> placeholder before running the dry-run command.',
          'Do not add credentials, cookies, sessions, tokens, usernames or passwords.',
          'Do not remotely fetch kmoni GIFs older than 3 hours; historical URL hints are provenance only.',
          'Run this template with --dry-run first; only run without --dry-run after review.',
        ],
        '_captureIssue': {
          'caseId': affectedFile.caseId,
          'captureDirectory': affectedFile.captureDirectory,
          'expectedFileName': affectedFile.fileName,
          'validCandidateCount': validCandidates.length,
          'candidateStatus': candidateStatus,
          'candidates': affectedFile.candidates
              .map((candidate) => candidate.toJson())
              .toList(),
          'remoteHints': affectedFile.remoteHints
              .map((hint) => hint.toJson())
              .toList(),
        },
        'caseId': affectedFile.caseId,
        'decisionStatus': 'capture_frame_repaired',
        'reviewedAtUtc': '<fill-reviewed-at-utc>',
        'reviewer': '<fill-reviewer-id>',
        'captureDirectory': affectedFile.captureDirectory,
        'candidatePath':
            selectedCandidate?.path ?? '<fill-local-gif-candidate-path>',
        'expectedFileName': affectedFile.fileName,
        'expectedSha256':
            selectedCandidate?.sha256Hex ?? '<fill-candidate-sha256>',
        'sourceDescription': '<fill-reviewed-source-description>',
      },
    );
  }

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'expectedFileName': expectedFileName,
    'outputFile': outputFile,
    'dryRunCommand': dryRunCommand,
    'candidateStatus': candidateStatus,
    'manualReviewRequired': true,
    'automaticClearance': false,
    'templateFields': [
      'caseId',
      'decisionStatus',
      'reviewedAtUtc',
      'reviewer',
      'captureDirectory',
      'candidatePath',
      'expectedFileName',
      'expectedSha256',
      'sourceDescription',
    ],
  };
}

class _RemoteRepairHint {
  final String source;
  final String url;
  final String notes;
  final bool remoteRetrievalAllowed;
  final int maxRemoteAgeHours;

  const _RemoteRepairHint({
    required this.source,
    required this.url,
    required this.notes,
    required this.remoteRetrievalAllowed,
    required this.maxRemoteAgeHours,
  });

  static List<_RemoteRepairHint> forFileName(String fileName) {
    final match = RegExp(
      r'^(\d{4})(\d{2})(\d{2})(\d{6})\.([a-z0-9_]+)\.gif$',
    ).firstMatch(fileName);
    if (match == null) return const <_RemoteRepairHint>[];

    final year = match.group(1)!;
    final month = match.group(2)!;
    final day = match.group(3)!;
    final layer = match.group(5)!;
    return [
      _RemoteRepairHint(
        source: 'nied_kmoni_realtime_image',
        url:
            'https://www.kmoni.bosai.go.jp/data/map_img/RealTimeImg/'
            '$layer/$year/$month/$day/$fileName',
        notes:
            'Historical URL hint only. Do not remotely fetch kmoni GIFs '
            'older than 3 hours; use a local/mirrored archive copy or a '
            'reviewed exclusion decision.',
        remoteRetrievalAllowed: false,
        maxRemoteAgeHours: 3,
      ),
    ];
  }

  Map<String, Object?> toJson() => {
    'source': source,
    'url': url,
    'notes': notes,
    'remoteRetrievalAllowed': remoteRetrievalAllowed,
    'maxRemoteAgeHours': maxRemoteAgeHours,
  };
}

class _LocalCandidateIndex {
  final Map<String, List<_LocalRepairCandidate>> byFileName;

  const _LocalCandidateIndex(this.byFileName);

  factory _LocalCandidateIndex.build(
    List<String> roots,
    List<String> warnings,
  ) {
    final byFileName = <String, List<_LocalRepairCandidate>>{};
    for (final root in roots) {
      final directory = Directory(root);
      if (!directory.existsSync()) {
        warnings.add('capture_repair_probe_scan_root_missing:$root');
        continue;
      }
      for (final entity in directory.listSync(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final fileName = _baseName(entity.path);
        if (!fileName.toLowerCase().endsWith('.gif')) continue;
        final candidate = _LocalRepairCandidate.fromFile(root, entity);
        byFileName.putIfAbsent(fileName, () => []).add(candidate);
      }
    }
    for (final entries in byFileName.values) {
      entries.sort((left, right) => left.path.compareTo(right.path));
    }
    return _LocalCandidateIndex(byFileName);
  }

  List<_LocalRepairCandidate> candidatesFor(String fileName) =>
      byFileName[fileName] ?? const <_LocalRepairCandidate>[];
}

class _LocalRepairCandidate {
  final String scanRoot;
  final String path;
  final int bytes;
  final String sha256Hex;
  final bool isGif;

  const _LocalRepairCandidate({
    required this.scanRoot,
    required this.path,
    required this.bytes,
    required this.sha256Hex,
    required this.isGif,
  });

  factory _LocalRepairCandidate.fromFile(String scanRoot, File file) {
    final bytes = file.readAsBytesSync();
    return _LocalRepairCandidate(
      scanRoot: scanRoot,
      path: file.path,
      bytes: bytes.length,
      sha256Hex: sha256.convert(bytes).toString(),
      isGif: _isGif(bytes),
    );
  }

  Map<String, Object?> toJson() => {
    'scanRoot': scanRoot,
    'path': path,
    'bytes': bytes,
    'sha256': sha256Hex,
    'isGif': isGif,
  };
}

List<String> _affectedFiles(Map<String, Object?> item) {
  final files = <String>{};
  for (final rawEvidence in _list(item['blockingEvidence'])) {
    final evidence = _map(rawEvidence);
    final affectedFile = evidence['affectedFile']?.toString();
    if (affectedFile != null && affectedFile.trim().isNotEmpty) {
      files.add(affectedFile.trim());
    }
  }
  files.addAll(
    _list(item['excludedFiles'])
        .map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty),
  );
  return files.toList(growable: false)..sort();
}

bool _isGif(List<int> bytes) {
  if (bytes.length < 6) return false;
  final header = String.fromCharCodes(bytes.take(6));
  return header == 'GIF87a' || header == 'GIF89a';
}

String _baseName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  return index < 0 ? normalized : normalized.substring(index + 1);
}

List<Object?> _list(Object? value) => value is List ? value : const [];

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};
