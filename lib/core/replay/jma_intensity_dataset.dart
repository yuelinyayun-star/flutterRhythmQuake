import 'dart:convert';

class JmaIntensityDatasetBuildResult {
  final Map<String, Object?> manifest;
  final Map<String, Object?> splits;
  final Map<String, Object?> qualityReport;

  const JmaIntensityDatasetBuildResult({
    required this.manifest,
    required this.splits,
    required this.qualityReport,
  });

  String qualityReportMarkdown() {
    final totals = qualityReport['totals']! as Map<String, Object?>;
    final bySplit = qualityReport['bySplit']! as Map<String, Object?>;
    final rejectionReasons =
        qualityReport['rejectionReasons']! as Map<String, Object?>;
    final buffer = StringBuffer()
      ..writeln('# JMA Intensity Pretraining Quality Report')
      ..writeln()
      ..writeln('Dataset: `${qualityReport['datasetId']}`')
      ..writeln()
      ..writeln('Split policy: `${qualityReport['splitPolicy']}`')
      ..writeln()
      ..writeln('## Totals')
      ..writeln()
      ..writeln('| Metric | Value |')
      ..writeln('| --- | ---: |');
    for (final entry in totals.entries) {
      buffer.writeln('| ${entry.key} | ${entry.value} |');
    }
    buffer
      ..writeln()
      ..writeln('## Eligible Events By Split')
      ..writeln()
      ..writeln('| Split | Events |')
      ..writeln('| --- | ---: |');
    for (final entry in bySplit.entries) {
      buffer.writeln('| ${entry.key} | ${entry.value} |');
    }
    buffer
      ..writeln()
      ..writeln('## Rejection Reasons')
      ..writeln()
      ..writeln('| Reason | Events |')
      ..writeln('| --- | ---: |');
    for (final entry in rejectionReasons.entries) {
      buffer.writeln('| ${entry.key} | ${entry.value} |');
    }
    _writeDistribution(buffer, 'Usable Station Count', 'stationCountBuckets');
    _writeDistribution(buffer, 'Magnitude', 'magnitudeBuckets');
    _writeDistribution(buffer, 'Depth', 'depthBuckets');
    _writeDistribution(buffer, 'Maximum Intensity', 'maximumIntensityClasses');
    _writeDistribution(buffer, 'Determination Flag', 'determinationFlags');
    return buffer.toString();
  }

  void _writeDistribution(StringBuffer buffer, String title, String key) {
    final values = qualityReport[key]! as Map<String, Object?>;
    buffer
      ..writeln()
      ..writeln('## $title')
      ..writeln()
      ..writeln('| Bucket | Events |')
      ..writeln('| --- | ---: |');
    for (final entry in values.entries) {
      buffer.writeln('| ${entry.key} | ${entry.value} |');
    }
  }
}

class JmaIntensityDatasetBuilder {
  final Map<int, String> splitByYear;
  final int minimumUsableStations;

  const JmaIntensityDatasetBuilder({
    this.splitByYear = const {2020: 'train', 2021: 'validation', 2022: 'test'},
    this.minimumUsableStations = 4,
  });

  JmaIntensityDatasetBuildResult build(
    Iterable<Map<String, Object?>> annualDatasets, {
    DateTime? generatedAt,
  }) {
    final entries = <Map<String, Object?>>[];
    final seenEventIds = <String>{};
    final rejectionReasons = <String, int>{};
    final stationBuckets = <String, int>{};
    final magnitudeBuckets = <String, int>{};
    final depthBuckets = <String, int>{};
    final intensityClasses = <String, int>{};
    final determinationFlags = <String, int>{};
    final sourceDatasets = <Map<String, Object?>>[];
    var observationCount = 0;
    var usableObservationCount = 0;

    for (final dataset in annualDatasets) {
      final year = (dataset['year']! as num).toInt();
      final split = splitByYear[year];
      if (split == null) {
        throw FormatException('No split configured for year $year.');
      }
      final events = dataset['events']! as List<Object?>;
      sourceDatasets.add({
        'datasetId': dataset['datasetId'],
        'year': year,
        'eventCount': events.length,
        'processingVersion': dataset['processingVersion'],
        'sourceUrl': dataset['sourceUrl'],
      });
      for (final rawEvent in events) {
        final event = rawEvent! as Map<String, Object?>;
        final eventId = event['eventId']! as String;
        if (!seenEventIds.add(eventId)) {
          throw FormatException('Duplicate eventId: $eventId');
        }
        final hypocenter =
            event['preferredHypocenter']! as Map<String, Object?>;
        final observations = event['observations']! as List<Object?>;
        final usableStations = <String>{};
        for (final rawObservation in observations) {
          final observation = rawObservation! as Map<String, Object?>;
          if (_number(observation['latitude']) != null &&
              _number(observation['longitude']) != null &&
              _number(observation['instrumentalIntensity']) != null) {
            usableStations.add(observation['stationId']! as String);
          }
        }
        observationCount += observations.length;
        usableObservationCount += usableStations.length;

        final latitude = _number(hypocenter['latitude']);
        final longitude = _number(hypocenter['longitude']);
        final depthKm = _number(hypocenter['depthKm']);
        final magnitude = _number(hypocenter['magnitude']);
        final reasons = <String>[];
        if (latitude == null || latitude < -90 || latitude > 90) {
          reasons.add('missing_or_invalid_latitude');
        }
        if (longitude == null || longitude < -180 || longitude > 180) {
          reasons.add('missing_or_invalid_longitude');
        }
        if (depthKm == null || depthKm < 0) {
          reasons.add('missing_or_invalid_depth');
        }
        if (magnitude == null) reasons.add('missing_magnitude');
        if (usableStations.length < minimumUsableStations) {
          reasons.add('fewer_than_${minimumUsableStations}_usable_stations');
        }
        for (final reason in reasons) {
          _increment(rejectionReasons, reason);
        }

        final maximumIntensity =
            (hypocenter['maximumIntensityClass'] as String?)?.trim();
        final determinationFlag = (hypocenter['determinationFlag'] as String?)
            ?.trim();
        _increment(stationBuckets, _stationBucket(usableStations.length));
        _increment(magnitudeBuckets, _magnitudeBucket(magnitude));
        _increment(depthBuckets, _depthBucket(depthKm));
        _increment(
          intensityClasses,
          maximumIntensity?.isNotEmpty == true ? maximumIntensity! : 'unknown',
        );
        _increment(
          determinationFlags,
          determinationFlag?.isNotEmpty == true ? determinationFlag! : 'blank',
        );
        entries.add({
          'eventId': eventId,
          'sourceDatasetId': dataset['datasetId'],
          'year': year,
          'split': split,
          'originTime': hypocenter['originTime'],
          'latitude': latitude,
          'longitude': longitude,
          'depthKm': depthKm,
          'magnitude': magnitude,
          'maximumIntensityClass': maximumIntensity,
          'determinationFlag': determinationFlag,
          'observationCount': observations.length,
          'usableObservationCount': usableStations.length,
          'eligible': reasons.isEmpty,
          'rejectionReasons': reasons,
        });
      }
    }
    entries.sort(
      (left, right) => (left['originTime']! as String).compareTo(
        right['originTime']! as String,
      ),
    );

    final splitIds = <String, List<String>>{
      'train': [],
      'validation': [],
      'test': [],
    };
    for (final entry in entries.where((item) => item['eligible']! as bool)) {
      splitIds[entry['split']!]!.add(entry['eventId']! as String);
    }
    final generated = (generatedAt ?? DateTime.now()).toUtc().toIso8601String();
    final policy = splitByYear.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(',');
    final datasetId =
        'jma_final_intensity_${splitByYear.keys.reduce((a, b) => a < b ? a : b)}_'
        '${splitByYear.keys.reduce((a, b) => a > b ? a : b)}';
    final totals = <String, Object?>{
      'events': entries.length,
      'eligibleEvents': entries
          .where((item) => item['eligible']! as bool)
          .length,
      'rejectedEvents': entries
          .where((item) => !(item['eligible']! as bool))
          .length,
      'observations': observationCount,
      'usableObservations': usableObservationCount,
      'usableObservationRate': observationCount == 0
          ? 0.0
          : usableObservationCount / observationCount,
    };
    return JmaIntensityDatasetBuildResult(
      manifest: {
        'schemaVersion': 1,
        'datasetId': datasetId,
        'domain': 'jma_final_intensity',
        'generatedAt': generated,
        'eligibilityPolicy': {
          'minimumUsableStations': minimumUsableStations,
          'usableStationRequires': [
            'stationId',
            'latitude',
            'longitude',
            'instrumentalIntensity',
          ],
          'requiredLabels': ['latitude', 'longitude', 'depthKm', 'magnitude'],
        },
        'sourceDatasets': sourceDatasets,
        'events': entries,
      },
      splits: {
        'schemaVersion': 1,
        'datasetId': datasetId,
        'generatedAt': generated,
        'policy': 'chronological_by_archive_year:$policy',
        'eligibleOnly': true,
        'splits': splitIds,
      },
      qualityReport: {
        'schemaVersion': 1,
        'datasetId': datasetId,
        'generatedAt': generated,
        'splitPolicy': 'chronological_by_archive_year:$policy',
        'totals': totals,
        'bySplit': {
          for (final entry in splitIds.entries) entry.key: entry.value.length,
        },
        'rejectionReasons': _sortedCounts(rejectionReasons),
        'stationCountBuckets': _orderedCounts(stationBuckets, const [
          '0-3',
          '4-9',
          '10-29',
          '30-99',
          '100+',
        ]),
        'magnitudeBuckets': _orderedCounts(magnitudeBuckets, const [
          'unknown',
          '<3',
          '3-3.9',
          '4-4.9',
          '5-5.9',
          '6+',
        ]),
        'depthBuckets': _orderedCounts(depthBuckets, const [
          'unknown',
          '0-29',
          '30-69',
          '70-299',
          '300+',
        ]),
        'maximumIntensityClasses': _sortedCounts(intensityClasses),
        'determinationFlags': _sortedCounts(determinationFlags),
      },
    );
  }

  static double? _number(Object? value) =>
      value is num ? value.toDouble() : null;

  static void _increment(Map<String, int> counts, String key) {
    counts[key] = (counts[key] ?? 0) + 1;
  }

  static String _stationBucket(int count) {
    if (count < 4) return '0-3';
    if (count < 10) return '4-9';
    if (count < 30) return '10-29';
    if (count < 100) return '30-99';
    return '100+';
  }

  static String _magnitudeBucket(double? value) {
    if (value == null) return 'unknown';
    if (value < 3) return '<3';
    if (value < 4) return '3-3.9';
    if (value < 5) return '4-4.9';
    if (value < 6) return '5-5.9';
    return '6+';
  }

  static String _depthBucket(double? value) {
    if (value == null) return 'unknown';
    if (value < 30) return '0-29';
    if (value < 70) return '30-69';
    if (value < 300) return '70-299';
    return '300+';
  }

  static Map<String, int> _orderedCounts(
    Map<String, int> counts,
    List<String> keys,
  ) => {for (final key in keys) key: counts[key] ?? 0};

  static Map<String, int> _sortedCounts(Map<String, int> counts) {
    final keys = counts.keys.toList()..sort();
    return {for (final key in keys) key: counts[key]!};
  }
}

Map<String, Object?> decodeJmaIntensityDataset(String source) =>
    jsonDecode(source) as Map<String, Object?>;
