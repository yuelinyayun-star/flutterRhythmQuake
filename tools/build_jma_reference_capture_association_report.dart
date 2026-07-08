import 'dart:convert';
import 'dart:io';

const _defaultManifest = 'docs/data/jma_reference_event_candidates.json';
const _defaultOutput =
    '.dart_tool/jma_reference_capture_association/report.json';
const _defaultMarkdown =
    'docs/baselines/jma_reference_capture_association.generated.md';

void main(List<String> args) {
  final manifestPath = _argument(args, '--manifest') ?? _defaultManifest;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = _JmaReferenceCaptureAssociationReport.build(
    manifestFile: File(manifestPath),
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote JMA reference capture-association report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report.errors.isNotEmpty) {
    exitCode = 1;
  }
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

class _JmaReferenceCaptureAssociationReport {
  final String manifestPath;
  final List<_JmaReferenceCaptureCase> cases;
  final List<String> errors;
  final List<String> warnings;

  const _JmaReferenceCaptureAssociationReport({
    required this.manifestPath,
    required this.cases,
    required this.errors,
    required this.warnings,
  });

  factory _JmaReferenceCaptureAssociationReport.build({
    required File manifestFile,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    final cases = <_JmaReferenceCaptureCase>[];
    final localIndex = _LocalReplayIndex.scan();

    if (!manifestFile.existsSync()) {
      errors.add(
        'jma_reference_candidate_manifest_missing:${manifestFile.path}',
      );
    } else {
      final manifest =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
      if (manifest['datasetId'] != 'jma_reference_event_candidates_v1') {
        errors.add('unexpected_jma_reference_candidate_dataset_id');
      }
      for (final rawEvent in _list(manifest['events'])) {
        final event = _map(rawEvent);
        final caseItem = _JmaReferenceCaptureCase.fromEvent(
          event,
          localIndex,
          errors,
        );
        cases.add(caseItem);
      }
    }

    cases.sort((left, right) => left.eventId.compareTo(right.eventId));
    return _JmaReferenceCaptureAssociationReport(
      manifestPath: manifestFile.path,
      cases: cases,
      errors: errors,
      warnings: warnings,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': 'jma_reference_capture_association_v1',
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'status': errors.isEmpty ? 'pass' : 'fail',
      'manifestPath': manifestPath,
      'summary': {
        'eventCount': cases.length,
        'pendingCaptureCount': cases
            .where((item) => item.status.contains('pending_capture'))
            .length,
        'captureAssociatedCount': cases
            .where((item) => item.captureDirectory != null)
            .length,
        'captureAssociationMissingCount': cases
            .where(
              (item) =>
                  item.captureDirectory == null &&
                  item.localCaptureCandidateCount == 0 &&
                  item.localFixtureCandidateCount == 0,
            )
            .length,
        'localCaptureCandidateMatchCount': cases.fold<int>(
          0,
          (total, item) => total + item.localCaptureCandidateCount,
        ),
        'localFixtureCandidateMatchCount': cases.fold<int>(
          0,
          (total, item) => total + item.localFixtureCandidateCount,
        ),
        'captureDirectoryMissingCount': cases
            .where(
              (item) =>
                  item.captureDirectory != null && !item.captureDirectoryExists,
            )
            .length,
        'captureReplayManifestMissingCount': cases
            .where(
              (item) =>
                  item.captureDirectory != null && !item.replayManifestExists,
            )
            .length,
      },
      'errors': errors,
      'warnings': warnings,
      'cases': cases.map((item) => item.toJson()).toList(),
    };
  }

  String toMarkdown() {
    final json = toJson();
    final summary = (json['summary'] as Map).cast<String, Object?>();
    final buffer = StringBuffer()
      ..writeln('# JMA Reference Capture Association')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Manifest: `$manifestPath`')
      ..writeln('- Events: `${summary['eventCount']}`')
      ..writeln('- Pending capture: `${summary['pendingCaptureCount']}`')
      ..writeln('- Capture associated: `${summary['captureAssociatedCount']}`')
      ..writeln(
        '- Missing local association: '
        '`${summary['captureAssociationMissingCount']}`',
      )
      ..writeln(
        '- Local capture candidate matches: '
        '`${summary['localCaptureCandidateMatchCount']}`',
      )
      ..writeln(
        '- Local fixture candidate matches: '
        '`${summary['localFixtureCandidateMatchCount']}`',
      )
      ..writeln(
        '- Capture directory missing: '
        '`${summary['captureDirectoryMissingCount']}`',
      )
      ..writeln(
        '- Replay manifest missing: '
        '`${summary['captureReplayManifestMissingCount']}`',
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
        '| Event | Status | Origin JST | Capture | Replay manifest | Local captures | Local fixtures |',
      )
      ..writeln('| --- | --- | --- | --- | --- | --- | --- |');
    for (final item in cases) {
      buffer.writeln(
        '| `${item.eventId}` | `${item.status}` | `${item.originTimeJst}` | '
        '${item.captureDirectoryExists ? 'yes' : 'no'} | '
        '${item.replayManifestExists ? 'yes' : 'no'} | '
        '`${item.localCaptureCandidates.join('`, `')}` | '
        '`${item.localFixtureCandidates.join('`, `')}` |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Decision')
      ..writeln()
      ..writeln(
        '- This report only checks whether a recent JMA reference candidate '
        'has a local replay/capture association. It does not promote the '
        'candidate into frozen metrics and does not mark final catalog truth.',
      )
      ..writeln(
        '- Pending candidates with no local matches remain reference-only and '
        'must wait for a replay package or a later explicit exclusion.',
      );
    return buffer.toString();
  }
}

class _JmaReferenceCaptureCase {
  final String eventId;
  final String status;
  final String originTimeJst;
  final String? captureDirectory;
  final bool captureDirectoryExists;
  final bool replayManifestExists;
  final List<String> localCaptureCandidates;
  final List<String> localFixtureCandidates;

  const _JmaReferenceCaptureCase({
    required this.eventId,
    required this.status,
    required this.originTimeJst,
    required this.captureDirectory,
    required this.captureDirectoryExists,
    required this.replayManifestExists,
    required this.localCaptureCandidates,
    required this.localFixtureCandidates,
  });

  int get localCaptureCandidateCount => localCaptureCandidates.length;

  int get localFixtureCandidateCount => localFixtureCandidates.length;

  factory _JmaReferenceCaptureCase.fromEvent(
    Map<String, Object?> event,
    _LocalReplayIndex localIndex,
    List<String> errors,
  ) {
    final eventId = event['eventId']?.toString() ?? '';
    if (eventId.isEmpty) {
      errors.add('jma_reference_capture_event_missing_id');
    }
    final originTimeJst = event['originTimeJst']?.toString() ?? '';
    final captureDirectory = event['captureDirectory']?.toString();
    final captureDir = captureDirectory == null
        ? null
        : Directory(captureDirectory);
    final captureDirectoryExists = captureDir?.existsSync() ?? false;
    final replayManifestExists =
        captureDirectoryExists &&
        (File('${captureDir!.path}/manifest.json').existsSync() ||
            File('${captureDir.path}/capture_manifest.json').existsSync());
    if (captureDirectory != null && !captureDirectoryExists) {
      errors.add('jma_reference_capture_directory_missing:$eventId');
    }
    if (captureDirectory != null && !replayManifestExists) {
      errors.add('jma_reference_replay_manifest_missing:$eventId');
    }
    final matchTokens = _matchTokens(eventId, originTimeJst);
    return _JmaReferenceCaptureCase(
      eventId: eventId,
      status: event['status']?.toString() ?? '',
      originTimeJst: originTimeJst,
      captureDirectory: captureDirectory,
      captureDirectoryExists: captureDirectoryExists,
      replayManifestExists: replayManifestExists,
      localCaptureCandidates: localIndex.captureDirectories
          .where((path) => _matchesAnyToken(path, matchTokens))
          .toList(growable: false),
      localFixtureCandidates: localIndex.fixtureFiles
          .where((path) => _matchesAnyToken(path, matchTokens))
          .toList(growable: false),
    );
  }

  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'status': status,
    'originTimeJst': originTimeJst,
    'captureDirectory': captureDirectory,
    'captureDirectoryExists': captureDirectoryExists,
    'replayManifestExists': replayManifestExists,
    'localCaptureCandidates': localCaptureCandidates,
    'localFixtureCandidates': localFixtureCandidates,
  };
}

class _LocalReplayIndex {
  final List<String> captureDirectories;
  final List<String> fixtureFiles;

  const _LocalReplayIndex({
    required this.captureDirectories,
    required this.fixtureFiles,
  });

  factory _LocalReplayIndex.scan() {
    return _LocalReplayIndex(
      captureDirectories: _listDirectories(Directory('tmp/captures')),
      fixtureFiles: _listFiles(
        Directory('test/fixtures/source_estimation'),
        extension: '.json',
      ),
    );
  }
}

List<String> _matchTokens(String eventId, String originTimeJst) {
  final tokens = <String>{};
  final normalizedEvent = _normalize(eventId);
  if (normalizedEvent.isNotEmpty) {
    tokens.add(normalizedEvent);
  }
  final parsed = DateTime.tryParse(originTimeJst);
  if (parsed != null) {
    final ymd = _two(parsed.year ~/ 100) + _two(parsed.year % 100);
    final dateToken = '$ymd${_two(parsed.month)}${_two(parsed.day)}';
    final minuteToken = '${_two(parsed.hour)}${_two(parsed.minute)}';
    tokens
      ..add('${dateToken}_$minuteToken')
      ..add('$dateToken$minuteToken');
  }
  tokens.removeWhere((token) => token.length < 4);
  return tokens.toList(growable: false);
}

bool _matchesAnyToken(String path, List<String> tokens) {
  final normalized = _normalize(path);
  return tokens.any(normalized.contains);
}

String _normalize(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
}

String _two(int value) => value.toString().padLeft(2, '0');

List<String> _listDirectories(Directory directory) {
  if (!directory.existsSync()) return const [];
  return directory
      .listSync()
      .whereType<Directory>()
      .map((entry) => entry.path.replaceAll('\\', '/'))
      .toList(growable: false)
    ..sort();
}

List<String> _listFiles(Directory directory, {required String extension}) {
  if (!directory.existsSync()) return const [];
  return directory
      .listSync()
      .whereType<File>()
      .where((entry) => entry.path.endsWith(extension))
      .map((entry) => entry.path.replaceAll('\\', '/'))
      .toList(growable: false)
    ..sort();
}

List<Object?> _list(Object? value) {
  if (value is List) return value;
  return const [];
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}
