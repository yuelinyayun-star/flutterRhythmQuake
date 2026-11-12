import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/lpgm_monitor_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_background_worker.dart';

void main() {
  test(
    'original LPGM images produce the same values in the persistent worker',
    () async {
      final reference = LpgmFrameProcessor(useNative: false);
      final worker = NiedBackgroundWorker.instance;
      try {
        final originals =
            Directory('test/fixtures/lpgm_worker_20261017')
                .listSync()
                .whereType<File>()
                .where((file) => file.path.endsWith('.gif'))
                .toList()
              ..sort((a, b) => a.path.compareTo(b.path));
        for (final file in originals) {
          final bytes = file.readAsBytesSync();
          final stamp = RegExp(
            r'lpgm_(\d{14})',
          ).firstMatch(file.path)!.group(1)!;
          final time = DateTime.parse(
            '${stamp.substring(0, 8)}T${stamp.substring(8)}',
          );
          final expected = reference.process(bytes, time);
          final actual = await worker.processLpgmFrame(
            imageBytes: bytes,
            dataTime: time,
          );
          expect(actual, isNotNull);
          expect(expected, isNotNull);
          expect(actual!.dataTime, expected!.dataTime);
          expect(actual.maxRawRgb, expected.maxRawRgb);
          expect(actual.maxSva, expected.maxSva);
          expect(actual.maxClass, expected.maxClass);
          expect(
            actual.topStations.map((s) => s.code),
            expected.topStations.map((s) => s.code),
          );
          expect(
            actual.topStations.map((s) => s.sva),
            expected.topStations.map((s) => s.sva),
          );
        }
        await worker.resetLpgm();
        final bytes = originals.first.readAsBytesSync();
        expect(
          await worker.processLpgmFrame(
            imageBytes: bytes,
            dataTime: DateTime(2026, 6, 1, 19, 50, 49),
          ),
          isNotNull,
        );
        final resetting = worker.resetLpgm();
        worker.stop();
        await resetting;
      } finally {
        reference.dispose();
        await worker.resetLpgm();
        worker.stop();
      }
    },
  );
}
