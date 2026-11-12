import 'dart:ffi';
import 'dart:typed_data';

import '../../services/sources/native_station_core_library_io.dart';
import '../event_detection/event_detection_models.dart';
import 'source_estimation_models.dart';
import 'station_observation_history.dart';

/// Numeric lifecycle, timing, amplitude and physical-peak state belongs to Rust.
/// Dart binds original metadata and prepared results to existing event views.
final class NativeStationRecordOwner implements Finalizable {
  NativeStationRecordOwner(DateTime startedAt) {
    _owner = _api.create(startedAt.microsecondsSinceEpoch);
    if (_owner == nullptr) {
      throw StateError('Cannot create native record owner');
    }
    _finalizer.attach(this, _owner, detach: this);
  }
  static bool get supported => StationCoreLibrary.supported;
  static final _api = _Bindings();
  static final _finalizer = NativeFinalizer(_api.destroyPointer);
  static Map<String, int> get diagnostics => {
    'sessions': _api.sessions(),
    'frames': _api.frames(),
  };
  late final Pointer<Void> _owner;
  final _ids = <String, int>{};
  StationCoreBuffer? _input, _output;
  bool _disposed = false;

  void update({
    required SeismicActiveEvent event,
    required List<SeismicStationSample> samples,
    required DateTime observedAt,
    required Set<String> members,
    required StationObservationHistory Function()? historyFactory,
    required void Function(
      SeismicStationEventRecord,
      SeismicStationSample,
      bool,
    )
    append,
  }) {
    if (_disposed) throw StateError('Native record owner disposed');
    final count = samples.length;
    if (count == 0) return;
    if (_input == null || _input!.length < count * 42 * 8) {
      _input?.dispose();
      _output?.dispose();
      _input = StationCoreBuffer(count * 42 * 8);
      _output = StationCoreBuffer(count * 28 * 8);
    }
    final words = _input!.pointer.cast<Int64>().asTypedList(count * 42);
    final bytes = ByteData.sublistView(words);
    words.fillRange(0, words.length, 0);
    for (var index = 0; index < count; index++) {
      final sample = samples[index], at = index * 42;
      words[at] = _ids.putIfAbsent(sample.descriptor.code, () => _ids.length);
      words[at + 1] = sample.rawLevel ?? 0;
      words[at + 2] = sample.detectLevel ?? 0;
      bytes.setFloat64((at + 3) * 8, sample.activity, Endian.host);
      words[at + 4] = sample.ascend;
      words[at + 5] = sample.isTriggered ? 1 : 0;
      words[at + 6] =
          (sample.value != null ? 1 : 0) |
          (sample.rawLevel != null ? 2 : 0) |
          (sample.detectLevel != null ? 4 : 0) |
          (sample.observedPga != null ? 8 : 0) |
          (sample.observedPgv != null ? 16 : 0) |
          (sample.observedPgd != null ? 32 : 0);
      bytes.setFloat64((at + 7) * 8, sample.value ?? 0, Endian.host);
      bytes.setFloat64((at + 8) * 8, sample.observedPga ?? 0, Endian.host);
      bytes.setFloat64((at + 9) * 8, sample.observedPgv ?? 0, Endian.host);
      bytes.setFloat64((at + 10) * 8, sample.observedPgd ?? 0, Endian.host);
      _writeInterval(words, at + 11, sample.firstRiseInterval);
      _writeInterval(words, at + 14, sample.firstTriggerInterval);
      words[at + 17] = members.contains(sample.descriptor.code) ? 1 : 0;
      for (final entry in sample.provenance.entries) {
        final p = entry.value;
        words[at + 18 + entry.key.index] =
            p.origin.index |
            (p.isIndependentPhysicalMeasurement ? 8 : 0) |
            (p.qualityFlags.contains('derived_from_shindo') ? 16 : 0);
      }
      var slot = 0;
      for (final entry in sample.physicalObservations.entries) {
        // Records select by observation.quantity, as the original tracker did.
        final p = entry.value, offset = at + 24 + slot++ * 3;
        bytes.setFloat64(offset * 8, p.value, Endian.host);
        words[offset + 1] = p.dataTime.microsecondsSinceEpoch;
        words[offset + 2] =
            1 |
            (p.quantity.index << 8) |
            (p.qualityFlags.contains('layer_missing') ? 2 : 0) |
            (p.qualityFlags.contains('pixel_undecodable') ? 4 : 0) |
            (p.qualityFlags.contains('stale_observation') ? 8 : 0);
      }
    }
    final status = _api.apply(
      _owner,
      _input!.pointer.cast(),
      count,
      observedAt.microsecondsSinceEpoch,
      observedAt.isUtc ? 1 : 0,
      _output!.pointer.cast(),
    );
    if (status != 0) throw StateError('Native record frame failed ($status)');
    final result = _output!.pointer.cast<Int64>().asTypedList(count * 28);
    final values = ByteData.sublistView(result);
    StationObservationHistory.batchUpdates(() {
      for (var index = 0; index < count; index++) {
        final at = index * 28, disposition = result[at];
        if (disposition == 0) continue;
        final sample = samples[index];
        final record = event.stationRecords.putIfAbsent(
          sample.descriptor.code,
          () => SeismicStationEventRecord(
            descriptor: sample.descriptor,
            firstObservedAt: observedAt,
            observationHistory: historyFactory?.call(),
          ),
        );
        append(record, sample, disposition == 2);
        final mask = result[at + 26], changed = result[at + 2];
        if (changed & (1 << 1) != 0) {
          record.state = StationLifecycleState.values[result[at + 1]];
        }
        if (changed & (1 << 4) != 0) {
          record.lastObservedAt = mask & 64 == 0
              ? null
              : _readTime(
                  result[at + 4],
                  result[at + 5] != 0,
                  observedAt,
                  record.lastObservedAt,
                );
        }
        if (changed & (1 << 6) != 0) {
          record.peakAt = mask & 32 == 0
              ? null
              : _readTime(
                  result[at + 6],
                  result[at + 7] != 0,
                  observedAt,
                  record.peakAt,
                );
        }
        if (changed & (1 << 8) != 0) {
          record.endAt = mask & 128 == 0
              ? null
              : _readTime(
                  result[at + 8],
                  result[at + 9] != 0,
                  observedAt,
                  record.endAt,
                );
        }
        if (changed & (1 << 10) != 0) {
          record.peakValue = mask & 1 == 0
              ? null
              : values.getFloat64((at + 10) * 8, Endian.host);
        }
        if (changed & (1 << 11) != 0) {
          record.lastValue = mask & 2 == 0
              ? null
              : values.getFloat64((at + 11) * 8, Endian.host);
        }
        if (changed & (1 << 12) != 0) {
          record.lastPga = mask & 4 == 0
              ? null
              : values.getFloat64((at + 12) * 8, Endian.host);
        }
        if (changed & (1 << 13) != 0) {
          record.lastPgv = mask & 8 == 0
              ? null
              : values.getFloat64((at + 13) * 8, Endian.host);
        }
        if (changed & (1 << 14) != 0) {
          record.lastPgd = mask & 16 == 0
              ? null
              : values.getFloat64((at + 14) * 8, Endian.host);
        }
        if (changed & (1 << 15) != 0) {
          record.lastRawLevel = mask & 256 == 0 ? null : result[at + 15];
        }
        if (changed & (1 << 16) != 0) {
          record.lastDetectLevel = mask & 512 == 0 ? null : result[at + 16];
        }
        if (changed & (1 << 17) != 0) {
          record.lastActivity = values.getFloat64((at + 17) * 8, Endian.host);
        }
        if (changed & (1 << 18) != 0) {
          record.lastAscend = result[at + 18];
        }
        if (changed & (1 << 19) != 0) {
          record.sampleCount = result[at + 19];
        }
        if (changed & (1 << 20) != 0) {
          record.firstRiseInterval = _readInterval(
            result,
            at + 20,
            record.firstRiseInterval,
            sample.firstRiseInterval,
          );
        }
        if (changed & (1 << 23) != 0) {
          record.firstTriggerInterval = _readInterval(
            result,
            at + 23,
            record.firstTriggerInterval,
            sample.firstTriggerInterval,
          );
        }
        if (disposition == 2) continue;
        final actions = result[at + 27];
        if (actions != 0) {
          for (final quantity in StationValueType.values) {
            final action = (actions >> (quantity.index * 4)) & 15;
            if (action == 1) record.eventPhysicalPeaks.remove(quantity);
            if (action >= 2) {
              record.eventPhysicalPeaks[quantity] = sample
                  .physicalObservations
                  .values
                  .elementAt(action - 2);
            }
          }
        }
        record.qualityFlags.addAll(sample.qualityFlags);
        record.provenance.addAll(sample.provenance);
      }
    });
  }

  static void _writeInterval(
    Int64List out,
    int at,
    ObservationTimeInterval? interval,
  ) {
    if (interval == null) return;
    out[at] = interval.start.microsecondsSinceEpoch;
    out[at + 1] = interval.end.microsecondsSinceEpoch;
    out[at + 2] =
        1 | (interval.start.isUtc ? 2 : 0) | (interval.end.isUtc ? 4 : 0);
  }

  static DateTime _readTime(
    int us,
    bool utc,
    DateTime current,
    DateTime? previous,
  ) {
    if (us == current.microsecondsSinceEpoch && utc == current.isUtc) {
      return current;
    }
    if (previous != null &&
        us == previous.microsecondsSinceEpoch &&
        utc == previous.isUtc) {
      return previous;
    }
    return DateTime.fromMicrosecondsSinceEpoch(us, isUtc: utc);
  }

  static ObservationTimeInterval? _readInterval(
    Int64List out,
    int at,
    ObservationTimeInterval? previous,
    ObservationTimeInterval? original,
  ) {
    final flags = out[at + 2];
    if (flags & 1 == 0) return null;
    for (final candidate in [previous, original]) {
      if (candidate != null &&
          candidate.start.microsecondsSinceEpoch == out[at] &&
          candidate.end.microsecondsSinceEpoch == out[at + 1] &&
          candidate.start.isUtc == (flags & 2 != 0) &&
          candidate.end.isUtc == (flags & 4 != 0)) {
        return candidate;
      }
    }
    throw StateError(
      'Native record returned an interval absent from original evidence',
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    _api.destroy(_owner);
    _input?.dispose();
    _output?.dispose();
    _input = null;
    _output = null;
    _ids.clear();
  }
}

class _Bindings {
  final _lib = StationCoreLibrary.library;
  late final create = _lib
      .lookupFunction<
        Pointer<Void> Function(Int64),
        Pointer<Void> Function(int)
      >('rq_station_record_create');
  late final destroyPointer = _lib
      .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'rq_station_record_destroy',
      );
  late final destroy = destroyPointer
      .asFunction<void Function(Pointer<Void>)>();
  late final sessions = _lib.lookupFunction<Uint64 Function(), int Function()>(
    'rq_station_record_sessions',
  );
  late final frames = _lib.lookupFunction<Uint64 Function(), int Function()>(
    'rq_station_record_frames',
  );
  late final apply = _lib
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<Uint64>,
          Size,
          Int64,
          Uint32,
          Pointer<Uint64>,
        ),
        int Function(
          Pointer<Void>,
          Pointer<Uint64>,
          int,
          int,
          int,
          Pointer<Uint64>,
        )
      >('rq_station_record_apply');
}
