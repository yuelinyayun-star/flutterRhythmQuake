import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/notification_service.dart';

void main() {
  test('JMA information sound follows the P2P information stage', () {
    expect(
      NotificationService.infoSoundKeyForTest(_event(title: '震度速報')),
      'prompt',
    );
    expect(
      NotificationService.infoSoundKeyForTest(_event(title: '震源に関する情報')),
      'hypocenter',
    );
    expect(
      NotificationService.infoSoundKeyForTest(_event(title: '震源・震度に関する情報')),
      'detail',
    );
    expect(
      NotificationService.infoSoundKeyForTest(_event(title: '震度・震源に関する情報')),
      'detail',
    );
    expect(
      NotificationService.infoSoundKeyForTest(_event(title: '各地の震度に関する情報')),
      'detail',
    );
  });

  test('JMA cancellation always uses the cancellation sound', () {
    expect(
      NotificationService.infoSoundKeyForTest(
        _event(title: '震源・震度に関する情報', isCanceled: true),
      ),
      'cancel',
    );
  });
}

UnifiedQuakeData _event({required String title, bool isCanceled = false}) {
  return UnifiedQuakeData(
    source: 'jmaEqlist',
    origin: 3,
    eventId: '20260809140518',
    isEew: false,
    timeZone: 9,
    titleText: title,
    reportNumText: '第1報',
    useShindo: true,
    maxIntensity: '4',
    className: 'yellow',
    hypocenter: '千葉県北東部',
    magnitude: 4.2,
    depth: 10,
    isCanceled: isCanceled,
  );
}
