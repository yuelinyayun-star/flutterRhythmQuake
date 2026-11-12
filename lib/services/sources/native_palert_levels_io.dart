import 'dart:ffi';
import 'dart:typed_data';

import 'native_station_core_library_io.dart';

typedef _ConfigureNative = Int32 Function(Pointer<Void>, Pointer<Int32>, Size);
typedef _ConfigureDart = int Function(Pointer<Void>, Pointer<Int32>, int);
typedef _ProcessNative =
    Int32 Function(Pointer<Void>, Int64, Pointer<Double>, Size, Pointer<Int32>);
typedef _ProcessDart =
    int Function(Pointer<Void>, int, Pointer<Double>, int, Pointer<Int32>);

final class NativePAlertLevels implements Finalizable {
  NativePAlertLevels() {
    _owner = _bindings.create();
    if (_owner == nullptr) {
      throw StateError('Cannot create P-Alert level history');
    }
    _finalizer.attach(this, _owner, detach: this);
  }
  static bool get supported => StationCoreLibrary.supported;
  static final _bindings = _Bindings();
  static final _finalizer = NativeFinalizer(_bindings.destroyPointer);
  static Map<String, int> get diagnostics => {
    'sessions': _bindings.sessions(),
    'calls': _bindings.calls(),
  };
  late final Pointer<Void> _owner;
  StationCoreBuffer? _input, _output;
  bool _disposed = false;
  int _count = 0;

  void configure(Int32List remap) {
    if (_disposed) throw StateError('P-Alert history disposed');
    final nextInput = StationCoreBuffer(remap.length * 3 * 8);
    final nextOutput = StationCoreBuffer(remap.length * 2 * 4);
    try {
      nextInput.pointer
          .cast<Int32>()
          .asTypedList(remap.length)
          .setAll(0, remap);
      final status = _bindings.configure(
        _owner,
        nextInput.pointer.cast(),
        remap.length,
      );
      if (status != 0) throw StateError('P-Alert layout failed ($status)');
    } catch (_) {
      nextInput.dispose();
      nextOutput.dispose();
      rethrow;
    }
    _input?.dispose();
    _output?.dispose();
    _input = nextInput;
    _output = nextOutput;
    _count = remap.length;
  }

  Int32List process(int time, Float64List input) {
    if (_disposed) throw StateError('P-Alert history disposed');
    if (input.length != _count * 3 || _input == null) {
      throw ArgumentError('P-Alert layout mismatch');
    }
    _input!.pointer.cast<Double>().asTypedList(input.length).setAll(0, input);
    final status = _bindings.process(
      _owner,
      time,
      _input!.pointer.cast(),
      _count,
      _output!.pointer.cast(),
    );
    if (status != 0) throw StateError('P-Alert levels failed ($status)');
    return Int32List.fromList(
      _output!.pointer.cast<Int32>().asTypedList(_count * 2),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    _bindings.destroy(_owner);
    _input?.dispose();
    _input = null;
    _output?.dispose();
    _output = null;
  }
}

class _Bindings {
  _Bindings() {
    final library = StationCoreLibrary.library;
    final version = library.lookupFunction<Uint32 Function(), int Function()>(
      'rq_palert_levels_abi_version',
    )();
    if (version != 1) {
      throw StateError('Unsupported P-Alert levels ABI $version');
    }
    create = library
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'rq_palert_levels_create',
        );
    configure = library.lookupFunction<_ConfigureNative, _ConfigureDart>(
      'rq_palert_levels_configure',
    );
    process = library.lookupFunction<_ProcessNative, _ProcessDart>(
      'rq_palert_levels_process',
    );
    destroyPointer = library
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
          'rq_palert_levels_destroy',
        );
    destroy = destroyPointer.asFunction<void Function(Pointer<Void>)>();
    sessions = library.lookupFunction<Uint64 Function(), int Function()>(
      'rq_palert_levels_sessions',
    );
    calls = library.lookupFunction<Uint64 Function(), int Function()>(
      'rq_palert_levels_calls',
    );
  }
  late final Pointer<Void> Function() create;
  late final _ConfigureDart configure;
  late final _ProcessDart process;
  late final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
  destroyPointer;
  late final void Function(Pointer<Void>) destroy;
  late final int Function() sessions, calls;
}
