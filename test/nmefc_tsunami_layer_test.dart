import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/tsunami_message.dart';
import 'package:flutterrhythmquake/widgets/map/nmefc_tsunami_layer.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('NMEFC information message is not active even with areas', () {
    const message = TsunamiMessage(
      source: TsunamiSource.nmefc,
      grade: TsunamiGrade.none,
      areas: [TsunamiAreaInfo(name: 'test area', grade: TsunamiGrade.none)],
      epicenterLat: 31,
      epicenterLng: 142,
      magnitude: 6.9,
      depth: 50,
    );

    expect(message.status, 0);
    expect(message.isActive, isFalse);
    expect(message.areas, isNotEmpty);
  });

  testWidgets('NMEFC layer does not render information epicenter marker', (
    tester,
  ) async {
    const message = TsunamiMessage(
      source: TsunamiSource.nmefc,
      grade: TsunamiGrade.none,
      title: 'Tsunami information',
      areas: [TsunamiAreaInfo(name: 'test area', grade: TsunamiGrade.none)],
      epicenterLat: 31,
      epicenterLng: 142,
      magnitude: 6.9,
      depth: 50,
    );

    await tester.pumpWidget(_mapWith(message));

    expect(find.text('M6.9'), findsNothing);
    expect(find.byType(MarkerLayer), findsNothing);
  });

  testWidgets(
    'NMEFC layer ignores shockInfo when no observation marker exists',
    (tester) async {
      const message = TsunamiMessage(
        source: TsunamiSource.nmefc,
        grade: TsunamiGrade.watch,
        title: 'Tsunami watch',
        epicenterLat: 31,
        epicenterLng: 142,
        magnitude: 6.9,
        depth: 50,
      );

      await tester.pumpWidget(_mapWith(message));

      expect(find.text('M6.9'), findsNothing);
      expect(find.byType(MarkerLayer), findsNothing);
    },
  );
}

Widget _mapWith(TsunamiMessage message) {
  return MaterialApp(
    home: Scaffold(
      body: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(31, 142),
          initialZoom: 5,
        ),
        children: [NmefcTsunamiLayer(tsunami: message)],
      ),
    ),
  );
}
