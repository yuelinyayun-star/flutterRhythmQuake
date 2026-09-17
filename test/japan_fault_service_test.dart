import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/japan_fault_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bytes = File(JapanFaultService.assetPath).readAsBytesSync();

  test(
    'original GSJ KMZ and all line coordinates match independent XML decode',
    () {
      expect(
        sha256.convert(bytes).toString(),
        '3b25267d6e641c81e5d443fffd18a957f1866bc91659cdff1a72369979259eb5',
      );
      final lines = parseJapanFaults(bytes);
      expect(lines, hasLength(3477));
      expect(
        lines.fold<int>(0, (count, line) => count + line.points.length),
        31942,
      );
      expect(lines.first.name, '001-01 羅臼岳活動セグメント');
      expect(
        lines.every((line) => line.colorArgb == 0x99D51605 && line.width == 4),
        isTrue,
      );
      final canonical = StringBuffer();
      for (final line in lines) {
        canonical.writeln(
          line.points
              .map(
                (p) =>
                    '${p.longitude.toStringAsFixed(9)},${p.latitude.toStringAsFixed(9)}',
              )
              .join(';'),
        );
      }
      expect(
        sha256.convert(utf8.encode(canonical.toString())).toString(),
        '773238297692ef1dbac3a9bb369d6c7abd17a07523e6264461ee9a8aff873233',
      );
    },
  );

  test('KMZ load is lazy, shared and retryable', () async {
    var reads = 0;
    final service = JapanFaultService(
      loadAsset: () async {
        reads++;
        return bytes;
      },
    );
    expect(reads, 0);
    final first = service.load();
    expect(identical(first, service.load()), isTrue);
    final lines = await first;
    expect(identical(lines, await service.load()), isTrue);
    expect(reads, 1);

    var attempts = 0;
    final retry = JapanFaultService(
      loadAsset: () async {
        if (attempts++ == 0) throw const FormatException('test load failure');
        return bytes;
      },
    );
    await expectLater(retry.load(), throwsFormatException);
    expect(await retry.load(), hasLength(3477));
    expect(() => parseJapanFaults(Uint8List(0)), throwsA(anything));
  });
}
