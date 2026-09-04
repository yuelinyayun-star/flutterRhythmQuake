import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

const _defaultTargetEventIds = <String>{
  '2011041214074228-37.0525-140.6435',
  '2014112222081790-36.6928-137.8910',
  '2016041421263443-32.7417-130.8087',
  '2016102114072257-35.3805-133.8562',
  '2016122821384904-36.7202-140.5742',
  '2018061807583414-34.8443-135.6217',
};

const _inputSpec = Matsuzaki2006ArchiveInputSpec(
  initialSearchRadiusKm: 100,
  maximumHorizontalSearchDistanceKm: 250,
  minimumSearchDepthKm: 5,
  maximumSearchDepthKm: 100,
  minimumObservations: 10,
  maximumObservations: 300,
  minimumInstrumentalIntensity: 0.5,
);

const _stages = <Matsuzaki2006JointSearchStage>[
  Matsuzaki2006JointSearchStage(
    latitudeStepDegrees: 0.5,
    longitudeStepDegrees: 0.5,
    depthStepKm: 20,
  ),
  Matsuzaki2006JointSearchStage.refinePreviousCandidates(
    latitudeStepDegrees: 0.1,
    longitudeStepDegrees: 0.1,
    depthStepKm: 10,
    maximumSeedCount: 6,
    seedRmsIncrease: 0.10,
  ),
  Matsuzaki2006JointSearchStage.refinePreviousCandidates(
    latitudeStepDegrees: 0.025,
    longitudeStepDegrees: 0.025,
    depthStepKm: 5,
    maximumSeedCount: 6,
    seedRmsIncrease: 0.05,
  ),
];

const _magnitudeSearchSpec = Matsuzaki2006ForwardSearchSpec(
  magnitudeScanStep: 0.1,
  refinementTolerance: 1e-7,
  objectiveTieTolerance: 1e-10,
  maximumRefinementIterations: 100,
);

void main(List<String> arguments) {
  _inputSpec.validate();
  final inputPaths = _values(arguments, '--input');
  final requestedIds = _values(arguments, '--event-id').toSet();
  final targetIds = requestedIds.isEmpty
      ? _defaultTargetEventIds
      : requestedIds;
  final outputDirectory = Directory(
    _value(arguments, '--output-dir') ??
        '.dart_tool/matsuzaki_2006_source_backed_point_source_inversion',
  );
  if (inputPaths.isEmpty || !arguments.contains('--allow-opened-2018')) {
    stderr.writeln(
      'Usage: dart run '
      'tool/matsuzaki_2006_source_backed_point_source_inversion_diagnostic.dart '
      '--input <annual.json> [...] --allow-opened-2018 '
      '[--event-id <event-id> ...] [--output-dir <directory>]',
    );
    exitCode = 64;
    return;
  }
  final missing = inputPaths.where((path) => !File(path).existsSync()).toList();
  if (missing.isNotEmpty) {
    stderr.writeln('Missing input files: ${missing.join(', ')}');
    exitCode = 66;
    return;
  }

  final rawEventsById = <String, Map<String, Object?>>{};
  for (final path in inputPaths) {
    final decoded = jsonDecode(File(path).readAsStringSync(encoding: utf8));
    if (decoded is! Map<String, Object?> ||
        decoded['events'] is! List<Object?>) {
      throw FormatException('Invalid annual dataset: $path');
    }
    for (final raw in decoded['events']! as List<Object?>) {
      if (raw is! Map<String, Object?> || raw['eventId'] is! String) continue;
      final id = raw['eventId']! as String;
      if (targetIds.contains(id)) {
        if (rawEventsById.containsKey(id)) {
          throw StateError('Duplicate target event across inputs: $id');
        }
        rawEventsById[id] = raw;
      }
    }
  }
  final missingTargets =
      targetIds.difference(rawEventsById.keys.toSet()).toList()..sort();
  if (missingTargets.isNotEmpty) {
    throw StateError('Target events not found: ${missingTargets.join(', ')}');
  }

  final models = <String, Matsuzaki2006AttenuationModel>{
    'published': const Matsuzaki2006AttenuationModel(),
    'finiteFaultSemanticFrozen2017': const Matsuzaki2006AttenuationModel(
      coefficients:
          Matsuzaki2006AttenuationCoefficients.finiteFaultSemanticFrozen2017,
    ),
  };
  const inputBuilder = Matsuzaki2006ArchiveInversionInputBuilder();
  final eventReports = <Map<String, Object?>>[];
  final modelRows = <Map<String, Object?>>[];

  final orderedEvents = rawEventsById.values.toList()
    ..sort(
      (left, right) =>
          (left['eventId']! as String).compareTo(right['eventId']! as String),
    );
  for (final rawEvent in orderedEvents) {
    final truth = _truth(rawEvent);
    final input = inputBuilder.build(rawEvent: rawEvent, spec: _inputSpec);
    if (!input.isReady) {
      throw StateError(
        'Target input is not ready: ${truth.eventId} (${input.status.name})',
      );
    }
    final results = <String, Object?>{};
    for (final modelEntry in models.entries) {
      final searchSpec = Matsuzaki2006JointSearchSpec(
        initialHorizontalBounds: input.initialHorizontalBounds!,
        hardHorizontalBounds: input.hardHorizontalBounds!,
        minimumDepthKm: _inputSpec.minimumSearchDepthKm,
        maximumDepthKm: _inputSpec.maximumSearchDepthKm,
        radialSearchConstraint: input.radialSearchConstraint,
        stages: _stages,
        horizontalExpansionDegrees: 0.5,
        maximumHorizontalExpansionRounds: 8,
        maximumCandidateEvaluations: 30000,
        minimumObservations: _inputSpec.minimumObservations,
        equivalentObjectiveTolerance: 1e-8,
        resolutionRmsIncrease: 0.05,
        magnitudeSearchSpec: _magnitudeSearchSpec,
      );
      final stopwatch = Stopwatch()..start();
      final result = Matsuzaki2006JointInverter(
        model: modelEntry.value,
      ).invert(observations: input.observations, searchSpec: searchSpec);
      stopwatch.stop();
      final row = _resultJson(
        result: result,
        truth: truth,
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
      );
      results[modelEntry.key] = row;
      modelRows.add({
        'eventId': truth.eventId,
        'model': modelEntry.key,
        ...row,
      });
      stdout.writeln(
        '${truth.eventId} ${modelEntry.key}: ${row['status']} '
        'rms=${row['minimumIntensityRms']} '
        'epi=${row['epicentralErrorKmMinimumEquivalent']} '
        'elapsed=${row['elapsedMilliseconds']}ms',
      );
    }
    eventReports.add({
      'eventId': truth.eventId,
      'originTime': truth.originTime,
      'truth': truth.toJson(),
      'input': {
        'status': input.status.name,
        'anchorLatitude': input.anchorLatitude,
        'anchorLongitude': input.anchorLongitude,
        'rawObservationCount': input.rawObservationCount,
        'validObservationCount': input.validObservationCount,
        'domainSafeObservationCount': input.domainSafeObservationCount,
        'selectedObservationCount': input.observations.length,
        'selectedStationIds': [
          for (final observation in input.observations) observation.id,
        ],
      },
      'models': results,
    });
  }

  final report = <String, Object?>{
    'schemaVersion':
        'matsuzaki_2006_source_backed_point_source_inversion_diagnostic_v1',
    'protocolStatus': 'source_backed_point_source_inversion_diagnostic_v1',
    'purpose':
        'Run unknown-event candidate point-source inversion on events with independently archived finite-fault geometry.',
    'inputPolicy': {
      'rawAnnualDatasetsRead': inputPaths,
      'observationsModified': false,
      'catalogTruthUsedFor':
          'eligibility and post-inversion error metrics only',
      'inputConstructionUsesCatalogTruth': false,
      'finiteFaultGeometryUsedDuringSearch': false,
      'stationBiasUsed': false,
      'productionAlgorithmChanged': false,
    },
    'searchProtocol': {
      'minimumInstrumentalIntensity': _inputSpec.minimumInstrumentalIntensity,
      'maximumObservations': _inputSpec.maximumObservations,
      'initialSearchRadiusKm': _inputSpec.initialSearchRadiusKm,
      'maximumHorizontalSearchDistanceKm':
          _inputSpec.maximumHorizontalSearchDistanceKm,
      'depthRangeKm': [
        _inputSpec.minimumSearchDepthKm,
        _inputSpec.maximumSearchDepthKm,
      ],
      'maximumCandidateEvaluations': 30000,
      'stages': [
        for (final stage in _stages)
          {
            'latitudeStepDegrees': stage.latitudeStepDegrees,
            'longitudeStepDegrees': stage.longitudeStepDegrees,
            'depthStepKm': stage.depthStepKm,
            'maximumSeedCount': stage.maximumRefinementSeedCount,
            'seedRmsIncrease': stage.refinementSeedRmsIncrease,
          },
      ],
    },
    'models': {
      for (final entry in models.entries)
        entry.key: entry.value.coefficients.toJson(),
    },
    'events': eventReports,
    'modelRows': modelRows,
  };
  outputDirectory.createSync(recursive: true);
  File('${outputDirectory.path}/report.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    encoding: utf8,
  );
  File(
    '${outputDirectory.path}/report.md',
  ).writeAsStringSync(_markdown(eventReports, modelRows), encoding: utf8);
  stdout.writeln('wrote ${outputDirectory.path}/report.json');
  stdout.writeln('wrote ${outputDirectory.path}/report.md');
}

Map<String, Object?> _resultJson({
  required Matsuzaki2006JointInversionResult result,
  required _Truth truth,
  required int elapsedMilliseconds,
}) {
  final candidates = [
    for (final candidate in result.bestCandidates)
      {
        'latitude': candidate.source.latitude,
        'longitude': candidate.source.longitude,
        'depthKm': candidate.source.depthKm,
        'magnitude': candidate.magnitude,
        'intensityRms': candidate.intensityRms,
        'meanIntensityResidual': candidate.meanIntensityResidual,
        'epicentralErrorKm':
            Matsuzaki2006PointSourceGeometry.hypocentralDistanceBetween(
              sourceLatitude: truth.latitude,
              sourceLongitude: truth.longitude,
              stationLatitude: candidate.source.latitude,
              stationLongitude: candidate.source.longitude,
              depthKm: 0,
            ),
        'depthAbsoluteErrorKm': (candidate.source.depthKm - truth.depthKm)
            .abs(),
        'magnitudeAbsoluteError': (candidate.magnitude - truth.magnitude).abs(),
      },
  ];
  double? metric(String key) => candidates.isEmpty
      ? null
      : candidates
            .map((candidate) => (candidate[key]! as num).toDouble())
            .reduce((left, right) => left < right ? left : right);
  return {
    'status': result.status.name,
    'isConverged': result.isConverged,
    'candidateEvaluationCount': result.candidateEvaluationCount,
    'elapsedMilliseconds': elapsedMilliseconds,
    'hardBoundaryContacts': [
      for (final boundary in result.hardBoundaryContacts) boundary.name,
    ]..sort(),
    'bestEquivalentCandidateCount': candidates.length,
    'minimumIntensityRms': result.bestCandidates.isEmpty
        ? null
        : result.bestCandidates.first.intensityRms,
    'epicentralErrorKmMinimumEquivalent': metric('epicentralErrorKm'),
    'depthAbsoluteErrorKmMinimumEquivalent': metric('depthAbsoluteErrorKm'),
    'magnitudeAbsoluteErrorMinimumEquivalent': metric('magnitudeAbsoluteError'),
    'bestCandidates': candidates,
  };
}

String _markdown(
  List<Map<String, Object?>> events,
  List<Map<String, Object?>> rows,
) {
  final buffer = StringBuffer()
    ..writeln('# 有来源有限断层事件的点源联合反演诊断')
    ..writeln()
    ..writeln(
      '本报告把六个已独立归档有限断层几何的事件，作为未知事件输入送入同一套候选点源联合搜索。搜索期间不读取有限断层几何和目录震源；目录真值只用于搜索完成后的误差统计。',
    )
    ..writeln()
    ..writeln(
      '| 年 | 事件 | 模型 | 状态 | RMS | 震中误差 km | 深度误差 km | 震级误差 | 边界 | 候选数 | 耗时 ms |',
    )
    ..writeln('|---:|---|---|---|---:|---:|---:|---:|---|---:|---:|');
  for (final row in rows) {
    final truth =
        (events.firstWhere(
              (event) => event['eventId'] == row['eventId'],
            )['truth']!
            as Map<String, Object?>);
    buffer.writeln(
      '| ${(truth['originTime']! as String).substring(0, 4)} | `${row['eventId']}` | '
      '`${row['model']}` | `${row['status']}` | ${_fixed(row['minimumIntensityRms'])} | '
      '${_fixed(row['epicentralErrorKmMinimumEquivalent'])} | '
      '${_fixed(row['depthAbsoluteErrorKmMinimumEquivalent'])} | '
      '${_fixed(row['magnitudeAbsoluteErrorMinimumEquivalent'])} | '
      '`${(row['hardBoundaryContacts']! as List<Object?>).join(', ')}` | '
      '${row['candidateEvaluationCount']} | ${row['elapsedMilliseconds']} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## 边界')
    ..writeln()
    ..writeln('- 这是点源搜索在真实事件上的迁移诊断，不是有限断层搜索，也不是新的盲测。')
    ..writeln('- 不能用本表的误差直接回调搜索半径、深度范围、站数或系数。')
    ..writeln('- 若点源搜索在有来源有限断层事件上出现系统性偏移，后续必须建立预声明的分层/混合距离模型，并用独立留出事件验证。')
    ..writeln()
    ..writeln('事件数：${events.length}；模型运行数：${rows.length}。');
  return buffer.toString();
}

class _Truth {
  const _Truth({
    required this.eventId,
    required this.originTime,
    required this.latitude,
    required this.longitude,
    required this.depthKm,
    required this.magnitude,
  });

  final String eventId;
  final String originTime;
  final double latitude;
  final double longitude;
  final double depthKm;
  final double magnitude;

  Map<String, Object> toJson() => {
    'originTime': originTime,
    'latitude': latitude,
    'longitude': longitude,
    'depthKm': depthKm,
    'magnitude': magnitude,
  };
}

_Truth _truth(Map<String, Object?> rawEvent) {
  final id = rawEvent['eventId'];
  final raw = rawEvent['preferredHypocenter'];
  if (id is! String || raw is! Map<String, Object?>) {
    throw FormatException('Target event has no preferred hypocenter.');
  }
  double number(String key) {
    final value = raw[key];
    if (value is! num || !value.isFinite) {
      throw FormatException('Invalid truth $key for $id.');
    }
    return value.toDouble();
  }

  return _Truth(
    eventId: id,
    originTime: raw['originTime'] is String ? raw['originTime']! as String : '',
    latitude: number('latitude'),
    longitude: number('longitude'),
    depthKm: number('depthKm'),
    magnitude: number('magnitude'),
  );
}

String _fixed(Object? value) =>
    value is num ? value.toDouble().toStringAsFixed(3) : '-';

String? _value(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index < 0 || index + 1 >= arguments.length) return null;
  return arguments[index + 1];
}

List<String> _values(List<String> arguments, String name) {
  final values = <String>[];
  for (var index = 0; index < arguments.length - 1; index++) {
    if (arguments[index] == name) values.add(arguments[index + 1]);
  }
  return values;
}
