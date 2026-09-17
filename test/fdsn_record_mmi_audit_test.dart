import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_channel_sensitivity.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_motion_service_io.dart';

void main() {
  const input = String.fromEnvironment('FDSN_MMI_AUDIT_INPUT');
  const output = String.fromEnvironment('FDSN_MMI_AUDIT_OUTPUT');
  test(
    'original event records: ObsPy decoding and production MMI',
    () {
      final spec = jsonDecode(File(input).readAsStringSync()) as Map;
      final bytes = File(spec['waveform'] as String).readAsBytesSync();
      final results = <Map<String, Object?>>[];
      for (final r in spec['records'] as List) {
        expect(r['length'], 512);
        final offset = r['offset'] as int;
        final decoded = decodeFdsnRecordForTest(
          Uint8List.sublistView(bytes, offset, offset + 512),
        );
        expect(
          decoded,
          orderedEquals(r['samples'] as List),
          reason: '${r['id']} ${r['start']}',
        );
        final row = (r['metadataRow'] as List).cast<String>();
        final response = FdsnChannelSensitivity.parse(
          row.join('|'),
          network: row[0],
          station: row[1],
          location: row[2],
          channel: row[3],
          time: DateTime.parse(r['start'] as String),
        );
        expect(response, isNotNull);
        final metrics = fdsnMetricsForTest(
          decoded!,
          (r['sampleRate'] as num).toDouble(),
          response!.sensitivity,
          response.unit,
        );
        results.add({
          'id': r['id'],
          'start': r['start'],
          'end': r['end'],
          'offset': offset,
          'sensitivity': response.sensitivity,
          'unit': response.unit,
          ...metrics,
        });
      }
      File(output).writeAsStringSync(
        const JsonEncoder.withIndent(
          '  ',
        ).convert({'waveformSha256': spec['sha256'], 'records': results}),
      );
    },
    skip: input.isEmpty || output.isEmpty,
  );
}
