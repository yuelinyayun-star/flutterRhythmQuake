import 'source_estimation_models.dart';

class SeismicStationObservationFrame {
  const SeismicStationObservationFrame({
    required this.dataTime,
    required this.receivedAt,
    required this.value,
    required this.rawLevel,
    required this.detectLevel,
    required this.isTriggered,
    required this.qualityFlags,
    this.physicalObservations = const {},
  });

  final DateTime dataTime;
  final DateTime receivedAt;
  final double? value;
  final int? rawLevel;
  final int? detectLevel;
  final bool isTriggered;
  final Set<String> qualityFlags;
  final Map<StationValueType, SeismicPhysicalObservation> physicalObservations;

  bool get isMissing => qualityFlags.contains('missing_observation');
  bool get isStale => qualityFlags.contains('stale_observation');
  bool get isDecodable => !qualityFlags.contains('pixel_undecodable');
}

class StationObservationHistory {
  StationObservationHistory({this.retention = const Duration(seconds: 60)});

  final Duration retention;
  final List<SeismicStationObservationFrame> _frames = [];

  List<SeismicStationObservationFrame> get frames => List.unmodifiable(_frames);

  int get length => _frames.length;
  bool get isEmpty => _frames.isEmpty;
  SeismicStationObservationFrame? get latest =>
      _frames.isEmpty ? null : _frames.last;

  void add(SeismicStationObservationFrame frame) {
    if (_frames.isNotEmpty && frame.dataTime.isBefore(_frames.last.dataTime)) {
      throw ArgumentError.value(
        frame.dataTime,
        'frame.dataTime',
        'Observation history must be chronological.',
      );
    }
    _frames.add(frame);
    final cutoff = frame.dataTime.subtract(retention);
    _frames.removeWhere((value) => value.dataTime.isBefore(cutoff));
  }

  void clear() => _frames.clear();
}
