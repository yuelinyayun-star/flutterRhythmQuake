import 'dart:ffi';
import 'dart:typed_data';
import '../../models/fssn_station_frame.dart';
import 'native_station_core_library_io.dart';

final class NativeFssnStations implements Finalizable {
  NativeFssnStations(Uint8List layout) {
    final input = StationCoreBuffer(layout.length);
    try {
      input.pointer.asTypedList(layout.length).setAll(0, layout);
      _owner = _bindings.create(input.pointer, layout.length);
      if (_owner == nullptr) {
        throw const FormatException('Invalid FSSN station layout');
      }
    } finally {
      input.dispose();
    }
    _finalizer.attach(this, _owner, detach: this);
    _count = _bindings.count(_owner);
    try {
      _input = StationCoreBuffer(1024);
      _output = StationCoreBuffer((1 + _count * 5) * 8);
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  static bool get supported => StationCoreLibrary.supported;
  static final _bindings = _Bindings();
  static final _finalizer = NativeFinalizer(_bindings.destroyPointer);
  static int get sessions => _bindings.sessions();
  late final Pointer<Void> _owner;
  late final int _count;
  StationCoreBuffer? _input, _output;
  bool _disposed = false;

  FssnStationFrame process(Uint8List bytes) {
    if (_disposed) throw StateError('FSSN station decoder disposed');
    if (bytes.length > 1024) {
      throw const FormatException('Oversized FSSN frame');
    }
    _input!.pointer.asTypedList(bytes.length).setAll(0, bytes);
    final length = 1 + _count * 5;
    final status = _bindings.process(
      _owner,
      _input!.pointer,
      bytes.length,
      _output!.pointer.cast(),
      length,
    );
    if (status != 0) throw FormatException('Invalid FSSN frame ($status)');
    // Copy values before the next native call or disposal can reuse this buffer.
    final output = _output!.pointer.cast<Double>().asTypedList(length);
    return FssnStationFrame(
      output[0].toInt(),
      List.unmodifiable(
        List.generate(_count, (i) {
          final offset = 1 + i * 5;
          return FssnStationReading(
            latitude: output[offset],
            longitude: output[offset + 1],
            pga: output[offset + 2] < 0 ? null : output[offset + 2],
            status: output[offset + 3].toInt(),
            argb: output[offset + 4].toInt(),
          );
        }),
      ),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    _bindings.destroy(_owner);
    _input?.dispose();
    _output?.dispose();
    _input = null;
    _output = null;
  }
}

class _Bindings {
  final _library = StationCoreLibrary.library;
  late final create = _library
      .lookupFunction<
        Pointer<Void> Function(Pointer<Uint8>, Size),
        Pointer<Void> Function(Pointer<Uint8>, int)
      >('rq_fssn_stations_create');
  late final count = _library
      .lookupFunction<
        Size Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('rq_fssn_stations_count');
  late final process = _library
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<Uint8>,
          Size,
          Pointer<Double>,
          Size,
        ),
        int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Double>, int)
      >('rq_fssn_stations_process');
  late final destroyPointer = _library
      .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'rq_fssn_stations_destroy',
      );
  late final destroy = destroyPointer
      .asFunction<void Function(Pointer<Void>)>();
  late final sessions = _library
      .lookupFunction<Size Function(), int Function()>(
        'rq_fssn_stations_sessions',
      );
}
