import 'dart:collection';
import 'dart:typed_data';
import 'native_observation_history.dart';
import 'source_estimation_models.dart';
import 'native_nied_observation_summary.dart';

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

class StationObservationHistory implements NativeObservationCommit {
  StationObservationHistory({this.retention = const Duration(seconds: 60)})
    : _frames = [];
  StationObservationHistory.native({
    this.retention = const Duration(seconds: 60),
  }) : _native = NativeObservationHistory();
  StationObservationHistory._packed(this.retention, this._packed);
  static bool get nativeSupported => NativeObservationHistory.supported;
  static void batchUpdates(void Function() action) =>
      NativeObservationHistory.batchUpdates(action);
  final Duration retention;
  List<SeismicStationObservationFrame>? _frames;
  NativeObservationHistory? _native;
  List<SeismicStationObservationFrame>? _packed, _snapshot;
  SeismicStationObservationFrame? _latest;
  Map<int, _ObservationMetadata>? _metadata;
  int _nextMetadataId = 0, _lastMetadataId = -1;
  NativeNiedObservationSummary? _niedSummary;
  int? _summaryObservedUs;
  static final _row = Int64List(7);
  static final _rowBytes = ByteData.sublistView(_row);

  /// Immutable, independently owned snapshot. Native views never leave storage.
  List<SeismicStationObservationFrame> get frames =>
      _snapshot ??= _native == null
      ? (_packed ?? List.unmodifiable(_frames!))
      : UnmodifiableListView(
          _PackedObservationFrames(
            _native!.snapshot(),
            Map.unmodifiable(_metadata ?? const {}),
          ),
        );
  int get length => _native?.length ?? _packed?.length ?? _frames!.length;
  bool get isEmpty => length == 0;
  SeismicStationObservationFrame? get latest => _native != null
      ? _latest
      : isEmpty
      ? null
      : (_packed ?? _frames!).last;

  bool get ownsNativeWindow => _native != null;

  /// Queries execute over the owned native window, without copying its rows.
  NativeNiedObservationSummary? niedSummary(DateTime? observedAt) {
    final native = _native;
    if (native == null) return null;
    final time = observedAt?.microsecondsSinceEpoch;
    if (_niedSummary == null || _summaryObservedUs != time) {
      _niedSummary = native.niedSummary(observedAt);
      _summaryObservedUs = time;
    }
    return _niedSummary;
  }

  double? nativePretriggerSeconds(DateTime earliest, DateTime fallback) =>
      _native!.pretriggerSeconds(earliest, fallback);

  bool nativeFastRiseExceeds(DateTime observedAt, int digit) =>
      _native!.fastRiseExceeds(observedAt, digit);

  /// Pointer-free copy for isolate transport; numeric history stays compact.
  StationObservationHistory detachedSnapshot() {
    // Exporting a result must not cache a second numeric window in its owner.
    // Explicit estimator reads still receive the stable frames snapshot above.
    final snapshot = _native == null
        ? frames
        : (_snapshot ??
              UnmodifiableListView(
                _PackedObservationFrames(
                  _native!.snapshot(),
                  Map.unmodifiable(_metadata ?? const {}),
                ),
              ));
    return StationObservationHistory._packed(retention, snapshot);
  }

  /// Release native storage while preserving externally retained record values.
  void disposeStorage() {
    final native = _native;
    if (native == null) return;
    _packed = frames;
    native.dispose();
    _native = null;
    _niedSummary = null;
    _metadata = null;
    _latest = null;
  }

  void add(SeismicStationObservationFrame frame) {
    final previous = latest;
    if (previous != null && frame.dataTime.isBefore(previous.dataTime)) {
      throw ArgumentError.value(
        frame.dataTime,
        'frame.dataTime',
        'Observation history must be chronological.',
      );
    }
    _snapshot = null;
    _niedSummary = null;
    final native = _native;
    if (native != null) {
      final metadata = _metadata ??= <int, _ObservationMetadata>{};
      final reuseMetadata =
          _lastMetadataId >= 0 &&
          previous != null &&
          identical(previous.qualityFlags, frame.qualityFlags) &&
          identical(previous.physicalObservations, frame.physicalObservations);
      final metadataId = reuseMetadata ? _lastMetadataId : _nextMetadataId++;
      if (!reuseMetadata) {
        metadata[metadataId] = _ObservationMetadata(
          frame.qualityFlags,
          frame.physicalObservations,
        );
      }
      _lastMetadataId = metadataId;
      _row[0] = frame.dataTime.microsecondsSinceEpoch;
      _row[1] = frame.receivedAt.microsecondsSinceEpoch;
      _rowBytes.setFloat64(16, frame.value ?? 0.0, Endian.host);
      _row[3] = frame.rawLevel ?? 0;
      _row[4] = frame.detectLevel ?? 0;
      _row[5] =
          (frame.value != null ? 1 : 0) |
          (frame.rawLevel != null ? 2 : 0) |
          (frame.detectLevel != null ? 4 : 0) |
          (frame.isTriggered ? 8 : 0) |
          (frame.dataTime.isUtc ? 16 : 0) |
          (frame.receivedAt.isUtc ? 32 : 0) |
          (frame.isMissing || frame.isStale || !frame.isDecodable ? 64 : 0);
      _row[6] = metadataId;
      final int cutoff;
      try {
        // The native window needs only the epoch threshold, not local calendar
        // fields. Keep the SDK operation at its range edges so its validation
        // and append-before-error behavior remain unchanged.
        final candidate =
            frame.dataTime.microsecondsSinceEpoch - retention.inMicroseconds;
        const limit = 8640000000000000000;
        cutoff = candidate >= -limit && candidate <= limit
            ? candidate
            : frame.dataTime.subtract(retention).microsecondsSinceEpoch;
      } catch (_) {
        // The original list appends before DateTime.subtract can throw.
        // Preserve that observable state, then propagate the original error.
        native.append(_row, -0x8000000000000000);
        _latest = frame;
        rethrow;
      }
      native.appendDeferred(_row, cutoff, this);
      // Chronology has already been checked. The current row survives iff its
      // time reaches the cutoff; this also preserves negative retention.
      _latest = _row[0] < cutoff ? null : frame;
      return;
    }
    if (_packed != null) {
      _frames = List.of(_packed!);
      _packed = null;
    }
    final values = _frames!;
    values.add(frame);
    final cutoff = frame.dataTime.subtract(retention);
    var expiredCount = 0;
    while (expiredCount < values.length &&
        values[expiredCount].dataTime.isBefore(cutoff)) {
      expiredCount++;
    }
    if (expiredCount > 0) values.removeRange(0, expiredCount);
  }

  @override
  void observationCommitted(int oldestMetadataId, int appendedMetadataId) {
    final metadata = _metadata;
    if (metadata == null) return;
    while (metadata.isNotEmpty &&
        metadata.keys.first <= appendedMetadataId &&
        (oldestMetadataId < 0 || metadata.keys.first < oldestMetadataId)) {
      metadata.remove(metadata.keys.first);
    }
  }

  @override
  void observationBatchFailed() {
    _snapshot = null;
    _niedSummary = null;
    _latest = _native!.length == 0 ? null : frames.last;
    _lastMetadataId = -1;
  }

  void clear() {
    _snapshot = null;
    _niedSummary = null;
    _packed = null;
    _latest = null;
    _metadata?.clear();
    if (_native != null) {
      _native!.clear();
    } else {
      (_frames ??= []).clear();
    }
  }
}

class _ObservationMetadata {
  const _ObservationMetadata(this.flags, this.physical);
  final Set<String> flags;
  final Map<StationValueType, SeismicPhysicalObservation> physical;
}

class _PackedObservationFrames
    extends ListBase<SeismicStationObservationFrame> {
  _PackedObservationFrames(this.rows, this.metadata) : bytes = rows.data;
  final NativeObservationSnapshot rows;
  final ByteData bytes;
  final Map<int, _ObservationMetadata> metadata;
  @override
  int get length => rows.count;
  @override
  set length(int value) =>
      throw UnsupportedError('Immutable observation snapshot');
  @override
  SeismicStationObservationFrame operator [](int index) {
    RangeError.checkValidIndex(index, this);
    final compactOffset = index * 24;
    final wide = bytes.getUint8(compactOffset + 23) != 0;
    final offset = wide
        ? rows.wideOffsets[bytes.getUint64(compactOffset, Endian.little)]!
        : compactOffset;
    final bits = wide
        ? bytes.getInt64(offset + 40, Endian.little)
        : bytes.getUint8(offset + 22);
    final metadataId = wide
        ? bytes.getInt64(offset + 48, Endian.little)
        : bytes.getUint32(offset + 16, Endian.little);
    final meta = metadata[metadataId]!;
    return SeismicStationObservationFrame(
      dataTime: DateTime.fromMicrosecondsSinceEpoch(
        wide
            ? bytes.getInt64(offset, Endian.little)
            : rows.baseUs + bytes.getInt32(offset + 8, Endian.little),
        isUtc: bits & 16 != 0,
      ),
      receivedAt: DateTime.fromMicrosecondsSinceEpoch(
        wide
            ? bytes.getInt64(offset + 8, Endian.little)
            : rows.baseUs + bytes.getInt32(offset + 12, Endian.little),
        isUtc: bits & 32 != 0,
      ),
      value: bits & 1 != 0
          ? bytes.getFloat64(offset + (wide ? 16 : 0), Endian.little)
          : null,
      rawLevel: bits & 2 != 0
          ? (wide
                ? bytes.getInt64(offset + 24, Endian.little)
                : bytes.getInt8(offset + 20))
          : null,
      detectLevel: bits & 4 != 0
          ? (wide
                ? bytes.getInt64(offset + 32, Endian.little)
                : bytes.getInt8(offset + 21))
          : null,
      isTriggered: bits & 8 != 0,
      qualityFlags: meta.flags,
      physicalObservations: meta.physical,
    );
  }

  @override
  void operator []=(int index, SeismicStationObservationFrame value) =>
      throw UnsupportedError('Immutable observation snapshot');
}
