import 'dart:ffi';
import 'dart:typed_data';

import 'package:iirjdart/butterworth.dart';

import '../../core/seedlink_activity.dart';
import 'native_station_core_library_io.dart';

typedef _AcceptNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Int64>,
      Size,
      Double,
      Int64,
      Pointer<Double>,
      Pointer<Double>,
    );
typedef _AcceptDart =
    int Function(
      Pointer<Void>,
      Pointer<Int64>,
      int,
      double,
      int,
      Pointer<Double>,
      Pointer<Double>,
    );

/// One persistent signal state per NSLC; one bounded scratch block per isolate.
/// Synchronous FFI calls contain no callbacks and do not retain input pointers.
final class NativeSeedLinkSignal implements Finalizable {
  NativeSeedLinkSignal() {
    _pointer = _bindings.create();
    if (_pointer == nullptr) throw StateError('Cannot create SeedLink signal');
    _finalizer.attach(this, _pointer, detach: this);
    _owners++;
  }

  static bool get supported => StationCoreLibrary.supported;
  static final _bindings = _Bindings();
  static final _finalizer = NativeFinalizer(_bindings.destroyPointer);
  static final _designs = <double, Float64List>{};
  static StationCoreBuffer? _input, _coefficients, _output;
  static Int64List? _samples;
  static Float64List? _coefficientValues, _outputValues;
  static int _owners = 0;
  static Map<String, int> get diagnostics => {
    'sessions': _bindings.sessions(),
    'calls': _bindings.calls(),
    'scratchBytes':
        (_input?.length ?? 0) +
        (_coefficients?.length ?? 0) +
        (_output?.length ?? 0),
  };

  late final Pointer<Void> _pointer;
  bool _disposed = false;
  SeedLinkActivity _snapshot = const SeedLinkActivity();
  SeedLinkActivity get snapshot => _snapshot;

  static Float64List _design(double rate) {
    final cached = _designs[rate];
    if (cached != null) return cached;
    final filter = Butterworth()..bandPass(3, rate, 3.5, 3);
    final values = Float64List(15);
    for (var stage = 0; stage < 3; stage++) {
      final c = filter.getBiquad(stage);
      values.setAll(stage * 5, [c.a1, c.a2, c.b0, c.b1, c.b2]);
    }
    if (_designs.length == 32) _designs.remove(_designs.keys.first);
    return _designs[rate] = values;
  }

  SeedLinkActivity accept(List<int> samples, double rate, DateTime start) {
    if (_disposed) throw StateError('SeedLink signal disposed');
    if (samples.isEmpty || !rate.isFinite || rate <= 0) return _snapshot;
    if (samples.length > 65535) throw ArgumentError('MiniSEED sample limit');
    final bytes = samples.length * 8;
    if ((_input?.length ?? 0) < bytes) {
      _input?.dispose();
      _input = StationCoreBuffer(bytes);
      _samples = _input!.pointer.cast<Int64>().asTypedList(samples.length);
    }
    if (_coefficients == null) {
      _coefficients = StationCoreBuffer(15 * 8);
      _coefficientValues = _coefficients!.pointer.cast<Double>().asTypedList(
        15,
      );
      _coefficientValues!.fillRange(0, 15, 0);
      _output = StationCoreBuffer(2 * 8);
      _outputValues = _output!.pointer.cast<Double>().asTypedList(2);
    }
    _samples!.setRange(0, samples.length, samples);
    if (rate > 10) _coefficientValues!.setAll(0, _design(rate));
    final status = _bindings.accept(
      _pointer,
      _input!.pointer.cast(),
      samples.length,
      rate,
      start.microsecondsSinceEpoch,
      _coefficients!.pointer.cast(),
      _output!.pointer.cast(),
    );
    if (status != 0) throw StateError('SeedLink signal failed ($status)');
    final ratio = _outputValues![0].isNaN ? null : _outputValues![0];
    final event = _outputValues![1] == 1;
    if (_snapshot.ratio != ratio || _snapshot.event != event) {
      _snapshot = SeedLinkActivity(ratio: ratio, event: event);
    }
    return _snapshot;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    _bindings.destroy(_pointer);
    if (--_owners == 0) {
      _input?.dispose();
      _input = null;
      _samples = null;
      _coefficients?.dispose();
      _coefficients = null;
      _coefficientValues = null;
      _output?.dispose();
      _output = null;
      _outputValues = null;
    }
  }
}

class _Bindings {
  _Bindings() {
    final library = StationCoreLibrary.library;
    final version = library.lookupFunction<Uint32 Function(), int Function()>(
      'rq_seedlink_signal_abi_version',
    )();
    if (version != 1) {
      throw StateError('Unsupported SeedLink signal ABI $version');
    }
    create = library
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'rq_seedlink_signal_create',
        );
    accept = library.lookupFunction<_AcceptNative, _AcceptDart>(
      'rq_seedlink_signal_accept',
    );
    destroyPointer = library
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
          'rq_seedlink_signal_destroy',
        );
    destroy = destroyPointer.asFunction<void Function(Pointer<Void>)>();
    sessions = library.lookupFunction<Uint64 Function(), int Function()>(
      'rq_seedlink_signal_sessions',
    );
    calls = library.lookupFunction<Uint64 Function(), int Function()>(
      'rq_seedlink_signal_calls',
    );
  }
  late final Pointer<Void> Function() create;
  late final _AcceptDart accept;
  late final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
  destroyPointer;
  late final void Function(Pointer<Void>) destroy;
  late final int Function() sessions, calls;
}
