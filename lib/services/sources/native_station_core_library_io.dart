import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// Shared library and caller-owned buffers for station-core FFI bindings.
class StationCoreLibrary {
  static bool get supported =>
      (Platform.isWindows || Platform.isAndroid) &&
      (Platform.environment['FLUTTER_TEST'] != 'true' ||
          Platform.environment.containsKey('RQ_STATION_CORE_LIBRARY'));

  static final DynamicLibrary library = _open();

  static DynamicLibrary _open() {
    final override = Platform.environment['RQ_STATION_CORE_LIBRARY'];
    if (override != null && !File(override).isAbsolute) {
      throw StateError('RQ_STATION_CORE_LIBRARY must be absolute');
    }
    final String path;
    if (override != null) {
      path = override;
    } else if (Platform.isAndroid) {
      path = 'librq_station_core.so';
    } else if (Platform.isWindows) {
      path =
          '${File(Platform.resolvedExecutable).parent.path}/rq_station_core.dll';
    } else {
      throw UnsupportedError(
        'Station core is not enabled on ${Platform.operatingSystem}',
      );
    }
    final library = DynamicLibrary.open(path);
    final version = library.lookupFunction<Uint32 Function(), int Function()>(
      'rq_station_core_abi_version',
    )();
    if (version != 1) {
      throw StateError('Unsupported station core ABI: $version');
    }
    return library;
  }
}

final class StationCoreBuffer implements Finalizable {
  StationCoreBuffer(int requested)
    : length = requested == 0 ? 1 : requested,
      pointer = malloc.allocate<Uint8>(requested == 0 ? 1 : requested) {
    _finalizer.attach(this, pointer.cast(), detach: this, externalSize: length);
  }
  static final _finalizer = NativeFinalizer(malloc.nativeFree);
  final int length;
  final Pointer<Uint8> pointer;
  bool _disposed = false;
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    malloc.free(pointer);
  }
}
