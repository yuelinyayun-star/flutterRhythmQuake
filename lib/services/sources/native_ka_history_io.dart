import 'dart:ffi';
import 'dart:typed_data';
import 'ka_station_history.dart';
import 'native_station_core_library_io.dart';
import 'native_station_image_decoder.dart';

class NativeKaHistorySession implements Finalizable {
  NativeKaHistorySession(this.count) {
    if (!supported) {
      throw UnsupportedError('Native KA history requires Windows');
    }
    if (count < 0 || count > 1048576) throw RangeError.range(count, 0, 1048576);
    _create();
    _input = StationCoreBuffer(count * 48);
    _output = StationCoreBuffer(count * 48);
    _inputInts = _input.pointer.cast<Int64>().asTypedList(count * 6);
    _inputDoubles = _input.pointer.cast<Double>().asTypedList(count * 6);
    _outputInts = _output.pointer.cast<Int64>().asTypedList(count * 6);
    _outputDoubles = _output.pointer.cast<Double>().asTypedList(count * 6);
    _histories = List.generate(
      count,
      (i) => _NativeHistory(this, i),
      growable: false,
    );
  }
  static bool get supported => StationCoreLibrary.supported;
  static final _Bindings _bindings = _Bindings();
  static final _finalizer = NativeFinalizer(_bindings.destroyPointer);
  static Map<String, int> get diagnostics => {
    ...NativeStationImageDecoder.memoryStats,
    'kaSessions': _bindings.sessions(),
    'kaCalls': _bindings.calls(),
  };
  final int count;
  late Pointer<Void> _pointer;
  late final List<_NativeHistory> _histories;
  List<KaStationHistory> get histories => _histories;
  late final StationCoreBuffer _input, _output;
  StationCoreBuffer? _historyBuffer;
  StationCoreBuffer? _frameHistoryBuffer;
  StationCoreBuffer? _observationFlags;
  bool _resultsBorrowed = false;
  bool _hasFrameResults = false;
  Uint8List? _flagsView;
  Int64List? _frameHistoryInts;
  bool _frameCopyReady = false;
  bool? _canCopyFrame;
  late final Int64List _inputInts, _outputInts;
  late final Float64List _outputDoubles;
  late final Float64List _inputDoubles;
  bool _disposed = false;
  int get bufferCapacityBytes =>
      _input.length +
      _output.length +
      (_historyBuffer?.length ?? 0) +
      (_frameHistoryBuffer?.length ?? 0) +
      (_observationFlags?.length ?? 0);
  void _create() {
    _pointer = _bindings.create(count);
    if (_pointer == nullptr) {
      throw StateError('Cannot allocate native KA session');
    }
    _finalizer.attach(this, _pointer, detach: this);
  }

  void _check() {
    if (_disposed) throw StateError('Native KA session disposed');
    if (_resultsBorrowed) throw StateError('Native KA results are borrowed');
  }

  /// Raw observation bridge; scale conversion and gap handling belong to Rust.
  void writeShindoInput(
    int index, {
    required double shindo,
    required int expireSeconds,
    required bool isActive,
  }) {
    _check();
    RangeError.checkValidIndex(index, _histories);
    final offset = index * 6;
    _inputInts[offset] = index;
    _inputDoubles[offset + 1] = shindo;
    _inputInts[offset + 2] = expireSeconds;
    _inputInts[offset + 3] = 0;
    _inputInts[offset + 4] = isActive ? 1 : 0;
    _inputInts[offset + 5] = 0;
  }

  void setShindoAbnormalCount(int index, int? value) {
    _check();
    RangeError.checkValidIndex(index, _histories);
    _status(
      _bindings.setShindoAbnormal(
        _pointer,
        index,
        value ?? 0,
        value == null ? 0 : 1,
      ),
    );
  }

  void processShindoFrame(int originalTimeMilliseconds) {
    _check();
    _observationFlags ??= StationCoreBuffer(count);
    _flagsView ??= _observationFlags!.pointer.asTypedList(count);
    _status(
      _bindings.processShindo(
        _pointer,
        _input.pointer.cast(),
        count,
        originalTimeMilliseconds,
        _output.pointer.cast(),
        _observationFlags!.pointer,
      ),
    );
    for (var i = 0; i < count; i++) {
      _histories[i]._invalidate(_outputInts[i * 6 + 5] & 0xffffffff);
    }
    _invalidateFrameCopy();
    _hasFrameResults = true;
  }

  void resetShindoClock() {
    _check();
    _status(_bindings.resetShindoClock(_pointer));
  }

  int observationFlags(int index) {
    _check();
    RangeError.checkValidIndex(index, _histories);
    if (_observationFlags == null) throw StateError('No raw KA frame');
    return _flagsView![index];
  }

  /// Synchronous native interop only; the pointer must not escape the callback.
  T withNativeResults<T>(T Function(Pointer<Void>, int) consume) {
    _check();
    if (!_hasFrameResults) {
      throw StateError('No complete native KA result frame');
    }
    _resultsBorrowed = true;
    try {
      return consume(_output.pointer.cast(), count);
    } finally {
      _resultsBorrowed = false;
    }
  }

  void writeInput(
    int index, {
    required int level,
    required int expireSeconds,
    required int baseTimeMilliseconds,
    required bool isActive,
    required int? abnormalUpdateCount,
  }) {
    _check();
    RangeError.checkValidIndex(index, _histories);
    final offset = index * 6;
    _inputInts[offset] = index;
    _inputInts[offset + 1] = level;
    _inputInts[offset + 2] = expireSeconds;
    _inputInts[offset + 3] = baseTimeMilliseconds;
    _inputInts[offset + 4] =
        (isActive ? 1 : 0) | (abnormalUpdateCount != null ? 2 : 0);
    _inputInts[offset + 5] = abnormalUpdateCount ?? 0;
  }

  void process() {
    _check();
    _status(
      _bindings.process(
        _pointer,
        _input.pointer.cast(),
        count,
        _output.pointer.cast(),
      ),
    );
    for (var i = 0; i < count; i++) {
      _histories[i]._invalidate(_outputInts[i * 6 + 5] & 0xffffffff);
    }
    _invalidateFrameCopy();
    _hasFrameResults = true;
  }

  KaHistoryResult result(int index) {
    _check();
    RangeError.checkValidIndex(index, _histories);
    final offset = index * 6;
    return KaHistoryResult(
      _outputInts[offset],
      _outputInts[offset + 1],
      _outputInts[offset + 2],
      _outputDoubles[offset + 3],
      (_outputInts[offset + 5] & (1 << 32)) == 0
          ? null
          : _outputInts[offset + 4],
    );
  }

  KaHistoryResult _updateOne(
    int index, {
    required int level,
    required int expireSeconds,
    required int baseTimeMilliseconds,
    required bool isActive,
    required int? abnormalUpdateCount,
  }) {
    writeInput(
      index,
      level: level,
      expireSeconds: expireSeconds,
      baseTimeMilliseconds: baseTimeMilliseconds,
      isActive: isActive,
      abnormalUpdateCount: abnormalUpdateCount,
    );
    _status(
      _bindings.process(
        _pointer,
        (_input.pointer + index * 48).cast(),
        1,
        (_output.pointer + index * 48).cast(),
      ),
    );
    _histories[index]._invalidate(_outputInts[index * 6 + 5] & 0xffffffff);
    _invalidateFrameCopy();
    return result(index);
  }

  Pointer<Int64> _historySpace(int length) {
    if ((_historyBuffer?.length ?? 0) < length * 8) {
      _historyBuffer?.dispose();
      _historyBuffer = StationCoreBuffer(length * 8);
    }
    return _historyBuffer?.pointer.cast<Int64>() ?? nullptr;
  }

  List<int> _copy(int index, int length) {
    _check();
    if (length == 0) return <int>[];
    // Snapshot consumers read most stations together. The private native frame
    // view is reused only while this session is live. Copy original entries by
    // typed index into an owned growable list before returning to any consumer.
    _canCopyFrame ??= _histories.every((h) => h.length <= 60);
    if (_canCopyFrame!) {
      if (!_frameCopyReady) {
        _frameHistoryBuffer ??= StationCoreBuffer(count * 60 * 8);
        final pointer = _frameHistoryBuffer!.pointer.cast<Int64>();
        _frameHistoryInts ??= pointer.asTypedList(count * 60);
        _status(_bindings.copyFrame(_pointer, pointer, count));
        _frameCopyReady = true;
      }
      final source = _frameHistoryInts!;
      final result = List<int>.filled(length, 0, growable: true);
      final offset = index * 60;
      for (var i = 0; i < length; i++) {
        result[i] = source[offset + i];
      }
      return result;
    }
    final buffer = _historySpace(length);
    _status(_bindings.copy(_pointer, index, buffer, length));
    // No native memory view escapes the call or the session lifetime.
    final source = buffer.asTypedList(length);
    final result = List<int>.filled(length, 0, growable: true);
    for (var i = 0; i < length; i++) {
      result[i] = source[i];
    }
    return result;
  }

  void _replace(int index, List<int> values) {
    _check();
    if (values.length > 1048576) {
      throw ArgumentError('KA history exceeds ABI limit');
    }
    final buffer = _historySpace(values.length);
    if (values.isNotEmpty) buffer.asTypedList(values.length).setAll(0, values);
    _status(_bindings.replace(_pointer, index, buffer, values.length));
    _invalidateFrameCopy();
  }

  void _invalidateFrameCopy() {
    _frameCopyReady = false;
    _canCopyFrame = null;
  }

  void reset() {
    _check();
    final next = _bindings.create(count);
    if (next == nullptr) throw StateError('Cannot reset native KA session');
    _finalizer.detach(this);
    _bindings.destroy(_pointer);
    _pointer = next;
    _finalizer.attach(this, _pointer, detach: this);
    for (final history in _histories) {
      history._invalidate(0);
    }
    _invalidateFrameCopy();
    _hasFrameResults = false;
  }

  void dispose() {
    if (_disposed) return;
    _check();
    // Retained station objects remain readable after a service stop.
    for (final history in _histories) {
      history._detach();
    }
    _disposed = true;
    _finalizer.detach(this);
    _bindings.destroy(_pointer);
    _pointer = nullptr;
    _input.dispose();
    _output.dispose();
    _historyBuffer?.dispose();
    _frameHistoryBuffer?.dispose();
    _observationFlags?.dispose();
    _flagsView = null;
    _frameHistoryInts = null;
    _invalidateFrameCopy();
  }

  static void _status(int code) {
    if (code != 0) throw StateError('Native KA ABI status $code');
  }
}

class _NativeHistory extends KaStationHistory {
  _NativeHistory(this._owner, this.index);
  NativeKaHistorySession? _owner;
  NativeKaHistorySession get owner =>
      _owner ?? (throw StateError('KA history detached'));
  final int index;
  int _length = 0;
  List<int>? _cache;
  bool _detached = false;
  @override
  bool get isNative => !_detached;
  @override
  List<int> detachedCopy() =>
      _cache != null ? List<int>.of(_cache!) : owner._copy(index, _length);
  List<int> get _values => _cache ??= owner._copy(index, _length);
  void _invalidate(int length) {
    _length = length;
    _cache = null;
  }

  void _detach() {
    _cache = List<int>.of(_values);
    _detached = true;
    _owner = null;
  }

  @override
  int get length => _length;
  @override
  set length(int value) {
    RangeError.checkValueInInterval(value, 0, _length);
    if (value == _length) return;
    replace(_values.take(value));
  }

  @override
  int operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return _values[index];
  }

  @override
  void operator []=(int index, int value) {
    RangeError.checkValidIndex(index, this);
    final next = List<int>.of(_values)..[index] = value;
    replace(next);
  }

  @override
  void replace(Iterable<int> values) {
    final copied = List<int>.of(values);
    if (!_detached) owner._replace(index, copied);
    _length = copied.length;
    _cache = copied;
  }

  @override
  void clear() => replace(const []);
  @override
  void add(int value) => replace([..._values, value]);
  @override
  void addAll(Iterable<int> values) => replace([..._values, ...values]);
  @override
  void insert(int index, int value) {
    RangeError.checkValueInInterval(index, 0, length);
    replace(List<int>.of(_values)..insert(index, value));
  }

  @override
  void insertAll(int index, Iterable<int> values) {
    RangeError.checkValueInInterval(index, 0, length);
    replace(List<int>.of(_values)..insertAll(index, values));
  }

  @override
  KaHistoryResult update({
    required int level,
    required int expireSeconds,
    required int baseTimeMilliseconds,
    required bool isActive,
    required int? abnormalUpdateCount,
  }) {
    if (_detached) {
      throw StateError('Detached KA history has no native processor');
    }
    return owner._updateOne(
      index,
      level: level,
      expireSeconds: expireSeconds,
      baseTimeMilliseconds: baseTimeMilliseconds,
      isActive: isActive,
      abnormalUpdateCount: abnormalUpdateCount,
    );
  }
}

class _Bindings {
  _Bindings() {
    final abi = StationCoreLibrary.library
        .lookupFunction<Uint32 Function(), int Function()>(
          'rq_ka_abi_version',
        )();
    if (abi != 1) throw StateError('Unsupported KA ABI $abi');
  }
  final create = StationCoreLibrary.library
      .lookupFunction<
        Pointer<Void> Function(UintPtr),
        Pointer<Void> Function(int)
      >('rq_ka_create');
  final destroy = StationCoreLibrary.library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('rq_ka_destroy');
  final destroyPointer = StationCoreLibrary.library
      .lookup<NativeFunction<Void Function(Pointer<Void>)>>('rq_ka_destroy');
  final process = StationCoreLibrary.library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Void>, UintPtr, Pointer<Void>),
        int Function(Pointer<Void>, Pointer<Void>, int, Pointer<Void>)
      >('rq_ka_process');
  late final processShindo = StationCoreLibrary.library
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<Void>,
          UintPtr,
          Int64,
          Pointer<Void>,
          Pointer<Uint8>,
        ),
        int Function(
          Pointer<Void>,
          Pointer<Void>,
          int,
          int,
          Pointer<Void>,
          Pointer<Uint8>,
        )
      >('rq_ka_process_shindo');
  late final resetShindoClock = StationCoreLibrary.library
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('rq_ka_reset_shindo_clock');
  late final setShindoAbnormal = StationCoreLibrary.library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Size, Int64, Uint8),
        int Function(Pointer<Void>, int, int, int)
      >('rq_ka_set_shindo_abnormal');
  final copy = StationCoreLibrary.library
      .lookupFunction<
        Int32 Function(Pointer<Void>, UintPtr, Pointer<Int64>, UintPtr),
        int Function(Pointer<Void>, int, Pointer<Int64>, int)
      >('rq_ka_copy_history');
  final copyFrame = StationCoreLibrary.library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Int64>, UintPtr),
        int Function(Pointer<Void>, Pointer<Int64>, int)
      >('rq_ka_copy_histories');
  final replace = StationCoreLibrary.library
      .lookupFunction<
        Int32 Function(Pointer<Void>, UintPtr, Pointer<Int64>, UintPtr),
        int Function(Pointer<Void>, int, Pointer<Int64>, int)
      >('rq_ka_replace_history');
  final sessions = StationCoreLibrary.library
      .lookupFunction<Uint64 Function(), int Function()>('rq_ka_sessions');
  final calls = StationCoreLibrary.library
      .lookupFunction<Uint64 Function(), int Function()>('rq_ka_calls');
}
