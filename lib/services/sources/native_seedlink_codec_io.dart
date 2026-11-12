import 'dart:ffi';
import 'dart:typed_data';
import 'native_station_core_library_io.dart';

typedef _DecodeNative =
    Int32 Function(
      Pointer<Uint8>,
      Size,
      Uint32,
      Uint8,
      Size,
      Pointer<Int32>,
      Size,
      Pointer<Size>,
    );
typedef _DecodeDart =
    int Function(
      Pointer<Uint8>,
      int,
      int,
      int,
      int,
      Pointer<Int32>,
      int,
      Pointer<Size>,
    );

/// One reusable synchronous copy buffer per isolate, never one per station.
class NativeSeedLinkCodec {
  static bool get supported => StationCoreLibrary.supported;
  static final _bindings = _Bindings();
  static StationCoreBuffer? _input, _output, _written;
  static Uint8List? _bytes;
  static Int32List? _values;

  static Map<String, int> get diagnostics => {
    'calls': _bindings.calls(),
    'scratchBytes':
        (_input?.length ?? 0) +
        (_output?.length ?? 0) +
        (_written?.length ?? 0),
  };

  static Int32List decode(
    Uint8List payload, {
    required int encoding,
    required Endian endian,
    required int sampleCount,
  }) {
    if (payload.isEmpty || sampleCount <= 0) return Int32List(0);
    final capacity = switch (encoding) {
      1 => payload.length ~/ 2,
      3 => payload.length ~/ 4,
      10 || 11 => payload.length * 2,
      _ => 0,
    }.clamp(0, sampleCount);
    if (capacity == 0) return Int32List(0);
    if ((_input?.length ?? 0) < payload.length) {
      _input?.dispose();
      _input = StationCoreBuffer(payload.length);
      _bytes = _input!.pointer.asTypedList(payload.length);
    }
    if ((_output?.length ?? 0) < capacity * 4) {
      _output?.dispose();
      _output = StationCoreBuffer(capacity * 4);
      _values = _output!.pointer.cast<Int32>().asTypedList(capacity);
    }
    _written ??= StationCoreBuffer(sizeOf<Size>());
    _bytes!.setRange(0, payload.length, payload);
    final status = _bindings.decode(
      _input!.pointer,
      payload.length,
      encoding,
      endian == Endian.big ? 1 : 0,
      sampleCount,
      _output!.pointer.cast(),
      capacity,
      _written!.pointer.cast(),
    );
    if (status != 0) throw StateError('SeedLink codec failed ($status)');
    final count = _written!.pointer.cast<Size>().value;
    // Returned samples own their storage; scratch reuse cannot alter an old record.
    return Int32List.fromList(Int32List.sublistView(_values!, 0, count));
  }

  static void releaseScratch() {
    _input?.dispose();
    _input = null;
    _bytes = null;
    _output?.dispose();
    _output = null;
    _values = null;
    _written?.dispose();
    _written = null;
  }
}

class _Bindings {
  _Bindings() {
    final library = StationCoreLibrary.library;
    final version = library.lookupFunction<Uint32 Function(), int Function()>(
      'rq_seedlink_codec_abi_version',
    )();
    if (version != 1) {
      throw StateError('Unsupported SeedLink codec ABI $version');
    }
    decode = library.lookupFunction<_DecodeNative, _DecodeDart>(
      'rq_seedlink_decode',
    );
    calls = library.lookupFunction<Uint64 Function(), int Function()>(
      'rq_seedlink_codec_calls',
    );
  }
  late final _DecodeDart decode;
  late final int Function() calls;
}
