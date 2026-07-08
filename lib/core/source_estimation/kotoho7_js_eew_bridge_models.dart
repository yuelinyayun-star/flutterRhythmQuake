class Kotoho7JsCircleTriggerInput {
  final Map<String, Object?> metadata;
  final String? scriptPath;
  final int stationIndex1;
  final int currentState;
  final int threshold;
  final int pointCount;
  final double shindo;
  final double triggerAgeSeconds;
  final List<Map<String, Object?>> stationDistances;

  const Kotoho7JsCircleTriggerInput({
    required this.metadata,
    this.scriptPath,
    required this.stationIndex1,
    required this.currentState,
    required this.threshold,
    required this.pointCount,
    required this.shindo,
    required this.triggerAgeSeconds,
    required this.stationDistances,
  });

  Map<String, Object?> toJson() => {
    'command': 'circleTrigger',
    'metadata': metadata,
    if (scriptPath != null) 'scriptPath': scriptPath,
    'stationIndex1': stationIndex1,
    'currentState': currentState,
    'threshold': threshold,
    'pointCount': pointCount,
    'shindo': shindo,
    'triggerAgeSeconds': triggerAgeSeconds,
    'stationDistances': stationDistances,
  };
}

class Kotoho7JsBridgeResult {
  final bool ok;
  final bool available;
  final Map<String, Object?> result;
  final Map<String, Object?> metadata;
  final String? error;

  const Kotoho7JsBridgeResult({
    required this.ok,
    required this.available,
    this.result = const {},
    this.metadata = const {},
    this.error,
  });

  bool get promoted => result['promoted'] == true;

  factory Kotoho7JsBridgeResult.unavailable(String reason) {
    return Kotoho7JsBridgeResult(ok: false, available: false, error: reason);
  }

  factory Kotoho7JsBridgeResult.fromJson(Map<String, Object?> json) {
    return Kotoho7JsBridgeResult(
      ok: json['ok'] == true,
      available: true,
      result: objectMap(json['result']),
      metadata: objectMap(json['metadata']),
      error: json['error']?.toString(),
    );
  }
}

Map<String, Object?> objectMap(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  return const <String, Object?>{};
}
