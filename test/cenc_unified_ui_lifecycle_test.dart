import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/cenc_ir_data.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
    EqlistManager().updateCencList(const []);
  });

  tearDown(() => SoundEffectService().enabled = true);

  test('expired CENC current report does not reopen UI or mutate history', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);

    provider.handleUnifiedEventForTest(
      _cencEvent(reviewed: true, reportTime: DateTime.utc(2020, 1, 1)),
    );

    expect(provider.unifiedEvents, isEmpty);
    expect(provider.historyBySource['cencEqlist'], isEmpty);
  });

  test('fresh CENC current report does not write the history bucket', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);

    provider.handleUnifiedEventForTest(_cencEvent(reviewed: true));

    expect(provider.unifiedEvents, hasLength(1));
    expect(provider.historyBySource['cencEqlist'], isEmpty);
  });

  test('same reviewed CENC report stays closed after dismissal', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    final event = _cencEvent(reviewed: true);

    provider.handleUnifiedEventForTest(event);
    expect(provider.unifiedEvents, hasLength(1));

    provider.dismissUnifiedEventForTest(event);
    expect(provider.unifiedEvents, isEmpty);

    provider.handleUnifiedEventForTest(event);
    expect(provider.unifiedEvents, isEmpty);
  });

  test(
    'reviewed CENC report can replace a dismissed automatic report once',
    () {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      final automatic = _cencEvent(reviewed: false);
      final reviewed = _cencEvent(reviewed: true);

      provider.handleUnifiedEventForTest(automatic);
      provider.dismissUnifiedEventForTest(automatic);
      provider.handleUnifiedEventForTest(reviewed);

      expect(provider.unifiedEvents, hasLength(1));
      expect(provider.unifiedEvents.single.reportNumText, '正式测定');

      provider.dismissUnifiedEventForTest(reviewed);
      provider.handleUnifiedEventForTest(reviewed);
      expect(provider.unifiedEvents, isEmpty);
    },
  );

  test('NowQuake realtime map data clears with its unified UI event', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    final event = _nowQuakeCencIrEvent('20260728111607');

    provider.updateRealtimeCencIrDataForTest(_cencIrData('20260728111607'));
    final initialRevision = provider.unifiedMapRevision;
    provider.handleUnifiedEventForTest(event);

    expect(provider.cencIrData?.reportId, '20260728111607');
    expect(provider.isManualCencIrActive, isFalse);
    expect(provider.unifiedEvents, hasLength(1));
    expect(provider.unifiedMapRevision, greaterThan(initialRevision));

    final acceptedRevision = provider.unifiedMapRevision;
    provider.dismissUnifiedEventForTest(event);

    expect(provider.unifiedEvents, isEmpty);
    expect(provider.cencIrData, isNull);
    expect(provider.unifiedMapRevision, greaterThan(acceptedRevision));
  });

  test(
    'NowQuake realtime map data is removed when UI rejects the event',
    () async {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);

      provider.updateRealtimeCencIrDataForTest(
        _cencIrData('20260728111607'),
        requireUnifiedEvent: true,
      );
      expect(provider.cencIrData?.reportId, '20260728111607');

      await Future<void>.delayed(const Duration(milliseconds: 1));

      expect(provider.unifiedEvents, isEmpty);
      expect(provider.cencIrData, isNull);
    },
  );

  test(
    'NowQuake realtime map data remains when unified UI accepts the event',
    () async {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);
      final event = _nowQuakeCencIrEvent('20260728111607');

      provider.updateRealtimeCencIrDataForTest(
        _cencIrData('20260728111607'),
        requireUnifiedEvent: true,
      );
      provider.handleUnifiedEventForTest(event);

      await Future<void>.delayed(const Duration(milliseconds: 1));

      expect(provider.unifiedEvents, hasLength(1));
      expect(provider.cencIrData?.reportId, '20260728111607');
    },
  );

  test('manual CENC intensity view stays independent from realtime UI', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    final event = _nowQuakeCencIrEvent('20260728111607');

    provider.updateRealtimeCencIrDataForTest(_cencIrData('20260728111607'));
    provider.handleUnifiedEventForTest(event);
    provider.updateManualCencIrDataForTest(_cencIrData('20260728111607'));

    expect(provider.isManualCencIrActive, isTrue);
    expect(provider.manualCencIrData?.reportId, '20260728111607');

    provider.dismissUnifiedEventForTest(event);

    expect(provider.unifiedEvents, isEmpty);
    expect(provider.cencIrData?.reportId, '20260728111607');

    provider.clearCencIrData();
    expect(provider.cencIrData, isNull);
    expect(provider.isManualCencIrActive, isFalse);
  });
}

UnifiedQuakeData _cencEvent({required bool reviewed, DateTime? reportTime}) {
  final now = DateTime.now().toUtc();
  return UnifiedQuakeData(
    source: 'cencEqlist',
    origin: 0,
    eventId: 'CC.20260725060436.5',
    isEew: false,
    timeZone: 0,
    titleText: '中国地震台网地震信息',
    reportNumText: reviewed ? '正式测定' : '自动测定',
    useShindo: false,
    maxIntensity: '7.0',
    className: 'orange',
    hypocenter: '瓦努阿图群岛',
    originTime: now.subtract(const Duration(minutes: 1)),
    reportTime: reportTime ?? now,
    magnitude: 5.9,
    depth: 40,
    depthText: '深度: 40km',
    lat: -15.2,
    lng: 167.1,
    apiTypeLabel: 'Wolfx',
  );
}

UnifiedQuakeData _nowQuakeCencIrEvent(String id) {
  final now = DateTime.now().toUtc();
  return UnifiedQuakeData(
    source: 'nowQuakeCencIr',
    origin: 1,
    eventId: id,
    isEew: false,
    timeZone: 8,
    titleText: '中国地震台网烈度速报',
    reportNumText: '',
    useShindo: false,
    maxIntensity: '9.9',
    className: 'purple',
    hypocenter: '青海海南州兴海县',
    originTime: now.subtract(const Duration(minutes: 1)),
    reportTime: now,
    magnitude: 5.7,
    depth: 10,
    depthText: '深度: 10km',
    lat: 35.349998,
    lng: 99.57,
    apiTypeLabel: 'NowQuake',
  );
}

CencIrData _cencIrData(String id) {
  final now = DateTime.now().toUtc();
  return CencIrData(
    source: CencIrDataSource.nowQuake,
    reportId: id,
    uniEventId: id,
    oriTime: now.subtract(const Duration(minutes: 1)),
    gmtCreate: now,
    locName: '青海海南州兴海县',
    epiLon: 99.57,
    epiLat: 35.349998,
    focDepth: 10,
    subjectCodes: 'intensity-report',
    intensityInfoText: '',
  );
}
