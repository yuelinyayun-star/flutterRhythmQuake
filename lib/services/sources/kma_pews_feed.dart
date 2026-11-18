import 'native_station_runtime.dart';

/// One direct PEWS actor per isolate, shared by EEW and station consumers.
class KmaPewsFeed {
  KmaPewsFeed({NativeStationRuntime Function()? runtimeFactory})
    : _runtimeFactory = runtimeFactory ?? NativeStationRuntime.new;

  static final instance = KmaPewsFeed();
  final NativeStationRuntime Function() _runtimeFactory;
  final _listeners = <Object, void Function(Map<String, dynamic>)>{};
  final _stationOwners = <Object>{};
  NativeStationRuntime? _runtime;
  Map<String, dynamic>? _latest;

  NativeStationRuntime? get runtime => _runtime;

  void attach(
    Object owner,
    void Function(Map<String, dynamic>) listener, {
    bool stations = false,
  }) {
    final hadStations = _stationOwners.isNotEmpty;
    if (stations) _stationOwners.add(owner);
    _listeners[owner] = listener;
    final latest = _latest;
    if (latest != null) {
      listener({...latest, 'signals': const [], 'eewEvents': const []});
    }
    if (_runtime != null) {
      if (!hadStations && stations) settings({'pewsStations': true});
      return;
    }
    final runtime = _runtime = _runtimeFactory();
    runtime.onFrame = (frame) {
      if (!identical(_runtime, runtime)) return;
      _latest = frame;
      for (final entry in _listeners.entries.toList()) {
        if (identical(_listeners[entry.key], entry.value)) entry.value(frame);
      }
    };
    try {
      runtime.start({
        'kind': 'kma',
        'source': 'pews_local',
        'pewsStations': _stationOwners.isNotEmpty,
      });
    } catch (_) {
      runtime.stop();
      _runtime = null;
      _listeners.remove(owner);
      _stationOwners.remove(owner);
      rethrow;
    }
  }

  void settings(Map<String, Object?> settings) => _runtime?.settings(settings);

  void detach(Object owner) {
    _listeners.remove(owner);
    final stoppedStations =
        _stationOwners.remove(owner) && _stationOwners.isEmpty;
    if (_listeners.isNotEmpty) {
      if (stoppedStations) {
        _latest = null;
        settings({'pewsStations': false});
      }
      return;
    }
    _runtime?.stop();
    _runtime = null;
    _latest = null;
  }
}
