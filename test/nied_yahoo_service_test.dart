import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/nied_yahoo_service.dart';

void main() {
  test('Yahoo realtime requests bypass intermediary HTTP caches', () {
    expect(NiedYahooService.realtimeRequestHeadersForTest, {
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
    });
  });

  test('Yahoo only publishes frames newer than the last source timestamp', () {
    final previous = DateTime(2026, 8, 4, 12, 0, 1);

    expect(
      NiedYahooService.isNewerFrameForTest(
        DateTime(2026, 8, 4, 12, 0, 2),
        previous,
      ),
      isTrue,
    );
    expect(NiedYahooService.isNewerFrameForTest(previous, previous), isFalse);
    expect(
      NiedYahooService.isNewerFrameForTest(
        DateTime(2026, 8, 4, 12, 0),
        previous,
      ),
      isFalse,
    );
  });
}
