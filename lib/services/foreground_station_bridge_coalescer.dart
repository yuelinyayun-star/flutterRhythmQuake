import 'dart:async';

/// Limits high-frequency station snapshots crossing from the Android
/// foreground-service isolate into the UI isolate.
///
/// Source connections and their raw frames remain untouched. Display snapshots
/// are coalesced per `(kind, source)` within [window] while preserving the
/// latest `originalJson` when present; detector signals (`kind == 'signal'`)
/// are emitted immediately so alert handling keeps its per-frame semantics.
/// When [paused] is true (e.g. UI is in background), coalescible snapshots are
/// retained in memory and flushed immediately when resumed. While [recording]
/// is true, every snapshot is emitted immediately so EEW history capture does
/// not depend on UI visibility or lose frames to coalescing.
class ForegroundStationBridgeCoalescer {
  ForegroundStationBridgeCoalescer({
    required this.emit,
    this.window = const Duration(milliseconds: 40),
    this.coalescibleKinds = const {
      'nied',
      'kma',
      'cwa',
      'snet',
      'seisjs',
      'palert',
      'lpgm',
      'whewsNied',
      'whewsSnet',
      'whewsKma',
      'fdsnStations',
      'fdsnMotion',
      'fdsnStatus',
      'fanRadar',
      'fanSatellite',
      'jmaRadar',
      'jmaSatelliteCloud',
      'nsmcSatelliteCloud',
      'cmaPrecipitation',
      'volcanoSites',
    },
    bool paused = false,
    bool recording = false,
  }) : _paused = paused,
       _recording = recording;

  final void Function(Map<String, dynamic> payload) emit;
  final Duration window;
  final Set<String> coalescibleKinds;
  final Map<String, Map<String, dynamic>> _pending = {};
  Timer? _timer;
  bool _disposed = false;
  bool _paused;
  bool _recording;

  bool get isPaused => _paused;
  bool get isRecording => _recording;

  void setRecording(bool recording) {
    if (_disposed || _recording == recording) return;
    _recording = recording;
    if (_recording) flush();
  }

  void setPaused(bool paused) {
    if (_disposed || _paused == paused) return;
    _paused = paused;
    if (_paused) {
      _timer?.cancel();
      _timer = null;
    } else if (_pending.isNotEmpty) {
      flush();
    }
  }

  void submit(Map<String, dynamic> payload) {
    if (_disposed) return;
    final kind = payload['kind']?.toString();
    if (kind == null || !coalescibleKinds.contains(kind) || _recording) {
      emit(payload);
      return;
    }
    final source = payload['source']?.toString() ?? '';
    final key = '$kind|$source';
    final previous = _pending[key];
    if (previous != null &&
        !payload.containsKey('originalJson') &&
        previous.containsKey('originalJson')) {
      _pending[key] = {...payload, 'originalJson': previous['originalJson']};
    } else {
      _pending[key] = payload;
    }
    if (_paused) return;
    _timer ??= Timer(window, flush);
  }

  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_disposed) {
      _pending.clear();
      return;
    }
    final pending = List<Map<String, dynamic>>.of(_pending.values);
    _pending.clear();
    for (final payload in pending) {
      emit(payload);
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }
}
