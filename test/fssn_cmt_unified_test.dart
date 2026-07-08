import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';

void main() {
  test('FSSN CMT unified event keeps nodal planes', () {
    final event = QuakeEventAdapter.convert('fssnCmt', {
      'eventId': 'FSSN2026mmky',
      'location': 'Afghanistan Hindu Kush region',
      'magnitude': 6.2,
      'depth': 194.1,
      'latitude': 36.5086,
      'longitude': 70.7912,
      'originTime': '2026-06-27 21:34:52',
      'shockTime': '2026-06-27 21:34:52',
      'nodalPlane1': '112/66/102',
      'nodalPlane2': '264/26/65',
    }, 1);

    expect(event, isNotNull);
    expect(event!.source, 'fssnCmt');
    expect(event.eventId, 'FSSN2026mmky');
    expect(event.nodalPlane1, '112/66/102');
    expect(event.nodalPlane2, '264/26/65');
  });
}
