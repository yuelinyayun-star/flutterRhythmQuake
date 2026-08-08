import 'dart:math' as math;

import 'matsuzaki_2006_attenuation_model.dart';
import 'matsuzaki_2006_geometry.dart';

class Matsuzaki2006ResidualSummary {
  const Matsuzaki2006ResidualSummary({
    required this.count,
    required this.meanResidual,
    required this.meanAbsoluteResidual,
    required this.rootMeanSquareResidual,
    required this.minimumResidual,
    required this.maximumResidual,
  });

  factory Matsuzaki2006ResidualSummary.fromResiduals(
    Iterable<double> residuals,
  ) {
    var count = 0;
    var sum = 0.0;
    var absoluteSum = 0.0;
    var squaredSum = 0.0;
    var minimum = double.infinity;
    var maximum = double.negativeInfinity;
    for (final residual in residuals) {
      count++;
      sum += residual;
      absoluteSum += residual.abs();
      squaredSum += residual * residual;
      minimum = math.min(minimum, residual);
      maximum = math.max(maximum, residual);
    }
    if (count == 0) {
      return const Matsuzaki2006ResidualSummary(
        count: 0,
        meanResidual: 0,
        meanAbsoluteResidual: 0,
        rootMeanSquareResidual: 0,
        minimumResidual: 0,
        maximumResidual: 0,
      );
    }
    return Matsuzaki2006ResidualSummary(
      count: count,
      meanResidual: sum / count,
      meanAbsoluteResidual: absoluteSum / count,
      rootMeanSquareResidual: math.sqrt(squaredSum / count),
      minimumResidual: minimum,
      maximumResidual: maximum,
    );
  }

  Map<String, Object> toJson() => {
    'count': count,
    'meanResidual': meanResidual,
    'meanAbsoluteResidual': meanAbsoluteResidual,
    'rootMeanSquareResidual': rootMeanSquareResidual,
    'minimumResidual': minimumResidual,
    'maximumResidual': maximumResidual,
  };

  final int count;
  final double meanResidual;
  final double meanAbsoluteResidual;
  final double rootMeanSquareResidual;
  final double minimumResidual;
  final double maximumResidual;
}

class Matsuzaki2006StationResidual {
  const Matsuzaki2006StationResidual({
    required this.stationId,
    required this.latitude,
    required this.longitude,
    required this.sourceDistanceKm,
    required this.observedIntensity,
    required this.predictedIntensity,
  });

  final String stationId;
  final double latitude;
  final double longitude;
  final double sourceDistanceKm;
  final double observedIntensity;
  final double predictedIntensity;

  double get residual => observedIntensity - predictedIntensity;

  Map<String, Object> toJson() => {
    'stationId': stationId,
    'latitude': latitude,
    'longitude': longitude,
    'sourceDistanceKm': sourceDistanceKm,
    'observedIntensity': observedIntensity,
    'predictedIntensity': predictedIntensity,
    'residual': residual,
  };
}

class Matsuzaki2006EventBaseline {
  Matsuzaki2006EventBaseline({
    required this.eventId,
    required this.year,
    required this.originTime,
    required this.latitude,
    required this.longitude,
    required this.depthKm,
    required this.magnitude,
    required this.magnitudeType,
    required this.maximumIntensityClass,
    required this.determinationFlag,
    required List<Matsuzaki2006StationResidual> stationResiduals,
  }) : stationResiduals = List.unmodifiable(stationResiduals),
       residualSummary = Matsuzaki2006ResidualSummary.fromResiduals(
         stationResiduals.map((station) => station.residual),
       );

  final String eventId;
  final int year;
  final String originTime;
  final double latitude;
  final double longitude;
  final double depthKm;
  final double magnitude;
  final String magnitudeType;
  final String maximumIntensityClass;
  final String determinationFlag;
  final List<Matsuzaki2006StationResidual> stationResiduals;
  final Matsuzaki2006ResidualSummary residualSummary;

  Map<String, Object> toJson() => {
    'eventId': eventId,
    'year': year,
    'originTime': originTime,
    'latitude': latitude,
    'longitude': longitude,
    'depthKm': depthKm,
    'magnitude': magnitude,
    'magnitudeType': magnitudeType,
    'maximumIntensityClass': maximumIntensityClass,
    'determinationFlag': determinationFlag,
    'stationCount': stationResiduals.length,
    'residualSummary': residualSummary.toJson(),
    'stations': stationResiduals.map((station) => station.toJson()).toList(),
  };
}

class Matsuzaki2006JmaBaselineResult {
  Matsuzaki2006JmaBaselineResult({
    required this.inputEventCount,
    required this.minimumStationsPerEvent,
    required Map<String, int> eventRejectionCounts,
    required Map<String, int> observationRejectionCounts,
    required List<Matsuzaki2006EventBaseline> events,
  }) : eventRejectionCounts = Map.unmodifiable(eventRejectionCounts),
       observationRejectionCounts = Map.unmodifiable(
         observationRejectionCounts,
       ),
       events = List.unmodifiable(events);

  final int inputEventCount;
  final int minimumStationsPerEvent;
  final Map<String, int> eventRejectionCounts;
  final Map<String, int> observationRejectionCounts;
  final List<Matsuzaki2006EventBaseline> events;

  int get stationResidualCount =>
      events.fold(0, (sum, event) => sum + event.stationResiduals.length);

  Matsuzaki2006ResidualSummary get overallResidualSummary =>
      Matsuzaki2006ResidualSummary.fromResiduals(
        events.expand(
          (event) => event.stationResiduals.map((station) => station.residual),
        ),
      );

  Map<String, Object> get eventEqualMetrics {
    if (events.isEmpty) {
      return const {
        'eventCount': 0,
        'meanOfEventMeanResiduals': 0.0,
        'meanOfEventMeanAbsoluteResiduals': 0.0,
        'meanOfEventRootMeanSquareResiduals': 0.0,
      };
    }
    var meanResidualSum = 0.0;
    var meanAbsoluteResidualSum = 0.0;
    var rootMeanSquareResidualSum = 0.0;
    for (final event in events) {
      meanResidualSum += event.residualSummary.meanResidual;
      meanAbsoluteResidualSum += event.residualSummary.meanAbsoluteResidual;
      rootMeanSquareResidualSum += event.residualSummary.rootMeanSquareResidual;
    }
    return {
      'eventCount': events.length,
      'meanOfEventMeanResiduals': meanResidualSum / events.length,
      'meanOfEventMeanAbsoluteResiduals':
          meanAbsoluteResidualSum / events.length,
      'meanOfEventRootMeanSquareResiduals':
          rootMeanSquareResidualSum / events.length,
    };
  }

  Map<String, Matsuzaki2006ResidualSummary> get byYear =>
      _groupedSummary((event, station) => event.year.toString());

  Map<String, Matsuzaki2006ResidualSummary> get byMagnitudeType =>
      _groupedSummary((event, station) => event.magnitudeType);

  Map<String, Matsuzaki2006ResidualSummary> get byMagnitudeBand =>
      _groupedSummary(
        (event, station) => event.magnitude < 6 ? '5.0-5.9' : '6.0-8.2',
      );

  Map<String, Matsuzaki2006ResidualSummary> get byDistanceBand =>
      _groupedSummary(
        (event, station) => _distanceBand(station.sourceDistanceKm),
      );

  Map<String, Matsuzaki2006ResidualSummary> get byDepthBand =>
      _groupedSummary((event, station) => _depthBand(event.depthKm));

  Map<String, Object> toJson() => {
    'schemaVersion': 'matsuzaki_2006_jma_forward_baseline_v1',
    'model': {
      'name': 'Matsuzaki-Hisada-Fukushima 2006 equation 12',
      'magnitudeRange': [
        Matsuzaki2006AttenuationModel.minimumMagnitude,
        Matsuzaki2006AttenuationModel.maximumMagnitude,
      ],
      'sourceDistanceRangeKm': [
        Matsuzaki2006AttenuationModel.minimumSourceDistanceKm,
        Matsuzaki2006AttenuationModel.maximumSourceDistanceKm,
      ],
      'sourceDepthDataRangeKm': [
        Matsuzaki2006AttenuationModel.minimumDepthKm,
        Matsuzaki2006AttenuationModel.maximumObservedDepthKm,
      ],
      'formulaDepthCapKm': Matsuzaki2006AttenuationModel.formulaDepthCapKm,
      'distanceDefinition': 'point_source_hypocentral_distance',
      'residualDefinition': 'observed_minus_predicted_instrumental_intensity',
    },
    'selection': {
      'supportedMagnitudeTypes': Matsuzaki2006JmaBaselineEvaluator
          .supportedMagnitudeTypes
          .toList(),
      'minimumStationsPerEvent': minimumStationsPerEvent,
      'observationDomain': 'JMA_archive_reported_intensity_1_or_higher',
      'alternateHypocenterPolicy':
          'exclude_events_with_unassigned_alternate_hypocenters',
    },
    'counts': {
      'inputEvents': inputEventCount,
      'acceptedEvents': events.length,
      'rejectedEvents': inputEventCount - events.length,
      'acceptedStationResiduals': stationResidualCount,
    },
    'eventRejectionCounts': eventRejectionCounts,
    'observationRejectionCounts': observationRejectionCounts,
    'overallResidualSummary': overallResidualSummary.toJson(),
    'eventEqualMetrics': eventEqualMetrics,
    'byYear': _summaryMapToJson(byYear),
    'byMagnitudeType': _summaryMapToJson(byMagnitudeType),
    'byMagnitudeBand': _summaryMapToJson(byMagnitudeBand),
    'byDistanceBand': _summaryMapToJson(byDistanceBand),
    'byDepthBand': _summaryMapToJson(byDepthBand),
    'events': events.map((event) => event.toJson()).toList(),
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Matsuzaki 2006 JMA Forward Baseline')
      ..writeln()
      ..writeln('This report evaluates the published coefficients at the JMA')
      ..writeln(
        'catalog hypocenter and depth. It does not search for a source.',
      )
      ..writeln()
      ..writeln(
        'Residual: `observed instrumental intensity - predicted intensity`.',
      )
      ..writeln()
      ..writeln(
        'The JMA annual archive contains reported intensity-1-or-higher',
      )
      ..writeln('stations; an absent station is not treated as intensity zero.')
      ..writeln()
      ..writeln('All grouped residual tables are station-weighted. A separate')
      ..writeln('event-equal summary is reported below. Rejection reasons are')
      ..writeln('non-exclusive and therefore do not sum to rejected events.')
      ..writeln()
      ..writeln('## Counts')
      ..writeln()
      ..writeln('| Metric | Value |')
      ..writeln('|---|---:|')
      ..writeln('| Input events | $inputEventCount |')
      ..writeln('| Accepted events | ${events.length} |')
      ..writeln('| Rejected events | ${inputEventCount - events.length} |')
      ..writeln('| Accepted station residuals | $stationResidualCount |')
      ..writeln('| Minimum stations per event | $minimumStationsPerEvent |');
    _writeCounts(buffer, 'Event Rejections', eventRejectionCounts);
    _writeCounts(buffer, 'Observation Rejections', observationRejectionCounts);
    _writeSummaryTable(buffer, 'Overall Residual', {
      'all': overallResidualSummary,
    });
    final equalMetrics = eventEqualMetrics;
    buffer
      ..writeln()
      ..writeln('## Event-Equal Residual')
      ..writeln()
      ..writeln(
        '| Events | Mean of event means | Mean event MAE | Mean event RMS |',
      )
      ..writeln('|---:|---:|---:|---:|')
      ..writeln(
        '| ${equalMetrics['eventCount']} | '
        '${(equalMetrics['meanOfEventMeanResiduals']! as double).toStringAsFixed(3)} | '
        '${(equalMetrics['meanOfEventMeanAbsoluteResiduals']! as double).toStringAsFixed(3)} | '
        '${(equalMetrics['meanOfEventRootMeanSquareResiduals']! as double).toStringAsFixed(3)} |',
      );
    _writeSummaryTable(buffer, 'By Year', byYear);
    _writeSummaryTable(buffer, 'By Magnitude Type', byMagnitudeType);
    _writeSummaryTable(buffer, 'By Magnitude Band', byMagnitudeBand);
    _writeSummaryTable(buffer, 'By Source Distance', byDistanceBand);
    _writeSummaryTable(buffer, 'By Depth', byDepthBand);

    buffer
      ..writeln()
      ..writeln('## Events')
      ..writeln()
      ..writeln(
        '| Event | Year | Type | M | Depth km | Stations | Mean | MAE | RMS |',
      )
      ..writeln('|---|---:|---|---:|---:|---:|---:|---:|---:|');
    for (final event in events) {
      final summary = event.residualSummary;
      buffer.writeln(
        '| `${event.eventId}` | ${event.year} | ${event.magnitudeType} | '
        '${event.magnitude.toStringAsFixed(1)} | '
        '${event.depthKm.toStringAsFixed(1)} | '
        '${event.stationResiduals.length} | '
        '${summary.meanResidual.toStringAsFixed(3)} | '
        '${summary.meanAbsoluteResidual.toStringAsFixed(3)} | '
        '${summary.rootMeanSquareResidual.toStringAsFixed(3)} |',
      );
    }
    return buffer.toString();
  }

  Map<String, Matsuzaki2006ResidualSummary> _groupedSummary(
    String Function(
      Matsuzaki2006EventBaseline event,
      Matsuzaki2006StationResidual station,
    )
    keyFor,
  ) {
    final residualsByKey = <String, List<double>>{};
    for (final event in events) {
      for (final station in event.stationResiduals) {
        final key = keyFor(event, station);
        residualsByKey.putIfAbsent(key, () => []).add(station.residual);
      }
    }
    final keys = residualsByKey.keys.toList()..sort();
    return {
      for (final key in keys)
        key: Matsuzaki2006ResidualSummary.fromResiduals(residualsByKey[key]!),
    };
  }

  static Map<String, Object> _summaryMapToJson(
    Map<String, Matsuzaki2006ResidualSummary> summaries,
  ) => {for (final entry in summaries.entries) entry.key: entry.value.toJson()};

  static void _writeCounts(
    StringBuffer buffer,
    String title,
    Map<String, int> counts,
  ) {
    buffer
      ..writeln()
      ..writeln('## $title')
      ..writeln()
      ..writeln('| Reason | Count |')
      ..writeln('|---|---:|');
    for (final entry in counts.entries) {
      buffer.writeln('| ${entry.key} | ${entry.value} |');
    }
  }

  static void _writeSummaryTable(
    StringBuffer buffer,
    String title,
    Map<String, Matsuzaki2006ResidualSummary> summaries,
  ) {
    buffer
      ..writeln()
      ..writeln('## $title')
      ..writeln()
      ..writeln('| Group | Stations | Mean | MAE | RMS | Min | Max |')
      ..writeln('|---|---:|---:|---:|---:|---:|---:|');
    for (final entry in summaries.entries) {
      final value = entry.value;
      buffer.writeln(
        '| ${entry.key} | ${value.count} | '
        '${value.meanResidual.toStringAsFixed(3)} | '
        '${value.meanAbsoluteResidual.toStringAsFixed(3)} | '
        '${value.rootMeanSquareResidual.toStringAsFixed(3)} | '
        '${value.minimumResidual.toStringAsFixed(3)} | '
        '${value.maximumResidual.toStringAsFixed(3)} |',
      );
    }
  }

  static String _distanceBand(double distanceKm) {
    if (distanceKm < 15) return '1-<15 km';
    if (distanceKm < 30) return '15-<30 km';
    if (distanceKm < 100) return '30-<100 km';
    return '100-500 km';
  }

  static String _depthBand(double depthKm) {
    if (depthKm < 30) return '0-<30 km';
    if (depthKm < 100) return '30-<100 km';
    return '100-183 km';
  }
}

class Matsuzaki2006JmaBaselineEvaluator {
  const Matsuzaki2006JmaBaselineEvaluator({
    this.minimumStationsPerEvent = 10,
    this.model = const Matsuzaki2006AttenuationModel(),
  });

  static const Set<String> supportedMagnitudeTypes = {'D', 'd', 'V', 'v'};

  final int minimumStationsPerEvent;
  final Matsuzaki2006AttenuationModel model;

  Matsuzaki2006JmaBaselineResult evaluate(
    Iterable<Map<String, Object?>> annualDatasets,
  ) {
    if (minimumStationsPerEvent <= 0) {
      throw StateError('minimumStationsPerEvent must be positive.');
    }
    final eventRejections = <String, int>{};
    final observationRejections = <String, int>{};
    final acceptedEvents = <Matsuzaki2006EventBaseline>[];
    var inputEventCount = 0;

    for (final dataset in annualDatasets) {
      final year = _number(dataset['year'])?.toInt();
      final rawEvents = dataset['events'];
      if (year == null || rawEvents is! List<Object?>) {
        throw const FormatException('Invalid JMA annual dataset envelope.');
      }
      for (final rawEvent in rawEvents) {
        inputEventCount++;
        if (rawEvent is! Map<String, Object?>) {
          _increment(eventRejections, 'invalid_event_record');
          continue;
        }
        final event = _evaluateEvent(
          event: rawEvent,
          year: year,
          eventRejections: eventRejections,
          observationRejections: observationRejections,
        );
        if (event != null) acceptedEvents.add(event);
      }
    }
    acceptedEvents.sort(
      (left, right) => left.originTime.compareTo(right.originTime),
    );
    return Matsuzaki2006JmaBaselineResult(
      inputEventCount: inputEventCount,
      minimumStationsPerEvent: minimumStationsPerEvent,
      eventRejectionCounts: _sortedCounts(eventRejections),
      observationRejectionCounts: _sortedCounts(observationRejections),
      events: acceptedEvents,
    );
  }

  Matsuzaki2006EventBaseline? _evaluateEvent({
    required Map<String, Object?> event,
    required int year,
    required Map<String, int> eventRejections,
    required Map<String, int> observationRejections,
  }) {
    final eventId = event['eventId'];
    final rawHypocenter = event['preferredHypocenter'];
    final rawAlternateHypocenters = event['alternateHypocenters'];
    final rawObservations = event['observations'];
    if (eventId is! String ||
        rawHypocenter is! Map<String, Object?> ||
        rawObservations is! List<Object?>) {
      _increment(eventRejections, 'invalid_event_record');
      return null;
    }

    final latitude = _number(rawHypocenter['latitude']);
    final longitude = _number(rawHypocenter['longitude']);
    final depthKm = _number(rawHypocenter['depthKm']);
    final magnitude = _number(rawHypocenter['magnitude']);
    final magnitudeType = (rawHypocenter['magnitudeType'] as String?)?.trim();
    final reasons = <String>[];
    if (rawAlternateHypocenters is List<Object?> &&
        rawAlternateHypocenters.isNotEmpty) {
      reasons.add('has_unassigned_alternate_hypocenters');
    }
    if (latitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude == null ||
        longitude < -180 ||
        longitude > 180) {
      reasons.add('invalid_hypocenter_coordinate');
    }
    if (depthKm == null ||
        depthKm < Matsuzaki2006AttenuationModel.minimumDepthKm ||
        depthKm > Matsuzaki2006AttenuationModel.maximumObservedDepthKm) {
      reasons.add('depth_outside_published_data_range');
    }
    if (magnitude == null ||
        magnitude < Matsuzaki2006AttenuationModel.minimumMagnitude ||
        magnitude > Matsuzaki2006AttenuationModel.maximumMagnitude) {
      reasons.add('magnitude_outside_published_calibration_range');
    }
    if (magnitudeType == null ||
        !supportedMagnitudeTypes.contains(magnitudeType)) {
      reasons.add('unsupported_magnitude_type');
    }
    if (reasons.isNotEmpty) {
      for (final reason in reasons) {
        _increment(eventRejections, reason);
      }
      return null;
    }
    final acceptedLatitude = latitude!;
    final acceptedLongitude = longitude!;
    final acceptedDepthKm = depthKm!;
    final acceptedMagnitude = magnitude!;
    final acceptedMagnitudeType = magnitudeType!;

    final stationResiduals = <Matsuzaki2006StationResidual>[];
    final seenStationIds = <String>{};
    for (final rawObservation in rawObservations) {
      if (rawObservation is! Map<String, Object?>) {
        _increment(observationRejections, 'invalid_observation_record');
        continue;
      }
      final stationId = rawObservation['stationId'];
      final stationLatitude = _number(rawObservation['latitude']);
      final stationLongitude = _number(rawObservation['longitude']);
      final observedIntensity = _number(
        rawObservation['instrumentalIntensity'],
      );
      if (stationId is! String || stationId.isEmpty) {
        _increment(observationRejections, 'missing_station_id');
        continue;
      }
      if (!seenStationIds.add(stationId)) {
        _increment(observationRejections, 'duplicate_station_id');
        continue;
      }
      if (stationLatitude == null ||
          stationLatitude < -90 ||
          stationLatitude > 90 ||
          stationLongitude == null ||
          stationLongitude < -180 ||
          stationLongitude > 180) {
        _increment(observationRejections, 'invalid_station_coordinate');
        continue;
      }
      if (observedIntensity == null || !observedIntensity.isFinite) {
        _increment(observationRejections, 'missing_instrumental_intensity');
        continue;
      }
      final sourceDistanceKm =
          Matsuzaki2006PointSourceGeometry.hypocentralDistanceBetween(
            sourceLatitude: acceptedLatitude,
            sourceLongitude: acceptedLongitude,
            stationLatitude: stationLatitude,
            stationLongitude: stationLongitude,
            depthKm: acceptedDepthKm,
          );
      if (sourceDistanceKm <
              Matsuzaki2006AttenuationModel.minimumSourceDistanceKm ||
          sourceDistanceKm >
              Matsuzaki2006AttenuationModel.maximumSourceDistanceKm) {
        _increment(
          observationRejections,
          'source_distance_outside_published_calibration_range',
        );
        continue;
      }
      stationResiduals.add(
        Matsuzaki2006StationResidual(
          stationId: stationId,
          latitude: stationLatitude,
          longitude: stationLongitude,
          sourceDistanceKm: sourceDistanceKm,
          observedIntensity: observedIntensity,
          predictedIntensity: model.predictIntensity(
            magnitude: acceptedMagnitude,
            sourceDistanceKm: sourceDistanceKm,
            depthKm: acceptedDepthKm,
          ),
        ),
      );
    }
    if (stationResiduals.length < minimumStationsPerEvent) {
      _increment(eventRejections, 'fewer_than_minimum_usable_stations');
      return null;
    }

    return Matsuzaki2006EventBaseline(
      eventId: eventId,
      year: year,
      originTime: (rawHypocenter['originTime'] as String?) ?? '',
      latitude: acceptedLatitude,
      longitude: acceptedLongitude,
      depthKm: acceptedDepthKm,
      magnitude: acceptedMagnitude,
      magnitudeType: acceptedMagnitudeType,
      maximumIntensityClass:
          (rawHypocenter['maximumIntensityClass'] as String?)?.trim() ?? '',
      determinationFlag:
          (rawHypocenter['determinationFlag'] as String?)?.trim() ?? '',
      stationResiduals: stationResiduals,
    );
  }

  static double? _number(Object? value) =>
      value is num ? value.toDouble() : null;

  static void _increment(Map<String, int> counts, String key) {
    counts[key] = (counts[key] ?? 0) + 1;
  }

  static Map<String, int> _sortedCounts(Map<String, int> counts) {
    final keys = counts.keys.toList()..sort();
    return {for (final key in keys) key: counts[key]!};
  }
}
