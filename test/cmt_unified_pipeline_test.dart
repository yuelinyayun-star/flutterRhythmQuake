import 'package:flutter_test/flutter_test.dart';
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
    _clearCmtBuckets();
  });

  tearDown(() {
    SoundEffectService().enabled = true;
    _clearCmtBuckets();
  });

  test(
    'JMA and F-net CMT update their buckets without entering default history',
    () {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);

      provider.handleUnifiedEventForTest(_cmtEvent('jmaCmt', 'jma-cmt-test'));
      provider.handleUnifiedEventForTest(_cmtEvent('fnetCmt', 'fnet-cmt-test'));

      expect(provider.historyBySource['jmaCmt'], hasLength(1));
      expect(provider.historyBySource['fnetCmt'], hasLength(1));
      expect(provider.historyList, isEmpty);
    },
  );

  test(
    'Hi-net AQUA CMT uses arrival time instead of expiring immediately',
    () async {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);

      provider.handleUnifiedEventForTest(
        _cmtEvent(
          'hinetAquaCmt',
          'hinet-aqua-cmt-test',
          originTime: DateTime.utc(2000),
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(provider.unifiedEvents, hasLength(1));
    },
  );
}

void _clearCmtBuckets() {
  final buckets = EqlistManager().getAllBuckets();
  for (final key in const [
    'cencCmt',
    'usgsCmt',
    'jmaCmt',
    'fnetCmt',
    'hinetAquaCmt',
  ]) {
    buckets[key]!.clear();
  }
}

UnifiedQuakeData _cmtEvent(
  String source,
  String eventId, {
  DateTime? originTime,
}) {
  return UnifiedQuakeData(
    source: source,
    origin: 0,
    eventId: eventId,
    isEew: false,
    timeZone: 9,
    titleText: '$source test',
    reportNumText: '自动',
    useShindo: false,
    maxIntensity: '-',
    className: 'gray',
    hypocenter: '测试区域',
    originTime: originTime ?? DateTime.now().toUtc(),
    magnitude: 5.5,
    depth: 20,
    depthText: '深さ: 20km',
    lat: 35,
    lng: 140,
  );
}
