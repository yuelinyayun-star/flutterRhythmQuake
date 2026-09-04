import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/volcano_icon_assets.dart';
import 'package:flutterrhythmquake/models/jma_volcano_site.dart';
import 'package:flutterrhythmquake/models/volcano_event_data.dart';

VolcanoEventData _volcano({
  String kindCode = 'VFVO51',
  String kindName = '火山状况解说信息',
  String infoKind = '火山の状況に関する解説情報（臨時）',
  String title = '阿蘇山 火山の状況に関する解説情報（臨時）',
  String headline = '＜火口周辺警報（噴火警戒レベル２、火口周辺規制）が継続＞',
}) {
  return VolcanoEventData(
    updates: 12,
    kindCode: kindCode,
    kindName: kindName,
    infoKind: infoKind,
    infoTypeName: '発表',
    title: title,
    volcanoName: '阿蘇山',
    volcanoCode: '503',
    craterName: '',
    headline: headline,
    activity: '',
    prevention: '',
    nextAdvisory: '',
    plumeDirection: '',
    observation: '',
    winds: const [],
    publishingOffice: '福岡管区気象台',
  );
}

JmaVolcanoSite _site({int alertLevel = 2, bool hasProvisionalInfo = false}) {
  return JmaVolcanoSite(
    code: '503',
    nameJp: '阿蘇山',
    nameEn: 'Aso',
    latitude: 32.884,
    longitude: 131.104,
    levelOperation: false,
    alertLevel: alertLevel,
    hasWarning: alertLevel >= 2,
    hasRecentInfo: hasProvisionalInfo,
    hasRecentEruption: false,
    hasProvisionalInfo: hasProvisionalInfo,
  );
}

void main() {
  test('provisional commentary with 臨時 uses Temp.png', () {
    expect(
      VolcanoIconAssets.forVolcanoEvent(_volcano()),
      VolcanoIconAssets.provisional,
    );
  });

  test('VFVO51 routine Sakurajima commentary uses parsed level icon', () {
    final volcano = _volcano(
      kindName: '火山状况解说信息',
      infoKind: '火山の状況に関する解説情報',
      title: '桜島 火山の状況に関する解説情報',
      headline: '＜火口周辺警報（噴火警戒レベル３、入山規制）が継続＞',
    );
    expect(volcano.isProvisionalCommentary, isFalse);
    expect(volcano.isCommentaryInfo, isTrue);
    expect(volcano.parsedAlertLevel, 3);
    expect(
      VolcanoIconAssets.forVolcanoEvent(volcano),
      'assets/images/volcano/Lv3.png',
    );
  });

  test('VFVO51 without 臨時 and without level falls back to generic icon', () {
    final volcano = _volcano(
      infoKind: '火山の状況に関する解説情報',
      title: '桜島 火山の状況に関する解説情報',
      headline: '活動が継続しています。',
    );
    expect(volcano.isProvisionalCommentary, isFalse);
    expect(
      VolcanoIconAssets.forVolcanoEvent(volcano),
      VolcanoIconAssets.generic,
    );
  });

  test('non-provisional events keep level icons', () {
    expect(
      VolcanoIconAssets.forVolcanoEvent(
        _volcano(
          kindCode: 'VFVO52',
          kindName: '喷发相关火山观测报',
          infoKind: '噴火に関する火山観測報',
          title: '桜島 噴火に関する火山観測報',
          headline: '噴火が発生しました。',
        ),
      ),
      VolcanoIconAssets.generic,
    );
    expect(
      VolcanoIconAssets.forVolcanoEvent(
        _volcano(
          kindCode: 'VFVO50',
          kindName: '喷火警报',
          infoKind: '噴火警報',
          title: '桜島 噴火警報',
          headline: '噴火警戒レベル４（避難）',
        ),
      ),
      'assets/images/volcano/Lv4.png',
    );
  });

  test('map sites use Temp.png only when marked provisional', () {
    expect(
      VolcanoIconAssets.forSite(_site(hasProvisionalInfo: true)),
      VolcanoIconAssets.provisional,
    );
    expect(VolcanoIconAssets.forSite(_site()), 'assets/images/volcano/Lv2.png');
  });
}
