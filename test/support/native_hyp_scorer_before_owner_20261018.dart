import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutterrhythmquake/services/sources/native_station_core_library_io.dart';
import 'package:flutterrhythmquake/core/source_estimation/native_hyp_geometry_io.dart' show writeHypDistances;
import 'package:flutterrhythmquake/core/source_estimation/native_hyp_score_result.dart';
import 'package:flutterrhythmquake/core/source_estimation/native_hyp_search_result.dart';
export 'package:flutterrhythmquake/core/source_estimation/native_hyp_score_result.dart';
export 'package:flutterrhythmquake/core/source_estimation/native_hyp_search_result.dart';

typedef _DistanceNative = Int32 Function(Double, Double, Pointer<Double>, Size);
typedef _SearchNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Double>,
      Pointer<NativeFunction<_DistanceNative>>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Int8>,
    );
typedef _SearchDart =
    int Function(
      Pointer<Void>,
      Pointer<Double>,
      Pointer<NativeFunction<_DistanceNative>>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Int8>,
    );

/// One ordered reference search owns the scoring state and reusable vectors.
final class NativeHypScorer implements Finalizable {
  NativeHypScorer({
    required List<double> coordinates,
    required Int64List stationInfo,
    required Float64List observedSeconds,
    required int inactiveCount,
  }) : _count = observedSeconds.length,
       _coordinates = Float64List.fromList(coordinates),
       _distanceKernel = _HypDistanceKernel(coordinates) {
    if (!supported) {
      throw UnsupportedError('Native HYP scorer requires Windows');
    }
    if (_count < 5 ||
        _count > 1048576 ||
        inactiveCount < 0 ||
        inactiveCount > 1048576 ||
        stationInfo.length != _count * 8 ||
        coordinates.length != (_count + inactiveCount) * 2) {
      throw ArgumentError('Invalid original HYP scoring input');
    }
    final info = StationCoreBuffer(stationInfo.length * 8);
    final observed = StationCoreBuffer(_count * 8);
    try {
      info.pointer
          .cast<Int64>()
          .asTypedList(stationInfo.length)
          .setAll(0, stationInfo);
      observed.pointer
          .cast<Double>()
          .asTypedList(_count)
          .setAll(0, observedSeconds);
      _pointer = _bindings.create(
        info.pointer.cast(),
        observed.pointer.cast(),
        _count,
        inactiveCount,
      );
      if (_pointer == nullptr) {
        throw StateError('Cannot create HYP scoring session');
      }
      _finalizer.attach(this, _pointer, detach: this);
    } finally {
      info.dispose();
      observed.dispose();
    }
    try {
      _input = StationCoreBuffer(3 * 8);
      _summary = StationCoreBuffer(4 * 8);
      _searchLog = StationCoreBuffer(33000 * 8);
      _distances = StationCoreBuffer((_count + inactiveCount) * 8);
      _output = StationCoreBuffer(NativeHypScoreResult.outputWords * 8);
      _waves = StationCoreBuffer(_count * 2);
      _distanceCallback = NativeCallable<_DistanceNative>.isolateLocal(
        _writeDistances,
        exceptionalReturn: 6,
      );
    } catch (_) {
      dispose();
      rethrow;
    }
  }
  static bool get supported => StationCoreLibrary.supported;
  static final _Bindings _bindings = _Bindings();
  static final _finalizer = NativeFinalizer(_bindings.destroyPointer);
  static int get calls => _bindings.calls();
  static int get sessions => _bindings.sessions();
  static int get searches => _bindings.searches();
  static Map<String, int> get distanceReuse => {
    'calls': _bindings.distanceCalls(),
    'hits': _bindings.distanceHits(),
  };
  final int _count;
  final Float64List _coordinates;
  final _HypDistanceKernel _distanceKernel;
  late Pointer<Void> _pointer;
  StationCoreBuffer? _input, _summary, _searchLog;
  StationCoreBuffer? _distances, _output, _waves;
  NativeCallable<_DistanceNative>? _distanceCallback;
  Object? _callbackError;
  StackTrace? _callbackStack;
  bool _disposed = false;

  int _writeDistances(
    double lat,
    double lng,
    Pointer<Double> output,
    int count,
  ) {
    try {
      if (count * 2 != _coordinates.length) {
        throw StateError('Native HYP distance count mismatch');
      }
      _distanceKernel.write(lat, lng, output.asTypedList(count));
      return 0;
    } catch (error, stack) {
      _callbackError = error;
      _callbackStack = stack;
      return 6;
    }
  }

  NativeHypSearchResult search(
    double latitude,
    double longitude,
    double depth,
  ) {
    if (_disposed) throw StateError('HYP scoring session disposed');
    _callbackError = null;
    _callbackStack = null;
    try {
      _input!.pointer.cast<Double>().asTypedList(3).setAll(0, [
        latitude,
        longitude,
        depth,
      ]);
      final status = _bindings.search(
        _pointer,
        _input!.pointer.cast(),
        _distanceCallback!.nativeFunction,
        _summary!.pointer.cast(),
        _output!.pointer.cast(),
        _waves!.pointer.cast(),
      );
      if (_callbackError != null) {
        Error.throwWithStackTrace(_callbackError!, _callbackStack!);
      }
      if (status != 0) throw StateError('HYP search failed (status $status)');
      final length = _bindings.logWords(_pointer);
      if (length % NativeHypSearchResult.rowWords != 0 || length > 33000) {
        throw StateError('Invalid HYP search log size $length');
      }
      final copyStatus = _bindings.logCopy(
        _pointer,
        _searchLog!.pointer.cast(),
        length,
      );
      if (copyStatus != 0) {
        throw StateError('HYP search log failed (status $copyStatus)');
      }
      return NativeHypSearchResult(
        Float64List.fromList(_summary!.pointer.cast<Double>().asTypedList(4)),
        _readScore(),
        Float64List.fromList(
          _searchLog!.pointer.cast<Double>().asTypedList(length),
        ),
      );
    } finally {
      _callbackError = null;
      _callbackStack = null;
    }
  }

  NativeHypScoreResult _readScore() => NativeHypScoreResult(
    Float64List.fromList(
      _output!.pointer.cast<Double>().asTypedList(
        NativeHypScoreResult.outputWords,
      ),
    ),
    Int8List.fromList(_waves!.pointer.cast<Int8>().asTypedList(_count * 2)),
  );

  NativeHypScoreResult evaluate(
    double latitude,
    double longitude,
    double depth,
  ) {
    if (_disposed) throw StateError('HYP scoring session disposed');
    _distanceKernel.write(
      latitude,
      longitude,
      _distances!.pointer.cast<Double>().asTypedList(_coordinates.length ~/ 2),
    );
    final status = _bindings.evaluate(
      _pointer,
      _distances!.pointer.cast(),
      depth,
      _output!.pointer.cast(),
      _waves!.pointer.cast(),
    );
    if (status != 0) throw StateError('HYP scoring failed (status $status)');
    return NativeHypScoreResult(
      Float64List.fromList(
        _output!.pointer.cast<Double>().asTypedList(
          NativeHypScoreResult.outputWords,
        ),
      ),
      Int8List.fromList(_waves!.pointer.cast<Int8>().asTypedList(_count * 2)),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _distanceCallback?.close();
    _input?.dispose();
    _summary?.dispose();
    _searchLog?.dispose();
    _distances?.dispose();
    _output?.dispose();
    _waves?.dispose();
    _finalizer.detach(this);
    _bindings.destroy(_pointer);
  }
}

/// Reuses station-only trigonometry across all HYP candidates. The candidate
/// arithmetic intentionally keeps the original order and `pow(..., 2)` calls
/// so the returned distances remain bit-identical to [writeHypDistances].
final class _HypDistanceKernel {
  _HypDistanceKernel(List<double> coordinates)
    : _latitudes = Float64List(coordinates.length ~/ 2),
      _longitudes = Float64List(coordinates.length ~/ 2),
      _cosLatitudes = Float64List(coordinates.length ~/ 2) {
    for (var i = 0; i < _latitudes.length; i++) {
      final lat = coordinates[i * 2], lng = coordinates[i * 2 + 1];
      _latitudes[i] = lat;
      _longitudes[i] = lng;
      _cosLatitudes[i] = math.cos(radians(lat));
    }
  }

  final Float64List _latitudes, _longitudes, _cosLatitudes;

  static double radians(double value) => value * math.pi / 180.0;

  void write(double latitude, double longitude, Float64List output) {
    final candidateCosine = math.cos(radians(latitude));
    for (var i = 0; i < _latitudes.length; i++) {
      final lat = _latitudes[i], lng = _longitudes[i];
      final a =
          math.pow(math.sin(radians(lat - latitude) / 2), 2) +
          candidateCosine *
              _cosLatitudes[i] *
              math.pow(math.sin(radians(lng - longitude) / 2), 2);
      output[i] = 6371.0088 * (2 * math.atan2(math.sqrt(a), math.sqrt(1 - a)));
    }
  }
}

class _Bindings {
  _Bindings() {
    final lib = StationCoreLibrary.library;
    final version = lib.lookupFunction<Uint32 Function(), int Function()>(
      'rq_hyp_score_abi_version',
    )();
    if (version != 1) throw StateError('Unsupported HYP scoring ABI: $version');
    create = lib
        .lookupFunction<
          Pointer<Void> Function(Pointer<Int64>, Pointer<Double>, Size, Size),
          Pointer<Void> Function(Pointer<Int64>, Pointer<Double>, int, int)
        >('rq_hyp_score_create');
    evaluate = lib
        .lookupFunction<
          Int32 Function(
            Pointer<Void>,
            Pointer<Double>,
            Double,
            Pointer<Double>,
            Pointer<Int8>,
          ),
          int Function(
            Pointer<Void>,
            Pointer<Double>,
            double,
            Pointer<Double>,
            Pointer<Int8>,
          )
        >('rq_hyp_score_evaluate');
    destroyPointer = lib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
      'rq_hyp_score_destroy',
    );
    destroy = destroyPointer.asFunction<void Function(Pointer<Void>)>();
    sessions = lib.lookupFunction<Uint64 Function(), int Function()>(
      'rq_hyp_score_sessions',
    );
    calls = lib.lookupFunction<Uint64 Function(), int Function()>(
      'rq_hyp_score_calls',
    );
    final searchVersion = lib.lookupFunction<Uint32 Function(), int Function()>(
      'rq_hyp_search_abi_version',
    )();
    if (searchVersion != 1) {
      throw StateError('Unsupported HYP search ABI: $searchVersion');
    }
    search = lib.lookupFunction<_SearchNative, _SearchDart>(
      'rq_hyp_score_search',
    );
    searches = lib.lookupFunction<Uint64 Function(), int Function()>(
      'rq_hyp_search_calls',
    );
    distanceCalls = lib.lookupFunction<Uint64 Function(), int Function()>(
      'rq_hyp_search_distance_calls',
    );
    distanceHits = lib.lookupFunction<Uint64 Function(), int Function()>(
      'rq_hyp_search_distance_hits',
    );
    logWords = lib
        .lookupFunction<
          Size Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('rq_hyp_search_log_words');
    logCopy = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Double>, Size),
          int Function(Pointer<Void>, Pointer<Double>, int)
        >('rq_hyp_search_log_copy');
  }
  late final Pointer<Void> Function(Pointer<Int64>, Pointer<Double>, int, int)
  create;
  late final int Function(
    Pointer<Void>,
    Pointer<Double>,
    double,
    Pointer<Double>,
    Pointer<Int8>,
  )
  evaluate;
  late final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
  destroyPointer;
  late final void Function(Pointer<Void>) destroy;
  late final int Function() sessions, calls;
  late final int Function() searches;
  late final int Function() distanceCalls, distanceHits;
  late final _SearchDart search;
  late final int Function(Pointer<Void>) logWords;
  late final int Function(Pointer<Void>, Pointer<Double>, int) logCopy;
}
