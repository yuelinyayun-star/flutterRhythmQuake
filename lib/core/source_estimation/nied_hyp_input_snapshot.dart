import 'dart:collection';

import 'package:latlong2/latlong.dart';

import '../calculator.dart';
import 'palert_source_profile.dart';

/// Parsed HYP values. This contains no native handles and may cross isolates.
class NiedHypStationValues {
  const NiedHypStationValues({
    required this.id,
    required this.code,
    required this.coordinate,
    required this.triggerAt,
    required this.updateAt,
    required this.level,
    required this.currentShindo,
    required this.ascend,
    required this.active,
    this.palertMaxLevel,
    this.palertSecondMaxLevel,
    this.nonQuietBoundary,
  });

  final String id;
  final String code;
  final LatLng coordinate;
  final DateTime? triggerAt;
  final DateTime? updateAt;
  final int? level;
  final double? currentShindo;
  final int ascend;
  final bool active;
  final int? palertMaxLevel;
  final int? palertSecondMaxLevel;
  final DateTime? nonQuietBoundary;

  bool get hasUpdateTime => updateAt != null;

  bool get hasInferenceWeight => palertMaxLevel != null
      ? PAlertSourceProfile.pickWeight(palertMaxLevel!) > 0
      : ascend >= 2;
}

/// Original NIED snapshot fields with a typed, immutable inference view.
/// Map consumers and JSON export see the same fields and insertion order.
final class NiedHypStationSnapshot extends MapBase<String, Object?>
    implements NiedHypStationValues {
  NiedHypStationSnapshot({
    required this.stationId,
    required this.code,
    required this.coordinate,
    required this.triggerStamp,
    required this.updateStamp,
    required this.ascend,
    required this.level,
    required this.currentShindo,
    required this.active,
  });

  final int stationId;
  @override
  final String code;
  @override
  final LatLng coordinate;
  final int? triggerStamp;
  final int updateStamp;
  @override
  final int ascend;
  @override
  final int level;
  @override
  final double? currentShindo;
  @override
  final bool active;

  @override
  late final String id = stationId.toString();
  @override
  late final DateTime? triggerAt = _time(triggerStamp);
  @override
  late final DateTime? updateAt = _time(updateStamp);
  @override
  bool get hasUpdateTime {
    if (updateStamp <= 0) return false;
    // A presence check need not materialize a local DateTime. Preserve the
    // original constructor's error for timestamps beyond its valid range.
    if (updateStamp <= 8640000000000000) return true;
    return updateAt != null;
  }

  late final List<double> _latLng = List<double>.unmodifiable([
    coordinate.latitude,
    coordinate.longitude,
  ]);
  late final bool hasUsableCoordinate =
      QuakeCalculator.isUsableMapCoordinate(
        coordinate.latitude,
        coordinate.longitude,
      ) &&
      !QuakeCalculator.isLikelyUninitializedCoordinate(
        coordinate.latitude,
        coordinate.longitude,
      );

  static DateTime? _time(int? stamp) => stamp == null || stamp <= 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(stamp, isUtc: false);

  @override
  int? get palertMaxLevel => null;
  @override
  int? get palertSecondMaxLevel => null;
  @override
  DateTime? get nonQuietBoundary => null;
  @override
  bool get hasInferenceWeight => ascend >= 2;

  static const _keys = [
    'id',
    'code',
    'latLng',
    'triggerStamp',
    'updateStamp',
    'ascend',
    'level',
    'shindo',
    'isActive',
  ];
  @override
  Iterable<String> get keys => _keys;
  @override
  Object? operator [](Object? key) => switch (key) {
    'id' => stationId,
    'code' => code,
    'latLng' => _latLng,
    'triggerStamp' => triggerStamp,
    'updateStamp' => updateStamp,
    'ascend' => ascend,
    'level' => level,
    'shindo' => currentShindo,
    'isActive' => active,
    _ => null,
  };
  @override
  bool containsKey(Object? key) => _keys.contains(key);
  @override
  void operator []=(String key, Object? value) =>
      throw UnsupportedError('Immutable NIED snapshot');
  @override
  Object? remove(Object? key) =>
      throw UnsupportedError('Immutable NIED snapshot');
  @override
  void clear() => throw UnsupportedError('Immutable NIED snapshot');
}

/// Only immutable topology carries a reusable parsed adjacency view.
/// Arbitrary mutable input maps still pass through the legacy parser.
final class NiedHypAdjacencySnapshot<T> extends MapBase<String, List<T>> {
  NiedHypAdjacencySnapshot(Map<String, List<T>> source)
    : _source = Map.unmodifiable({
        for (final entry in source.entries)
          entry.key: List<T>.unmodifiable(entry.value),
      });

  final Map<String, List<T>> _source;
  // Static Expando storage belongs to this isolate. A transported snapshot
  // carries only its original lists, never this consumer's derived cache.
  static final _parsedBySnapshot = Expando<Map<String, Set<String>>>();
  Map<String, Set<String>> get parsed =>
      _parsedBySnapshot[this] ??= _ParsedHypAdjacency(_source);
  @override
  Iterable<String> get keys => _source.keys;
  @override
  List<T>? operator [](Object? key) => _source[key];
  @override
  bool containsKey(Object? key) => _source.containsKey(key);
  @override
  void operator []=(String key, List<T> value) =>
      throw UnsupportedError('Immutable NIED adjacency');
  @override
  List<T>? remove(Object? key) =>
      throw UnsupportedError('Immutable NIED adjacency');
  @override
  void clear() => throw UnsupportedError('Immutable NIED adjacency');
}

/// Most frames use only a small part of the station graph. Parse neighbors on
/// first access instead of retaining sets for the entire network.
final class _ParsedHypAdjacency extends MapBase<String, Set<String>> {
  _ParsedHypAdjacency(this._source);
  final Map<String, List<Object?>> _source;
  final Map<String, Set<String>> _accessed = {};
  @override
  Iterable<String> get keys => _source.keys;
  @override
  bool containsKey(Object? key) => _source.containsKey(key);
  @override
  Set<String>? operator [](Object? key) {
    final neighbors = _source[key];
    if (neighbors == null) return null;
    return _accessed.putIfAbsent(
      key as String,
      () =>
          Set<String>.unmodifiable(neighbors.map((value) => value.toString())),
    );
  }

  @override
  void operator []=(String key, Set<String> value) =>
      throw UnsupportedError('Immutable parsed NIED adjacency');
  @override
  Set<String>? remove(Object? key) =>
      throw UnsupportedError('Immutable parsed NIED adjacency');
  @override
  void clear() => throw UnsupportedError('Immutable parsed NIED adjacency');
}
