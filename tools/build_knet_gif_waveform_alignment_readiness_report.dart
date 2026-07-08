import 'dart:convert';
import 'dart:io';
import 'dart:math';

const _defaultFixtureDirectory = 'test/fixtures/source_estimation';
const _defaultWaveformManifest =
    'tmp/knet_waveform_seed_download_manifest.json';
const _defaultDownloadReport = 'tmp/knet_downloads/download_report.json';
const _defaultFeatureIndex =
    'tmp/knet_features/knet_waveform_feature_index.json';
const _defaultOutput =
    '.dart_tool/knet_gif_waveform_alignment_readiness/report.json';
const _defaultMarkdown =
    'docs/baselines/knet_gif_waveform_alignment_readiness.generated.md';

void main(List<String> args) {
  final fixtureDirectory =
      _argument(args, '--fixtures') ?? _defaultFixtureDirectory;
  final waveformManifestPath =
      _argument(args, '--waveform-manifest') ?? _defaultWaveformManifest;
  final downloadReportPath =
      _argument(args, '--download-report') ?? _defaultDownloadReport;
  final featureIndexPath =
      _argument(args, '--feature-index') ?? _defaultFeatureIndex;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = _ReadinessReport.build(
    fixtureDirectory: Directory(fixtureDirectory),
    waveformManifestFile: File(waveformManifestPath),
    downloadReportFile: File(downloadReportPath),
    featureIndexFile: File(featureIndexPath),
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote K-NET/GIF waveform alignment readiness report');
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

class _ReadinessReport {
  final String fixtureDirectoryPath;
  final String waveformManifestPath;
  final String downloadReportPath;
  final String featureIndexPath;
  final List<_CaptureCase> captureCases;
  final List<_WaveformCandidate> waveformCandidates;
  final List<_WaveformOnlyCase> waveformOnlyCases;
  final List<String> errors;
  final List<String> warnings;

  const _ReadinessReport({
    required this.fixtureDirectoryPath,
    required this.waveformManifestPath,
    required this.downloadReportPath,
    required this.featureIndexPath,
    required this.captureCases,
    required this.waveformCandidates,
    required this.waveformOnlyCases,
    required this.errors,
    required this.warnings,
  });

  factory _ReadinessReport.build({
    required Directory fixtureDirectory,
    required File waveformManifestFile,
    required File downloadReportFile,
    required File featureIndexFile,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    final captureFixtures = _loadCaptureFixtures(fixtureDirectory, errors);
    final waveformCandidates = _loadWaveformCandidates(
      waveformManifestFile,
      errors,
    );
    final downloadSummaryByEventId = _loadDownloadSummaryByEventId(
      downloadReportFile,
      warnings,
    );
    final featureEntriesByEventId = _loadFeatureEntriesByEventId(
      featureIndexFile,
      warnings,
    );
    final captureCases = <_CaptureCase>[];
    final matchedWaveformEventIds = <String>{};

    for (final fixture in captureFixtures) {
      final match = _matchWaveformCandidate(fixture, waveformCandidates);
      if (match?.candidate.eventId case final eventId?) {
        matchedWaveformEventIds.add(eventId);
      }
      final downloadSummary = match == null
          ? null
          : downloadSummaryByEventId[match.candidate.eventId];
      final featureEntries = match == null
          ? const <_FeatureEntry>[]
          : featureEntriesByEventId[match.candidate.eventId] ?? const [];
      captureCases.add(
        _CaptureCase.fromFixture(
          fixture: fixture,
          match: match,
          downloadSummary: downloadSummary,
          featureEntries: featureEntries,
        ),
      );
    }

    captureCases.sort((a, b) => a.caseId.compareTo(b.caseId));
    waveformCandidates.sort((a, b) => a.eventId.compareTo(b.eventId));
    final waveformOnlyCases =
        waveformCandidates
            .where(
              (candidate) =>
                  !matchedWaveformEventIds.contains(candidate.eventId),
            )
            .map(
              (candidate) => _WaveformOnlyCase(
                eventId: candidate.eventId,
                originTimeJst: candidate.originTimeJst,
                region: candidate.eventLabels.join(','),
                niedDirectoryId: candidate.niedDirectoryId,
                featureCount:
                    featureEntriesByEventId[candidate.eventId]?.length ?? 0,
                downloadSummary: downloadSummaryByEventId[candidate.eventId],
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => a.eventId.compareTo(b.eventId));

    return _ReadinessReport(
      fixtureDirectoryPath: fixtureDirectory.path,
      waveformManifestPath: waveformManifestFile.path,
      downloadReportPath: downloadReportFile.path,
      featureIndexPath: featureIndexFile.path,
      captureCases: captureCases,
      waveformCandidates: waveformCandidates,
      waveformOnlyCases: waveformOnlyCases,
      errors: errors,
      warnings: warnings,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': 'knet_gif_waveform_alignment_readiness_v1',
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'status': errors.isEmpty ? 'pass' : 'fail',
      'fixtureDirectoryPath': fixtureDirectoryPath,
      'waveformManifestPath': waveformManifestPath,
      'downloadReportPath': downloadReportPath,
      'featureIndexPath': featureIndexPath,
      'summary': {
        'captureFixtureCount': captureCases.length,
        'waveformCandidateCount': waveformCandidates.length,
        'matchedCaptureWaveformCandidateCount': captureCases
            .where((item) => item.matchedWaveformEventId != null)
            .length,
        'readyForAlignmentCount': captureCases
            .where((item) => item.readiness == 'ready_for_alignment')
            .length,
        'candidateDirectoryUnconfirmedCount': captureCases
            .where(
              (item) => item.readiness == 'candidate_directory_id_unconfirmed',
            )
            .length,
        'waveformDownloadedNeedsFeatureBuildCount': captureCases
            .where(
              (item) =>
                  item.readiness == 'waveform_downloaded_needs_feature_build',
            )
            .length,
        'captureOnlyNeedsWaveformCandidateCount': captureCases
            .where(
              (item) =>
                  item.readiness == 'capture_only_needs_waveform_candidate',
            )
            .length,
        'waveformOnlyNoLocalCaptureCount': waveformOnlyCases.length,
      },
      'errors': errors,
      'warnings': warnings,
      'captureCases': captureCases.map((item) => item.toJson()).toList(),
      'waveformOnlyCases': waveformOnlyCases
          .map((item) => item.toJson())
          .toList(),
    };
  }

  String toMarkdown() {
    final json = toJson();
    final summary = (json['summary'] as Map).cast<String, Object?>();
    final buffer = StringBuffer()
      ..writeln('# K-NET GIF/Waveform Alignment Readiness')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Fixture directory: `$fixtureDirectoryPath`')
      ..writeln('- Waveform manifest: `$waveformManifestPath`')
      ..writeln('- Download report: `$downloadReportPath`')
      ..writeln('- Feature index: `$featureIndexPath`')
      ..writeln('- Capture fixtures: `${summary['captureFixtureCount']}`')
      ..writeln('- Waveform candidates: `${summary['waveformCandidateCount']}`')
      ..writeln(
        '- Matched capture/candidate pairs: '
        '`${summary['matchedCaptureWaveformCandidateCount']}`',
      )
      ..writeln('- Ready for alignment: `${summary['readyForAlignmentCount']}`')
      ..writeln(
        '- Directory id unconfirmed: '
        '`${summary['candidateDirectoryUnconfirmedCount']}`',
      )
      ..writeln(
        '- Downloaded but feature build pending: '
        '`${summary['waveformDownloadedNeedsFeatureBuildCount']}`',
      )
      ..writeln(
        '- Capture-only cases needing waveform candidate: '
        '`${summary['captureOnlyNeedsWaveformCandidateCount']}`',
      )
      ..writeln(
        '- Waveform-only cases without local capture: '
        '`${summary['waveformOnlyNoLocalCaptureCount']}`',
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
      ..writeln('## Capture Cases')
      ..writeln()
      ..writeln(
        '| Case | Origin JST | Region | Match | Directory id | Downloads | Features | Readiness | Next action |',
      )
      ..writeln('| --- | --- | --- | --- | --- | --- | --- | --- | --- |');
    for (final item in captureCases) {
      buffer.writeln(
        '| `${item.caseId}` | `${item.originTimeJst}` | `${item.region}` | '
        '${item.matchedWaveformEventId == null ? '-' : '`${item.matchedWaveformEventId}`'} | '
        '${item.matchedNiedDirectoryId == null ? '-' : '`${item.matchedNiedDirectoryId}`'} | '
        '`${item.downloadStatus}` | `${item.featureCount}` | '
        '`${item.readiness}` | `${item.nextAction}` |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Waveform-only Candidates')
      ..writeln()
      ..writeln('| Event | Origin JST | Directory id | Features | Downloads |')
      ..writeln('| --- | --- | --- | ---: | --- |');
    for (final item in waveformOnlyCases) {
      buffer.writeln(
        '| `${item.eventId}` | `${item.originTimeJst}` | '
        '`${item.niedDirectoryId}` | `${item.featureCount}` | '
        '`${item.downloadStatus}` |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Decision')
      ..writeln()
      ..writeln(
        '- This report tracks whether local GIF capture fixtures already have '
        'a same-event official waveform path. It does not promote any case '
        'into frozen metrics and does not mutate runtime source estimation.',
      )
      ..writeln(
        '- `candidate_directory_id_unconfirmed` means the case is the current '
        'best overlap candidate, but its NIED waveform directory id still '
        'needs confirmation before download and feature generation.',
      )
      ..writeln(
        '- `capture_only_needs_waveform_candidate` means local GIF is present '
        'but the event has not yet been seeded into the waveform manifest.',
      );
    return buffer.toString();
  }
}

List<_CaptureFixture> _loadCaptureFixtures(
  Directory fixtureDirectory,
  List<String> errors,
) {
  if (!fixtureDirectory.existsSync()) {
    errors.add('capture_fixture_directory_missing:${fixtureDirectory.path}');
    return const [];
  }
  final fixtures = <_CaptureFixture>[];
  for (final entity in fixtureDirectory.listSync()) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final json = jsonDecode(entity.readAsStringSync()) as Map<String, Object?>;
    if (json['caseType']?.toString() != 'event') continue;
    final captureDirectory = json['captureDirectory']?.toString();
    final truth = _map(json['truth']);
    final classification = _map(json['classification']);
    final caseId = json['caseId']?.toString() ?? '';
    if (caseId.isEmpty || captureDirectory == null || truth.isEmpty) continue;
    final originTimeJst = truth['originTimeJst']?.toString();
    final latitude = _toDouble(truth['latitude']);
    final longitude = _toDouble(truth['longitude']);
    final magnitude = _toDouble(truth['magnitude']);
    if (originTimeJst == null || latitude == null || longitude == null) {
      continue;
    }
    fixtures.add(
      _CaptureFixture(
        caseId: caseId,
        originTimeJst: originTimeJst,
        originTime: _parseJst(originTimeJst),
        latitude: latitude,
        longitude: longitude,
        magnitude: magnitude,
        region: classification['region']?.toString() ?? '',
        truthSource: truth['source']?.toString() ?? '',
        captureDirectory: captureDirectory,
      ),
    );
  }
  return fixtures;
}

List<_WaveformCandidate> _loadWaveformCandidates(
  File manifestFile,
  List<String> errors,
) {
  if (!manifestFile.existsSync()) {
    errors.add('waveform_manifest_missing:${manifestFile.path}');
    return const [];
  }
  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
  final events = _list(manifest['events']);
  return events
      .map((rawEvent) {
        final event = _map(rawEvent);
        final originTimeJst = event['originTimeJst']?.toString() ?? '';
        return _WaveformCandidate(
          eventId: event['eventId']?.toString() ?? '',
          originTimeJst: originTimeJst,
          originTime: DateTime.parse(originTimeJst),
          latitude: _toDouble(event['latitude']) ?? 0,
          longitude: _toDouble(event['longitude']) ?? 0,
          magnitude: _toDouble(event['magnitude']),
          niedDirectoryId: event['niedDirectoryId']?.toString() ?? '',
          source: event['source']?.toString() ?? '',
          notes: event['notes']?.toString() ?? '',
          eventLabels: _stringList(event['eventLabels']),
        );
      })
      .toList(growable: false);
}

Map<String, _DownloadSummary> _loadDownloadSummaryByEventId(
  File reportFile,
  List<String> warnings,
) {
  if (!reportFile.existsSync()) {
    warnings.add('download_report_missing');
    return const {};
  }
  final report =
      jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
  final records = _list(report['records']);
  final grouped = <String, List<Map<String, Object?>>>{};
  for (final rawRecord in records) {
    final record = _map(rawRecord);
    final eventId = record['eventId']?.toString();
    if (eventId == null || eventId.isEmpty) continue;
    grouped.putIfAbsent(eventId, () => []).add(record);
  }
  return {
    for (final entry in grouped.entries)
      entry.key: _DownloadSummary.fromRecords(entry.value),
  };
}

Map<String, List<_FeatureEntry>> _loadFeatureEntriesByEventId(
  File featureIndexFile,
  List<String> warnings,
) {
  if (!featureIndexFile.existsSync()) {
    warnings.add('feature_index_missing');
    return const {};
  }
  final report =
      jsonDecode(featureIndexFile.readAsStringSync()) as Map<String, Object?>;
  final entries = _list(report['entries']);
  final grouped = <String, List<_FeatureEntry>>{};
  for (final rawEntry in entries) {
    final entry = _map(rawEntry);
    final eventId = entry['eventId']?.toString();
    if (eventId == null || eventId.isEmpty) continue;
    grouped
        .putIfAbsent(eventId, () => [])
        .add(
          _FeatureEntry(
            format: entry['format']?.toString() ?? '',
            featurePackagePath: entry['featurePackagePath']?.toString() ?? '',
          ),
        );
  }
  return grouped;
}

_CandidateMatch? _matchWaveformCandidate(
  _CaptureFixture fixture,
  List<_WaveformCandidate> candidates,
) {
  _CandidateMatch? best;
  for (final candidate in candidates) {
    final timeDeltaSeconds =
        (fixture.originTime.difference(candidate.originTime).inSeconds).abs();
    if (timeDeltaSeconds > 120) continue;
    final distanceKm = _haversineKm(
      fixture.latitude,
      fixture.longitude,
      candidate.latitude,
      candidate.longitude,
    );
    if (distanceKm > 80) continue;
    final magnitudeDelta =
        fixture.magnitude == null || candidate.magnitude == null
        ? 0.0
        : (fixture.magnitude! - candidate.magnitude!).abs();
    if (magnitudeDelta > 1.0) continue;
    final score = timeDeltaSeconds + distanceKm + magnitudeDelta * 10.0;
    final match = _CandidateMatch(
      candidate: candidate,
      timeDeltaSeconds: timeDeltaSeconds,
      distanceKm: distanceKm,
      magnitudeDelta: magnitudeDelta,
      score: score,
    );
    if (best == null || match.score < best.score) {
      best = match;
    }
  }
  return best;
}

class _CaptureFixture {
  final String caseId;
  final String originTimeJst;
  final DateTime originTime;
  final double latitude;
  final double longitude;
  final double? magnitude;
  final String region;
  final String truthSource;
  final String captureDirectory;

  const _CaptureFixture({
    required this.caseId,
    required this.originTimeJst,
    required this.originTime,
    required this.latitude,
    required this.longitude,
    required this.magnitude,
    required this.region,
    required this.truthSource,
    required this.captureDirectory,
  });
}

class _WaveformCandidate {
  final String eventId;
  final String originTimeJst;
  final DateTime originTime;
  final double latitude;
  final double longitude;
  final double? magnitude;
  final String niedDirectoryId;
  final String source;
  final String notes;
  final List<String> eventLabels;

  _WaveformCandidate({
    required this.eventId,
    required this.originTimeJst,
    required this.originTime,
    required this.latitude,
    required this.longitude,
    required this.magnitude,
    required this.niedDirectoryId,
    required this.source,
    required this.notes,
    required this.eventLabels,
  });

  bool get directoryIdIsProvisional {
    final lower = '$source $notes'.toLowerCase();
    return lower.contains('provisional') ||
        lower.contains('helper value') ||
        lower.contains('must be confirmed') ||
        lower.contains('directory id must be confirmed');
  }
}

class _CandidateMatch {
  final _WaveformCandidate candidate;
  final int timeDeltaSeconds;
  final double distanceKm;
  final double magnitudeDelta;
  final double score;

  const _CandidateMatch({
    required this.candidate,
    required this.timeDeltaSeconds,
    required this.distanceKm,
    required this.magnitudeDelta,
    required this.score,
  });
}

class _CaptureCase {
  final String caseId;
  final String originTimeJst;
  final String region;
  final String truthSource;
  final String captureDirectory;
  final String? matchedWaveformEventId;
  final String? matchedNiedDirectoryId;
  final int? matchTimeDeltaSeconds;
  final double? matchDistanceKm;
  final String downloadStatus;
  final int featureCount;
  final String readiness;
  final String nextAction;

  const _CaptureCase({
    required this.caseId,
    required this.originTimeJst,
    required this.region,
    required this.truthSource,
    required this.captureDirectory,
    required this.matchedWaveformEventId,
    required this.matchedNiedDirectoryId,
    required this.matchTimeDeltaSeconds,
    required this.matchDistanceKm,
    required this.downloadStatus,
    required this.featureCount,
    required this.readiness,
    required this.nextAction,
  });

  factory _CaptureCase.fromFixture({
    required _CaptureFixture fixture,
    required _CandidateMatch? match,
    required _DownloadSummary? downloadSummary,
    required List<_FeatureEntry> featureEntries,
  }) {
    final featureCount = featureEntries.length;
    final readiness = switch ((match, featureCount > 0, downloadSummary)) {
      (null, _, _) => 'capture_only_needs_waveform_candidate',
      (_, true, _) => 'ready_for_alignment',
      (final _CandidateMatch candidateMatch?, false, _)
          when candidateMatch.candidate.directoryIdIsProvisional =>
        'candidate_directory_id_unconfirmed',
      (_, false, final _DownloadSummary summary?)
          when summary.successfulRecordCount > 0 =>
        'waveform_downloaded_needs_feature_build',
      (_, false, _) => 'waveform_not_downloaded',
    };
    final nextAction = switch (readiness) {
      'ready_for_alignment' => 'export_gif_observations_and_run_alignment',
      'candidate_directory_id_unconfirmed' =>
        'confirm_nied_directory_id_then_download_waveforms',
      'waveform_downloaded_needs_feature_build' =>
        'build_waveform_features_then_run_alignment',
      'waveform_not_downloaded' => 'download_waveforms_for_matched_candidate',
      _ => 'seed_waveform_candidate_for_local_capture',
    };
    return _CaptureCase(
      caseId: fixture.caseId,
      originTimeJst: fixture.originTimeJst,
      region: fixture.region,
      truthSource: fixture.truthSource,
      captureDirectory: fixture.captureDirectory,
      matchedWaveformEventId: match?.candidate.eventId,
      matchedNiedDirectoryId: match?.candidate.niedDirectoryId,
      matchTimeDeltaSeconds: match?.timeDeltaSeconds,
      matchDistanceKm: match?.distanceKm,
      downloadStatus: downloadSummary?.label ?? 'none',
      featureCount: featureCount,
      readiness: readiness,
      nextAction: nextAction,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'caseId': caseId,
      'originTimeJst': originTimeJst,
      'region': region,
      'truthSource': truthSource,
      'captureDirectory': captureDirectory,
      'matchedWaveformEventId': matchedWaveformEventId,
      'matchedNiedDirectoryId': matchedNiedDirectoryId,
      'matchTimeDeltaSeconds': matchTimeDeltaSeconds,
      'matchDistanceKm': matchDistanceKm,
      'downloadStatus': downloadStatus,
      'featureCount': featureCount,
      'readiness': readiness,
      'nextAction': nextAction,
    };
  }
}

class _WaveformOnlyCase {
  final String eventId;
  final String originTimeJst;
  final String region;
  final String niedDirectoryId;
  final int featureCount;
  final _DownloadSummary? downloadSummary;

  const _WaveformOnlyCase({
    required this.eventId,
    required this.originTimeJst,
    required this.region,
    required this.niedDirectoryId,
    required this.featureCount,
    required this.downloadSummary,
  });

  String get downloadStatus => downloadSummary?.label ?? 'none';

  Map<String, Object?> toJson() {
    return {
      'eventId': eventId,
      'originTimeJst': originTimeJst,
      'region': region,
      'niedDirectoryId': niedDirectoryId,
      'featureCount': featureCount,
      'downloadStatus': downloadStatus,
    };
  }
}

class _DownloadSummary {
  final int successfulRecordCount;
  final int failedRecordCount;
  final int existingRecordCount;

  const _DownloadSummary({
    required this.successfulRecordCount,
    required this.failedRecordCount,
    required this.existingRecordCount,
  });

  factory _DownloadSummary.fromRecords(List<Map<String, Object?>> records) {
    var successful = 0;
    var failed = 0;
    var existing = 0;
    for (final record in records) {
      switch (record['status']?.toString()) {
        case 'downloaded':
          successful++;
        case 'existing':
          successful++;
          existing++;
        case 'failed':
          failed++;
      }
    }
    return _DownloadSummary(
      successfulRecordCount: successful,
      failedRecordCount: failed,
      existingRecordCount: existing,
    );
  }

  String get label =>
      'success:$successfulRecordCount failed:$failedRecordCount existing:$existingRecordCount';
}

class _FeatureEntry {
  final String format;
  final String featurePackagePath;

  const _FeatureEntry({required this.format, required this.featurePackagePath});
}

List<Object?> _list(Object? value) => value is List<Object?> ? value : const [];

Map<String, Object?> _map(Object? value) =>
    value is Map<String, Object?> ? value : const {};

List<String> _stringList(Object? value) => value is List<Object?>
    ? value.whereType<String>().toList(growable: false)
    : const [];

double? _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusKm = 6371.0;
  final dLat = _toRadians(lat2 - lat1);
  final dLon = _toRadians(lon2 - lon1);
  final a =
      pow(sin(dLat / 2), 2) +
      cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * pow(sin(dLon / 2), 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return earthRadiusKm * c;
}

double _toRadians(double degrees) => degrees * pi / 180.0;

DateTime _parseJst(String value) {
  final normalized =
      value.endsWith('Z') || value.contains(RegExp(r'[+-]\d{2}:\d{2}$'))
      ? value
      : '$value+09:00';
  return DateTime.parse(normalized);
}
