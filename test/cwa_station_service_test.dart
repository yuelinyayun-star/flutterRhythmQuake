import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/cwa_station_service.dart';

void main() {
  group('TREM RTS stream parsing', () {
    test('decodes complete SSE data lines without changing payload values', () {
      final payload = CwaStationService.decodeSseDataLine(
        'data: {"station":{"123":{"pga":1.25,"pgv":0.4,"i":-2.9,"I":1.2,"alert":1}},"time":1787111000123}',
      );

      expect(payload, isNotNull);
      expect(payload!['time'], 1787111000123);
      final station = payload['station'] as Map<String, dynamic>;
      final values = station['123'] as Map<String, dynamic>;
      expect(values['pga'], 1.25);
      expect(values['i'], -2.9);
      expect(values['I'], 1.2);
      expect(values['alert'], 1);
    });

    test('ignores SSE metadata and malformed data lines', () {
      expect(CwaStationService.decodeSseDataLine('event: info'), isNull);
      expect(
        CwaStationService.decodeSseDataLine('data: {"location":"lb-tpe1"}'),
        {'location': 'lb-tpe1'},
      );
      expect(CwaStationService.decodeSseDataLine('data: {broken'), isNull);
      expect(CwaStationService.decodeSseDataLine('data:'), isNull);
    });
  });

  group('TREM RTS frame acceptance helpers', () {
    test('only truthy alert values activate alert intensity', () {
      for (final value in <Object>[true, 1, -1, '1', 'true']) {
        expect(CwaStationService.isActiveAlertValue(value), isTrue);
      }
      for (final value in <Object?>[null, false, 0, '0', 'false', 'null', '']) {
        expect(CwaStationService.isActiveAlertValue(value), isFalse);
      }
    });

    test('requires frame time to advance strictly', () {
      final previous = DateTime.fromMillisecondsSinceEpoch(1787111000000);
      expect(CwaStationService.isNewerFrameTime(null, previous), isTrue);
      expect(CwaStationService.isNewerFrameTime(previous, previous), isFalse);
      expect(
        CwaStationService.isNewerFrameTime(
          previous,
          previous.subtract(const Duration(milliseconds: 1)),
        ),
        isFalse,
      );
      expect(
        CwaStationService.isNewerFrameTime(
          previous,
          previous.add(const Duration(milliseconds: 1)),
        ),
        isTrue,
      );
    });
  });
}
