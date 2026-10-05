import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/station_history_frame.dart';
import 'package:flutterrhythmquake/services/debug/station_archive_storage.dart';
import 'package:flutterrhythmquake/services/debug/station_json_archive.dart';

void main() {
  test(
    'compressed and legacy tables keep original captured JSON byte-exact',
    () {
      final original =
          jsonDecode(
                File(
                  'test/fixtures/whews_nied/observations.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final frame = StationHistoryFrame(
        receivedAt: DateTime.parse('2026-09-08T10:47:23.899674Z'),
        snapshot: {'kind': 'nied', 'stations': []},
        originalJson: original,
      );
      final archive = StationJsonArchive.encode([frame]);
      final text = jsonEncode(archive);
      final compressed = StationArchiveStorage.encode(archive);
      expect(compressed.length, lessThan(text.length));
      for (final stored in [text, compressed]) {
        final restored = StationJsonArchive.decode(
          StationArchiveStorage.decode(stored),
        );
        expect(jsonEncode(restored.single.toMap()), jsonEncode(frame.toMap()));
      }
    },
  );

  test('numeric types and signed zero are not coalesced', () {
    final table = StationJsonTable();
    expect(table.intern(1), isNot(table.intern(1.0)));
    expect(table.intern(0.0), isNot(table.intern(-0.0)));
    expect(table.intern(true), isNot(table.intern(1)));
    expect(table.intern('1'), isNot(table.intern(1)));
  });

  test(
    'compact table merge preserves frames without expanding source maps',
    () {
      final raw =
          jsonDecode(
                File(
                  'test/fixtures/whews_nied/observations.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final frames = [
        for (final second in [23, 24])
          StationHistoryFrame(
            receivedAt: DateTime.utc(2026, 9, 8, 10, 47, second),
            snapshot: {'kind': 'nied', 'stations': []},
            originalJson: raw,
          ),
      ];
      final table = StationJsonTable();
      final roots = [
        for (final frame in frames)
          ...table.append(StationJsonArchive.encode([frame])),
      ];
      expect(
        StationJsonArchive.decode(
          table.archive(roots),
        ).map((f) => jsonEncode(f.toMap())),
        frames.map((f) => jsonEncode(f.toMap())),
      );
      expect(table.receipt(roots.last), frames.last.receivedAt);
      expect(
        () => table.append({
          'format': StationJsonArchive.format,
          'nodes': [
            ['l', 0],
          ],
          'frames': [0],
        }),
        throwsFormatException,
      );
    },
  );
}
