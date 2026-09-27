import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/fan_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final basePayload = <String, dynamic>{
    'id': 'ci12345678',
    'shockTime': '2026-09-27 12:00:00',
    'placeName': 'Southern California',
    'latitude': 34.1,
    'longitude': -118.2,
    'magnitude': 4.5,
    'depth': 10,
  };

  for (final updates in <Object?>[null, 0, -1, 'invalid']) {
    test('FAN SA defaults invalid report number $updates to first report', () {
      final payload = Map<String, dynamic>.from(basePayload);
      if (updates != null) payload['updates'] = updates;

      final event = FanService.decodeEventPayload(payload, sourceHint: 'sa');

      expect(event, isNotNull);
      expect(event!.source, 'sa');
      expect(event.reportNumText, '第1報');
    });
  }

  test('FAN SA preserves a valid upstream report number', () {
    final event = FanService.decodeEventPayload({
      ...basePayload,
      'updates': '3',
    }, sourceHint: 'sa');

    expect(event, isNotNull);
    expect(event!.reportNumText, '第3報');
  });
}
