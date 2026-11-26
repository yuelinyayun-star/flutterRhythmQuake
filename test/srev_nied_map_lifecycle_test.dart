import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/widgets/map/quake_map_view.dart';

void main() {
  testWidgets(
    'SREV production map layers keep frozen sources and hide expired waves independently',
    (tester) async {
      SourceEstimate source(double lon, String state, double? p, double? s) =>
          SourceEstimate(
            latitude: 35,
            longitude: lon,
            depthKm: 40,
            magnitude: 3.4,
            confidence: 0,
            method: 'nied_srev_hyp_rust_v1',
            supportingStationCount: 100,
            diagnostics: {
              'srev_hyp_state': state,
              'srev_error': 24.0,
              'selected_detection_id': lon == 135 ? 1 : 2,
              'srev_p_radius_km': p,
              'srev_s_radius_km': s,
            },
          );
      Future<void> render(List<SourceEstimate> sources) async {
        await tester.pumpWidget(
          MaterialApp(
            home: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(35, 138),
                initialZoom: 4,
              ),
              children: [
                buildNiedHypSourceMarkerLayer(
                  sources,
                  primary: sources.isEmpty ? null : sources.first,
                ),
                for (final a in sources)
                  buildNiedEstimateMapLayers(
                    estimate: a,
                    maxShindo: 2,
                    accent: Colors.green,
                    waveColor: Colors.green,
                    algorithmElapsedSeconds: 1000,
                  ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      List<double> radii() => tester
          .widgetList<CircleLayer<Object>>(find.byType(CircleLayer<Object>))
          .expand((l) => l.circles.map((c) => c.radius))
          .toList();
      await render([
        source(135, 'updating', 800, 500),
        source(141, 'updating', 400, 200),
      ]);
      expect(radii(), [800000, 500000, 400000, 200000]);
      expect(find.text('当前 40km 误差24.00'), findsOneWidget);
      expect(find.text('震源 2 40km 误差24.00'), findsOneWidget);
      expect(find.textContaining('更新中'), findsNothing);
      await render([
        source(135, 'finished', 900, 600),
        source(141, 'updating', 450, 250),
      ]);
      expect(radii(), [900000, 600000, 450000, 250000]);
      expect(find.textContaining('更新结束'), findsNothing);
      expect(find.textContaining('更新中'), findsNothing);
      expect(find.textContaining('SREV残差'), findsNothing);
      expect(find.text('当前 40km 误差24.00'), findsOneWidget);
      expect(find.text('震源 2 40km 误差24.00'), findsOneWidget);
      await render([
        source(135, 'finished', 999999, 999999),
        source(141, 'updating', null, 250),
      ]);
      expect(radii(), [250000]);
      expect(find.text('当前 40km 误差24.00'), findsOneWidget);
      await render([source(141, 'updating', 450, 250)]);
      expect(find.textContaining('更新结束'), findsNothing);
      expect(find.text('当前 40km 误差24.00'), findsOneWidget);
      expect(find.textContaining('震源 2'), findsNothing);
      expect(radii(), [450000, 250000]);
      await render([]);
      expect(find.byType(MarkerLayer), findsNothing);
      expect(radii(), isEmpty);
    },
  );
}
