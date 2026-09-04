import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/tsunami_message.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/volcano_event_data.dart';
import 'package:flutterrhythmquake/models/typhoon_data.dart';
import 'package:flutterrhythmquake/models/jma_lpgm_bulletin.dart';
import 'package:flutterrhythmquake/models/jma_megaquake_advisory.dart';

void main() {
  test('unified payload keeps volcano-specific fields', () {
    final event = UnifiedQuakeData(
      source: 'whewsVolcano',
      origin: 3,
      eventId: 'vfvo-1',
      isEew: false,
      timeZone: 9,
      titleText: '火山情報',
      reportNumText: '',
      useShindo: false,
      maxIntensity: '-',
      className: 'orange',
      hypocenter: '桜島',
      volcanoEvent: VolcanoEventData(
        updates: 2,
        kindCode: 'VFVO53',
        kindName: '降灰予報',
        infoKind: '定時',
        infoTypeName: '発表',
        title: '桜島 降灰予報',
        volcanoName: '桜島',
        volcanoCode: '506',
        craterName: '南岳山頂火口',
        headline: '降灰が予想されます',
        activity: '',
        prevention: '',
        nextAdvisory: '',
        plumeDirection: '東',
        observation: '',
        winds: [VolcanoWindProfile(heightFt: 1000, degree: 90, speedKt: 12)],
        publishingOffice: '気象庁',
        ashfallWindows: [
          VolcanoAshfallWindow(
            label: '今後1時間',
            items: [
              VolcanoAshfallItem(
                phenomenon: '降灰',
                phenomenonCode: 'ash',
                areaNames: ['鹿児島市'],
                areaCodes: ['46201'],
                plumeDirection: '東',
                polygons: [
                  [VolcanoAshfallCoordinate(latitude: 31.6, longitude: 130.6)],
                ],
              ),
            ],
          ),
        ],
      ),
    );

    final restored = UnifiedQuakeData.fromMap(event.toMap());
    expect(restored.volcanoEvent?.kindCode, 'VFVO53');
    expect(restored.volcanoEvent?.winds.single.speedKt, 12);
    expect(
      restored
          .volcanoEvent
          ?.ashfallWindows
          .single
          .items
          .single
          .polygons
          .single
          .single
          .latitude,
      31.6,
    );
  });

  test('tsunami payload keeps areas and observations', () {
    final message = TsunamiMessage(
      source: TsunamiSource.nmefc,
      id: 'ts-1',
      reportTime: '2026-08-22 12:00:00',
      title: '海啸警报',
      titleText: '海啸警报发布',
      grade: TsunamiGrade.warning,
      areas: const [
        TsunamiAreaInfo(
          name: '测试海岸',
          grade: TsunamiGrade.warning,
          height: 1.2,
          description: '1.2m',
        ),
      ],
      observations: const [
        TsunamiObservationInfo(
          stationName: '站点A',
          location: '海岸',
          latitude: 30,
          longitude: 130,
          maxWaveHeight: '1.0m',
          maxWaveHeightMeters: 1,
        ),
      ],
    );

    final restored = TsunamiMessage.fromMap(message.toMap());
    expect(restored.source, TsunamiSource.nmefc);
    expect(restored.areas.single.height, 1.2);
    expect(restored.observations.single.stationName, '站点A');
  });

  test('foreground auxiliary models keep source fields', () {
    const typhoon = TyphoonData(
      tfid: '2510',
      name: '测试台风',
      enname: 'TEST',
      isActive: true,
      startTime: '2026-08-22 00:00:00',
      endTime: '',
      warnLevel: '黄色',
      centerLng: 130,
      centerLat: 25,
      land: const [],
      points: const [],
      ckposition: '海上',
      jl: '100',
    );
    final restoredTyphoon = TyphoonData.fromMap(typhoon.toMap());
    expect(restoredTyphoon?.tfid, '2510');
    expect(restoredTyphoon?.centerLat, 25);

    const bulletin = JmaLpgmBulletin(
      eventId: '202608220001',
      serial: 2,
      infoType: '发布',
      headline: '长周期地震动に関する観測情報',
      maxInt: '3',
      maxLgInt: 2,
      lgCategory: '1',
      latitude: 35,
      longitude: 140,
      depthKm: 20,
      magnitude: 6.2,
    );
    final restoredBulletin = JmaLpgmBulletin.fromMap(bulletin.toMap());
    expect(restoredBulletin.eventId, bulletin.eventId);
    expect(restoredBulletin.magnitude, 6.2);

    const advisory = JmaMegaquakeAdvisory(
      id: 'vyse-1',
      eventId: 'ev-1',
      family: JmaMegaquakeFamily.nankai,
      telegramCode: 'VYSE50',
      keyword: JmaMegaquakeKeyword.investigating,
      title: '南海トラフ地震臨時情報',
    );
    final restoredAdvisory = JmaMegaquakeAdvisory.fromMap(advisory.toMap());
    expect(restoredAdvisory.family, JmaMegaquakeFamily.nankai);
    expect(restoredAdvisory.keyword, JmaMegaquakeKeyword.investigating);
  });
}
