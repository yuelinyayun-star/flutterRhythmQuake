import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';

void main() {
  group('CENC CMT adapter', () {
    test('自动产出：字段映射 + reportNumText', () {
      final event = QuakeEventAdapter.convert('cencCmt', {
        'eventId': 'cenc_cmt_2023-12-18T15:59:30.000Z_35.700_102.300',
        'location': '',
        'magnitude': 5.9,
        'depth': 10.0,
        'centroidDepth': 14.0,
        'latitude': 35.7,
        'longitude': 102.3,
        'originTime': '2023-12-18T15:59:30.000Z',
        'reportTime': '2023-12-18T16:05:00.000Z',
        'nodalPlane1': '112/66/102',
        'nodalPlane2': '264/26/65',
        'reviewType': 'automatic',
      }, 0);

      expect(event, isNotNull);
      expect(event!.source, 'cencCmt');
      expect(
        event.eventId,
        'cenc_cmt_2023-12-18T15:59:30.000Z_35.700_102.300',
      );
      expect(event.titleText, 'CENC 地震矩心矩张量解');
      expect(event.reportNumText, '自动');
      expect(event.apiTypeLabel, 'CENC');
      expect(event.nodalPlane1, '112/66/102');
      expect(event.nodalPlane2, '264/26/65');
      expect(event.centroidDepth, 14.0);
      expect(event.depth, 10.0);
      expect(event.depthText, '深度: 10km');
      expect(event.magnitude, 5.9);
    });

    test('人工复核：reportNumText 显示正式测定', () {
      final event = QuakeEventAdapter.convert('cencCmt', {
        'eventId': 'cenc_cmt_test_reviewed',
        'location': '',
        'magnitude': 6.0,
        'depth': 12.0,
        'centroidDepth': 15.0,
        'latitude': 35.7,
        'longitude': 102.3,
        'originTime': '2023-12-18T15:59:30.000Z',
        'nodalPlane1': '110/70/100',
        'nodalPlane2': '260/25/60',
        'reviewType': 'reviewed',
      }, 0);

      expect(event, isNotNull);
      expect(event!.reportNumText, '正式');
      expect(event.centroidDepth, 15.0);
    });

    test('centroidDepth 缺失时为 null', () {
      final event = QuakeEventAdapter.convert('cencCmt', {
        'eventId': 'cenc_cmt_test_no_cd',
        'location': '',
        'magnitude': 5.5,
        'depth': 8.0,
        'latitude': 35.7,
        'longitude': 102.3,
        'originTime': '2023-12-18T15:59:30.000Z',
        'nodalPlane1': '112/66/102',
        'nodalPlane2': '264/26/65',
        'reviewType': 'automatic',
      }, 0);

      expect(event, isNotNull);
      expect(event!.centroidDepth, isNull);
    });
  });
}
