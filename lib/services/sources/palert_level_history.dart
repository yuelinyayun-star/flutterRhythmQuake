import 'dart:typed_data';

import '../../core/source_estimation/palert_source_profile.dart';
import 'palert_wire_values.dart';
import 'native_palert_levels_stub.dart'
    if (dart.library.io) 'native_palert_levels_io.dart';

/// Batches original measurements; returned levels own their storage.
class PAlertLevelHistory {
  static const holdDuration = Duration(seconds: 3);
  PAlertLevelHistory({bool? useNative})
    : _useNative = useNative ?? NativePAlertLevels.supported;

  final bool _useNative;
  NativePAlertLevels? _native;
  List<String> _ids = const [];
  List<List<({int time, int level})>> _history = [];
  Float64List _input = Float64List(0);

  void setStations(Iterable<String> ids) {
    final next = ids.toList(growable: false);
    final old = {for (var i = 0; i < _ids.length; i++) _ids[i]: i};
    final remap = Int32List.fromList([for (final id in next) old[id] ?? -1]);
    if (_useNative) {
      (_native ??= NativePAlertLevels()).configure(remap);
    } else {
      _history = [for (final index in remap) index < 0 ? [] : _history[index]];
    }
    _ids = next;
    _input = Float64List(next.length * 3);
  }

  Int32List process(
    DateTime time,
    Map<String, double> pga,
    Map<String, double> pgv,
  ) {
    for (var i = 0; i < _ids.length; i++) {
      final value = pga[_ids[i]];
      _input[i * 3] = value == null ? 0 : 1;
      _input[i * 3 + 1] = value ?? double.nan;
      _input[i * 3 + 2] = pgv[_ids[i]] ?? double.nan;
    }
    return _processInput(time);
  }

  Int32List processWireValues(
    DateTime time,
    PAlertWireValues values, {
    required bool includePgv,
  }) {
    if (values.rows.length != _ids.length * 4) {
      throw ArgumentError('P-Alert field layout mismatch');
    }
    for (var i = 0; i < _ids.length; i++) {
      _input[i * 3] = values.rows[i * 4];
      _input[i * 3 + 1] = values.rows[i * 4 + 1];
      _input[i * 3 + 2] = includePgv && values.rows[i * 4 + 2] != 0
          ? values.rows[i * 4 + 3]
          : double.nan;
    }
    return _processInput(time);
  }

  Int32List _processInput(DateTime time) {
    final stamp = time.microsecondsSinceEpoch;
    if (_useNative) return _native!.process(stamp, _input);
    final output = Int32List(_ids.length * 2)
      ..fillRange(0, _ids.length * 2, -1);
    final cutoff = stamp - holdDuration.inMicroseconds;
    for (var i = 0; i < _ids.length; i++) {
      if (_input[i * 3] == 0) continue;
      final level = PAlertSourceProfile.level(
        _input[i * 3 + 1],
        _input[i * 3 + 2],
      );
      final samples = _history[i];
      samples.removeWhere(
        (sample) => sample.time < cutoff || sample.time > stamp,
      );
      if (level >= 0) samples.add((time: stamp, level: level));
      var held = level;
      for (final sample in samples) {
        if (sample.level > held) held = sample.level;
      }
      output[i * 2] = level;
      output[i * 2 + 1] = held;
    }
    return output;
  }

  void clear() {
    _native?.dispose();
    _native = null;
    _ids = const [];
    _history = [];
    _input = Float64List(0);
  }
}
