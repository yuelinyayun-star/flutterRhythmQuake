class Kotoho7ReceiverObservation {
  const Kotoho7ReceiverObservation({
    required this.stationCode,
    required this.observedAtUtc,
    required this.gifDecodedShindo,
    this.scratchTenIndex,
  });

  final String stationCode;
  final DateTime observedAtUtc;
  final double gifDecodedShindo;
  final int? scratchTenIndex;

  Map<String, Object?> toJson() => {
    'stationCode': stationCode,
    'observedAtUtc': observedAtUtc.toUtc().toIso8601String(),
    'gifDecodedShindo': gifDecodedShindo,
    if (scratchTenIndex != null) 'tenIndex': scratchTenIndex,
  };
}

class Kotoho7ReceiverBridgeInput {
  const Kotoho7ReceiverBridgeInput({
    required this.observations,
    this.scriptPath = 'tools/kotoho7_receiver_bridge_runner.js',
    this.serverScriptPath = 'tools/kotoho7_receiver_bridge_server.js',
    this.sessionKey = 'default',
    this.persistent = true,
    this.resetSession = false,
    this.cloudRt = true,
    this.traceStations = false,
    this.runHyp = true,
    this.timeout = const Duration(seconds: 4),
  });

  final List<Kotoho7ReceiverObservation> observations;
  final String scriptPath;
  final String serverScriptPath;
  final String sessionKey;
  final bool persistent;
  final bool resetSession;
  final bool cloudRt;
  final bool traceStations;
  final bool runHyp;
  final Duration timeout;
}

class Kotoho7ReceiverBridgeResult {
  const Kotoho7ReceiverBridgeResult({
    required this.ok,
    required this.available,
    this.result = const {},
    this.error,
    this.elapsedMilliseconds,
  });

  final bool ok;
  final bool available;
  final Map<String, Object?> result;
  final String? error;
  final int? elapsedMilliseconds;

  Map<String, Object?> get bestSourceByError =>
      objectMap(result['bestSourceByError']);

  Map<String, Object?> get finalState => objectMap(result['final']);

  int get processedFrameCount => _intValue(result['processedFrameCount']) ?? 0;

  int get peakDetectionIdCount =>
      _intValue(result['peakDetectionIdCount']) ?? 0;

  int get peakEstimatedStations =>
      _intValue(result['peakEstimatedStations']) ?? 0;

  factory Kotoho7ReceiverBridgeResult.unavailable(String reason) {
    return Kotoho7ReceiverBridgeResult(
      ok: false,
      available: false,
      error: reason,
    );
  }
}

class Kotoho7ReceiverBridgeQueueStatus {
  const Kotoho7ReceiverBridgeQueueStatus({
    required this.pendingFrameCount,
    required this.inFlightSessionCount,
    required this.sessionCount,
  });

  final int pendingFrameCount;
  final int inFlightSessionCount;
  final int sessionCount;

  bool get hasWork => pendingFrameCount > 0 || inFlightSessionCount > 0;
}

Map<String, Object?> objectMap(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  return const <String, Object?>{};
}

double? doubleValue(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
