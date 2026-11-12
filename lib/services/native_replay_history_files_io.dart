import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'replay_history_files.dart';
import 'sources/native_station_core_library_io.dart';

/// Serialization boundary for the Rust file owner. Live reception uses its
/// byte-bounded writer; no asynchronous Dart closure retains incoming models.
class NativeReplayHistoryFiles extends ReplayHistoryFiles
    implements Finalizable {
  NativeReplayHistoryFiles(super.root) {
    if (!supported) {
      throw UnsupportedError(
        'Native replay files require a supported file backend',
      );
    }
    using((arena) {
      final bytes = utf8.encode(root);
      final input = arena<Uint8>(bytes.length);
      input.asTypedList(bytes.length).setAll(0, bytes);
      _owner = _api.open(input, bytes.length);
    });
    if (_owner == nullptr) {
      throw StateError('Native replay store requires an absolute UTF-8 root');
    }
    _finalizer.attach(this, _owner, detach: this);
  }

  // Replay IO has no Windows dependency. Android uses the packaged Rust
  // backend; Linux is separately enabled for this file-only implementation.
  static bool get supported =>
      StationCoreLibrary.supported ||
      (Platform.isLinux &&
          (Platform.environment['FLUTTER_TEST'] != 'true' ||
              Platform.environment.containsKey('RQ_STATION_CORE_LIBRARY')));
  static final _api = _Bindings();
  static final _finalizer = NativeFinalizer(_api.closePointer);
  static int get sessions => _api.sessions();
  static int get results => _api.results();
  static int get calls => _api.calls();
  Pointer<Void> _owner = nullptr;

  @override
  void dispose() {
    if (_owner == nullptr) {
      return;
    }
    _finalizer.detach(this);
    _api.close(_owner);
    _owner = nullptr;
  }

  @override
  void acceptFrame(String key, Map frame) =>
      _call(8, key, bytes: JsonUtf8Encoder().convert(frame));

  @override
  String acceptReport(String key, Map report) =>
      utf8.decode(_call(9, key, bytes: JsonUtf8Encoder().convert(report))!);

  @override
  String acceptCollectorJson(String directory, String prefix, Map value) =>
      utf8.decode(
        _call(
          12,
          directory,
          digest: prefix,
          bytes: JsonUtf8Encoder().convert(value),
        )!,
      );

  @override
  String acceptCollectorFrame(String prefix, Map frame) => utf8.decode(
    _call(
      13,
      'frames',
      digest: prefix,
      bytes: JsonUtf8Encoder().convert(frame),
    )!,
  );

  @override
  Map<String, dynamic> get pendingStatus =>
      Map<String, dynamic>.from(jsonDecode(utf8.decode(_call(10, '')!)) as Map);

  @override
  Future<void> flushPending() async {
    // Poll metadata only; never block the Flutter isolate waiting for disk.
    while ((pendingStatus['pending'] as int) != 0) {
      await Future<void>.delayed(const Duration(milliseconds: 4));
    }
  }

  @override
  void retryPending() => _call(11, '');

  Uint8List? _call(
    int op,
    String key, {
    String digest = '',
    List<int> bytes = const [],
  }) {
    if (_owner == nullptr) {
      throw StateError('Native replay store is closed');
    }
    if (bytes.length > 128 * 1024 * 1024) {
      throw const FormatException('Replay file exceeds size limit');
    }
    return using((arena) {
      Pointer<Uint8> copy(List<int> bytes) {
        final pointer = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
        pointer.asTypedList(bytes.length).setAll(0, bytes);
        return pointer;
      }

      final keyBytes = utf8.encode(key), digestBytes = utf8.encode(digest);
      final result = _api.apply(
        _owner,
        op,
        copy(keyBytes),
        keyBytes.length,
        copy(digestBytes),
        digestBytes.length,
        copy(bytes),
        bytes.length,
      );
      if (result == nullptr) {
        throw StateError('Native replay file request failed');
      }
      try {
        final length = arena<Size>(), code = arena<Int32>();
        final data = _api.result(result, length, code);
        if (length.value > 128 * 1024 * 1024 ||
            (data == nullptr && length.value != 0)) {
          throw StateError('Invalid native replay file response');
        }
        if (code.value == 1) {
          return null;
        }
        if (code.value != 0) {
          final message = utf8.decode(data.asTypedList(length.value));
          if (code.value == 2) {
            throw FormatException(message);
          }
          throw StateError(message);
        }
        return Uint8List.fromList(data.asTypedList(length.value));
      } finally {
        _api.resultFree(result);
      }
    });
  }

  @override
  Future<Map<String, dynamic>?> record(String key) async {
    final bytes = _call(0, key);
    return bytes == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
  }

  @override
  Future<bool> writeRecord(String key, Object? value, Map? snapshot) async {
    _call(
      1,
      key,
      bytes: JsonUtf8Encoder().convert({
        'key': key,
        'value': value,
        'snapshot': ?snapshot,
      }),
    );
    return true;
  }

  @override
  Future<String> writeReport(String key, Map report) async =>
      utf8.decode(_call(2, key, bytes: JsonUtf8Encoder().convert(report))!);

  @override
  Future<Map<String, dynamic>> readReport(String key, String digest) async =>
      Map<String, dynamic>.from(
        jsonDecode(utf8.decode(_call(3, key, digest: digest)!)) as Map,
      );

  @override
  Future<bool> writeFrame(String key, Map frame) async {
    _call(4, key, bytes: JsonUtf8Encoder().convert(frame));
    return true;
  }

  @override
  Future<Map<String, dynamic>> readFrame(String key) async =>
      Map<String, dynamic>.from(jsonDecode(utf8.decode(_call(5, key)!)) as Map);

  @override
  Future<bool> remove(String key, {bool frame = false}) async {
    _call(frame ? 7 : 6, key);
    return true;
  }
}

typedef _Close = Void Function(Pointer<Void>);

class _Bindings {
  final lib = Platform.isLinux
      ? DynamicLibrary.open(
          Platform.environment['RQ_STATION_CORE_LIBRARY'] ??
              '${File(Platform.resolvedExecutable).parent.path}/lib/librq_station_core.so',
        )
      : StationCoreLibrary.library;
  late final open = lib
      .lookupFunction<
        Pointer<Void> Function(Pointer<Uint8>, Size),
        Pointer<Void> Function(Pointer<Uint8>, int)
      >('rq_replay_files_open');
  late final apply = lib
      .lookupFunction<
        Pointer<Void> Function(
          Pointer<Void>,
          Uint32,
          Pointer<Uint8>,
          Size,
          Pointer<Uint8>,
          Size,
          Pointer<Uint8>,
          Size,
        ),
        Pointer<Void> Function(
          Pointer<Void>,
          int,
          Pointer<Uint8>,
          int,
          Pointer<Uint8>,
          int,
          Pointer<Uint8>,
          int,
        )
      >('rq_replay_files_apply');
  late final result = lib
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Void>, Pointer<Size>, Pointer<Int32>),
        Pointer<Uint8> Function(Pointer<Void>, Pointer<Size>, Pointer<Int32>)
      >('rq_replay_files_result');
  late final resultFree = lib
      .lookupFunction<_Close, void Function(Pointer<Void>)>(
        'rq_replay_files_result_free',
      );
  late final closePointer = lib.lookup<NativeFunction<_Close>>(
    'rq_replay_files_close',
  );
  late final close = closePointer.asFunction<void Function(Pointer<Void>)>();
  late final sessions = lib.lookupFunction<Size Function(), int Function()>(
    'rq_replay_files_sessions',
  );
  late final results = lib.lookupFunction<Size Function(), int Function()>(
    'rq_replay_files_results',
  );
  late final calls = lib.lookupFunction<Size Function(), int Function()>(
    'rq_replay_files_calls',
  );
}
