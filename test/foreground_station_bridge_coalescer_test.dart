import 'package:flutter_test/flutter_test.dart';

import 'package:flutterrhythmquake/services/foreground_station_bridge_coalescer.dart';

void main() {
  test(
    'keeps only the latest display snapshot per source and preserves originalJson',
    () async {
      final emitted = <Map<String, dynamic>>[];
      final coalescer = ForegroundStationBridgeCoalescer(
        emit: emitted.add,
        window: const Duration(milliseconds: 5),
      );
      coalescer.submit({'kind': 'fanRadar', 'source': 'fan', 'value': 1});
      coalescer.submit({'kind': 'fanRadar', 'source': 'fan', 'value': 2});
      coalescer.submit({'kind': 'jmaRadar', 'source': 'jma', 'value': 3});
      coalescer.submit({
        'kind': 'cwa',
        'source': 'trem',
        'value': 1,
        'originalJson': {'frame': 1},
      });
      coalescer.submit({'kind': 'cwa', 'source': 'trem', 'value': 2});
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(emitted, [
        {'kind': 'fanRadar', 'source': 'fan', 'value': 2},
        {'kind': 'jmaRadar', 'source': 'jma', 'value': 3},
        {
          'kind': 'cwa',
          'source': 'trem',
          'value': 2,
          'originalJson': {'frame': 1},
        },
      ]);
      coalescer.dispose();
    },
  );

  test(
    'emits detector signals immediately and holds snapshots while paused',
    () {
      final emitted = <Map<String, dynamic>>[];
      final coalescer = ForegroundStationBridgeCoalescer(
        emit: emitted.add,
        paused: true,
      );
      final signal = {'kind': 'signal', 'source': 'kma', 'action': 'detected'};
      coalescer.submit({'kind': 'nied', 'source': 'lmoni', 'value': 1});
      coalescer.submit({'kind': 'nied', 'source': 'lmoni', 'value': 2});
      coalescer.submit({'kind': 'palert', 'value': 10});
      coalescer.submit(signal);
      expect(emitted, [signal]);

      coalescer.setPaused(false);
      expect(emitted, [
        signal,
        {'kind': 'nied', 'source': 'lmoni', 'value': 2},
        {'kind': 'palert', 'value': 10},
      ]);
      coalescer.dispose();
    },
  );

  test('recording flushes pending data and bypasses pause and coalescing', () {
    final emitted = <Map<String, dynamic>>[];
    final coalescer = ForegroundStationBridgeCoalescer(
      emit: emitted.add,
      paused: true,
    );
    coalescer.submit({'kind': 'nied', 'source': 'lmoni', 'value': 0});
    expect(emitted, isEmpty);

    coalescer.setRecording(true);
    expect(emitted, [
      {'kind': 'nied', 'source': 'lmoni', 'value': 0},
    ]);
    coalescer.submit({'kind': 'nied', 'source': 'lmoni', 'value': 1});
    coalescer.submit({'kind': 'nied', 'source': 'lmoni', 'value': 2});
    expect(emitted.map((frame) => frame['value']), [0, 1, 2]);

    coalescer.setRecording(false);
    coalescer.submit({'kind': 'nied', 'source': 'lmoni', 'value': 3});
    expect(emitted.map((frame) => frame['value']), [0, 1, 2]);
    coalescer.setPaused(false);
    expect(emitted.map((frame) => frame['value']), [0, 1, 2, 3]);
    coalescer.dispose();
  });

  test(
    'an EEW received before the first station frame starts unpaused recording',
    () {
      final emitted = <Map<String, dynamic>>[];
      final coalescer = ForegroundStationBridgeCoalescer(
        emit: emitted.add,
        paused: true,
        recording: true,
      );
      coalescer.submit({'kind': 'cwa', 'source': 'trem', 'value': 1});
      coalescer.submit({'kind': 'cwa', 'source': 'trem', 'value': 2});
      expect(emitted.map((frame) => frame['value']), [1, 2]);
      coalescer.dispose();
    },
  );
}
