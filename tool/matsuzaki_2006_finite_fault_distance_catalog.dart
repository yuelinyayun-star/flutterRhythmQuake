import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

void main(List<String> arguments) {
  final inputPaths = _values(arguments, '--input');
  final outputDirectory = Directory(
    _value(arguments, '--output-dir') ??
        '.dart_tool/matsuzaki_2006_finite_fault_distance_catalog',
  );
  if (inputPaths.isEmpty) {
    stderr.writeln(
      'Usage: dart run '
      'tool/matsuzaki_2006_finite_fault_distance_catalog.dart '
      '--input <annual.json> [...] --allow-opened-2018 '
      '[--output-dir <directory>]',
    );
    exitCode = 64;
    return;
  }
  if (!arguments.contains('--allow-opened-2018')) {
    stderr.writeln(
      'Refusing to read the opened 2018 audit year without explicit '
      '--allow-opened-2018.',
    );
    exitCode = 65;
    return;
  }
  final missing = inputPaths.where((path) => !File(path).existsSync()).toList();
  if (missing.isNotEmpty) {
    stderr.writeln('Missing input files: ${missing.join(', ')}');
    exitCode = 66;
    return;
  }

  final datasetsByYear = <int, Map<String, Object?>>{};
  for (final inputPath in inputPaths) {
    final dataset = _readJsonObject(inputPath);
    final year = dataset['year'];
    if (year is! int) {
      throw FormatException('Annual dataset has no integer year: $inputPath');
    }
    if (datasetsByYear.containsKey(year)) {
      throw FormatException('Duplicate annual dataset for year $year.');
    }
    datasetsByYear[year] = dataset;
  }
  const requiredYears = {2011, 2014, 2016, 2018};
  final missingYears = requiredYears.difference(datasetsByYear.keys.toSet());
  if (missingYears.isNotEmpty) {
    throw FormatException(
      'Missing required annual datasets: ${missingYears.toList()..sort()}.',
    );
  }

  const evaluator = Matsuzaki2006JmaBaselineEvaluator();
  final sortedDatasets = datasetsByYear.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  final baseline = evaluator.evaluate(
    sortedDatasets.map((entry) => entry.value),
  );
  final baselineEventsById = {
    for (final event in baseline.events) event.eventId: event,
  };

  const expectedNearfieldCounts = <String, int>{
    '2011041214074228-37.0525-140.6435': 14,
    '2014112222081790-36.6928-137.8910': 15,
    '2016041421263443-32.7417-130.8087': 41,
    '2016102114072257-35.3805-133.8562': 25,
    '2016122821384904-36.7202-140.5742': 20,
    '2018061807583414-34.8443-135.6217': 98,
  };
  final eventReports = <Map<String, Object?>>[];
  final nearfieldDistanceRecords = <Map<String, Object?>>[];
  final fullAcceptedDistanceRecords = <Map<String, Object?>>[];
  final nearfieldPointDistances = <double>[];
  final nearfieldFiniteDistances = <double>[];
  final fullAcceptedPointDistances = <double>[];
  final fullAcceptedFiniteDistances = <double>[];
  var nearfieldEventStationPairCount = 0;
  var fullAcceptedEventStationPairCount = 0;
  var nearfieldEvaluableVariantDistanceCount = 0;
  var nearfieldOutsideDomainVariantDistanceCount = 0;
  var fullAcceptedEvaluableVariantDistanceCount = 0;
  var fullAcceptedOutsideDomainVariantDistanceCount = 0;

  for (final configuration
      in Matsuzaki2006SourceBackedDistanceOverrides.eventGeometries) {
    final event = baselineEventsById[configuration.eventId];
    if (event == null) {
      throw StateError(
        'Expected accepted event ${configuration.eventId} in year '
        '${configuration.year}.',
      );
    }
    if (event.year != configuration.year) {
      throw StateError(
        'Event ${configuration.eventId} was loaded from year ${event.year}, '
        'expected ${configuration.year}.',
      );
    }
    final nearStations =
        event.stationResiduals
            .where((station) => station.sourceDistanceKm < 30)
            .toList()
          ..sort((left, right) {
            final distanceComparison = left.sourceDistanceKm.compareTo(
              right.sourceDistanceKm,
            );
            return distanceComparison != 0
                ? distanceComparison
                : left.stationId.compareTo(right.stationId);
          });
    if (nearStations.length != expectedNearfieldCounts[configuration.eventId]) {
      throw StateError(
        'Expected ${expectedNearfieldCounts[configuration.eventId]} '
        'point-source nearfield stations for ${configuration.eventId}, found '
        '${nearStations.length}.',
      );
    }

    nearfieldEventStationPairCount += nearStations.length;
    fullAcceptedEventStationPairCount += event.stationResiduals.length;
    nearfieldPointDistances.addAll(
      nearStations.map((station) => station.sourceDistanceKm),
    );
    fullAcceptedPointDistances.addAll(
      event.stationResiduals.map((station) => station.sourceDistanceKm),
    );
    final eventVariantReports = <Map<String, Object?>>[];
    final stationReports = <Map<String, Object?>>[];
    final overridesByVariantId = <String, Matsuzaki2006EventDistanceOverride>{};

    for (final variant in configuration.variants) {
      final override =
          Matsuzaki2006SourceBackedDistanceOverrides.evaluateVariant(
            event: event,
            geometry: configuration,
            variant: variant,
          );
      overridesByVariantId[variant.id] = override;
      final nearOverrides = override.stations
          .where((station) => station.pointSourceDistanceKm < 30)
          .toList();
      final nearSummary = _populationSummary(nearOverrides);
      final fullSummary = _populationSummary(override.stations);
      nearfieldFiniteDistances.addAll(
        nearOverrides.map((station) => station.finiteFaultDistanceKm),
      );
      fullAcceptedFiniteDistances.addAll(
        override.stations.map((station) => station.finiteFaultDistanceKm),
      );
      nearfieldEvaluableVariantDistanceCount +=
          nearSummary.evaluableDistanceCount;
      nearfieldOutsideDomainVariantDistanceCount +=
          nearSummary.outsideDomainDistanceCount;
      fullAcceptedEvaluableVariantDistanceCount +=
          fullSummary.evaluableDistanceCount;
      fullAcceptedOutsideDomainVariantDistanceCount +=
          fullSummary.outsideDomainDistanceCount;
      nearfieldDistanceRecords.addAll(
        nearOverrides.map(
          (station) => _distanceRecord(
            event: event,
            configuration: configuration,
            variant: variant,
            station: station,
          ),
        ),
      );
      fullAcceptedDistanceRecords.addAll(
        override.stations.map(
          (station) => _distanceRecord(
            event: event,
            configuration: configuration,
            variant: variant,
            station: station,
          ),
        ),
      );
      eventVariantReports.add({
        'id': variant.id,
        'label': variant.label,
        'selectionStatus': configuration.variants.length == 1
            ? 'only_source_backed_variant_for_event'
            : variant.id == configuration.preferredVariant.id
            ? 'preferred_by_independent_source_structure_evidence'
            : 'retained_lower_resolution_geodetic_simplification',
        'faultPlanes': variant.faultPlanes
            .map((plane) => plane.toJson())
            .toList(),
        'distanceRecordCount': nearSummary.distanceRecordCount,
        'evaluableDistanceCount': nearSummary.evaluableDistanceCount,
        'outsidePublishedDistanceDomainCount':
            nearSummary.outsideDomainDistanceCount,
        'distanceSummary': nearSummary.distanceSummary,
        'finiteFaultMinusPointSourceSummary': nearSummary.differenceSummary,
        'distanceExclusions': nearSummary.exclusions,
        'nearfieldDiagnosticPopulation': nearSummary.toJson(),
        'fullAcceptedEventStationPopulation': fullSummary.toJson(),
      });
    }

    for (final station in nearStations) {
      final variantDistances = <String, Object?>{};
      for (final variant in configuration.variants) {
        final finiteDistance = overridesByVariantId[variant.id]!.stations
            .singleWhere(
              (candidate) =>
                  candidate.originalStation.stationId == station.stationId,
            )
            .finiteFaultDistanceKm;
        variantDistances[variant.id] = {
          'finiteFaultDistanceKm': finiteDistance,
          'finiteFaultMinusPointSourceKm':
              finiteDistance - station.sourceDistanceKm,
          'evaluationStatus': _isPublishedDistance(finiteDistance)
              ? 'evaluated'
              : 'outside_published_source_distance_domain',
        };
      }
      stationReports.add({
        'stationId': station.stationId,
        'latitude': station.latitude,
        'longitude': station.longitude,
        'observedIntensity': station.observedIntensity,
        'pointSourceDistanceKm': station.sourceDistanceKm,
        'geometryVariants': variantDistances,
      });
    }

    eventReports.add({
      'eventId': event.eventId,
      'year': event.year,
      'originTime': event.originTime,
      'regionName': configuration.regionName,
      'latitude': event.latitude,
      'longitude': event.longitude,
      'catalogDepthKm': event.depthKm,
      'magnitude': event.magnitude,
      'magnitudeType': event.magnitudeType,
      'maximumIntensityClass': event.maximumIntensityClass,
      'acceptedStationCount': event.stationResiduals.length,
      'pointSourceNearfieldStationCount': nearStations.length,
      'geometryRecord': configuration.geometryRecord,
      'geometryVariantCount': configuration.variants.length,
      'geometrySelectionStatus': configuration.variants.length == 1
          ? 'unambiguous_for_catalog'
          : 'preferred_variant_selected_by_independent_source_structure_evidence',
      'preferredGeometryVariantId': configuration.preferredVariant.id,
      'geometryVariants': eventVariantReports,
      'stations': stationReports,
    });
  }

  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_finite_fault_distance_catalog_v2',
    'experimentPolicy': {
      'productionAdoption': false,
      'coefficientsEvaluated': false,
      'coefficientsRefitted': false,
      'distanceFloorApplied': false,
      'sourceDataMutated': false,
      'nearfieldDefinition': 'point_source_distance_below_30_km',
      'distanceDefinition':
          'minimum_3d_distance_from_surface_station_to_source_backed_finite_fault_union',
      'publishedDistanceDomainKm': {'minimum': 1, 'maximum': 500},
      'outsideDomainPolicy':
          'preserve_raw_geometry_distance_and_exclude_only_from_attenuation_evaluation',
      'multipleGeometryPolicy':
          'preserve_all_source_backed_variants_and_choose_preferred_only_from_independent_source_structure_evidence',
      'populationPolicy': {
        'nearfieldDiagnosticPopulation':
            'point_source_distance_below_30_km_preserved_for_prior_diagnostic_cross_validation',
        'fullAcceptedEventStationPopulation':
            'all_strict_baseline_accepted_stations_for_each_source_backed_event',
      },
    },
    'catalogStatus': {
      'eventCount': eventReports.length,
      'pointSourceNearfieldEventStationPairCount':
          nearfieldEventStationPairCount,
      'geometryVariantDistanceRecordCount': nearfieldDistanceRecords.length,
      'evaluableGeometryVariantDistanceRecordCount':
          nearfieldEvaluableVariantDistanceCount,
      'outsidePublishedDistanceDomainRecordCount':
          nearfieldOutsideDomainVariantDistanceCount,
      'fullAcceptedEventStationPairCount': fullAcceptedEventStationPairCount,
      'fullAcceptedGeometryVariantDistanceRecordCount':
          fullAcceptedDistanceRecords.length,
      'fullAcceptedEvaluableGeometryVariantDistanceRecordCount':
          fullAcceptedEvaluableVariantDistanceCount,
      'fullAcceptedOutsidePublishedDistanceDomainRecordCount':
          fullAcceptedOutsideDomainVariantDistanceCount,
      'eventWithMultipleGeometryVariantsCount':
          Matsuzaki2006SourceBackedDistanceOverrides.eventGeometries
              .where((configuration) => configuration.variants.length > 1)
              .length,
      'readyForFiniteFaultSemanticCalibration2010To2016': true,
      'readyForFrozen2018GeometryBranchEvaluation': true,
    },
    'aggregateDistanceSummaries': {
      'pointSourceUniqueEventStationPairs': _summary(nearfieldPointDistances),
      'finiteFaultGeometryVariantRecords': _summary(nearfieldFiniteDistances),
      'nearfieldDiagnosticPopulation': {
        'pointSourceUniqueEventStationPairs': _summary(nearfieldPointDistances),
        'finiteFaultGeometryVariantRecords': _summary(nearfieldFiniteDistances),
      },
      'fullAcceptedEventStationPopulation': {
        'pointSourceUniqueEventStationPairs': _summary(
          fullAcceptedPointDistances,
        ),
        'finiteFaultGeometryVariantRecords': _summary(
          fullAcceptedFiniteDistances,
        ),
      },
    },
    'events': eventReports,
    'distanceRecords': nearfieldDistanceRecords,
    'fullAcceptedDistanceRecords': fullAcceptedDistanceRecords,
  };

  outputDirectory.createSync(recursive: true);
  final jsonFile = File('${outputDirectory.path}/report.json');
  final markdownFile = File('${outputDirectory.path}/report.md');
  jsonFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    encoding: utf8,
  );
  markdownFile.writeAsStringSync(
    _toMarkdown(eventReports, report['catalogStatus']! as Map<String, Object?>),
    encoding: utf8,
  );
  stdout.writeln(
    'events=${eventReports.length} '
    'nearfieldEventStationPairs=$nearfieldEventStationPairCount '
    'nearfieldVariantDistanceRecords=${nearfieldDistanceRecords.length} '
    'fullEventStationPairs=$fullAcceptedEventStationPairCount '
    'fullVariantDistanceRecords=${fullAcceptedDistanceRecords.length} '
    'fullOutsideDomain=$fullAcceptedOutsideDomainVariantDistanceCount',
  );
  stdout.writeln('wrote ${markdownFile.path}');
  stdout.writeln('wrote ${jsonFile.path}');
}

Map<String, Object?> _distanceRecord({
  required Matsuzaki2006EventBaseline event,
  required Matsuzaki2006SourceBackedEventGeometry configuration,
  required Matsuzaki2006SourceBackedGeometryVariant variant,
  required Matsuzaki2006StationDistanceOverride station,
}) => {
  'eventId': event.eventId,
  'year': event.year,
  'regionName': configuration.regionName,
  'stationId': station.originalStation.stationId,
  'stationLatitude': station.originalStation.latitude,
  'stationLongitude': station.originalStation.longitude,
  'observedIntensity': station.originalStation.observedIntensity,
  'catalogDepthKm': event.depthKm,
  'magnitude': event.magnitude,
  'pointSourceDistanceKm': station.pointSourceDistanceKm,
  'geometryVariantId': variant.id,
  'finiteFaultDistanceKm': station.finiteFaultDistanceKm,
  'finiteFaultMinusPointSourceKm':
      station.finiteFaultDistanceKm - station.pointSourceDistanceKm,
  'finiteFaultEvaluationStatus': station.isInsidePublishedDistanceDomain
      ? 'evaluated'
      : 'outside_published_source_distance_domain',
};

_PopulationSummary _populationSummary(
  List<Matsuzaki2006StationDistanceOverride> stations,
) {
  final exclusions = <Map<String, Object>>[];
  for (final station in stations) {
    if (!station.isInsidePublishedDistanceDomain) {
      exclusions.add({
        'stationId': station.originalStation.stationId,
        'finiteFaultDistanceKm': station.finiteFaultDistanceKm,
        'reason': 'outside_published_source_distance_domain_1_to_500_km',
      });
    }
  }
  return _PopulationSummary(
    distanceRecordCount: stations.length,
    evaluableDistanceCount: stations.length - exclusions.length,
    outsideDomainDistanceCount: exclusions.length,
    distanceSummary: _summary(
      stations.map((station) => station.finiteFaultDistanceKm).toList(),
    ),
    differenceSummary: _summary(
      stations
          .map(
            (station) =>
                station.finiteFaultDistanceKm - station.pointSourceDistanceKm,
          )
          .toList(),
    ),
    exclusions: exclusions,
  );
}

class _PopulationSummary {
  const _PopulationSummary({
    required this.distanceRecordCount,
    required this.evaluableDistanceCount,
    required this.outsideDomainDistanceCount,
    required this.distanceSummary,
    required this.differenceSummary,
    required this.exclusions,
  });

  final int distanceRecordCount;
  final int evaluableDistanceCount;
  final int outsideDomainDistanceCount;
  final Map<String, Object> distanceSummary;
  final Map<String, Object> differenceSummary;
  final List<Map<String, Object>> exclusions;

  Map<String, Object> toJson() => {
    'distanceRecordCount': distanceRecordCount,
    'evaluableDistanceCount': evaluableDistanceCount,
    'outsidePublishedDistanceDomainCount': outsideDomainDistanceCount,
    'distanceSummary': distanceSummary,
    'finiteFaultMinusPointSourceSummary': differenceSummary,
    'distanceExclusions': exclusions,
  };
}

bool _isPublishedDistance(double distanceKm) =>
    distanceKm >= Matsuzaki2006AttenuationModel.minimumSourceDistanceKm &&
    distanceKm <= Matsuzaki2006AttenuationModel.maximumSourceDistanceKm;

Map<String, Object> _summary(List<double> values) {
  if (values.isEmpty) {
    return const {'count': 0};
  }
  var sum = 0.0;
  var minimum = values.first;
  var maximum = values.first;
  for (final value in values) {
    sum += value;
    if (value < minimum) minimum = value;
    if (value > maximum) maximum = value;
  }
  return {
    'count': values.length,
    'minimum': minimum,
    'mean': sum / values.length,
    'maximum': maximum,
  };
}

Map<String, Object?> _readJsonObject(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync(encoding: utf8));
  if (decoded is! Map<String, Object?>) {
    throw FormatException('Expected a JSON object in $path.');
  }
  return decoded;
}

List<String> _values(List<String> arguments, String name) {
  final values = <String>[];
  for (var index = 0; index < arguments.length; index++) {
    if (arguments[index] == name && index + 1 < arguments.length) {
      values.add(arguments[index + 1]);
      index++;
    }
  }
  return values;
}

String? _value(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index == -1 || index + 1 >= arguments.length) return null;
  return arguments[index + 1];
}

String _toMarkdown(
  List<Map<String, Object?>> events,
  Map<String, Object?> catalogStatus,
) {
  final buffer = StringBuffer()
    ..writeln('# Matsuzaki 2006 Finite-Fault Distance Catalog')
    ..writeln()
    ..writeln(
      'This report is a geometry-only experiment. It reads the original JMA '
      'annual datasets, does not refit coefficients, and applies no distance '
      'floor.',
    )
    ..writeln()
    ..writeln('## Catalog Status')
    ..writeln()
    ..writeln('- Events: ${catalogStatus['eventCount']}')
    ..writeln(
      '- Unique point-source nearfield event/station pairs: '
      '${catalogStatus['pointSourceNearfieldEventStationPairCount']}',
    )
    ..writeln(
      '- Geometry-variant distance records: '
      '${catalogStatus['geometryVariantDistanceRecordCount']}',
    )
    ..writeln(
      '- Outside published 1-500 km distance domain: '
      '${catalogStatus['outsidePublishedDistanceDomainRecordCount']}',
    )
    ..writeln(
      '- Full accepted event/station pairs: '
      '${catalogStatus['fullAcceptedEventStationPairCount']}',
    )
    ..writeln(
      '- Full geometry-variant distance records: '
      '${catalogStatus['fullAcceptedGeometryVariantDistanceRecordCount']}',
    )
    ..writeln(
      '- Full records outside published 1-500 km distance domain: '
      '${catalogStatus['fullAcceptedOutsidePublishedDistanceDomainRecordCount']}',
    )
    ..writeln(
      '- Ready for 2010-2016 finite-fault semantic calibration: '
      '${catalogStatus['readyForFiniteFaultSemanticCalibration2010To2016']}',
    )
    ..writeln()
    ..writeln('## Events')
    ..writeln()
    ..writeln(
      '| Event | Region | Nearfield pairs | Geometry variants | Selection |',
    )
    ..writeln('|---|---|---:|---:|---|');
  for (final event in events) {
    buffer.writeln(
      '| `${event['eventId']}` | ${event['regionName']} | '
      '${event['pointSourceNearfieldStationCount']} | '
      '${event['geometryVariantCount']} | '
      '${event['geometrySelectionStatus']} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Geometry Variants')
    ..writeln();
  for (final event in events) {
    buffer
      ..writeln('### ${event['regionName']}')
      ..writeln()
      ..writeln(
        '| Variant | Near count | Near evaluable | Near outside | Near min km | '
        'Near mean km | Near max km | Full count | Full evaluable | '
        'Full outside | Full mean km |',
      )
      ..writeln('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
    final variants = event['geometryVariants']! as List<Map<String, Object?>>;
    for (final variant in variants) {
      final distance = variant['distanceSummary']! as Map<String, Object>;
      final full =
          variant['fullAcceptedEventStationPopulation']! as Map<String, Object>;
      final fullDistance = full['distanceSummary']! as Map<String, Object>;
      buffer.writeln(
        '| `${variant['id']}` | ${variant['distanceRecordCount']} | '
        '${variant['evaluableDistanceCount']} | '
        '${variant['outsidePublishedDistanceDomainCount']} | '
        '${_metric(distance['minimum']! as double)} | '
        '${_metric(distance['mean']! as double)} | '
        '${_metric(distance['maximum']! as double)} | '
        '${full['distanceRecordCount']} | ${full['evaluableDistanceCount']} | '
        '${full['outsidePublishedDistanceDomainCount']} | '
        '${_metric(fullDistance['mean']! as double)} |',
      );
    }
    buffer.writeln();
  }
  buffer
    ..writeln('## Boundary')
    ..writeln()
    ..writeln(
      'The 2010-2016 calibration population has one unambiguous source-backed '
      'geometry for each configured event. Osaka retains both source-backed '
      'geometry variants; independent source-structure evidence prefers the '
      'double-rectangle union, while the single rectangle remains a '
      'lower-resolution geodetic simplification. This preference does not use '
      'the frozen intensity residual. '
      'Distances below 1 km are preserved in JSON and marked outside the '
      'published attenuation domain.',
    );
  return buffer.toString();
}

String _metric(double value) => value.toStringAsFixed(6);
