import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/native_seedlink_codec_io.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_motion_service_io.dart';

import 'support/seedlink_codec_before_20261015.dart';

(Uint8List, int, Endian, int) payload(Uint8List record) {
  final data = ByteData.sublistView(record);
  final year = data.getUint16(20, Endian.big);
  final header = year >= 1900 && year <= 2200 ? Endian.big : Endian.little;
  var block = data.getUint16(46, header);
  while (data.getUint16(block, header) != 1000) {
    block = data.getUint16(block + 2, header);
  }
  return (
    Uint8List.sublistView(record, data.getUint16(44, header)),
    record[block + 4],
    record[block + 5] != 0 ? Endian.big : Endian.little,
    data.getUint16(30, header),
  );
}

void main() {
  final enabled = NativeSeedLinkCodec.supported;
  final spec = File(
    'tmp/fdsn_connection_review/costa_rica_QUEP_mmi_input.json',
  );
  test(
    '206 unchanged original MiniSEED records match ObsPy and frozen Dart',
    () {
      addTearDown(NativeSeedLinkCodec.releaseScratch);
      final metadata = jsonDecode(spec.readAsStringSync()) as Map;
      final original = File(metadata['waveform'] as String).readAsBytesSync();
      final hash = sha256.convert(original).toString();
      expect(hash, metadata['sha256']);
      var count = 0, samples = 0;
      for (final row in (metadata['records'] as List).cast<Map>()) {
        final offset = row['offset'] as int;
        final record = Uint8List.sublistView(original, offset, offset + 512);
        final (data, encoding, endian, sampleCount) = payload(record);
        final native = NativeSeedLinkCodec.decode(
          data,
          encoding: encoding,
          endian: endian,
          sampleCount: sampleCount,
        );
        final saved = Int32List.fromList(native);
        expect(native, row['samples']);
        expect(
          native,
          DartMiniSeedDecoderReference.decode(
            data,
            encoding: encoding,
            endian: endian,
            sampleCount: sampleCount,
          ),
        );
        expect(decodeFdsnRecordForTest(record), row['samples']);
        // A later decode or buffer release cannot change a retained old record.
        NativeSeedLinkCodec.releaseScratch();
        expect(native, saved);
        count++;
        samples += native.length;
      }
      expect(sha256.convert(original).toString(), hash);
      expect(count, 206);
      expect(NativeSeedLinkCodec.diagnostics['scratchBytes'], 0);
      stdout.writeln(
        jsonEncode({
          'waveformSha256': hash,
          'records': count,
          'samples': samples,
        }),
      );
    },
    skip: !enabled || !spec.existsSync(),
  );

  test(
    'controlled codec fixtures preserve partial payloads for both byte orders',
    () {
      addTearDown(NativeSeedLinkCodec.releaseScratch);
      final rows =
          jsonDecode(
                File(
                  'test/fixtures/fdsn_codec/expected.json',
                ).readAsStringSync(),
              )
              as List;
      for (final row in rows.cast<Map>()) {
        final bytes = File(
          'test/fixtures/fdsn_codec/${row['file']}',
        ).readAsBytesSync();
        final offset = row['offset'] as int;
        final record = Uint8List.sublistView(bytes, offset, offset + 512);
        final (data, encoding, endian, count) = payload(record);
        for (var length = 0; length <= data.length; length++) {
          final prefix = Uint8List.sublistView(data, 0, length);
          final expected = DartMiniSeedDecoderReference.decode(
            prefix,
            encoding: encoding,
            endian: endian,
            sampleCount: count,
          );
          expect(
            NativeSeedLinkCodec.decode(
              prefix,
              encoding: encoding,
              endian: endian,
              sampleCount: count,
            ),
            expected,
            reason: '${row['file']}@$offset prefix $length',
          );
        }
      }
      expect(
        NativeSeedLinkCodec.decode(
          Uint8List(64),
          encoding: 999,
          endian: Endian.big,
          sampleCount: 100,
        ),
        isEmpty,
      );
    },
    skip: !enabled,
  );
}
