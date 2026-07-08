import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/replay/jma_hypocenter_record.dart';

void main() {
  test('parses the official 96-byte JMA hypocenter layout', () {
    final fields = List<String>.filled(96, ' ');
    void put(int start, String value) {
      for (var index = 0; index < value.length; index++) {
        fields[start - 1 + index] = value[index];
      }
    }

    put(1, 'J');
    put(2, '2026');
    put(6, '06');
    put(8, '20');
    put(10, '21');
    put(12, '25');
    put(14, '2734');
    put(22, '039');
    put(25, '5358');
    put(33, '0142');
    put(37, '3072');
    put(45, '038  ');
    put(53, '34');
    put(55, 'V');
    put(59, '7');
    put(60, '1');
    put(61, '1');
    put(62, '1');
    put(69, 'IWATE OFFSHORE');
    put(93, '064');
    put(96, 'K');

    final event = const JmaHypocenterRecordParser().parse(fields.join());

    expect(event, isNotNull);
    expect(event!.originTime, DateTime.utc(2026, 6, 20, 12, 25, 27, 340));
    expect(event.latitude, closeTo(39.893, 0.00001));
    expect(event.longitude, closeTo(142.512, 0.00001));
    expect(event.depthKm, 38);
    expect(event.magnitude, 3.4);
    expect(event.region, 'IWATE OFFSHORE');
    expect(event.status, 'final');
    expect(event.metadata['stationCount'], 64);
  });

  test('rejects non-JMA and indeterminate records', () {
    expect(const JmaHypocenterRecordParser().parse('U'.padRight(96)), isNull);
    expect(
      const JmaHypocenterRecordParser().parse('${'J'.padRight(95)}N'),
      isNull,
    );
  });
}
