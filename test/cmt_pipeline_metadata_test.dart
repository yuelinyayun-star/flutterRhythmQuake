import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/quake_time.dart';
import 'package:flutterrhythmquake/models/cmt_solution_metadata.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';

Map<String, dynamic> _cencItem(String id, String originTime) => {
  'eventId': id,
  'originTime': originTime,
  'latitude': 35.7,
  'longitude': 102.3,
  'depth': 10.0,
  'magnitude': 5.9,
  'centroidDepth': 14.0,
  'nodalPlane1': '112/66/102',
  'nodalPlane2': '264/26/65',
  'reviewType': 'automatic',
};

void main() {
  group('CMT source pipeline', () {
    test('a list contributes only its newest valid CMT candidate', () {
      final event = QuakeProvider.latestCmtCandidateForTest('cencCmt', [
        _cencItem('older', '2026-08-01T03:00:00.000Z'),
        _cencItem('newest', '2026-08-02T03:00:00.000Z'),
        {'eventId': 'invalid'},
      ]);

      expect(event, isNotNull);
      expect(event!.eventId, 'newest');
    });

    test(
      'USGS CMT preserves raw solution metadata without using it as magnitude',
      () {
        final event = QuakeEventAdapter.convert('usgsCmt', {
          'eventId': 'us-test',
          'originTime': '2026-08-02 16:35:26',
          'latitude': -38.0347,
          'longitude': 177.9278,
          'depth': 35.5,
          'magnitude': 5.6,
          'centroidDepth': 31.2,
          'nodalPlane1': '10/20/30',
          'nodalPlane2': '40/50/60',
          'cmtMetadata': {
            'centroidTime': '2026-08-02T08:35:31.2Z',
            'centroidLatitude': -38.0401,
            'centroidLongitude': 177.9302,
            'scalarMoment': '3.18E+17',
            'doubleCoupleRatio': 0.9417,
          },
          'momentTensor': {
            'mrr': '1.20E+17',
            'mtt': '-2.20E+17',
            'mpp': '1.00E+17',
            'mrt': '2.00E+16',
            'mrp': '3.00E+16',
            'mtp': '4.00E+16',
          },
          'momentTensorConvention': 'rtp',
        }, 0);

        expect(event, isNotNull);
        expect(event!.magnitude, 5.6);
        expect(event.cmtMetadata!.centroidTime, '2026-08-02T08:35:31.2Z');
        expect(event.cmtMetadata!.scalarMoment, '3.18E+17');
        expect(event.cmtMetadata!.doubleCoupleRatio, 0.9417);
        expect(event.cmtMetadata!.momentTensorConvention, 'rtp');
        expect(event.cmtMetadata!.rawMomentTensor!['mrr'], '1.20E+17');
      },
    );

    test('Japanese CMT sources use the UTC+9 display classification', () {
      final event = QuakeMessage(
        source: QuakeSourceType.hinetAquaCmt,
        eventId: 'aqua-test',
        location: '',
        magnitude: 4.2,
        latitude: 37.2,
        longitude: 141.8,
        depth: 49,
        originTime: DateTime(2026, 7, 22, 20, 11, 30),
      );

      expect(QuakeTime.targetOffset(event), const Duration(hours: 9));
      expect(QuakeTime.zoneLabel(event), 'UTC+9');
    });

    test('CMT raw metadata survives QuakeMessage serialization', () {
      final message = QuakeMessage(
        source: QuakeSourceType.jmaCmt,
        eventId: 'jma-cmt-test',
        location: '',
        magnitude: 5.4,
        latitude: 31.9,
        longitude: 132.0,
        depth: 21,
        originTime: DateTime.utc(2026, 8, 1, 19, 10, 53),
        cmtMetadata: const CmtSolutionMetadata(
          centroidTime: '2026-08-02 04:10:55.6',
          scalarMoment: '1.6',
          scalarMomentExponent: 17,
          scalarMomentUnit: 'Nm',
          nonDoubleCoupleRatio: 0.04,
          stationCount: 14,
          varianceReduction: 90,
          rawMomentTensor: {'mrr': '1.6E+17'},
          momentTensorConvention: 'rtp',
        ),
      );

      final restored = QuakeMessage.fromMap(message.toMap());
      expect(restored.cmtMetadata, isNotNull);
      expect(restored.cmtMetadata!.scalarMomentExponent, 17);
      expect(restored.cmtMetadata!.stationCount, 14);
      expect(restored.cmtMetadata!.varianceReduction, 90);
      expect(restored.cmtMetadata!.rawMomentTensor!['mrr'], '1.6E+17');
      expect(restored.cmtMetadata!.momentTensorConvention, 'rtp');
    });
  });
}
