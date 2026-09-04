import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/whews_station_service.dart';

void main() {
  test(
    'KMA optional PGA and PGV retain raw values outside the MMI range',
    () async {
      final service = WhewsStationService(
        kind: WhewsStationKind.kma,
        apiToken: 'test-token',
      );
      final frames = <WhewsStationFrame>[];
      final subscription = service.frameStream.listen(frames.add);

      service.handleMessageForTesting({
        'type': 'kma_stations_update',
        'stations': [
          {'latitude': 37.5, 'longitude': 127.0},
          {'latitude': 35.1, 'longitude': 129.0},
        ],
      });
      service.handleMessageForTesting({
        'Data': {
          'timestamp': '2026-08-06T12:00:00+09:00',
          'mmi': [2, 3],
          'pga': [20.5, 125.75],
          'pgv': [12.25, 18.5],
        },
      });
      await Future<void>.delayed(Duration.zero);

      expect(frames, hasLength(1));
      expect(frames.single.values, [2.0, 3.0]);
      expect(frames.single.pga, [20.5, 125.75]);
      expect(frames.single.pgv, [12.25, 18.5]);

      await subscription.cancel();
      service.dispose();
    },
  );

  test('NIED and S-Net invalid sentinel is not displayable as shindo 0', () {
    expect(whewsNiedSnetValueIsValid(-3.0), isFalse);
    expect(whewsNiedSnetValueIsValid(-2.99), isTrue);
    expect(whewsNiedSnetValueIsValid(0.0), isTrue);
    expect(whewsNiedSnetValueIsValid(7.01), isFalse);
    expect(whewsNiedSnetValueIsValid(double.nan), isFalse);
  });

  test('NIED rejects an out-of-range primary value without clamping', () async {
    final service = WhewsStationService(
      kind: WhewsStationKind.nied,
      apiToken: 'test-token',
    );
    final frames = <WhewsStationFrame>[];
    final subscription = service.frameStream.listen(frames.add);

    service.handleMessageForTesting({
      'type': 'nied_stations_update',
      'stations': [
        {'latitude': 35.0, 'longitude': 139.0},
      ],
    });
    service.handleMessageForTesting({
      'Data': {
        'timestamp': '2026-08-10T12:00:00+09:00',
        'shindo': [99],
      },
    });
    await Future<void>.delayed(Duration.zero);

    expect(frames, isEmpty);
    await subscription.cancel();
    service.dispose();
  });

  test('negative PGA rejects the complete station frame', () async {
    final service = WhewsStationService(
      kind: WhewsStationKind.snet,
      apiToken: 'test-token',
    );
    final frames = <WhewsStationFrame>[];
    final subscription = service.frameStream.listen(frames.add);

    service.handleMessageForTesting({
      'type': 'snet_stations_update',
      'stations': [
        {'latitude': 35.0, 'longitude': 142.0},
      ],
    });
    service.handleMessageForTesting({
      'Data': {
        'timestamp': '2026-08-10T12:00:00+09:00',
        'shindo': [1.2],
        'pga': [-0.1],
      },
    });
    await Future<void>.delayed(Duration.zero);

    expect(frames, isEmpty);
    await subscription.cancel();
    service.dispose();
  });
}
