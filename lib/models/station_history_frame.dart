import 'source_payload.dart';

class StationHistoryFrame {
  static const kinds = {
    'nied',
    'snet',
    'kma',
    'cwa',
    'seisjs',
    'palert',
    'lpgm',
  };
  final DateTime receivedAt;
  final Map<String, dynamic> snapshot;
  final Map<String, dynamic>? originalJson;
  String get kind => snapshot['kind'] as String;

  StationHistoryFrame({
    required DateTime receivedAt,
    required Map<String, dynamic> snapshot,
    Map<String, dynamic>? originalJson,
  }) : receivedAt = receivedAt.toUtc(),
       snapshot = snapshotSourcePayload(snapshot),
       originalJson = originalJson == null
           ? null
           : snapshotSourcePayload(originalJson) {
    if (!kinds.contains(this.snapshot['kind']) ||
        (kind == 'lpgm'
            ? this.snapshot['topStations'] is! List
            : this.snapshot['stations'] is! List)) {
      throw const FormatException('Invalid station history snapshot');
    }
    _validateDetection(this.snapshot['detection']);
  }

  static void _validateDetection(dynamic detection) {
    if (detection == null) return;
    if (detection is! Map ||
        detection['stage'] is! String ||
        !const {
          'idle',
          'weak',
          'detected',
          'strong',
        }.contains(detection['stage']) ||
        !const [
          'weakCount',
          'detectedCount',
          'strongCount',
          'maxShindo',
        ].every((key) => detection[key] is int) ||
        detection['gridCells'] is! Map ||
        detection['detectedStations'] is! List) {
      throw const FormatException('Invalid station detection snapshot');
    }
    for (final entry in (detection['gridCells'] as Map).entries) {
      final cell = entry.value;
      if (entry.key is! String ||
          cell is! Map ||
          cell['lat'] is! num ||
          cell['lng'] is! num ||
          cell['level'] is! int ||
          cell['shindo'] is! num) {
        throw const FormatException('Invalid station detection cell');
      }
    }
    for (final station in detection['detectedStations'] as List) {
      if (station is! Map ||
          !const [
            'code',
            'prefecture',
            'detectReason',
          ].every((key) => station[key] is String) ||
          !const [
            'level',
            'jmaShindo',
            'detectState',
          ].every((key) => station[key] is int)) {
        throw const FormatException('Invalid detected station entry');
      }
    }
  }

  Map<String, dynamic> toMap() => {
    'receivedAt': receivedAt.toIso8601String(),
    'snapshot': snapshot,
    if (originalJson != null) 'originalJson': originalJson,
  };

  factory StationHistoryFrame.fromMap(Map map) {
    final time = DateTime.tryParse(map['receivedAt']?.toString() ?? '');
    if (time == null ||
        !time.isUtc ||
        map['snapshot'] is! Map ||
        (map['originalJson'] != null && map['originalJson'] is! Map)) {
      throw const FormatException('Invalid station history frame');
    }
    return StationHistoryFrame(
      receivedAt: time,
      snapshot: Map<String, dynamic>.from(map['snapshot'] as Map),
      originalJson: map['originalJson'] == null
          ? null
          : Map<String, dynamic>.from(map['originalJson'] as Map),
    );
  }
}
