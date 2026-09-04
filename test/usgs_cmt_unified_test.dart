import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/quake_time.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';

void main() {
  group('USGS CMT adapter', () {
    test('reviewed：字段映射 + reportNumText', () {
      final event = QuakeEventAdapter.convert('usgsCmt', {
        'eventId': 'us7000t37a',
        'location': '瓦努阿图群岛',
        'magnitude': 6.0,
        'depth': 44.637,
        'centroidDepth': 15.5,
        'latitude': -14.0205,
        'longitude': 166.8006,
        'originTime': '2026-07-25 05:37:55',
        'nodalPlane1': '130.24/60.08/139.58',
        'nodalPlane2': '243.25/55.81/37.09',
        'reviewType': 'reviewed',
      }, 0);

      expect(event, isNotNull);
      expect(event!.source, 'usgsCmt');
      expect(event.eventId, 'us7000t37a');
      expect(event.titleText, 'USGS 地震矩心矩张量解');
      expect(event.reportNumText, '正式');
      expect(event.apiTypeLabel, 'USGS');
      expect(event.nodalPlane1, '130.24/60.08/139.58');
      expect(event.nodalPlane2, '243.25/55.81/37.09');
      expect(event.centroidDepth, 15.5);
      expect(event.depth, 44.637);
      expect(event.depthText, '深度: 44km');
      expect(event.magnitude, 6.0);
    });

    test('automatic：reportNumText 显示自动测定', () {
      final event = QuakeEventAdapter.convert('usgsCmt', {
        'eventId': 'us6000tgb9',
        'location': '日本熊本县',
        'magnitude': 6.8,
        'depth': 10.0,
        'centroidDepth': 12.3,
        'latitude': 32.6817,
        'longitude': 130.7217,
        'originTime': '2026-07-30 12:00:00',
        'nodalPlane1': '200/45/90',
        'nodalPlane2': '20/45/90',
        'reviewType': 'automatic',
      }, 0);

      expect(event, isNotNull);
      expect(event!.reportNumText, '自动');
      expect(event.centroidDepth, 12.3);
    });

    test('centroidDepth 缺失时为 null', () {
      final event = QuakeEventAdapter.convert('usgsCmt', {
        'eventId': 'us_test_no_cd',
        'location': '测试区域',
        'magnitude': 5.5,
        'depth': 8.0,
        'latitude': 35.7,
        'longitude': 102.3,
        'originTime': '2026-07-30 12:00:00',
        'nodalPlane1': '112/66/102',
        'nodalPlane2': '264/26/65',
        'reviewType': 'reviewed',
      }, 0);

      expect(event, isNotNull);
      expect(event!.centroidDepth, isNull);
    });

    test('UTC ISO eventtime keeps the USGS CMT absolute instant', () {
      final event = QuakeEventAdapter.convert('usgsCmt', {
        'eventId': 'usgs_cmt_utc_test',
        'location': '测试区域',
        'magnitude': 5.8,
        'depth': 20.0,
        'latitude': 35.0,
        'longitude': 140.0,
        'originTime': '2026-07-30T04:00:00.000Z',
        'reviewType': 'reviewed',
      }, 0);

      expect(event, isNotNull);
      expect(event!.timeZone, QuakeTime.systemTimeZoneHours);
      expect(QuakeTime.unifiedInstantUtc(event), DateTime.utc(2026, 7, 30, 4));
    });
  });
}
