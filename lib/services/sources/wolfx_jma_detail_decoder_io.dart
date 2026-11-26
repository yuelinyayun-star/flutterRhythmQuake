import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'native_station_core_library_io.dart';
import 'wolfx_jma_detail_decoder_portable.dart' as portable;

final _decode = StationCoreLibrary.library
    .lookupFunction<
      Pointer<Uint8> Function(Pointer<Uint8>, Size, Pointer<Size>),
      Pointer<Uint8> Function(Pointer<Uint8>, int, Pointer<Size>)
    >('rq_wolfx_jma_detail');
final _free = StationCoreLibrary.library
    .lookupFunction<
      Void Function(Pointer<Uint8>, Size),
      void Function(Pointer<Uint8>, int)
    >('rq_wolfx_jma_detail_free');

Map<String, dynamic> decodeWolfxJmaDetail(Uint8List bytes) {
  if (!StationCoreLibrary.supported) {
    return portable.decodeWolfxJmaDetail(bytes);
  }
  return using((arena) {
    final input = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    final length = arena<Size>();
    input.asTypedList(bytes.length).setAll(0, bytes);
    final output = _decode(input, bytes.length, length);
    if (output == nullptr) throw const FormatException('Wolfx JMA detail');
    try {
      return jsonDecode(utf8.decode(output.asTypedList(length.value)))
          as Map<String, dynamic>;
    } finally {
      _free(output, length.value);
    }
  });
}
