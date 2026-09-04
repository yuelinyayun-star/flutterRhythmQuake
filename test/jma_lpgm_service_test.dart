import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/jma_lpgm_bulletin.dart';
import 'package:flutterrhythmquake/services/sources/jma_lpgm_service.dart';
import 'package:flutterrhythmquake/widgets/ui/jma_lpgm_sidebar_panel.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('parses VXSE62 stations, class and hypocenter', () {
    final service = JmaLpgmService();
    addTearDown(service.dispose);
    final bulletin = service.parseDetailForTesting(_vxse62Xml());

    expect(bulletin, isNotNull);
    expect(bulletin!.eventId, '20170706100000');
    expect(bulletin.serial, 1);
    expect(bulletin.infoType, '発表');
    expect(bulletin.maxLgInt, 4);
    expect(bulletin.maxInt, '7');
    expect(bulletin.lgCategory, '4');
    expect(bulletin.hypocenter, '駿河湾');
    expect(bulletin.latitude, 35.0);
    expect(bulletin.longitude, 138.5);
    expect(bulletin.depthKm, 10);
    expect(bulletin.magnitude, 6.6);
    expect(bulletin.headline, contains('長周期地震動階級４'));
    expect(bulletin.regions.map((region) => region.name), contains('大阪府北部'));
    expect(bulletin.regionsAtMaxClass().map((region) => region.name), [
      '千葉県南部',
    ]);

    final station = bulletin.stations.single;
    expect(station.name, '大阪中央区大手前');
    expect(station.code, '2712800');
    expect(station.intensity, '4');
    expect(station.lgInt, 3);
    expect(station.sva, 79.4);
    expect(station.lgIntPerPeriod.map((item) => item.value), [3, 2]);
    expect(station.svaPerPeriod.first.value, 79.4);
    expect(station.area, '大阪府北部');
    expect(jmaLpgmCategoryLabel(bulletin.lgCategory), contains('震度偏低'));
  });

  test('skips training telegrams and treats cancel as inactive', () {
    final service = JmaLpgmService();
    addTearDown(service.dispose);
    expect(service.parseDetailForTesting(_vxse62Xml(status: '訓練')), isNull);

    final canceled = service.parseDetailForTesting(_vxse62CancelXml());
    expect(canceled, isNotNull);
    expect(canceled!.isCanceled, isTrue);
    expect(
      canceled.isActive(now: DateTime.parse('2017-07-06T10:30:00+09:00')),
      isFalse,
    );
  });

  test(
    'keeps a recent class-1 bulletin active and expires after one minute',
    () {
      final bulletin = JmaLpgmBulletin(
        eventId: '20260815010000',
        serial: 1,
        infoType: '発表',
        headline: '阶级1',
        maxInt: '4',
        maxLgInt: 1,
        lgCategory: '1',
        originTime: DateTime.parse('2026-08-15T01:00:00+09:00'),
      );

      expect(
        bulletin.isActive(now: DateTime.parse('2026-08-15T01:00:30+09:00')),
        isTrue,
      );
      expect(
        bulletin.isActive(now: DateTime.parse('2026-08-15T01:01:01+09:00')),
        isFalse,
      );
    },
  );

  test('feed parser keeps VXSE62 and drops volcano entries', () {
    final service = JmaLpgmService();
    addTearDown(service.dispose);
    final ids = service.lpgmEntryIdsForTesting('''
<feed>
  <entry>
    <id>https://www.data.jma.go.jp/developer/xml/data/20170706_VXSE62_1.xml</id>
    <title>長周期地震動に関する観測情報</title>
    <updated>2017-07-06T01:05:17Z</updated>
    <link href="https://example.test/vxse62.xml"/>
  </entry>
  <entry>
    <id>https://www.data.jma.go.jp/developer/xml/data/20170706_VFVO50_1.xml</id>
    <title>噴火警報・予報</title>
    <updated>2017-07-06T01:00:00Z</updated>
    <link href="https://example.test/volcano.xml"/>
  </entry>
</feed>
''');

    expect(ids, [
      'https://www.data.jma.go.jp/developer/xml/data/20170706_VXSE62_1.xml',
    ]);
  });

  test('fetchNow stores the latest active VXSE62 bulletin', () async {
    final origin = DateTime.now().toUtc().subtract(const Duration(minutes: 20));
    final xml = _vxse62Xml(
      originTime: _jstStamp(origin),
      reportTime: _jstStamp(
        DateTime.now().toUtc().subtract(const Duration(seconds: 20)),
      ),
    );
    final client = MockClient((request) async {
      if (request.url.path.endsWith('eqvol.xml')) {
        return http.Response.bytes(
          utf8.encode(_feedXml()),
          200,
          headers: const {'content-type': 'application/xml; charset=utf-8'},
        );
      }
      if (request.url.path.endsWith('vxse62.xml')) {
        return http.Response.bytes(
          utf8.encode(xml),
          200,
          headers: const {'content-type': 'application/xml; charset=utf-8'},
        );
      }
      return http.Response('missing', 404);
    });
    final service = JmaLpgmService(client: client);
    addTearDown(service.dispose);

    await service.fetchNow();

    expect(service.latest?.eventId, '20170706100000');
    expect(service.latest?.maxLgInt, 4);
    expect(service.latest?.stations.single.name, '大阪中央区大手前');
  });

  test('refetches and applies a same-Serial revised bulletin', () async {
    final now = DateTime.now().toUtc();
    var feedUpdated = _jstStamp(now);
    var detailXml = _vxse62Xml(
      originTime: _jstStamp(now.subtract(const Duration(minutes: 20))),
      reportTime: _jstStamp(now.subtract(const Duration(seconds: 20))),
    );
    var detailRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('eqvol.xml')) {
        return http.Response.bytes(
          utf8.encode(_feedXml(updated: feedUpdated)),
          200,
          headers: const {'content-type': 'application/xml; charset=utf-8'},
        );
      }
      if (request.url.path.endsWith('vxse62.xml')) {
        detailRequests++;
        return http.Response.bytes(utf8.encode(detailXml), 200);
      }
      return http.Response('missing', 404);
    });
    final service = JmaLpgmService(client: client);
    addTearDown(service.dispose);

    await service.fetchNow();
    final firstReportTime = service.latest?.reportTime;

    feedUpdated = _jstStamp(now.add(const Duration(minutes: 1)));
    detailXml = _vxse62Xml(
      originTime: _jstStamp(now.subtract(const Duration(minutes: 20))),
      reportTime: _jstStamp(now.subtract(const Duration(seconds: 10))),
    );
    await service.fetchNow();

    expect(detailRequests, 2);
    expect(service.latest?.serial, 1);
    expect(service.latest?.reportTime, isNot(firstReportTime));
  });

  testWidgets('sidebar shows official class, region and station', (
    tester,
  ) async {
    final service = JmaLpgmService();
    addTearDown(service.dispose);
    final bulletin = service.parseDetailForTesting(_vxse62Xml())!;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            height: 320,
            child: JmaLpgmSidebarPanel(
              bulletin: bulletin,
              scale: (value) => value,
            ),
          ),
        ),
      ),
    );

    expect(find.text('长周期地震动观测情报'), findsOneWidget);
    expect(find.textContaining('JMA · VXSE62'), findsOneWidget);
    expect(find.textContaining('最大阶级：4'), findsOneWidget);
    expect(find.textContaining('最大震度：7'), findsOneWidget);
    expect(find.textContaining('千葉県南部'), findsOneWidget);
    expect(find.textContaining('大阪中央区大手前'), findsOneWidget);
    expect(find.textContaining('震度4'), findsOneWidget);
  });
}

String _feedXml({String updated = '2017-07-06T01:05:17Z'}) {
  return '''
<feed>
  <entry>
    <id>https://www.data.jma.go.jp/developer/xml/data/20170706_VXSE62_1.xml</id>
    <title>長周期地震動に関する観測情報</title>
    <updated>$updated</updated>
    <link href="https://example.test/vxse62.xml"/>
  </entry>
</feed>
''';
}

String _vxse62CancelXml() {
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<Report>
  <Control>
    <Title>長周期地震動に関する観測情報</Title>
    <Status>通常</Status>
  </Control>
  <Head>
    <Title>長周期地震動に関する観測情報</Title>
    <ReportDateTime>2017-07-06T10:10:00+09:00</ReportDateTime>
    <EventID>20170706100000</EventID>
    <InfoType>取消</InfoType>
    <Serial>2</Serial>
    <Headline><Text>取消します。</Text></Headline>
  </Head>
</Report>
''';
}

String _jstStamp(DateTime utc) {
  final jst = utc.toUtc().add(const Duration(hours: 9));
  String two(int number) => number.toString().padLeft(2, '0');
  return '${jst.year}-${two(jst.month)}-${two(jst.day)}T'
      '${two(jst.hour)}:${two(jst.minute)}:${two(jst.second)}+09:00';
}

String _vxse62Xml({
  String status = '通常',
  String originTime = '2017-07-06T10:00:00+09:00',
  String reportTime = '2017-07-06T10:05:00+09:00',
}) {
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<Report xmlns="http://xml.kishou.go.jp/jmaxml1/">
  <Control>
    <Title>長周期地震動に関する観測情報</Title>
    <DateTime>2017-07-06T01:05:17Z</DateTime>
    <Status>$status</Status>
    <PublishingOffice>気象庁</PublishingOffice>
  </Control>
  <Head>
    <Title>長周期地震動に関する観測情報</Title>
    <ReportDateTime>$reportTime</ReportDateTime>
    <TargetDateTime>$reportTime</TargetDateTime>
    <EventID>20170706100000</EventID>
    <InfoType>発表</InfoType>
    <Serial>1</Serial>
    <InfoKind>長周期地震動に関する観測情報</InfoKind>
    <Headline>
      <Text>１１日０５時０７分ころの地震により、長周期地震動階級４を観測した地域があります。</Text>
      <Information type="長周期地震動に関する観測情報（細分区域）">
        <Item>
          <Kind><Name>長周期地震動階級4</Name></Kind>
          <Areas>
            <Area><Name>千葉県南部</Name><Code>342</Code></Area>
          </Areas>
        </Item>
      </Information>
    </Headline>
  </Head>
  <Body>
    <Earthquake>
      <OriginTime>$originTime</OriginTime>
      <Hypocenter>
        <Area>
          <Name>駿河湾</Name>
          <Code type="震央地名">485</Code>
          <jmx_eb:Coordinate description="北緯３５．０度 東経１３８．５度 深さ１０ｋｍ" datum="日本測地系">+35.0+138.5-10000/</jmx_eb:Coordinate>
        </Area>
      </Hypocenter>
      <jmx_eb:Magnitude type="Mj" description="Ｍ６．６">6.6</jmx_eb:Magnitude>
    </Earthquake>
    <Intensity>
      <Observation>
        <MaxInt>7</MaxInt>
        <MaxLgInt>4</MaxLgInt>
        <LgCategory>4</LgCategory>
        <Pref>
          <Name>千葉県</Name>
          <Code>12</Code>
          <MaxInt>7</MaxInt>
          <MaxLgInt>4</MaxLgInt>
          <Area>
            <Name>千葉県南部</Name>
            <Code>342</Code>
            <MaxInt>7</MaxInt>
            <MaxLgInt>4</MaxLgInt>
          </Area>
        </Pref>
        <Pref>
          <Name>大阪府</Name>
          <Code>27</Code>
          <MaxInt>4</MaxInt>
          <MaxLgInt>3</MaxLgInt>
          <Area>
            <Name>大阪府北部</Name>
            <Code>520</Code>
            <MaxInt>4</MaxInt>
            <MaxLgInt>3</MaxLgInt>
            <IntensityStation>
              <Name>大阪中央区大手前</Name>
              <Code>2712800</Code>
              <Int>4</Int>
              <LgInt>3</LgInt>
              <LgIntPerPeriod PeriodicBand="1" PeriodUnit="秒台">3</LgIntPerPeriod>
              <LgIntPerPeriod PeriodicBand="2" PeriodUnit="秒台">2</LgIntPerPeriod>
              <Sva>79.4</Sva>
              <SvaPerPeriod PeriodicBand="1" PeriodUnit="秒台">79.4</SvaPerPeriod>
              <SvaPerPeriod PeriodicBand="2" PeriodUnit="秒台">34.6</SvaPerPeriod>
            </IntensityStation>
          </Area>
        </Pref>
      </Observation>
    </Intensity>
    <Comments>
      <URI>https://www.data.jma.go.jp/eew/data/ltpgm/20170706100000/index.html</URI>
    </Comments>
  </Body>
</Report>
''';
}
