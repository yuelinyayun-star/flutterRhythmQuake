import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/tsunami_message.dart';

void main() {
  test(
    'P2P immediate maps only missing arrival status and preserves raw data',
    () {
      // Protocol edge fixtures, not live bulletins.
      for (final immediate in [true, false, null]) {
        for (final condition in [null, '', ' ', '津波到達中と推測', '第１波の到達を確認']) {
          final raw = <String, dynamic>{
            'issue': {'time': '2026/10/19 12:00:00'},
            'areas': [
              <String, dynamic>{
                'name': 'protocol region',
                'grade': 'Warning',
              'immediate': ?immediate,
                'firstHeight': {
                'condition': ?condition,
                  'arrivalTime': '2026/10/19 12:10:00',
                },
                'maxHeight': {'value': 3, 'description': '３ｍ'},
              },
            ],
          };
          final original = jsonEncode(raw);
          final message = TsunamiMessage.parseJmaTsunami(raw);
          final area = message.areas.single;
          expect(
            area.condition,
            immediate == true && (condition == null || condition.trim().isEmpty)
                ? 'ただちに津波来襲と予測'
                : condition,
          );
          expect(area.arrivalTime, '2026/10/19 12:10:00');
          expect(area.grade, TsunamiGrade.warning);
          expect(area.height, 3);
          expect(jsonEncode(raw), original);
          expect(jsonEncode(message.sourcePayload), original);
        }
      }
    },
  );

  test('P2P immediate without firstHeight does not become unknown', () {
    final message = TsunamiMessage.parseJmaTsunami({
      'issue': {'time': '2026/10/19 12:00:00'},
      'areas': [
        {'name': 'protocol region', 'grade': 'Watch', 'immediate': true},
      ],
    });
    expect(message.areas.single.condition, 'ただちに津波来襲と予測');
    expect(message.areas.single.arrivalTime, isNull);
  });
}
