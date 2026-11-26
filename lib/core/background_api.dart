import 'app_edition.dart';

enum BackgroundEewFeed {
  cenc('大陆 CENC', 1),
  cea('大陆 CEA', 1),
  ceaPr('大陆 CEA-PR', 1),
  fujian('福建', 1),
  chongqing('重庆', 1),
  sichuan('四川', 1),
  cwa('台湾 CWA', 2),
  jma('日本 JMA', 4),
  kma('韩国 KMA', 0),
  sa('美国 ShakeAlert', 0),
  sasmex('墨西哥 SASMEX', 0),
  icl('大陆 ICL', 1),
  globalQuake('全球测站自动预警', 0);

  const BackgroundEewFeed(this.label, this.priorityRegion);
  final String label;
  final int priorityRegion;
}

enum BackgroundApi {
  wolfx('Wolfx', {
    BackgroundEewFeed.cenc,
    BackgroundEewFeed.cea,
    BackgroundEewFeed.fujian,
    BackgroundEewFeed.chongqing,
    BackgroundEewFeed.sichuan,
    BackgroundEewFeed.cwa,
    BackgroundEewFeed.jma,
  }),
  jian('JIAN', {
    BackgroundEewFeed.cea,
    BackgroundEewFeed.ceaPr,
    BackgroundEewFeed.cwa,
    BackgroundEewFeed.jma,
    BackgroundEewFeed.kma,
    BackgroundEewFeed.sa,
  }),
  whews('WHEWS', {
    BackgroundEewFeed.cea,
    BackgroundEewFeed.ceaPr,
    BackgroundEewFeed.cwa,
    BackgroundEewFeed.jma,
    BackgroundEewFeed.kma,
    BackgroundEewFeed.sa,
  }),
  fan('FAN Studio', {
    BackgroundEewFeed.cea,
    BackgroundEewFeed.ceaPr,
    BackgroundEewFeed.cwa,
    BackgroundEewFeed.jma,
    BackgroundEewFeed.kma,
    BackgroundEewFeed.sa,
  }),
  rhythm('Rhythm', {BackgroundEewFeed.kma, BackgroundEewFeed.sasmex}),
  kmaPews('KMA-PEWS', {BackgroundEewFeed.kma}),
  p2p('P2PQuake', {}, details: '日本地震情报、海啸情报'),
  fssn('FSSN', {}, details: '地震情报、震源机制解'),
  nowQuake('NowQuake', {}, details: 'CENC 烈度速报'),
  globalQuake('GlobalQuake', {BackgroundEewFeed.globalQuake}),
  jianIcl('JIAN ICL', {BackgroundEewFeed.icl}),
  chinaEewIcl('China_EEW ICL', {BackgroundEewFeed.icl});

  const BackgroundApi(this.label, this.feeds, {this.details});

  static const automaticPreferenceKey = 'background_api_automatic';
  static const manualSelectionPreferenceKey = 'background_api_manual_selection';

  final String label;
  final Set<BackgroundEewFeed> feeds;
  final String? details;

  bool get availableInEdition => switch (this) {
    globalQuake => AppEdition.hasGlobalQuake,
    jianIcl || chinaEewIcl => AppEdition.hasIcl,
    _ => true,
  };

  String get coverageLabel =>
      details ??
      '${feeds.length} 个 EEW 源 · ${feeds.map((feed) => feed.label).join('、')}';

  int get priorityRegions =>
      feeds.fold(0, (mask, feed) => mask | feed.priorityRegion);

  int feedMask({required bool priorityOnly}) => feeds.fold(
    0,
    (mask, feed) => priorityOnly && feed.priorityRegion == 0
        ? mask
        : mask | (1 << feed.index),
  );

  static Set<BackgroundApi> readManualSelection(List<String>? saved) => {
    for (final api in values)
      if (saved?.contains(api.name) ?? false) api,
  };
}
