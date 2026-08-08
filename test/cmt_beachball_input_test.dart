import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/cmt_moment_tensor.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/widgets/map/fssn_cmt_layer.dart';

void main() {
  group('CMT beachball inputs', () {
    test('converts an r-theta-phi tensor into the renderer NED basis', () {
      final tensor = CmtMomentTensor.fromRtpMap({
        'mrr': 1,
        'mtt': 2,
        'mpp': 3,
        'mrt': 4,
        'mrp': 5,
        'mtp': 6,
      });

      expect(tensor, isNotNull);
      expect(tensor!.mnn, 2);
      expect(tensor.mee, 3);
      expect(tensor.mdd, 1);
      expect(tensor.mne, -6);
      expect(tensor.mnd, 4);
      expect(tensor.med, -5);
    });

    test('FSSN CMT adapter preserves documented NED tensor components', () {
      final event = QuakeEventAdapter.convert('fssnCmt', {
        'eventId': 'fssn-cmt-test',
        'location': 'test',
        'originTime': '2026-08-04 12:00:00',
        'magnitude': 5.4,
        'depth': 20,
        'latitude': 30.0,
        'longitude': 120.0,
        'nodalPlane1': '200/77/74',
        'nodalPlane2': '73/21/141',
        'centroidDepth': 18,
        'momentTensorConvention': 'ned',
        'momentTensor': {
          'mnn': '-1.0e+17',
          'mee': '-2.0e+17',
          'mdd': '3.0e+17',
          'mne': '4.0e+17',
          'mnd': '-5.0e+17',
          'med': '6.0e+17',
        },
      }, 0);

      expect(event, isNotNull);
      expect(event!.momentTensor, isNotNull);
      expect(event.momentTensor!.mnd, -5.0e17);

      final marker = FssnCmtMarker.fromQuakeMessage(
        QuakeMessage(
          source: QuakeSourceType.fssnCmt,
          eventId: 'fssn-cmt-marker-test',
          location: 'test',
          magnitude: 5.4,
          latitude: 30,
          longitude: 120,
          depth: 20,
          originTime: DateTime.utc(2026, 8, 4),
          nodalPlane1: '200/77/74',
          nodalPlane2: '73/21/141',
        ),
      );
      expect(marker.nodalPlane1, '200/77/74');
      expect(marker.nodalPlane2, '73/21/141');
    });

    test('missing CMT input stays empty instead of fabricating 0/90/0', () {
      final marker = FssnCmtMarker.fromQuakeMessage(
        QuakeMessage(
          source: QuakeSourceType.usgsCmt,
          eventId: 'empty-cmt',
          location: 'test',
          magnitude: 5,
          latitude: 0,
          longitude: 0,
          depth: 10,
          originTime: DateTime.utc(2026, 8, 4),
        ),
      );

      expect(marker.nodalPlane1, isNull);
      expect(marker.nodalPlane2, isNull);
      expect(marker.momentTensor, isNull);
    });

    test('renders a source-supplied NP2 when NP1 is absent', () {
      expect(
        CmtBeachball.hasRenderableMechanism(nodalPlane2: '174.50/62.98/98.05'),
        isTrue,
      );
    });

    test('rejects malformed or physically invalid nodal planes', () {
      expect(
        CmtBeachball.hasRenderableMechanism(nodalPlane: '337.22/91/74.66'),
        isFalse,
      );
      expect(
        CmtBeachball.hasRenderableMechanism(nodalPlane2: 'not/a/plane'),
        isFalse,
      );
    });
  });
}
