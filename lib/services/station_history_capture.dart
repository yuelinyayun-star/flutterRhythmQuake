import '../core/app_edition.dart';
import '../models/source_payload.dart';
import '../models/station_history_frame.dart';

/// Raw JSON is kept separately from decoded display snapshots. Image/binary
/// sources intentionally have no originalJson rather than invented JSON.
class StationHistoryCapture {
  static final instance = StationHistoryCapture();
  final _raw = <String, Map<String, dynamic>>{};
  final _latest = <String, StationHistoryFrame Function()>{};
  final _listeners = <void Function(StationHistoryFrame)>{};
  final _disabledKinds = <String>{};
  bool get recording => _listeners.isNotEmpty;

  bool isEnabled(String kind) =>
      StationHistoryFrame.kinds.contains(kind) &&
      !_disabledKinds.contains(kind) &&
      (kind != 'palert' || AppEdition.hasPAlertStations);

  void setEnabled(String kind, bool enabled) {
    if (!StationHistoryFrame.kinds.contains(kind)) {
      throw ArgumentError.value(
        kind,
        'kind',
        'Unsupported station history kind',
      );
    }
    if (enabled) {
      _disabledKinds.remove(kind);
    } else {
      _disabledKinds.add(kind);
    }
    // Never seed a later EEW with a frame from before this source was disabled.
    if (!isEnabled(kind)) _latest.remove(kind);
  }

  void retainOriginal(String source, String part, Map payload) {
    _raw[source] = snapshotSourcePayload({
      ...?_raw[source],
      part: snapshotSourcePayload(Map<String, dynamic>.from(payload)),
    });
  }

  void restoreOriginal(String source, Map payload) =>
      _raw[source] = snapshotSourcePayload(Map<String, dynamic>.from(payload));

  Map<String, dynamic>? original(String source) => _raw[source];

  void publish(
    String kind,
    Map<String, dynamic> Function() snapshot, {
    String? source,
    Map<String, dynamic>? originalJson,
    DateTime? receivedAt,
  }) {
    if (!isEnabled(kind)) return;
    final received = receivedAt ?? DateTime.now();
    final original = originalJson ?? (source == null ? null : _raw[source]);
    StationHistoryFrame build() => StationHistoryFrame(
      receivedAt: received,
      snapshot: snapshot(),
      originalJson: original,
    );
    _latest[kind] = build;
    if (!recording) return;
    final frame = build();
    for (final listener in List.of(_listeners)) {
      if (!isEnabled(kind)) break;
      listener(frame);
    }
  }

  Iterable<StationHistoryFrame> get latest => _latest.entries
      .where((entry) => isEnabled(entry.key))
      .map((entry) => entry.value());
  void addListener(void Function(StationHistoryFrame) listener) =>
      _listeners.add(listener);
  void removeListener(void Function(StationHistoryFrame) listener) =>
      _listeners.remove(listener);
}
