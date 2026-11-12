import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutterrhythmquake/services/sources/native_seedlink_codec_io.dart';
import '../test/support/seedlink_codec_before_20261015.dart';

void main(List<String> args) {
  final mode = args[0];
  final repeats = int.parse(args.length > 1 ? args[1] : '300');
  final spec =
      jsonDecode(
            File(
              'tmp/fdsn_connection_review/costa_rica_QUEP_mmi_input.json',
            ).readAsStringSync(),
          )
          as Map;
  final original = File(spec['waveform'] as String).readAsBytesSync();
  final records = <(Uint8List, int, Endian, int)>[];
  for (final row in (spec['records'] as List).cast<Map>()) {
    final start = row['offset'] as int;
    final record = Uint8List.sublistView(original, start, start + 512);
    final data = ByteData.sublistView(record);
    final year = data.getUint16(20, Endian.big);
    final headerEndian = year >= 1900 && year <= 2200
        ? Endian.big
        : Endian.little;
    var block = data.getUint16(46, headerEndian);
    while (data.getUint16(block, headerEndian) != 1000) {
      block = data.getUint16(block + 2, headerEndian);
    }
    records.add((
      Uint8List.sublistView(record, data.getUint16(44, headerEndian)),
      record[block + 4],
      record[block + 5] != 0 ? Endian.big : Endian.little,
      data.getUint16(30, headerEndian),
    ));
  }
  final decode = mode == 'rust'
      ? NativeSeedLinkCodec.decode
      : DartMiniSeedDecoderReference.decode;
  // Warm both implementations with exactly the same unchanged records.
  for (final (payload, encoding, endian, count) in records) {
    decode(payload, encoding: encoding, endian: endian, sampleCount: count);
  }
  final rssBefore = ProcessInfo.currentRss;
  final watch = Stopwatch()..start();
  var samples = 0, checksum = 0;
  for (var repeat = 0; repeat < repeats; repeat++) {
    for (final (payload, encoding, endian, count) in records) {
      final values = decode(
        payload,
        encoding: encoding,
        endian: endian,
        sampleCount: count,
      );
      samples += values.length;
      if (values.isNotEmpty) checksum += values.first + values.last;
    }
  }
  watch.stop();
  stdout.writeln(
    jsonEncode({
      'mode': mode,
      'original_sha256': spec['sha256'],
      'records': records.length * repeats,
      'samples': samples,
      'checksum': checksum,
      'processing_ms': watch.elapsedMicroseconds / 1000,
      'rss_mb': ProcessInfo.currentRss / 1048576,
      'rss_delta_mb': (ProcessInfo.currentRss - rssBefore) / 1048576,
    }),
  );
  if (mode == 'rust') NativeSeedLinkCodec.releaseScratch();
}
