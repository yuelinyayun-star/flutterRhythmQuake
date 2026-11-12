import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'sources/native_station_core_library_io.dart';

/// Platform paths only. Rust keeps source, replay and event business state.
Future<void> initializeNativeCore() async {
  if (!Platform.isAndroid) return;
  final support = await getApplicationSupportDirectory();
  final cache = await getTemporaryDirectory();
  final initialize = StationCoreLibrary.library
      .lookupFunction<
        Uint32 Function(Pointer<Uint8>, Pointer<Uint8>),
        int Function(Pointer<Uint8>, Pointer<Uint8>)
      >('rq_android_initialize');
  using((arena) {
    final status = initialize(
      support.path.toNativeUtf8(allocator: arena).cast(),
      cache.path.toNativeUtf8(allocator: arena).cast(),
    );
    if (status != 0) {
      throw StateError('Android Rust initialization failed ($status)');
    }
  });
}
