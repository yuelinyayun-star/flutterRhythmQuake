import 'dart:ffi';
import 'dart:typed_data';
import '../../services/sources/native_station_core_library_io.dart';
import 'native_hyp_score_result.dart';
import 'native_hyp_search_result.dart';

typedef _SearchNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Int8>,
    );
typedef _SearchDart =
    int Function(
      Pointer<Void>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Int8>,
    );
typedef _SearchOptionsNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Double>,
      Uint32,
      Size,
      Double,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Int8>,
    );
typedef _SearchOptionsDart =
    int Function(
      Pointer<Void>,
      Pointer<Double>,
      int,
      int,
      double,
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
  }) : _count = observedSeconds.length {
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
    final geometry = StationCoreBuffer(coordinates.length * 8);
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
      geometry.pointer
          .cast<Double>()
          .asTypedList(coordinates.length)
          .setAll(0, coordinates);
      final status = _bindings.setCoordinates(
        _pointer,
        geometry.pointer.cast(),
        coordinates.length ~/ 2,
      );
      if (status != 0) {
        _bindings.destroy(_pointer);
        throw StateError('Cannot prepare native HYP geometry (status $status)');
      }
      _finalizer.attach(this, _pointer, detach: this);
    } finally {
      info.dispose();
      observed.dispose();
      geometry.dispose();
    }
    try {
      _input = StationCoreBuffer(3 * 8);
      _summary = StationCoreBuffer(4 * 8);
      _searchLog = StationCoreBuffer(33000 * 8);
      _output = StationCoreBuffer(NativeHypScoreResult.outputWords * 8);
      _waves = StationCoreBuffer(_count * 2);
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
  late Pointer<Void> _pointer;
  StationCoreBuffer? _input, _summary, _searchLog;
  StationCoreBuffer? _output, _waves;
  bool _disposed = false;

  NativeHypSearchResult search(
    double latitude,
    double longitude,
    double depth, {
    bool finalJoint = false,
    int finalJointMinCount = 15,
    double finalJointMaxScore = 5.0,
  }) {
    if (_disposed) throw StateError('HYP scoring session disposed');

    _input!.pointer.cast<Double>().asTypedList(3).setAll(0, [
      latitude,
      longitude,
      depth,
    ]);
    final status = finalJoint
        ? _bindings.searchOptions(
            _pointer,
            _input!.pointer.cast(),
            1,
            finalJointMinCount,
            finalJointMaxScore,
            _summary!.pointer.cast(),
            _output!.pointer.cast(),
            _waves!.pointer.cast(),
          )
        : _bindings.search(
            _pointer,
            _input!.pointer.cast(),
            _summary!.pointer.cast(),
            _output!.pointer.cast(),
            _waves!.pointer.cast(),
          );
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
    final status = _bindings.evaluateAt(
      _pointer,
      latitude,
      longitude,
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
    _input?.dispose();
    _summary?.dispose();
    _searchLog?.dispose();
    _output?.dispose();
    _waves?.dispose();
    _finalizer.detach(this);
    _bindings.destroy(_pointer);
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
    setCoordinates = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Double>, Size),
          int Function(Pointer<Void>, Pointer<Double>, int)
        >('rq_hyp_score_geometry_set');
    evaluateAt = lib
        .lookupFunction<
          Int32 Function(
            Pointer<Void>,
            Double,
            Double,
            Double,
            Pointer<Double>,
            Pointer<Int8>,
          ),
          int Function(
            Pointer<Void>,
            double,
            double,
            double,
            Pointer<Double>,
            Pointer<Int8>,
          )
        >('rq_hyp_score_evaluate_owned');
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
      'rq_hyp_score_search_owned',
    );
    searchOptions = lib
        .lookupFunction<_SearchOptionsNative, _SearchOptionsDart>(
          'rq_hyp_score_search_owned_options',
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
  late final int Function(Pointer<Void>, Pointer<Double>, int) setCoordinates;
  late final int Function(
    Pointer<Void>,
    double,
    double,
    double,
    Pointer<Double>,
    Pointer<Int8>,
  )
  evaluateAt;
  late final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
  destroyPointer;
  late final void Function(Pointer<Void>) destroy;
  late final int Function() sessions, calls;
  late final int Function() searches;
  late final int Function() distanceCalls, distanceHits;
  late final _SearchDart search;
  late final _SearchOptionsDart searchOptions;
  late final int Function(Pointer<Void>) logWords;
  late final int Function(Pointer<Void>, Pointer<Double>, int) logCopy;
}
