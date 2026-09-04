import 'dart:math' as math;

import '../../services/sources/jp_shindo_scale.dart';
import 'srev_kaizou_scratch_station_table.dart';

const int srevKaizouScratchStationCount = 1748;
const double srevKaizouMinimumStationDistanceKm = 20.0;
const Duration srevKaizouMaximumShindoHoldDuration = Duration(seconds: 10);

const String srevKaizouMagnitudeModelId = 'srev_kaizou_scratch_magnitude_v1';
const String srevKaizouMagnitudeSourceRevision =
    't0729/srev-kaizou@fe881fe9a172c02e81c88011792af22804255a84';
const String srevKaizouMagnitudeSourceProjectSha256 =
    srevKaizouScratchProjectSha256;

class SrevKaizouMagnitudeStation {
  const SrevKaizouMagnitudeStation({
    required this.code,
    required this.latitude,
    required this.longitude,
    this.name,
  });

  final String code;
  final double latitude;
  final double longitude;
  final String? name;
}

class SrevKaizouMagnitudeResult {
  const SrevKaizouMagnitudeResult({
    required this.magnitude,
    required this.roundedSourceLatitude,
    required this.roundedSourceLongitude,
    required this.nearestStationCode,
    required this.nearestStationName,
    required this.nearestStationDistanceKm,
    required this.clampedStationDistanceKm,
    required this.inputIntensity,
    required this.processedIntensity,
    required this.multipleSources,
    required this.scannedStationCount,
  });

  final double magnitude;
  final double roundedSourceLatitude;
  final double roundedSourceLongitude;
  final String nearestStationCode;
  final String? nearestStationName;
  final double nearestStationDistanceKm;
  final double clampedStationDistanceKm;
  final double inputIntensity;
  final double processedIntensity;
  final bool multipleSources;
  final int scannedStationCount;

  Map<String, Object?> toDiagnostics() => <String, Object?>{
    'srev_kaizou_magnitude_model': srevKaizouMagnitudeModelId,
    'srev_kaizou_magnitude_source_revision': srevKaizouMagnitudeSourceRevision,
    'srev_kaizou_magnitude_source_project_sha256':
        srevKaizouMagnitudeSourceProjectSha256,
    'srev_kaizou_magnitude_supported': true,
    'srev_kaizou_magnitude': magnitude,
    'srev_kaizou_magnitude_source_latitude_rounded_0_1': roundedSourceLatitude,
    'srev_kaizou_magnitude_source_longitude_rounded_0_1':
        roundedSourceLongitude,
    'srev_kaizou_magnitude_nearest_station_code': nearestStationCode,
    'srev_kaizou_magnitude_nearest_station_name': nearestStationName,
    'srev_kaizou_magnitude_nearest_station_distance_km':
        nearestStationDistanceKm,
    'srev_kaizou_magnitude_clamped_station_distance_km':
        clampedStationDistanceKm,
    'srev_kaizou_magnitude_input_intensity': inputIntensity,
    'srev_kaizou_magnitude_processed_intensity': processedIntensity,
    'srev_kaizou_magnitude_branch': multipleSources
        ? 'multiple_sources_detection_max'
        : 'single_source_global_max',
    'srev_kaizou_magnitude_station_count': scannedStationCount,
    'srev_kaizou_magnitude_arithmetic':
        'scratch_two_pow10_then_log10_plus_1_73_log10_distance',
  };
}

/// Publishes one magnitude for each HYP report and freezes it at the
/// hypocenter's stable point.
class SrevKaizouMagnitudePublicationState {
  int? _targetReportNumber;
  int? _publishedReportNumber;
  SrevKaizouMagnitudeResult? _publishedResult;
  bool _locked = false;
  int? _lockedReportNumber;

  int? get targetReportNumber => _targetReportNumber;
  int? get publishedReportNumber => _publishedReportNumber;
  SrevKaizouMagnitudeResult? get publishedResult => _publishedResult;
  bool get locked => _locked;
  int? get lockedReportNumber => _lockedReportNumber;

  SrevKaizouMagnitudeResult? update({
    required int reportNumber,
    required bool stable,
    required SrevKaizouMagnitudeResult? Function() calculate,
  }) {
    if (reportNumber <= 0) return null;
    if (_locked) return _publishedResult;

    if (_targetReportNumber != reportNumber) {
      _targetReportNumber = reportNumber;
      _publishedReportNumber = null;
      _publishedResult = null;
    }

    // A report is consumed at most once. If the source data was not ready
    // when the report arrived, retry until that report obtains a valid value.
    if (_publishedResult == null) {
      final result = calculate();
      if (result != null) {
        _publishedReportNumber = reportNumber;
        _publishedResult = result;
      }
    }

    if (stable &&
        _publishedResult != null &&
        _publishedReportNumber == reportNumber) {
      _locked = true;
      _lockedReportNumber = reportNumber;
    }
    return _publishedResult;
  }

  void copyFrom(SrevKaizouMagnitudePublicationState source) {
    _targetReportNumber = source._targetReportNumber;
    _publishedReportNumber = source._publishedReportNumber;
    _publishedResult = source._publishedResult;
    _locked = source._locked;
    _lockedReportNumber = source._lockedReportNumber;
  }

  Map<String, Object?> toDiagnostics() => <String, Object?>{
    'srev_kaizou_magnitude_target_report_num': _targetReportNumber,
    'srev_kaizou_magnitude_published_report_num': _publishedReportNumber,
    'srev_kaizou_magnitude_locked': _locked,
    'srev_kaizou_magnitude_locked_report_num': _lockedReportNumber,
    'srev_kaizou_magnitude_update_policy':
        'hyp_report_change_then_lock_on_stable',
  };
}

final List<SrevKaizouMagnitudeStation> srevKaizouScratchStations =
    List<SrevKaizouMagnitudeStation>.unmodifiable(
      List<SrevKaizouMagnitudeStation>.generate(
        srevKaizouScratchStationTable.length,
        (index) {
          final station = srevKaizouScratchStationTable[index];
          return SrevKaizouMagnitudeStation(
            code: 'scratch:${(index + 1).toString().padLeft(4, '0')}',
            latitude: station.latitude,
            longitude: station.longitude,
            name: station.name,
          );
        },
        growable: false,
      ),
    );

double srevKaizouRoundCoordinate(double value) => (value * 10.0).round() / 10.0;

double srevKaizouStationDistanceKm({
  required double roundedSourceLatitude,
  required double roundedSourceLongitude,
  required double stationLatitude,
  required double stationLongitude,
}) {
  final latitudePart = (roundedSourceLatitude - stationLatitude) * 111.2;
  final longitudePart =
      6371.0 *
      (roundedSourceLongitude - stationLongitude) *
      (3.1416 / 180.0) *
      math.cos(
        ((roundedSourceLatitude + stationLatitude) / 2.0) * math.pi / 180.0,
      );
  return math.sqrt(latitudePart * latitudePart + longitudePart * longitudePart);
}

double? srevKaizouScratchConvertedShindo(double rawShindo) {
  if (!rawShindo.isFinite) return null;
  final level = JpShindoScale.levelFromShindo(rawShindo);
  if (level < 0) return null;
  return JpShindoScale.rawShindoFromLevel(level);
}

double srevKaizouProcessedIntensity(
  double inputIntensity, {
  required bool multipleSources,
}) {
  if (multipleSources && inputIntensity > 4.0) {
    return (inputIntensity - 4.0) / 2.0 + 5.0;
  }
  return inputIntensity;
}

double? srevKaizouMagnitudeFromDistanceAndIntensity({
  required double stationDistanceKm,
  required double inputIntensity,
  required bool multipleSources,
}) {
  if (!stationDistanceKm.isFinite ||
      stationDistanceKm <= 0.0 ||
      !inputIntensity.isFinite) {
    return null;
  }
  final processedIntensity = srevKaizouProcessedIntensity(
    inputIntensity,
    multipleSources: multipleSources,
  );
  final intensityExponent = (processedIntensity - 0.94) / 2.0;
  final firstIntensityPower = math.pow(10.0, intensityExponent).toDouble();
  final secondIntensityPower = math.pow(10.0, intensityExponent).toDouble();
  final intensityProduct = firstIntensityPower * secondIntensityPower;
  final magnitude =
      1.0 * (math.log(intensityProduct) / math.ln10) +
      1.73 * (math.log(stationDistanceKm) / math.ln10);
  if (!magnitude.isFinite) return null;
  return magnitude < 0.0 ? 0.0 : magnitude;
}

SrevKaizouMagnitudeResult? calculateSrevKaizouMagnitude({
  required double sourceLatitude,
  required double sourceLongitude,
  required double inputIntensity,
  required bool multipleSources,
  List<SrevKaizouMagnitudeStation>? stations,
}) {
  if (!sourceLatitude.isFinite ||
      !sourceLongitude.isFinite ||
      !inputIntensity.isFinite) {
    return null;
  }
  final stationTable = stations ?? srevKaizouScratchStations;
  if (stationTable.isEmpty) return null;

  final roundedLatitude = srevKaizouRoundCoordinate(sourceLatitude);
  final roundedLongitude = srevKaizouRoundCoordinate(sourceLongitude);
  SrevKaizouMagnitudeStation? nearestStation;
  var nearestDistanceKm = double.infinity;
  for (final station in stationTable) {
    if (!station.latitude.isFinite || !station.longitude.isFinite) continue;
    final distanceKm = srevKaizouStationDistanceKm(
      roundedSourceLatitude: roundedLatitude,
      roundedSourceLongitude: roundedLongitude,
      stationLatitude: station.latitude,
      stationLongitude: station.longitude,
    );
    if (!distanceKm.isFinite || distanceKm >= nearestDistanceKm) continue;
    nearestDistanceKm = distanceKm;
    nearestStation = station;
  }
  if (nearestStation == null || !nearestDistanceKm.isFinite) return null;

  final clampedDistanceKm = math.max(
    nearestDistanceKm,
    srevKaizouMinimumStationDistanceKm,
  );
  final magnitude = srevKaizouMagnitudeFromDistanceAndIntensity(
    stationDistanceKm: clampedDistanceKm,
    inputIntensity: inputIntensity,
    multipleSources: multipleSources,
  );
  if (magnitude == null) return null;

  return SrevKaizouMagnitudeResult(
    magnitude: magnitude,
    roundedSourceLatitude: roundedLatitude,
    roundedSourceLongitude: roundedLongitude,
    nearestStationCode: nearestStation.code,
    nearestStationName: nearestStation.name,
    nearestStationDistanceKm: nearestDistanceKm,
    clampedStationDistanceKm: clampedDistanceKm,
    inputIntensity: inputIntensity,
    processedIntensity: srevKaizouProcessedIntensity(
      inputIntensity,
      multipleSources: multipleSources,
    ),
    multipleSources: multipleSources,
    scannedStationCount: stationTable.length,
  );
}

class SrevKaizouMagnitudeIntensityState {
  SrevKaizouMagnitudeIntensityState({
    this.holdDuration = srevKaizouMaximumShindoHoldDuration,
  });

  final Duration holdDuration;
  final Map<String, _HeldSrevKaizouShindo> _heldByStationCode =
      <String, _HeldSrevKaizouShindo>{};
  DateTime? _lastObservedAt;

  void updateFrame(
    Map<String, double?> currentRawShindoByStationCode, {
    required DateTime observedAt,
  }) {
    final previousObservedAt = _lastObservedAt;
    if (previousObservedAt != null && observedAt.isBefore(previousObservedAt)) {
      clear();
    }
    _lastObservedAt = observedAt;
    _heldByStationCode.removeWhere((_, held) {
      return observedAt.difference(held.updatedAt) > holdDuration;
    });

    for (final entry in currentRawShindoByStationCode.entries) {
      final rawShindo = entry.value;
      if (rawShindo == null) continue;
      final convertedShindo = srevKaizouScratchConvertedShindo(rawShindo);
      if (convertedShindo == null) continue;
      final held = _heldByStationCode[entry.key];
      if (held == null ||
          convertedShindo > held.value ||
          observedAt.difference(held.updatedAt) > holdDuration) {
        _heldByStationCode[entry.key] = _HeldSrevKaizouShindo(
          value: convertedShindo,
          updatedAt: observedAt,
        );
      }
    }
  }

  double? maximumFor(Iterable<String> stationCodes) {
    var maximum = double.negativeInfinity;
    var found = false;
    for (final code in stationCodes) {
      final held = _heldByStationCode[code];
      if (held == null) continue;
      found = true;
      if (held.value > maximum) maximum = held.value;
    }
    return found ? maximum : null;
  }

  void clear() {
    _heldByStationCode.clear();
    _lastObservedAt = null;
  }
}

class _HeldSrevKaizouShindo {
  const _HeldSrevKaizouShindo({required this.value, required this.updatedAt});

  final double value;
  final DateTime updatedAt;
}
