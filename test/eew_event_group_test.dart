import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';

void main() {
  test('EEW history groups preserve unified reports through JSON maps', () {
    final firstArrivedAt = DateTime.utc(2026, 8, 23, 2, 0, 1);
    final event = UnifiedQuakeData(
      source: 'wolfx',
      origin: 0,
      eventId: 'history-test',
      isEew: true,
      timeZone: 9,
      titleText: '緊急地震速報・警報',
      reportNumText: '第25報（最終）',
      useShindo: true,
      maxIntensity: '5弱',
      className: 'orange',
      hypocenter: '茨城県南部',
      originTime: DateTime.utc(2026, 8, 23, 2),
      reportTime: DateTime.utc(2026, 8, 23, 2, 0, 25),
      magnitude: 6.4,
      depth: 80,
      depthText: '深さ: 80km',
      lat: 36.1,
      lng: 140.1,
      isFinal: true,
      apiTypeLabel: 'Wolfx',
      arrivedAt: firstArrivedAt,
    );
    final group = EewEventGroup(
      eventId: event.eventId,
      reports: [event],
      firstArrivedAt: firstArrivedAt,
    );

    final restored = EewEventGroup.fromMap(group.toMap());

    expect(restored.eventId, group.eventId);
    expect(restored.reportCount, 1);
    expect(restored.latestReportNumber, 25);
    expect(restored.latest.reportNumText, '第25報（最終）');
    expect(restored.latest.depthText, '深さ: 80km');
    expect(restored.latest.isFinal, isTrue);
    expect(restored.latest.apiTypeLabel, 'Wolfx');
    expect(restored.firstArrivedAt, firstArrivedAt);

    final dedupedGroup = EewEventGroup(
      eventId: event.eventId,
      reports: [
        event,
        event.copyWith(reportNumText: '第24报'),
      ],
      firstArrivedAt: firstArrivedAt,
    );
    expect(dedupedGroup.reportCount, 2);
    expect(dedupedGroup.latestReportNumber, 25);
  });
}
