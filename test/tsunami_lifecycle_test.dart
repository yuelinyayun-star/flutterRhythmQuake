import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/tsunami_message.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sound_effect_service.dart';
import 'package:flutterrhythmquake/services/tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectService().enabled = false;
    TtsService().eventEnabled = false;
  });

  tearDown(() => SoundEffectService().enabled = true);

  test('older JMA tsunami report cannot overwrite the current report', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);

    provider.handleTsunamiEventForTest(
      _jmaWarning(id: 'new', reportTime: '2026-08-10 12:20:00'),
    );
    provider.handleTsunamiEventForTest(
      _jmaWarning(
        id: 'old',
        reportTime: '2026-08-10 12:10:00',
        areaName: '旧区域',
      ),
    );

    expect(provider.jmaTsunami?.id, 'new');
    expect(provider.jmaTsunami?.areas.single.name, '有明・八代海');
  });

  test('same JMA report from another API is deduped by body and time', () {
    final provider = QuakeProvider();
    addTearDown(provider.dispose);
    var notifications = 0;
    provider.addListener(() => notifications++);

    final first = _jmaWarning(id: 'p2p-id', reportTime: '2026-08-10 12:20:00');
    provider.handleTsunamiEventForTest(first);
    provider.handleTsunamiEventForTest(first.copyWith(id: 'whews-id'));

    expect(notifications, 1);
    expect(provider.jmaTsunami?.id, 'p2p-id');
  });

  test(
    'same report can enrich details without replacing its stable identity',
    () {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);

      provider.handleTsunamiEventForTest(
        _jmaWarning(id: 'p2p-id', reportTime: '2026-08-10 12:20:00'),
      );
      provider.handleTsunamiEventForTest(
        _jmaWarning(
          id: 'whews-id',
          reportTime: '2026-08-10 12:20:00',
          description: '１ｍ',
          arrivalTime: '2026-08-10 12:45:00',
        ),
      );

      expect(provider.jmaTsunami?.id, 'p2p-id');
      expect(provider.jmaTsunami?.areas.single.description, '１ｍ');
      expect(
        provider.jmaTsunami?.areas.single.arrivalTime,
        '2026-08-10 12:45:00',
      );
    },
  );

  test(
    'new cancellation clears the layer and old active report stays rejected',
    () {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);

      provider.handleTsunamiEventForTest(
        _jmaWarning(id: 'warning', reportTime: '2026-08-10 12:20:00'),
      );
      provider.handleTsunamiEventForTest(
        const TsunamiMessage(
          source: TsunamiSource.jma,
          id: 'cancel',
          reportTime: '2026-08-10 12:30:00',
          title: '津波警報・注意報解除',
          titleText: '津波注意報を解除しました。',
          grade: TsunamiGrade.none,
        ),
      );
      provider.handleTsunamiEventForTest(
        _jmaWarning(id: 'late-old', reportTime: '2026-08-10 12:25:00'),
      );

      expect(provider.jmaTsunami?.isActive, isFalse);
      expect(provider.jmaTsunami?.isCancellation, isTrue);
      expect(provider.jmaTsunami?.reportTime, '2026-08-10 12:30:00');
    },
  );

  test(
    'initial aggregate snapshot restores state without losing its marker',
    () {
      final provider = QuakeProvider();
      addTearDown(provider.dispose);

      provider.handleTsunamiEventForTest(
        _jmaWarning(
          id: 'snapshot',
          reportTime: '2026-08-10 12:20:00',
        ).copyWith(isInitialSnapshot: true),
      );

      expect(provider.jmaTsunami?.isActive, isTrue);
      expect(provider.jmaTsunami?.isInitialSnapshot, isTrue);
    },
  );
}

TsunamiMessage _jmaWarning({
  required String id,
  required String reportTime,
  String areaName = '有明・八代海',
  String? description,
  String? arrivalTime,
}) {
  return TsunamiMessage(
    source: TsunamiSource.jma,
    id: id,
    reportTime: reportTime,
    title: '津波注意報',
    titleText: '津波注意報発表中',
    grade: TsunamiGrade.watch,
    className: 'yellow',
    areas: [
      TsunamiAreaInfo(
        name: areaName,
        grade: TsunamiGrade.watch,
        description: description,
        arrivalTime: arrivalTime,
      ),
    ],
  );
}
