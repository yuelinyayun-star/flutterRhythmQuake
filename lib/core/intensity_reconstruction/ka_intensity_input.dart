import 'package:latlong2/latlong.dart';

/// The measurement domain carried by an independent Japanese intensity input.
///
/// These values are deliberately separate. A Yahoo KA level is an encoded
/// bucket, while a GIF value is a continuous instrumental-shindo estimate
/// decoded from a color pixel.
enum KaIntensityValueKind { yahooLevel, gifContinuousShindo }

/// Exact KA level semantics used by Yahoo's real-time intensity string.
class KaLevelScale {
  KaLevelScale._();

  static const int noData = -1;
  static const int minimum = 0;
  static const int maximum = 20;

  static bool isInDomain(int level) => level >= noData && level <= maximum;

  /// Mirrors KA `getLevelFromInstShindo` without using the old 30-value
  /// Scratch scale.
  static int fromContinuousShindo(double shindo) {
    if (!shindo.isFinite || shindo < -3.0) return noData;
    if (shindo == -3.0) return 0;
    if (shindo >= 6.5) return 20;
    return (shindo * 2 + 7).floor();
  }

  /// Representative midpoint used only for diagnostics and plotting.
  ///
  /// Yahoo provides a bucket, not this floating-point value. Callers must not
  /// treat the midpoint as an observed continuous shindo.
  static double diagnosticMidpoint(int level) {
    if (level < minimum || level > maximum) {
      throw ArgumentError.value(level, 'level', 'Expected KA level 0..20.');
    }
    if (level == 0) return -3.0;
    if (level == 20) return 6.5;
    return (level + 0.5 - 7) / 2;
  }

  static String jmaClassLabel(int level) {
    if (level < minimum || level > maximum) return 'no_data';
    if (level <= 7) return '0';
    if (level <= 9) return '1';
    if (level <= 11) return '2';
    if (level <= 13) return '3';
    if (level <= 15) return '4';
    if (level == 16) return '5-';
    if (level == 17) return '5+';
    if (level == 18) return '6-';
    if (level == 19) return '6+';
    return '7';
  }

  /// Human-readable instrumental-shindo interval represented by a KA level.
  static String intervalLabel(int level) {
    if (level == 0) return 'I = -3.0';
    if (level == 1) return '-3.0 < I < -2.5';
    if (level >= 2 && level <= 19) {
      final lower = (level - 7) / 2;
      final upper = (level - 6) / 2;
      return '${lower.toStringAsFixed(1)} <= I < ${upper.toStringAsFixed(1)}';
    }
    if (level == 20) return 'I >= 6.5';
    return 'no data';
  }
}

class KaStationIdentity {
  const KaStationIdentity({
    required this.stationId,
    required this.coordinate,
    required this.network,
    required this.yahooSiteIndex,
  });

  final String stationId;
  final LatLng coordinate;
  final String network;
  final int yahooSiteIndex;
}

/// One source observation at one station and one observation timestamp.
class KaIntensityObservation {
  const KaIntensityObservation({
    required this.eventId,
    required this.station,
    required this.observedAt,
    required this.kind,
    required this.sourceLayer,
    required this.qualityFlags,
    this.yahooRawLevel,
    this.gifContinuousShindo,
    this.gifKaLevel,
  });

  final String eventId;
  final KaStationIdentity station;
  final DateTime observedAt;
  final KaIntensityValueKind kind;
  final String sourceLayer;
  final List<String> qualityFlags;
  final int? yahooRawLevel;
  final double? gifContinuousShindo;
  final int? gifKaLevel;

  bool get hasUsableYahooLevel =>
      yahooRawLevel != null &&
      yahooRawLevel! >= KaLevelScale.minimum &&
      yahooRawLevel! <= KaLevelScale.maximum;

  bool get hasUsableGifLevel =>
      gifContinuousShindo != null &&
      gifKaLevel != null &&
      gifKaLevel! >= KaLevelScale.minimum &&
      gifKaLevel! <= KaLevelScale.maximum;
}

/// A strict same-station, same-observation-second Yahoo/GIF pair.
class KaYahooGifPair {
  KaYahooGifPair({required this.yahoo, required this.gif})
    : assert(yahoo.kind == KaIntensityValueKind.yahooLevel),
      assert(gif.kind == KaIntensityValueKind.gifContinuousShindo),
      assert(yahoo.eventId == gif.eventId),
      assert(yahoo.station.stationId == gif.station.stationId),
      assert(
        yahoo.observedAt.millisecondsSinceEpoch ==
            gif.observedAt.millisecondsSinceEpoch,
      );

  final KaIntensityObservation yahoo;
  final KaIntensityObservation gif;

  int get levelDifference => gif.gifKaLevel! - yahoo.yahooRawLevel!;

  Map<String, Object?> toJson() => {
    'eventId': yahoo.eventId,
    'stationId': yahoo.station.stationId,
    'latitude': yahoo.station.coordinate.latitude,
    'longitude': yahoo.station.coordinate.longitude,
    'network': yahoo.station.network,
    'observedAt': yahoo.observedAt.toIso8601String(),
    'yahooRawLevel': yahoo.yahooRawLevel,
    'gifDecodedContinuousShindo': gif.gifContinuousShindo,
    'gifCurrentKaLevel': gif.gifKaLevel,
    'levelDifference': levelDifference,
    'sourceLayer': gif.sourceLayer,
    'qualityFlags': {...yahoo.qualityFlags, ...gif.qualityFlags}.toList(),
  };
}

/// Real-time input keeps every observation second; no peak is synthesized.
class KaRealtimeSnapshotInput {
  const KaRealtimeSnapshotInput({
    required this.eventId,
    required this.observedAt,
    required this.valueKind,
    required this.observations,
  });

  final String eventId;
  final DateTime observedAt;
  final KaIntensityValueKind valueKind;
  final List<KaIntensityObservation> observations;
}

/// Event-level calibration input contains an explicitly selected final peak.
///
/// This is still a KA/GIF instrumental product. It is not a JMA final station
/// intensity report and not a historical macroseismic-intensity observation.
class KaFinalPeakCalibrationInput {
  const KaFinalPeakCalibrationInput({
    required this.eventId,
    required this.station,
    required this.valueKind,
    required this.peakObservedAt,
    required this.peakValue,
    required this.frameCount,
    required this.qualityFlags,
  });

  final String eventId;
  final KaStationIdentity station;
  final KaIntensityValueKind valueKind;
  final DateTime peakObservedAt;
  final double peakValue;
  final int frameCount;
  final List<String> qualityFlags;
}
