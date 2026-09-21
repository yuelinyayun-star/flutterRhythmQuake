import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_event_tracker.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_presentation.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/map_state_provider.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sources/palert_source_state.dart';
import 'package:flutterrhythmquake/widgets/map/palert_source_visibility.dart';
import 'package:flutterrhythmquake/widgets/ui/alert_module.dart';
import 'package:flutterrhythmquake/widgets/ui/ui_runtime_flags.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final origin = DateTime.utc(2026, 9, 21, 1);
SourceEstimate estimate({
  String method = 'palert_hyp_v1',
  double longitude = 121,
}) => SourceEstimate(
  latitude: 23.5,
  longitude: longitude,
  depthKm: 10,
  originTime: origin,
  confidence: 0.8,
  method: method,
  supportingStationCount: 6,
  diagnostics: const {
    'quality_score': 0,
    'quality_rank': 'B',
    'wave_counts': {'P': 4, 'S': 2, 'O': 0},
  },
);
UnifiedQuakeData cwa({
  double latitude = 23.5,
  double longitude = 121,
  double depth = 10,
  int seconds = 0,
  bool canceled = false,
  bool assumption = false,
  String source = 'cwaEew',
}) => UnifiedQuakeData(
  source: source,
  origin: 1,
  eventId: 'controlled-eew',
  isEew: true,
  timeZone: 8,
  titleText: 'Test EEW',
  reportNumText: '1',
  useShindo: true,
  maxIntensity: '2',
  className: 'blue',
  hypocenter: 'Test',
  originTime: DateTime(2026, 9, 21, 9).add(Duration(seconds: seconds)),
  lat: latitude,
  lng: longitude,
  depth: depth,
  isCanceled: canceled,
  isAssumption: assumption,
);
SeismicActiveEvent event(String source) => SeismicActiveEvent(
  eventId: 'controlled-$source',
  sourceId: source,
  startedAt: origin,
  updatedAt: origin,
  stageName: 'confirmed',
  maxShindo: 2,
  estimate: estimate(
    method: source == 'palert' ? 'palert_hyp_v1' : 'nied_dart_hyp_v1',
  ),
  metadata: const {'palert_max_cwa_intensity_index': 2},
);

class TestProvider extends QuakeProvider {
  @override
  final List<UnifiedQuakeData> unifiedEvents = [];
  void add(UnifiedQuakeData value) {
    unifiedEvents.add(value);
    notifyListeners();
  }
}

void main() {
  test('only matched CWA hides; source wall clock is converted to UTC', () {
    bool visible(UnifiedQuakeData e) =>
        shouldShowPAlertSource(estimate(), [e], hideOnMatchingEew: true);
    expect(visible(cwa()), isFalse);
    expect(
      visible(cwa(latitude: 24.5, longitude: 122, depth: 110, seconds: 10)),
      isFalse,
    );
    expect(visible(cwa(latitude: 24.501)), isTrue);
    expect(visible(cwa(longitude: 122.001)), isTrue);
    expect(visible(cwa(depth: 111)), isTrue);
    expect(visible(cwa(seconds: 11)), isTrue);
    expect(visible(cwa(canceled: true)), isTrue);
    expect(visible(cwa(assumption: true)), isTrue);
    expect(visible(cwa(source: 'jmaEew')), isTrue);
    expect(
      shouldShowPAlertSource(estimate(), [cwa()], hideOnMatchingEew: false),
      isTrue,
    );
    expect(
      shouldShowPAlertSource(estimate(longitude: 179.8), [
        cwa(longitude: -179.8),
      ], hideOnMatchingEew: true),
      isFalse,
    );
  });

  testWidgets('P-Alert and NIED share the title and existing switches', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final quake = TestProvider();
    final map = MapStateProvider()..setShowEstimatedEpicenter(true);
    StationEventTracker.instance.currentNiedEvent.value = event('nied');
    PAlertSourceState.events.value = [event('palert')];
    UiRuntimeFlags.hideGridOnEewNotifier.value = false;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<QuakeProvider>.value(value: quake),
          ChangeNotifierProvider.value(value: map),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: AlertModule())),
        ),
      ),
    );
    expect(find.text(sourceEstimationTitle), findsNWidgets(2));
    expect(find.textContaining('P-A 本地推算'), findsNothing);
    quake.add(cwa());
    await tester.pump();
    expect(find.text(sourceEstimationTitle), findsNWidgets(2));
    UiRuntimeFlags.hideGridOnEewNotifier.value = true;
    await tester.pump();
    expect(find.text(sourceEstimationTitle), findsOneWidget);
    UiRuntimeFlags.hideGridOnEewNotifier.value = false;
    await tester.pump();
    expect(find.text(sourceEstimationTitle), findsNWidgets(2));
    map.setShowEstimatedEpicenter(false);
    await tester.pump();
    expect(find.text(sourceEstimationTitle), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    PAlertSourceState.events.value = const [];
    StationEventTracker.instance.currentNiedEvent.value = null;
    quake.dispose();
    map.dispose();
  });
}
