import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import '../../models/source_payload.dart';
import '../../models/station_history_frame.dart';
import '../sources/native_station_core_library_io.dart';

/// UI bridge: native archive validation/decoding returns immutable frame views.
class NativeStationReplayBlock {
  static bool get supported => StationCoreLibrary.supported;
  static final _api = _Bindings();
  static T _input<T>(
    Map block,
    T Function(Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, int)
    call,
  ) => using((arena) {
    final data = block['data'] as String, hash = block['sha256'] as String;
    final index = JsonUtf8Encoder().convert(block['frames']);
    final d = data.toNativeUtf8(allocator: arena).cast<Uint8>();
    final h = hash.toNativeUtf8(allocator: arena).cast<Uint8>();
    final i = arena<Uint8>(index.length);
    i.asTypedList(index.length).setAll(0, index);
    return call(d, data.length, h, hash.length, i, index.length);
  });
  static (List<StationHistoryFrame>, int) _views(
    Uint8List bytes,
    int expanded,
    bool error,
  ) {
    if (error) throw FormatException(utf8.decode(bytes));
    final roots = PackedSourceJson(bytes).root as List;
    return (
      [for (final frame in roots) StationHistoryFrame.fromMap(frame as Map)],
      expanded,
    );
  }

  static (List<StationHistoryFrame>, int) decode(Map block) =>
      _input(block, (d, n, h, hn, i, inCount) {
        final owner = _api.sync(d, n, h, hn, i, inCount);
        if (owner == nullptr)
          throw const FormatException('Native station block input rejected');
        try {
          return using((arena) {
            final length = arena<Size>(),
                expanded = arena<Int64>(),
                error = arena<Uint32>();
            final data = _api.result(owner, length, expanded, error);
            return _views(
              Uint8List.fromList(data.asTypedList(length.value)),
              expanded.value,
              error.value != 0,
            );
          });
        } finally {
          _api.free(owner);
        }
      });
  static Future<(List<StationHistoryFrame>, int)> decodeAsync(Map block) async {
    final port = ReceivePort();
    final result = Completer<(List<StationHistoryFrame>, int)>();
    port.listen((dynamic message) {
      try {
        if (message is! List || message[0] != 'station_replay_block_v1')
          throw const FormatException('Invalid native replay response');
        result.complete(
          _views(
            message[1] as Uint8List,
            message[2] as int,
            message[3] as bool,
          ),
        );
      } catch (error, stack) {
        result.completeError(error, stack);
      } finally {
        port.close();
      }
    });
    try {
      final code = _input(
        block,
        (d, n, h, hn, i, inCount) => _api.async(
          d,
          n,
          h,
          hn,
          i,
          inCount,
          port.sendPort.nativePort,
          NativeApi.postCObject.cast(),
        ),
      );
      if (code != 0)
        throw const FormatException('Native station block input rejected');
      return await result.future;
    } finally {
      port.close();
    }
  }
}

class _Bindings {
  final lib = StationCoreLibrary.library;
  late final sync = lib
      .lookupFunction<
        Pointer<Void> Function(
          Pointer<Uint8>,
          Size,
          Pointer<Uint8>,
          Size,
          Pointer<Uint8>,
          Size,
        ),
        Pointer<Void> Function(
          Pointer<Uint8>,
          int,
          Pointer<Uint8>,
          int,
          Pointer<Uint8>,
          int,
        )
      >('rq_replay_block_sync');
  late final async = lib
      .lookupFunction<
        Uint32 Function(
          Pointer<Uint8>,
          Size,
          Pointer<Uint8>,
          Size,
          Pointer<Uint8>,
          Size,
          Int64,
          Pointer<Void>,
        ),
        int Function(
          Pointer<Uint8>,
          int,
          Pointer<Uint8>,
          int,
          Pointer<Uint8>,
          int,
          int,
          Pointer<Void>,
        )
      >('rq_replay_block_async');
  late final result = lib
      .lookupFunction<
        Pointer<Uint8> Function(
          Pointer<Void>,
          Pointer<Size>,
          Pointer<Int64>,
          Pointer<Uint32>,
        ),
        Pointer<Uint8> Function(
          Pointer<Void>,
          Pointer<Size>,
          Pointer<Int64>,
          Pointer<Uint32>,
        )
      >('rq_replay_block_result');
  late final free = lib
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('rq_replay_block_free');
}
