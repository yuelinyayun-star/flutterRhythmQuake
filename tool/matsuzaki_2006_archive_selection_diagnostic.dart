import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';
import 'package:flutterrhythmquake/core/replay/jma_intensity_archive.dart';

const _minimumDepthKm = 5.0;
const _maximumDepthKm = 100.0;
const _minimumObservations = 10;

void main(List<String> arguments) {
  final manifestPath = _value(arguments, '--manifest');
  final years = _years(arguments);
  final outputDirectoryPath =
      _value(arguments, '--output-dir') ??
      '.dart_tool/matsuzaki_2006_archive_selection_diagnostic';
  if (manifestPath == null || years.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/matsuzaki_2006_archive_selection_diagnostic.dart '
      '--manifest <archive_manifest.json> --years <2010,2011,...> '
      '[--output-dir <directory>]',
    );
    exitCode = 64;
    return;
  }

  final manifest = _readJsonObject(manifestPath);
  final stationManifest = manifest['stationTable'];
  final yearManifest = manifest['years'];
  if (stationManifest is! Map<String, Object?> ||
      yearManifest is! List<Object?>) {
    throw const FormatException('Archive manifest has no station/year data.');
  }
  final stationDataPath = stationManifest['dataFile'];
  if (stationDataPath is! String) {
    throw const FormatException('Station data path is missing.');
  }
  final stationFile = File(stationDataPath);
  _verifyDataFile(
    file: stationFile,
    expectedBytes: stationManifest['dataBytes'],
  );
  final stations = const JmaIntensityStationTableParser().parse(
    stationFile.readAsBytesSync(),
  );
  if (stations.isEmpty) {
    throw const FormatException('Station table contains no valid stations.');
  }

  final manifestByYear = <int, Map<String, Object?>>{};
  for (final item in yearManifest) {
    if (item is! Map<String, Object?> || item['year'] is! num) continue;
    manifestByYear[(item['year']! as num).toInt()] = item;
  }
  final models = <String, Matsuzaki2006AttenuationModel>{
    'published': const Matsuzaki2006AttenuationModel(),
    'finiteFaultSemanticFrozen2017': const Matsuzaki2006AttenuationModel(
      coefficients:
          Matsuzaki2006AttenuationCoefficients.finiteFaultSemanticFrozen2017,
    ),
  };
  final events = <Map<String, Object?>>[];
  final yearInputSummaries = <String, Object?>{};

  for (final year in years) {
    final source = manifestByYear[year];
    if (source == null) {
      throw FormatException('Year $year is not present in the manifest.');
    }
    final dataPath = source['dataFile'];
    if (dataPath is! String) {
      throw FormatException('Year $year has no raw data path.');
    }
    final dataFile = File(dataPath);
    _verifyDataFile(file: dataFile, expectedBytes: source['dataBytes']);
    final rawEvents = const JmaIntensityArchiveParser().parse(
      dataFile.readAsBytesSync(),
    );
    final statusCounts = <String, int>{};
    var accepted = 0;
    for (final event in rawEvents) {
      final prepared = _prepareEvent(event: event, stations: stations);
      _increment(statusCounts, prepared.status);
      if (!prepared.isReady) continue;
      accepted++;
      final activeDomainStations = <_DomainStation>[];
      for (final station in stations.values) {
        if (!station.wasActiveAt(prepared.originTime)) continue;
        final sourceDistanceKm =
            Matsuzaki2006PointSourceGeometry.hypocentralDistanceBetween(
              sourceLatitude: prepared.latitude,
              sourceLongitude: prepared.longitude,
              stationLatitude: station.latitude,
              stationLongitude: station.longitude,
              depthKm: prepared.depthKm,
            );
        if (sourceDistanceKm <
                Matsuzaki2006AttenuationModel.minimumSourceDistanceKm ||
            sourceDistanceKm >
                Matsuzaki2006AttenuationModel.maximumSourceDistanceKm) {
          continue;
        }
        activeDomainStations.add(
          _DomainStation(station: station, sourceDistanceKm: sourceDistanceKm),
        );
      }
      final modelResults = <String, Object?>{};
      for (final entry in models.entries) {
        modelResults[entry.key] = _modelEventDiagnostic(
          model: entry.value,
          prepared: prepared,
          activeDomainStations: activeDomainStations,
        );
      }
      final activeDomainStationIds = {
        for (final item in activeDomainStations) item.station.stationId,
      };
      final archivedActiveDomainStationIds = prepared.reportedStationIds
          .intersection(activeDomainStationIds);
      final validActiveDomainStationIds = prepared.validObservations.keys
          .where(activeDomainStationIds.contains)
          .toSet();
      var validInactiveAtOriginCount = 0;
      var validActiveBelowDistanceDomainCount = 0;
      var validActiveAboveDistanceDomainCount = 0;
      for (final observation in prepared.validObservations.values) {
        if (!observation.station.wasActiveAt(prepared.originTime)) {
          validInactiveAtOriginCount++;
          continue;
        }
        final sourceDistanceKm =
            Matsuzaki2006PointSourceGeometry.hypocentralDistanceBetween(
              sourceLatitude: prepared.latitude,
              sourceLongitude: prepared.longitude,
              stationLatitude: observation.station.latitude,
              stationLongitude: observation.station.longitude,
              depthKm: prepared.depthKm,
            );
        if (sourceDistanceKm <
            Matsuzaki2006AttenuationModel.minimumSourceDistanceKm) {
          validActiveBelowDistanceDomainCount++;
        } else if (sourceDistanceKm >
            Matsuzaki2006AttenuationModel.maximumSourceDistanceKm) {
          validActiveAboveDistanceDomainCount++;
        }
      }
      final officialCount = prepared.officialIntensityStationCount;
      events.add({
        'year': year,
        'eventId': prepared.eventId,
        'originTime': prepared.originTime.toIso8601String(),
        'catalog': {
          'latitude': prepared.latitude,
          'longitude': prepared.longitude,
          'depthKm': prepared.depthKm,
          'magnitude': prepared.magnitude,
          'magnitudeType': prepared.magnitudeType,
        },
        'archiveSelection': {
          'officialIntensityStationCount': officialCount,
          'rawObservationRecordCount': prepared.rawObservationRecordCount,
          'validInstrumentalObservationCount':
              prepared.validObservations.length,
          'officialCountMinusRawRecordCount': officialCount == null
              ? null
              : officialCount - prepared.rawObservationRecordCount,
          'minimumReportedInstrumentalIntensity': prepared
              .validObservations
              .values
              .map((item) => item.intensity)
              .reduce(math.min),
          'maximumReportedInstrumentalIntensity': prepared
              .validObservations
              .values
              .map((item) => item.intensity)
              .reduce(math.max),
          'reportedStationMissingFromTableCount':
              prepared.reportedStationMissingFromTableIds.length,
          'reportedStationMissingFromTableIds':
              prepared.reportedStationMissingFromTableIds,
          'reportedStationInactiveAtOriginCount':
              prepared.reportedStationInactiveAtOriginIds.length,
          'reportedStationInactiveAtOriginIds':
              prepared.reportedStationInactiveAtOriginIds,
          'activeDomainStationOpportunityCount': activeDomainStations.length,
          'archivedActiveDomainStationCount':
              archivedActiveDomainStationIds.length,
          'validInstrumentalActiveDomainStationCount':
              validActiveDomainStationIds.length,
          'validInstrumentalOutsideActiveDomainStationCount':
              prepared.validObservations.length -
              validActiveDomainStationIds.length,
          'validInstrumentalInactiveAtOriginCount': validInactiveAtOriginCount,
          'validInstrumentalActiveBelowDistanceDomainCount':
              validActiveBelowDistanceDomainCount,
          'validInstrumentalActiveAboveDistanceDomainCount':
              validActiveAboveDistanceDomainCount,
        },
        'models': modelResults,
      });
    }
    yearInputSummaries['$year'] = {
      'rawEventCount': rawEvents.length,
      'acceptedEventCount': accepted,
      'statusCounts': _sortedCounts(statusCounts),
      'rawDataPath': dataFile.path,
      'rawDataBytes': dataFile.lengthSync(),
      'archiveUrl': source['archiveUrl'],
      'archiveSha256': source['archiveSha256'],
    };
    stdout.writeln('processed $year: $accepted eligible events');
  }

  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_archive_selection_diagnostic_v1',
    'protocolStatus': 'opened_years_diagnostic_not_blind',
    'manifestPath': manifestPath,
    'officialIndexUrl': manifest['officialIndexUrl'],
    'years': years,
    'stationTable': {
      'dataPath': stationFile.path,
      'dataBytes': stationFile.lengthSync(),
      'stationCount': stations.length,
      'archiveUrl': stationManifest['url'],
      'archiveSha256': stationManifest['archiveSha256'],
    },
    'selectionSemantics': {
      'archived':
          'A station has an original event observation record. Valid '
          'instrumental intensity is never replaced or modified.',
      'notArchived':
          'The station table marks the station active at origin time and its '
          'catalog-source distance is 1-500 km, but the event has no station '
          'record. This is not assigned intensity zero or any other value.',
      'predictionUse':
          'Model intensity at the catalog source is used only to stratify '
          'archive inclusion. It is not an observation or imputed value.',
    },
    'eligibility': {
      'magnitudeRange': [
        Matsuzaki2006AttenuationModel.minimumMagnitude,
        Matsuzaki2006AttenuationModel.maximumMagnitude,
      ],
      'supportedMagnitudeTypes':
          Matsuzaki2006JmaBaselineEvaluator.supportedMagnitudeTypes.toList()
            ..sort(),
      'depthRangeKm': [_minimumDepthKm, _maximumDepthKm],
      'minimumValidInstrumentalObservations': _minimumObservations,
      'alternateHypocentersExcluded': true,
    },
    'yearInputSummaries': yearInputSummaries,
    'archiveSummary': _archiveSummary(events),
    'modelSummaries': {
      for (final modelName in models.keys)
        modelName: _modelSummary(events, modelName),
    },
    'events': events,
  };
  final outputDirectory = Directory(outputDirectoryPath)
    ..createSync(recursive: true);
  final jsonFile = File('${outputDirectory.path}/report.json');
  jsonFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report),
    encoding: utf8,
  );
  final markdownFile = File('${outputDirectory.path}/report.md');
  markdownFile.writeAsStringSync(_markdown(report), encoding: utf8);
  stdout.writeln(jsonEncode(report['archiveSummary']));
  stdout.writeln(jsonEncode(report['modelSummaries']));
  stdout.writeln('wrote ${jsonFile.path}');
  stdout.writeln('wrote ${markdownFile.path}');
}

_PreparedEvent _prepareEvent({
  required JmaIntensityEvent event,
  required Map<String, JmaIntensityStation> stations,
}) {
  if (event.hypocenters.length != 1) {
    return _PreparedEvent.invalid('alternate_hypocenters');
  }
  final source = event.preferredHypocenter;
  final depthKm = source.depthKm;
  final magnitude = source.magnitude;
  if (depthKm == null ||
      depthKm < _minimumDepthKm ||
      depthKm > _maximumDepthKm) {
    return _PreparedEvent.invalid('depth_outside_diagnostic_range');
  }
  if (magnitude == null ||
      magnitude < Matsuzaki2006AttenuationModel.minimumMagnitude ||
      magnitude > Matsuzaki2006AttenuationModel.maximumMagnitude) {
    return _PreparedEvent.invalid('magnitude_outside_published_range');
  }
  final magnitudeType = source.magnitudeType.trim();
  if (!Matsuzaki2006JmaBaselineEvaluator.supportedMagnitudeTypes.contains(
    magnitudeType,
  )) {
    return _PreparedEvent.invalid('unsupported_magnitude_type');
  }
  final valid = <String, _ReportedObservation>{};
  final reportedStationIds = <String>{};
  final missingFromTableIds = <String>[];
  final inactiveAtOriginIds = <String>[];
  for (final observation in event.observations) {
    final stationId = observation.stationId;
    if (!reportedStationIds.add(stationId)) {
      throw FormatException(
        'Duplicate station $stationId in event ${event.eventId}.',
      );
    }
    final station = stations[stationId];
    if (station == null) {
      missingFromTableIds.add(stationId);
      continue;
    }
    if (!station.wasActiveAt(source.originTime)) {
      inactiveAtOriginIds.add(stationId);
    }
    final intensity = observation.instrumentalIntensity;
    if (intensity == null || !intensity.isFinite) continue;
    valid[stationId] = _ReportedObservation(
      station: station,
      intensity: intensity,
    );
  }
  if (valid.length < _minimumObservations) {
    return _PreparedEvent.invalid('insufficient_instrumental_observations');
  }
  return _PreparedEvent.ready(
    eventId: event.eventId,
    originTime: source.originTime,
    latitude: source.latitude,
    longitude: source.longitude,
    depthKm: depthKm,
    magnitude: magnitude,
    magnitudeType: magnitudeType,
    officialIntensityStationCount: source.intensityStationCount,
    rawObservationRecordCount: event.observations.length,
    validObservations: valid,
    reportedStationIds: reportedStationIds,
    reportedStationMissingFromTableIds: missingFromTableIds,
    reportedStationInactiveAtOriginIds: inactiveAtOriginIds,
  );
}

Map<String, Object?> _modelEventDiagnostic({
  required Matsuzaki2006AttenuationModel model,
  required _PreparedEvent prepared,
  required List<_DomainStation> activeDomainStations,
}) {
  final opportunityByPrediction = <String, int>{};
  final archivedByPrediction = <String, int>{};
  final notArchivedByPrediction = <String, int>{};
  final opportunityByDistance = <String, int>{};
  final archivedByDistance = <String, int>{};
  final notArchivedByDistance = <String, int>{};
  var archivedWithInstrumental = 0;
  var residualSum = 0.0;
  var residualSquaredSum = 0.0;
  for (final item in activeDomainStations) {
    final predicted = model.predictIntensity(
      magnitude: prepared.magnitude,
      sourceDistanceKm: item.sourceDistanceKm,
      depthKm: prepared.depthKm,
    );
    final predictionBin = _predictionBin(predicted);
    final distanceBin = _distanceBin(item.sourceDistanceKm);
    _increment(opportunityByPrediction, predictionBin);
    _increment(opportunityByDistance, distanceBin);
    final stationId = item.station.stationId;
    if (prepared.reportedStationIds.contains(stationId)) {
      _increment(archivedByPrediction, predictionBin);
      _increment(archivedByDistance, distanceBin);
      final observation = prepared.validObservations[stationId];
      if (observation != null) {
        archivedWithInstrumental++;
        final residual = observation.intensity - predicted;
        residualSum += residual;
        residualSquaredSum += residual * residual;
      }
    } else {
      _increment(notArchivedByPrediction, predictionBin);
      _increment(notArchivedByDistance, distanceBin);
    }
  }
  final archivedCount = archivedByPrediction.values.fold<int>(
    0,
    (sum, value) => sum + value,
  );
  final notArchivedCount = notArchivedByPrediction.values.fold<int>(
    0,
    (sum, value) => sum + value,
  );
  return {
    'activeDomainOpportunityCount': activeDomainStations.length,
    'archivedCount': archivedCount,
    'notArchivedCount': notArchivedCount,
    'archivedWithInstrumentalIntensityCount': archivedWithInstrumental,
    'archivedResidualMean': archivedWithInstrumental == 0
        ? null
        : residualSum / archivedWithInstrumental,
    'archivedResidualRms': archivedWithInstrumental == 0
        ? null
        : math.sqrt(residualSquaredSum / archivedWithInstrumental),
    'opportunityByPredictionBin': _completePredictionBins(
      opportunityByPrediction,
    ),
    'archivedByPredictionBin': _completePredictionBins(archivedByPrediction),
    'notArchivedByPredictionBin': _completePredictionBins(
      notArchivedByPrediction,
    ),
    'opportunityByDistanceBin': _completeDistanceBins(opportunityByDistance),
    'archivedByDistanceBin': _completeDistanceBins(archivedByDistance),
    'notArchivedByDistanceBin': _completeDistanceBins(notArchivedByDistance),
  };
}

Map<String, Object?> _archiveSummary(List<Map<String, Object?>> events) {
  final selections = [
    for (final event in events)
      event['archiveSelection']! as Map<String, Object?>,
  ];
  int sumInt(String key) => selections.fold<int>(
    0,
    (sum, item) => sum + ((item[key] as num?)?.toInt() ?? 0),
  );
  final minimumIntensities = selections
      .map(
        (item) =>
            (item['minimumReportedInstrumentalIntensity']! as num).toDouble(),
      )
      .toList();
  return {
    'eligibleEventCount': events.length,
    'officialCountMissingEventCount': selections
        .where((item) => item['officialIntensityStationCount'] == null)
        .length,
    'officialCountMismatchEventCount': selections.where((item) {
      final difference = item['officialCountMinusRawRecordCount'];
      return difference is num && difference.toInt() != 0;
    }).length,
    'rawObservationRecordCount': sumInt('rawObservationRecordCount'),
    'validInstrumentalObservationCount': sumInt(
      'validInstrumentalObservationCount',
    ),
    'instrumentalIntensityMissingRecordCount':
        sumInt('rawObservationRecordCount') -
        sumInt('validInstrumentalObservationCount'),
    'minimumReportedInstrumentalIntensity': minimumIntensities.reduce(math.min),
    'reportedStationMissingFromTableCount': sumInt(
      'reportedStationMissingFromTableCount',
    ),
    'reportedStationInactiveAtOriginCount': sumInt(
      'reportedStationInactiveAtOriginCount',
    ),
    'activeDomainStationOpportunityCount': sumInt(
      'activeDomainStationOpportunityCount',
    ),
    'archivedActiveDomainStationCount': sumInt(
      'archivedActiveDomainStationCount',
    ),
    'validInstrumentalActiveDomainStationCount': sumInt(
      'validInstrumentalActiveDomainStationCount',
    ),
    'validInstrumentalOutsideActiveDomainStationCount': sumInt(
      'validInstrumentalOutsideActiveDomainStationCount',
    ),
    'validInstrumentalInactiveAtOriginCount': sumInt(
      'validInstrumentalInactiveAtOriginCount',
    ),
    'validInstrumentalActiveBelowDistanceDomainCount': sumInt(
      'validInstrumentalActiveBelowDistanceDomainCount',
    ),
    'validInstrumentalActiveAboveDistanceDomainCount': sumInt(
      'validInstrumentalActiveAboveDistanceDomainCount',
    ),
  };
}

Map<String, Object?> _modelSummary(
  List<Map<String, Object?>> events,
  String modelName,
) {
  final results = [
    for (final event in events)
      ((event['models']! as Map<String, Object?>)[modelName]!
          as Map<String, Object?>),
  ];
  Map<String, int> sumBins(String key, List<String> bins) {
    final total = {for (final bin in bins) bin: 0};
    for (final result in results) {
      final counts = result[key]! as Map<String, Object?>;
      for (final bin in bins) {
        total[bin] = total[bin]! + (counts[bin]! as num).toInt();
      }
    }
    return total;
  }

  final opportunities = sumBins('opportunityByPredictionBin', _predictionBins);
  final archived = sumBins('archivedByPredictionBin', _predictionBins);
  final notArchived = sumBins('notArchivedByPredictionBin', _predictionBins);
  final distanceOpportunities = sumBins(
    'opportunityByDistanceBin',
    _distanceBins,
  );
  final distanceArchived = sumBins('archivedByDistanceBin', _distanceBins);
  final distanceNotArchived = sumBins(
    'notArchivedByDistanceBin',
    _distanceBins,
  );
  final eventNotArchivedPredictedAtLeastPoint5Rates = <double>[];
  for (final result in results) {
    final counts =
        result['notArchivedByPredictionBin']! as Map<String, Object?>;
    final total = (result['notArchivedCount']! as num).toInt();
    if (total == 0) continue;
    final above = _predictionBins
        .skip(2)
        .fold<int>(0, (sum, bin) => sum + (counts[bin]! as num).toInt());
    eventNotArchivedPredictedAtLeastPoint5Rates.add(above / total);
  }
  final residualEventMeans = results
      .map((result) => result['archivedResidualMean'])
      .whereType<num>()
      .map((value) => value.toDouble())
      .toList();
  final residualEventRms = results
      .map((result) => result['archivedResidualRms'])
      .whereType<num>()
      .map((value) => value.toDouble())
      .toList();
  return {
    'eventCount': results.length,
    'predictionBins': _selectionBinSummary(
      bins: _predictionBins,
      opportunities: opportunities,
      archived: archived,
      notArchived: notArchived,
    ),
    'distanceBins': _selectionBinSummary(
      bins: _distanceBins,
      opportunities: distanceOpportunities,
      archived: distanceArchived,
      notArchived: distanceNotArchived,
    ),
    'notArchivedPredictedAtLeast0_5Count': _predictionBins
        .skip(2)
        .fold<int>(0, (sum, bin) => sum + notArchived[bin]!),
    'notArchivedPredictedAtLeast1_5Count': _predictionBins
        .skip(3)
        .fold<int>(0, (sum, bin) => sum + notArchived[bin]!),
    'eventNotArchivedPredictedAtLeast0_5RateMedian': _percentile(
      eventNotArchivedPredictedAtLeastPoint5Rates,
      0.5,
    ),
    'archivedResidualEventMeanAverage': residualEventMeans.isEmpty
        ? null
        : residualEventMeans.reduce((left, right) => left + right) /
              residualEventMeans.length,
    'archivedResidualEventRmsAverage': residualEventRms.isEmpty
        ? null
        : residualEventRms.reduce((left, right) => left + right) /
              residualEventRms.length,
  };
}

Map<String, Object?> _selectionBinSummary({
  required List<String> bins,
  required Map<String, int> opportunities,
  required Map<String, int> archived,
  required Map<String, int> notArchived,
}) => {
  for (final bin in bins)
    bin: {
      'opportunityCount': opportunities[bin],
      'archivedCount': archived[bin],
      'notArchivedCount': notArchived[bin],
      'archiveInclusionRate': opportunities[bin] == 0
          ? null
          : archived[bin]! / opportunities[bin]!,
    },
};

String _markdown(Map<String, Object?> report) {
  final summaries = report['modelSummaries']! as Map<String, Object?>;
  final buffer = StringBuffer()
    ..writeln('# Matsuzaki 2006 JMA Archive Selection Diagnostic')
    ..writeln()
    ..writeln('Years: `${(report['years']! as List<Object?>).join(', ')}`')
    ..writeln()
    ..writeln('Protocol status: `${report['protocolStatus']}`')
    ..writeln()
    ..writeln(
      'A notArchived station is never assigned intensity zero or any imputed '
      'value. Model prediction is used only to stratify archive inclusion.',
    )
    ..writeln()
    ..writeln('## Archive')
    ..writeln()
    ..writeln('```json')
    ..writeln(
      const JsonEncoder.withIndent('  ').convert(report['archiveSummary']),
    )
    ..writeln('```')
    ..writeln()
    ..writeln('## Models')
    ..writeln();
  for (final entry in summaries.entries) {
    buffer
      ..writeln('### ${entry.key}')
      ..writeln()
      ..writeln('```json')
      ..writeln(const JsonEncoder.withIndent('  ').convert(entry.value))
      ..writeln('```')
      ..writeln();
  }
  return buffer.toString();
}

const _predictionBins = <String>[
  'less_than_0',
  '0_to_less_than_0_5',
  '0_5_to_less_than_1_5',
  '1_5_to_less_than_2_5',
  '2_5_or_greater',
];

String _predictionBin(double value) {
  if (value < 0) return _predictionBins[0];
  if (value < 0.5) return _predictionBins[1];
  if (value < 1.5) return _predictionBins[2];
  if (value < 2.5) return _predictionBins[3];
  return _predictionBins[4];
}

Map<String, int> _completePredictionBins(Map<String, int> counts) => {
  for (final bin in _predictionBins) bin: counts[bin] ?? 0,
};

const _distanceBins = <String>[
  '1_to_less_than_30_km',
  '30_to_less_than_100_km',
  '100_to_less_than_300_km',
  '300_to_500_km',
];

String _distanceBin(double value) {
  if (value < 30) return _distanceBins[0];
  if (value < 100) return _distanceBins[1];
  if (value < 300) return _distanceBins[2];
  return _distanceBins[3];
}

Map<String, int> _completeDistanceBins(Map<String, int> counts) => {
  for (final bin in _distanceBins) bin: counts[bin] ?? 0,
};

Map<String, Object?> _readJsonObject(String path) {
  final file = File(path);
  if (!file.existsSync()) throw ArgumentError('File does not exist: $path');
  final decoded = jsonDecode(file.readAsStringSync(encoding: utf8));
  if (decoded is! Map<String, Object?>) {
    throw FormatException('Expected a JSON object: $path');
  }
  return decoded;
}

void _verifyDataFile({required File file, required Object? expectedBytes}) {
  if (!file.existsSync()) {
    throw ArgumentError('Raw data file does not exist: ${file.path}');
  }
  if (expectedBytes is num && file.lengthSync() != expectedBytes.toInt()) {
    throw FormatException(
      'Raw data size mismatch for ${file.path}: '
      '${file.lengthSync()} != ${expectedBytes.toInt()}.',
    );
  }
}

List<int> _years(List<String> arguments) {
  final raw = _value(arguments, '--years');
  if (raw == null) return const [];
  final years = <int>[];
  for (final part in raw.split(',')) {
    final value = int.tryParse(part.trim());
    if (value == null) throw FormatException('Invalid year: $part');
    if (!years.contains(value)) years.add(value);
  }
  years.sort();
  return years;
}

String? _value(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  return index >= 0 && index + 1 < arguments.length
      ? arguments[index + 1]
      : null;
}

void _increment(Map<String, int> counts, String key) {
  counts[key] = (counts[key] ?? 0) + 1;
}

Map<String, int> _sortedCounts(Map<String, int> counts) {
  final keys = counts.keys.toList()..sort();
  return {for (final key in keys) key: counts[key]!};
}

double? _percentile(List<double> values, double fraction) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final position = (sorted.length - 1) * fraction;
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower];
  final weight = position - lower;
  return sorted[lower] * (1 - weight) + sorted[upper] * weight;
}

class _PreparedEvent {
  const _PreparedEvent._({
    required this.status,
    required this.eventId,
    required this.originTime,
    required this.latitude,
    required this.longitude,
    required this.depthKm,
    required this.magnitude,
    required this.magnitudeType,
    required this.officialIntensityStationCount,
    required this.rawObservationRecordCount,
    required this.validObservations,
    required this.reportedStationIds,
    required this.reportedStationMissingFromTableIds,
    required this.reportedStationInactiveAtOriginIds,
  });

  factory _PreparedEvent.invalid(String status) => _PreparedEvent._(
    status: status,
    eventId: '',
    originTime: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    latitude: 0,
    longitude: 0,
    depthKm: 0,
    magnitude: 0,
    magnitudeType: '',
    officialIntensityStationCount: null,
    rawObservationRecordCount: 0,
    validObservations: const {},
    reportedStationIds: const {},
    reportedStationMissingFromTableIds: const [],
    reportedStationInactiveAtOriginIds: const [],
  );

  factory _PreparedEvent.ready({
    required String eventId,
    required DateTime originTime,
    required double latitude,
    required double longitude,
    required double depthKm,
    required double magnitude,
    required String magnitudeType,
    required int? officialIntensityStationCount,
    required int rawObservationRecordCount,
    required Map<String, _ReportedObservation> validObservations,
    required Set<String> reportedStationIds,
    required List<String> reportedStationMissingFromTableIds,
    required List<String> reportedStationInactiveAtOriginIds,
  }) => _PreparedEvent._(
    status: 'ready',
    eventId: eventId,
    originTime: originTime,
    latitude: latitude,
    longitude: longitude,
    depthKm: depthKm,
    magnitude: magnitude,
    magnitudeType: magnitudeType,
    officialIntensityStationCount: officialIntensityStationCount,
    rawObservationRecordCount: rawObservationRecordCount,
    validObservations: Map.unmodifiable(validObservations),
    reportedStationIds: Set.unmodifiable(reportedStationIds),
    reportedStationMissingFromTableIds: List.unmodifiable(
      reportedStationMissingFromTableIds,
    ),
    reportedStationInactiveAtOriginIds: List.unmodifiable(
      reportedStationInactiveAtOriginIds,
    ),
  );

  final String status;
  final String eventId;
  final DateTime originTime;
  final double latitude;
  final double longitude;
  final double depthKm;
  final double magnitude;
  final String magnitudeType;
  final int? officialIntensityStationCount;
  final int rawObservationRecordCount;
  final Map<String, _ReportedObservation> validObservations;
  final Set<String> reportedStationIds;
  final List<String> reportedStationMissingFromTableIds;
  final List<String> reportedStationInactiveAtOriginIds;

  bool get isReady => status == 'ready';
}

class _ReportedObservation {
  const _ReportedObservation({required this.station, required this.intensity});

  final JmaIntensityStation station;
  final double intensity;
}

class _DomainStation {
  const _DomainStation({required this.station, required this.sourceDistanceKm});

  final JmaIntensityStation station;
  final double sourceDistanceKm;
}
