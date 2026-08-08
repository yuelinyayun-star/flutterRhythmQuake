import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_event_tracker.dart';
import 'package:flutterrhythmquake/screens/main_screen.dart';
import 'package:flutterrhythmquake/widgets/ui/ui_runtime_flags.dart';

void main() {
  final eventNotifier = StationEventTracker.instance.currentNiedEvent;
  const curveCanvasKey = ValueKey('nied-hyp-curve-canvas');

  setUp(() {
    eventNotifier.value = null;
    UiRuntimeFlags.niedHypCurvePanelVisibleNotifier.value = true;
  });
  tearDown(() {
    eventNotifier.value = null;
    UiRuntimeFlags.niedHypCurvePanelVisibleNotifier.value = true;
  });

  testWidgets(
    'NIED curve overlay survives event clearing, resize, and unmount',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_curveHost());
      eventNotifier.value = _curveEvent();
      await _pumpUntilCurvePaints(tester);
      _expectSquareSize(
        tester.getSize(find.byKey(curveCanvasKey)),
        minSide: 250,
        maxSide: 300,
      );

      eventNotifier.value = null;
      await tester.pump();

      await tester.binding.setSurfaceSize(const Size(560, 900));
      await tester.pump();

      eventNotifier.value = _curveEvent();
      await _pumpUntilCurvePaints(tester);
      _expectSquareSize(
        tester.getSize(find.byKey(curveCanvasKey)),
        minSide: 240,
        maxSide: 300,
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('NIED curve overlay rebuilds after deactivate and activate', (
    tester,
  ) async {
    final overlayKey = GlobalKey();
    var showOnLeft = true;
    late StateSetter setHostState;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            final overlay = buildNiedHypCurveOverlayForTesting(key: overlayKey);
            return Row(
              children: [
                Expanded(
                  child: Stack(children: showOnLeft ? [overlay] : const []),
                ),
                Expanded(
                  child: Stack(children: showOnLeft ? const [] : [overlay]),
                ),
              ],
            );
          },
        ),
      ),
    );
    eventNotifier.value = _curveEvent();
    await _pumpUntilCurvePaints(tester);

    setHostState(() => showOnLeft = false);
    await tester.pump();
    await _pumpUntilCurvePaints(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('NIED curve overlay obeys the Debug visibility switch', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    UiRuntimeFlags.niedHypCurvePanelVisibleNotifier.value = false;
    await tester.pumpWidget(_curveHost());
    eventNotifier.value = _curveEvent();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(curveCanvasKey), findsNothing);

    UiRuntimeFlags.niedHypCurvePanelVisibleNotifier.value = true;
    await _pumpUntilCurvePaints(tester);
    expect(find.byKey(curveCanvasKey), findsOneWidget);
    _expectSquareSize(
      tester.getSize(find.byKey(curveCanvasKey)),
      minSide: 250,
      maxSide: 300,
    );
  });

  testWidgets(
    'NIED curve overlay follows published depth revisions in background mode',
    (tester) async {
      final rawPanels = <Map<String, Object?>>[_curvePanel(depthKm: 10)];
      await tester.pumpWidget(_curveHost(prepareInBackground: true));

      eventNotifier.value = _curveEvent(
        depthKm: 10,
        curveRevision: 1,
        rawPanels: rawPanels,
      );
      await _pumpUntilPaintedDepth(tester, 10);

      rawPanels.single['depth_km'] = 160.0;
      eventNotifier.value = _curveEvent(
        depthKm: 160,
        curveRevision: 2,
        rawPanels: rawPanels,
      );
      await _pumpUntilPaintedDepth(tester, 160);

      rawPanels.single['depth_km'] = 30.0;
      eventNotifier.value = _curveEvent(
        depthKm: 30,
        curveRevision: 3,
        rawPanels: rawPanels,
      );
      await _pumpUntilPaintedDepth(tester, 30);
    },
  );
}

void _expectSquareSize(
  Size size, {
  required double minSide,
  required double maxSide,
}) {
  expect(size.width, closeTo(size.height, 1e-9));
  expect(size.width, inInclusiveRange(minSide, maxSide));
}

Widget _curveHost({bool prepareInBackground = false}) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          buildNiedHypCurveOverlayForTesting(
            prepareInBackground: prepareInBackground,
          ),
        ],
      ),
    ),
  );
}

Future<void> _pumpUntilCurvePaints(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find
        .byKey(const ValueKey('nied-hyp-curve-canvas'))
        .evaluate()
        .isNotEmpty) {
      return;
    }
  }
  fail('The NIED curve payload was not rendered.');
}

Future<void> _pumpUntilPaintedDepth(
  WidgetTester tester,
  double expectedDepthKm,
) async {
  for (var i = 0; i < 50; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    final finder = find.byKey(const ValueKey('nied-hyp-curve-canvas'));
    if (finder.evaluate().isEmpty) continue;
    final customPaint = tester.widget<CustomPaint>(finder);
    final dynamic painter = customPaint.painter;
    final dynamic panels = painter.panels;
    if (panels.isNotEmpty &&
        ((panels.first.depthKm as num).toDouble() - expectedDepthKm).abs() <
            1e-9) {
      return;
    }
  }
  fail('The NIED curve did not repaint at depth $expectedDepthKm km.');
}

SeismicActiveEvent _curveEvent({
  double depthKm = 10,
  int curveRevision = 1,
  List<Map<String, Object?>>? rawPanels,
}) {
  final now = DateTime.utc(2026, 7, 18, 3);
  return SeismicActiveEvent(
    eventId: 'curve-lifecycle',
    sourceId: StationEventTracker.niedSourceId,
    startedAt: now,
    updatedAt: now,
    stageName: 'confirmed',
    maxShindo: 3,
    estimate: SourceEstimate(
      latitude: 35.5,
      longitude: 139.5,
      depthKm: depthKm,
      originTime: now.subtract(const Duration(seconds: 2)),
      confidence: 0.8,
      method: 'nied-dart-hyp',
      supportingStationCount: 2,
      diagnostics: {
        'score': 1.2,
        'elapsed_since_first_trigger_s': 2.0,
        'effective_station_count': 2,
        'travel_time_curve_revision': curveRevision,
        'travel_time_curve_panels':
            rawPanels ?? <Map<String, Object?>>[_curvePanel(depthKm: depthKm)],
      },
    ),
  );
}

Map<String, Object?> _curvePanel({required double depthKm}) => {
  'label': 'selected',
  'selected': true,
  'latitude': 35.5,
  'longitude': 139.5,
  'depth_km': depthKm,
  'origin_time': '2026-07-18T02:59:58.000Z',
  'time_reference': '2026-07-18T03:00:00.000Z',
  'time_reference_model': 'earliest_effective_scoring_station_trigger',
  'distance_axis_model': 'epicentral_surface_distance_haversine_6371_km',
  'travel_time_model': 'jma2001_scratch_polynomial_hypocentral_distance_input',
  'score': 1.2,
  'rmse': 0.4,
  'error_level': 1.2,
  'active_timing_rmse': 0.4,
  'inactive_penalty': 0.0,
  'weight_sum': 2.0,
  'station_scale': 100.0,
  'wave_count_penalty_multiplier': 1.0,
  'p_wave_count': 2,
  's_wave_count': 0,
  'effective_station_count': 2,
  'observed_min_s': 0.0,
  'observed_max_s': 3.0,
  'distance_max_km': 20.0,
  'samples': const [
    {
      'code': 'A',
      'distance_km': 0.0,
      'observed_s': 0.0,
      'predicted_s': 0.1,
      'residual_s': -0.1,
      'weight': 1.0,
      'level': 4,
      'wave': 'P',
    },
    {
      'code': 'B',
      'distance_km': 20.0,
      'observed_s': 3.0,
      'predicted_s': 2.8,
      'residual_s': 0.2,
      'weight': 1.0,
      'level': 5,
      'wave': 'P',
    },
  ],
  'p_curve': const [
    {'distance_km': 0.0, 'arrival_s': 0.1},
    {'distance_km': 20.0, 'arrival_s': 2.8},
  ],
  's_curve': const [
    {'distance_km': 0.0, 'arrival_s': 0.2},
    {'distance_km': 20.0, 'arrival_s': 5.0},
  ],
};
