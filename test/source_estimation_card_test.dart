import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimator.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_event_tracker.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

void main() {
  final tracker = StationEventTracker.instance;

  setUp(tracker.resetNied);
  tearDown(tracker.resetNied);

  testWidgets('colors source estimation by estimated shindo in unified UI', (
    tester,
  ) async {
    final observedAt = DateTime.utc(2026, 6, 21, 1);
    tracker.setNiedEstimator(const _Kotoho7JsUiEstimator());
    tracker.ingestNiedFrame(
      stations: [
        _station('N', const LatLng(36, 140), observedAt),
        _station('E', const LatLng(35, 141), observedAt),
        _station('S', const LatLng(34, 140), observedAt),
        _station('W', const LatLng(35, 139), observedAt),
      ],
      observedAt: observedAt,
      stageName: 'confirmed',
      maxShindo: 4,
      eventId: 'ui-quality-event',
      metadata: const {
        'source_trigger_member_ids': ['N', 'E', 'S', 'W'],
      },
    );

    expect(tracker.currentNiedEvent.value?.estimate, isNotNull);

    await _pumpAlertModule(tester);
    await tester.pump();

    expect(find.text('\u9707\u6e90\u672c\u5730\u63a8\u7b97'), findsOneWidget);
    expect(
      find.text('\u9707\u6e90\u672c\u5730\u63a8\u7b97 \u7b2c1\u62a5'),
      findsNothing,
    );
    expect(find.text('4'), findsOneWidget);
    expect(find.text('\u68c0\u51fa\u9707\u5ea6'), findsOneWidget);
    expect(find.textContaining('JS\u8bef\u5dee 1.250'), findsOneWidget);
    expect(find.textContaining('\u89e6\u53d1 4\u7ad9'), findsOneWidget);
    expect(find.textContaining('\u652f\u6301 4\u7ad9'), findsWidgets);
  });

  for (final (jmaIndex, coarseShindo, main, suffix) in const [
    (5, 5, '5', '-'),
    (6, 5, '5', '+'),
    (7, 6, '6', '-'),
    (8, 6, '6', '+'),
  ]) {
    testWidgets('shows exact kotoho7 JMA badge index $jmaIndex', (
      tester,
    ) async {
      final observedAt = DateTime.utc(2026, 7, 28, 1);
      tracker.setNiedEstimator(
        _Kotoho7JsUiEstimator(jmaIndex: jmaIndex, jmaClass: coarseShindo),
      );
      tracker.ingestNiedFrame(
        stations: [
          _station('N', const LatLng(36, 140), observedAt),
          _station('E', const LatLng(35, 141), observedAt),
          _station('S', const LatLng(34, 140), observedAt),
          _station('W', const LatLng(35, 139), observedAt),
        ],
        observedAt: observedAt,
        stageName: 'confirmed',
        maxShindo: coarseShindo,
        eventId: 'ui-kotoho7-shindo-$jmaIndex',
        metadata: const {
          'source_trigger_member_ids': ['N', 'E', 'S', 'W'],
        },
      );

      await _pumpAlertModule(tester);
      await tester.pump();

      expect(find.text(main), findsOneWidget);
      expect(find.text(suffix), findsOneWidget);
      expect(find.text('\u68c0\u51fa\u9707\u5ea6'), findsOneWidget);
    });

    testWidgets('shows exact Dart HYP JMA badge index $jmaIndex', (
      tester,
    ) async {
      final observedAt = DateTime.utc(2026, 7, 28, 1);
      tracker.setNiedEstimator(const _DartHypUiEstimator());
      tracker.ingestNiedFrame(
        stations: [
          _station('N', const LatLng(36, 140), observedAt),
          _station('E', const LatLng(35, 141), observedAt),
          _station('S', const LatLng(34, 140), observedAt),
          _station('W', const LatLng(35, 139), observedAt),
        ],
        observedAt: observedAt,
        stageName: 'confirmed',
        maxShindo: coarseShindo,
        eventId: 'ui-dart-hyp-shindo-$jmaIndex',
        metadata: {
          'nied_max_jma_shindo_index': jmaIndex,
          'source_trigger_member_ids': const ['N', 'E', 'S', 'W'],
        },
      );

      await _pumpAlertModule(tester);
      await tester.pump();

      expect(find.text(main), findsOneWidget);
      expect(find.text(suffix), findsOneWidget);
      expect(find.text('\u68c0\u51fa\u9707\u5ea6'), findsOneWidget);
    });
  }

  testWidgets('shows only current Dart HYP result diagnostics and JST time', (
    tester,
  ) async {
    final observedAt = DateTime.utc(2026, 7, 17, 19, 45, 22);
    tracker.setNiedEstimator(const _DartHypUiEstimator());
    tracker.ingestNiedFrame(
      stations: [
        _station('N', const LatLng(36, 140), observedAt),
        _station('E', const LatLng(35, 141), observedAt),
        _station('S', const LatLng(34, 140), observedAt),
        _station('W', const LatLng(35, 139), observedAt),
      ],
      observedAt: observedAt,
      stageName: 'confirmed',
      maxShindo: 1,
      eventId: 'ui-dart-hyp-event',
      metadata: const {
        'source_trigger_member_ids': ['N', 'E', 'S', 'W'],
      },
    );

    await _pumpAlertModule(tester);
    await tester.pump();

    expect(find.text('\u9707\u6e90\u672c\u5730\u63a8\u7b97'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('\u68c0\u51fa\u9707\u5ea6'), findsOneWidget);
    expect(find.text('35.783\u00b0N, 141.317\u00b0E'), findsOneWidget);
    expect(
      find.text(
        '\u6df1\u5ea6 40km \u00b7 \u652f\u6301 5\u7ad9 \u00b7 Dart HYP',
      ),
      findsOneWidget,
    );
    expect(
      find.text('07-18 04:45:14  \u8bef\u5dee 12.35 \u00b7 \u8d28\u91cf C'),
      findsOneWidget,
    );
    expect(
      find.text('\u89e6\u53d1 6\u7ad9 (P: 3 | S: 2 | O: 1)'),
      findsOneWidget,
    );
    expect(find.textContaining('37.0%'), findsNothing);
    expect(find.textContaining('--s'), findsNothing);
    expect(find.textContaining('P90 --km'), findsNothing);

    tracker.resetNied();
    await tester.pump();

    expect(find.text('\u9707\u6e90\u672c\u5730\u63a8\u7b97'), findsNothing);
  });

  testWidgets('shows candidate region metadata without replacing epicenter', (
    tester,
  ) async {
    final observedAt = DateTime.utc(2026, 6, 21, 1);
    tracker.setNiedEstimator(const _CandidateRegionEstimator());
    tracker.ingestNiedFrame(
      stations: [
        _station('N', const LatLng(36, 140), observedAt),
        _station('E', const LatLng(35, 141), observedAt),
      ],
      observedAt: observedAt,
      stageName: 'confirmed',
      maxShindo: 2,
      eventId: 'ui-candidate-region-event',
      metadata: const {
        'source_trigger_member_ids': ['N', 'E'],
      },
    );

    await _pumpAlertModule(tester);
    await tester.pump();

    expect(
      find.textContaining('35.000\u00b0N, 140.000\u00b0E'),
      findsOneWidget,
    );
    expect(
      find.textContaining('\u5019\u9009\u533a\u57df \u5f85\u786e\u8ba4'),
      findsOneWidget,
    );
  });

  testWidgets('shows local support diagnostics for delayed candidate region', (
    tester,
  ) async {
    final observedAt = DateTime.utc(2026, 6, 25, 10, 21, 57);
    tracker.setNiedEstimator(
      _SequenceEstimator([
        _localSupportCandidateEstimate(),
        _localSupportConvergedEstimate(),
      ]),
    );
    final firstMembers = List.generate(6, (index) => 'LS${index + 1}');
    final laterMembers = List.generate(11, (index) => 'LS${index + 1}');

    tracker.ingestNiedFrame(
      stations: [
        for (var i = 0; i < firstMembers.length; i++)
          _station(firstMembers[i], LatLng(0, i * 0.01), observedAt),
      ],
      observedAt: observedAt,
      stageName: 'confirmed',
      maxShindo: 1,
      eventId: 'ui-local-support-event',
      metadata: {'source_trigger_member_ids': firstMembers},
    );
    tracker.ingestNiedFrame(
      stations: [
        for (var i = 0; i < laterMembers.length; i++)
          _station(
            laterMembers[i],
            LatLng(0, i * 0.005),
            observedAt.add(const Duration(seconds: 3)),
          ),
      ],
      observedAt: observedAt.add(const Duration(seconds: 3)),
      stageName: 'confirmed',
      maxShindo: 1,
      eventId: 'ui-local-support-event',
      metadata: {'source_trigger_member_ids': laterMembers},
    );

    await _pumpAlertModule(tester);
    await tester.pump();

    expect(
      find.textContaining('\u5019\u9009\u533a\u57df \u5ef6\u8fdf\u786e\u8ba4'),
      findsOneWidget,
    );
    expect(
      find.textContaining('\u672c\u5730\u652f\u6301 11\u7ad9 +5'),
      findsOneWidget,
    );
    expect(find.textContaining('0.000\u00b0N, 0.020\u00b0E'), findsOneWidget);
  });

  testWidgets('hides source estimation card when estimated epicenter is off', (
    tester,
  ) async {
    final observedAt = DateTime.utc(2026, 6, 21, 1);
    tracker.setNiedEstimator(const _Kotoho7JsUiEstimator());
    tracker.ingestNiedFrame(
      stations: [
        _station('N', const LatLng(36, 140), observedAt),
        _station('E', const LatLng(35, 141), observedAt),
        _station('S', const LatLng(34, 140), observedAt),
        _station('W', const LatLng(35, 139), observedAt),
      ],
      observedAt: observedAt,
      stageName: 'confirmed',
      maxShindo: 4,
      eventId: 'ui-hidden-event',
      metadata: const {
        'source_trigger_member_ids': ['N', 'E', 'S', 'W'],
      },
    );

    await _pumpAlertModule(tester, showEstimatedEpicenter: false);
    await tester.pump();

    expect(
      find.text('\u9707\u6e90\u672c\u5730\u63a8\u7b97 \u7b2c1\u62a5'),
      findsNothing,
    );
  });
}

Future<void> _pumpAlertModule(
  WidgetTester tester, {
  bool showEstimatedEpicenter = true,
}) async {
  final mapState = MapStateProvider()
    ..setShowEstimatedEpicenter(showEstimatedEpicenter);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => QuakeProvider()),
        ChangeNotifierProvider<MapStateProvider>.value(value: mapState),
      ],
      child: const MaterialApp(home: Scaffold(body: AlertModule())),
    ),
  );
}

class _Kotoho7JsUiEstimator implements SourceEstimator {
  const _Kotoho7JsUiEstimator({this.jmaIndex = 4, this.jmaClass = 4});

  final int jmaIndex;
  final int jmaClass;

  @override
  String get methodId => 'nied_gif_kotoho7_js_receiver_v1';

  @override
  bool supports(SourceEstimationRequest request) => true;

  @override
  SourceEstimate estimate(SourceEstimationRequest request) {
    return SourceEstimate(
      latitude: 35,
      longitude: 140,
      depthKm: 40,
      confidence: 0.4,
      method: methodId,
      supportingStationCount: 4,
      originTime: request.observedAt,
      diagnostics: {
        'best_source_error': 1.25,
        'best_source_applied_count': 4,
        'processed_frame_count': 1,
        'peak_detection_id_count': 1,
        'bridge_elapsed_ms': 8,
        'js_map_max_shindo_class': jmaClass.toDouble(),
        'js_map_max_shindo_index': jmaIndex.toDouble(),
        'best_source_phase_stations': [
          {'code': 'N', 'lat': 36.0, 'lng': 140.0, 'phase': 'p'},
          {'code': 'E', 'lat': 35.0, 'lng': 141.0, 'phase': 's'},
          {'code': 'S', 'lat': 34.0, 'lng': 140.0, 'phase': 'other'},
          {'code': 'W', 'lat': 35.0, 'lng': 139.0, 'phase': 'p'},
        ],
      },
    );
  }
}

class _DartHypUiEstimator
    implements SourceEstimator, SourceEstimatorLifecycleOwner {
  const _DartHypUiEstimator();

  @override
  String get methodId => 'nied_dart_hyp_v1';

  @override
  bool get requiresEveryFrame => true;

  @override
  bool get ownsOutputLifecycle => true;

  @override
  bool supports(SourceEstimationRequest request) => true;

  @override
  SourceEstimate estimate(SourceEstimationRequest request) {
    return SourceEstimate(
      latitude: 35.783,
      longitude: 141.317,
      depthKm: 40,
      originTime: DateTime.utc(2026, 7, 17, 19, 45, 14),
      confidence: 0.37,
      method: methodId,
      supportingStationCount: 5,
      diagnostics: const {
        'error_level': 12.3456,
        'quality_rank': 'C',
        'wave_counts': {'P': 3, 'S': 2, 'O': 1},
      },
    );
  }
}

class _CandidateRegionEstimator implements SourceEstimator {
  const _CandidateRegionEstimator();

  @override
  String get methodId => 'test_candidate_region';

  @override
  bool supports(SourceEstimationRequest request) => true;

  @override
  SourceEstimate estimate(SourceEstimationRequest request) {
    return SourceEstimate(
      latitude: 35,
      longitude: 140,
      confidence: 0.4,
      method: methodId,
      supportingStationCount: 2,
      originTime: request.observedAt,
      diagnostics: const {
        'candidate_corrections': {
          'one_sided_boundary_centroid_guard': {
            'latitude': 35.5,
            'longitude': 140.5,
          },
        },
        'top_timing_picks': [
          {
            'code': 'N',
            'network': 'K-NET',
            'latitude': 35.0,
            'longitude': 140.0,
            'delay_s': 0.0,
            'value': 2.0,
          },
          {
            'code': 'E',
            'network': 'K-NET',
            'latitude': 35.5,
            'longitude': 140.5,
            'delay_s': 1.0,
            'value': 0.0,
          },
        ],
      },
    );
  }
}

class _SequenceEstimator implements SourceEstimator {
  _SequenceEstimator(this.estimates);

  final List<SourceEstimate> estimates;
  var _index = 0;

  @override
  String get methodId => 'test_sequence';

  @override
  bool supports(SourceEstimationRequest request) => true;

  @override
  SourceEstimate estimate(SourceEstimationRequest request) {
    if (_index >= estimates.length) return estimates.last;
    return estimates[_index++];
  }
}

SourceEstimate _localSupportCandidateEstimate() {
  return const SourceEstimate(
    latitude: 0,
    longitude: 1.38,
    confidence: 0.4,
    method: 'test_sequence',
    supportingStationCount: 6,
    diagnostics: {
      'station_geometry': 'one_sided',
      'candidate_corrections': {
        'one_sided_boundary_centroid_guard': {
          'latitude': 0.0,
          'longitude': 1.0,
        },
      },
      'top_timing_picks': [
        {
          'code': 'LS1',
          'network': 'K-NET',
          'latitude': 0.0,
          'longitude': 0.0,
          'delay_s': 0.0,
          'value': 2.0,
        },
        {
          'code': 'LS2',
          'network': 'K-NET',
          'latitude': 0.0,
          'longitude': 1.0,
          'delay_s': 1.0,
          'value': 0.0,
        },
      ],
    },
  );
}

SourceEstimate _localSupportConvergedEstimate() {
  return const SourceEstimate(
    latitude: 0,
    longitude: 0.02,
    confidence: 0.4,
    method: 'test_sequence',
    supportingStationCount: 11,
    diagnostics: {'station_geometry': 'surrounded'},
  );
}

NiedStation _station(String code, LatLng coordinate, DateTime observedAt) {
  return NiedStation(
      id: code.codeUnitAt(0),
      code: code,
      name: code,
      coordinate: coordinate,
      network: 'K-NET',
      prefecture: 'Test',
      expireSeconds: 10,
    )
    ..level = 8
    ..level = 7
    ..continuousShindo = 0.5
    ..activity = 6
    ..ascend = 2
    ..isActive = true
    ..lastUpdate = observedAt;
}
