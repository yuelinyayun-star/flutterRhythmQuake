import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/widgets/map/information_event_fill_layer.dart';
import 'package:flutterrhythmquake/widgets/map/intensity_fill_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'JMA information without reported regions does not estimate map fill',
    (tester) async {
      const event = UnifiedQuakeData(
        source: 'jmaEqlist',
        origin: 2,
        eventId: 'jma-info-without-regions',
        isEew: false,
        timeZone: 9,
        titleText: '震度速報',
        reportNumText: '',
        useShindo: true,
        maxIntensity: '4',
        className: 'yellow',
        hypocenter: '测试震中',
        magnitude: 6.0,
        depth: 10.0,
        lat: 35.0,
        lng: 139.0,
      );

      await tester.pumpWidget(
        const MaterialApp(home: InformationEventFillLayer(event: event)),
      );
      await tester.pumpAndSettle();

      final layer = tester.widget<IntensityFillLayer>(
        find.byType(IntensityFillLayer),
      );
      expect(layer.allowJmaEstimate, isFalse);
      expect(find.byType(PolygonLayer), findsNothing);
    },
  );
}
