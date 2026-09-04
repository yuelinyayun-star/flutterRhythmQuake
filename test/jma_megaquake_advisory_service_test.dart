import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/jma_megaquake_advisory.dart';
import 'package:flutterrhythmquake/services/sources/jma_megaquake_advisory_service.dart';
import 'package:flutterrhythmquake/widgets/ui/jma_megaquake_sidebar_panel.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('parses VYSE50 megaquake warning keyword and body', () {
    final service = JmaMegaquakeAdvisoryService();
    addTearDown(service.dispose);
    final advisory = service.parseDetailForTesting(
      _vyse50Xml(),
      id: 'https://example.test/20191107_VYSE50_1.xml',
      detailUrl: 'https://example.test/vyse50.xml',
    );

    expect(advisory, isNotNull);
    expect(advisory!.eventId, '20191107140400');
    expect(advisory.telegramCode, 'VYSE50');
    expect(advisory.family, JmaMegaquakeFamily.nankai);
    expect(advisory.keyword, JmaMegaquakeKeyword.megaquakeWarning);
    expect(advisory.keywordLabel, '巨大地震警戒');
    expect(advisory.serialCode, '120');
    expect(advisory.serialName, '巨大地震警戒');
    expect(advisory.headline, contains('防災対応'));
    expect(advisory.bodyText, contains('モーメントマグニチュード'));
    expect(advisory.nextAdvisory, contains('南海トラフ地震関連解説情報'));
    expect(advisory.displayTitle, '南海トラフ地震臨時情報（巨大地震警戒）');
  });

  test('parses VYSE51 extra commentary and VYSE60 subsequent-quake watch', () {
    final service = JmaMegaquakeAdvisoryService();
    addTearDown(service.dispose);

    final commentary = service.parseDetailForTesting(
      _vyse51Xml(),
      id: 'https://example.test/20191107_VYSE51_2.xml',
    );
    expect(commentary, isNotNull);
    expect(commentary!.telegramCode, 'VYSE51');
    expect(commentary.keyword, JmaMegaquakeKeyword.extraCommentary);
    expect(commentary.serial, '2');
    expect(commentary.serialCode, '210');
    expect(commentary.displayTitle, '南海トラフ地震関連解説情報（第２号）');

    final watch = service.parseDetailForTesting(
      _vyse60Xml(),
      id: 'https://example.test/20191107_VYSE60_1.xml',
    );
    expect(watch, isNotNull);
    expect(watch!.telegramCode, 'VYSE60');
    expect(watch.family, JmaMegaquakeFamily.hokkaidoSanriku);
    expect(watch.keyword, JmaMegaquakeKeyword.subsequentQuakeWatch);
    expect(watch.displayTitle, '北海道・三陸沖後発地震注意情報');
  });

  test('skips training telegrams', () {
    final service = JmaMegaquakeAdvisoryService();
    addTearDown(service.dispose);
    expect(service.parseDetailForTesting(_vyse50Xml(status: '訓練')), isNull);
  });

  test('parses monthly VYSE52 routine commentary', () {
    final service = JmaMegaquakeAdvisoryService();
    addTearDown(service.dispose);
    final advisory = service.parseDetailForTesting(
      _vyse52Xml(),
      id: 'https://example.test/20191107_VYSE52_1.xml',
    );

    expect(advisory, isNotNull);
    expect(advisory!.telegramCode, 'VYSE52');
    expect(advisory.keyword, JmaMegaquakeKeyword.routineCommentary);
    expect(advisory.serialName, '定例解説');
    expect(advisory.serialCode, '200');
    expect(advisory.displayTitle, '南海トラフ地震関連解説情報');
    expect(advisory.keywordLabel, '定例解説');
    expect(
      advisory.isActive(now: DateTime.parse('2019-11-07T14:12:00+09:00')),
      isTrue,
    );
  });

  test('treats cancel as inactive and drops it from the sidebar cache', () {
    final now = DateTime.parse('2026-08-15T02:00:00+09:00');
    final service = JmaMegaquakeAdvisoryService(now: () => now);
    addTearDown(service.dispose);
    service.ingestForTesting(
      JmaMegaquakeAdvisory(
        id: 'nankai-1',
        eventId: '20260815010000',
        family: JmaMegaquakeFamily.nankai,
        telegramCode: 'VYSE50',
        keyword: JmaMegaquakeKeyword.megaquakeWarning,
        title: '南海トラフ地震臨時情報',
        reportTime: now,
        expiresAt: now.add(const Duration(days: 7)),
      ),
    );
    expect(service.active, hasLength(1));

    final canceled = service.parseDetailForTesting(
      _vyse50CancelXml(
        reportTime: '2026-08-15T02:00:01+09:00',
        eventId: '20260815010000',
      ),
    );
    expect(canceled, isNotNull);
    expect(canceled!.isCanceled, isTrue);
    expect(canceled.isActive(now: now), isFalse);

    service.ingestForTesting(canceled);
    expect(service.active, isEmpty);
  });

  test(
    'stale cancellation does not clear a newer report in the same family',
    () {
      final now = DateTime.parse('2026-08-15T02:00:00+09:00');
      final service = JmaMegaquakeAdvisoryService(now: () => now);
      addTearDown(service.dispose);
      service.ingestForTesting(
        JmaMegaquakeAdvisory(
          id: 'new',
          eventId: '20260815020000',
          family: JmaMegaquakeFamily.nankai,
          telegramCode: 'VYSE50',
          keyword: JmaMegaquakeKeyword.megaquakeWarning,
          title: '南海トラフ地震臨時情報',
          reportTime: now,
          expiresAt: now.add(const Duration(days: 7)),
        ),
      );

      service.ingestForTesting(
        service.parseDetailForTesting(
          _vyse50CancelXml(
            reportTime: '2026-08-15T01:59:59+09:00',
            eventId: '20260815010000',
          ),
        )!,
      );

      expect(service.active, hasLength(1));
      expect(service.active.single.eventId, '20260815020000');
    },
  );

  test('expires investigating after five minutes', () {
    final investigating = JmaMegaquakeAdvisory(
      id: 'inv',
      eventId: '20260815010000',
      family: JmaMegaquakeFamily.nankai,
      telegramCode: 'VYSE50',
      keyword: JmaMegaquakeKeyword.investigating,
      title: '南海トラフ地震臨時情報',
      reportTime: DateTime.parse('2026-08-15T01:00:00+09:00'),
      expiresAt: DateTime.parse(
        '2026-08-15T01:00:00+09:00',
      ).add(jmaMegaquakeTtl(JmaMegaquakeKeyword.investigating)),
    );
    expect(
      investigating.isActive(now: DateTime.parse('2026-08-15T01:04:00+09:00')),
      isTrue,
    );
    expect(
      investigating.isActive(now: DateTime.parse('2026-08-15T01:06:00+09:00')),
      isFalse,
    );
    expect(jmaMegaquakeTtl(JmaMegaquakeKeyword.megaquakeWarning).inMinutes, 5);
    expect(
      jmaMegaquakeTtl(JmaMegaquakeKeyword.subsequentQuakeWatch).inMinutes,
      5,
    );
    expect(jmaMegaquakeTtl(JmaMegaquakeKeyword.routineCommentary).inMinutes, 5);
    expect(JmaMegaquakeAdvisoryService.refreshInterval.inMinutes, 10);
  });

  test('feed parser keeps VYSE50/51/52/60 and drops volcano entries', () {
    final service = JmaMegaquakeAdvisoryService();
    addTearDown(service.dispose);
    final ids = service.targetEntryIdsForTesting('''
<feed>
  <entry>
    <id>https://www.data.jma.go.jp/developer/xml/data/20191107_VYSE50_1.xml</id>
    <title>南海トラフ地震臨時情報</title>
    <updated>2019-11-07T05:04:24Z</updated>
    <link href="https://example.test/vyse50.xml"/>
  </entry>
  <entry>
    <id>https://www.data.jma.go.jp/developer/xml/data/20191107_VYSE51_2.xml</id>
    <title>南海トラフ地震関連解説情報</title>
    <updated>2019-11-07T05:10:36Z</updated>
    <link href="https://example.test/vyse51.xml"/>
  </entry>
  <entry>
    <id>https://www.data.jma.go.jp/developer/xml/data/20191107_VYSE52_1.xml</id>
    <title>南海トラフ地震関連解説情報</title>
    <updated>2019-11-07T05:12:33Z</updated>
    <link href="https://example.test/vyse52.xml"/>
  </entry>
  <entry>
    <id>https://www.data.jma.go.jp/developer/xml/data/20191107_VYSE60_1.xml</id>
    <title>北海道・三陸沖後発地震注意情報</title>
    <updated>2019-11-07T05:20:00Z</updated>
    <link href="https://example.test/vyse60.xml"/>
  </entry>
  <entry>
    <id>https://www.data.jma.go.jp/developer/xml/data/20191107_VFVO50_1.xml</id>
    <title>噴火警報・予報</title>
    <updated>2019-11-07T05:00:00Z</updated>
    <link href="https://example.test/volcano.xml"/>
  </entry>
</feed>
''');

    expect(ids, [
      'https://www.data.jma.go.jp/developer/xml/data/20191107_VYSE50_1.xml',
      'https://www.data.jma.go.jp/developer/xml/data/20191107_VYSE51_2.xml',
      'https://www.data.jma.go.jp/developer/xml/data/20191107_VYSE52_1.xml',
      'https://www.data.jma.go.jp/developer/xml/data/20191107_VYSE60_1.xml',
    ]);
  });

  test('VYSE51 after a warning keeps the warning keyword in the sidebar', () {
    final service = JmaMegaquakeAdvisoryService();
    addTearDown(service.dispose);
    final now = DateTime.now().toUtc();
    service.ingestForTesting(
      JmaMegaquakeAdvisory(
        id: 'warn',
        eventId: '20260815010000',
        family: JmaMegaquakeFamily.nankai,
        telegramCode: 'VYSE50',
        keyword: JmaMegaquakeKeyword.megaquakeWarning,
        title: '南海トラフ地震臨時情報',
        serialName: '巨大地震警戒',
        serialCode: '120',
        headline: '巨大地震警戒を発表',
        reportTime: now,
        expiresAt: now.add(const Duration(days: 7)),
      ),
    );
    service.ingestForTesting(
      JmaMegaquakeAdvisory(
        id: 'note',
        eventId: '20260815010000',
        family: JmaMegaquakeFamily.nankai,
        telegramCode: 'VYSE51',
        keyword: JmaMegaquakeKeyword.extraCommentary,
        title: '南海トラフ地震関連解説情報',
        serial: '2',
        serialName: '臨時解説',
        serialCode: '210',
        headline: 'その後の状況を発表',
        bodyText: '地震活動は活発な状態が続いています。',
        reportTime: now.add(const Duration(hours: 6)),
        expiresAt: now.add(const Duration(days: 7)),
      ),
    );

    expect(service.active, hasLength(1));
    expect(service.active.single.keyword, JmaMegaquakeKeyword.megaquakeWarning);
    expect(service.active.single.telegramCode, 'VYSE51');
    expect(service.active.single.serialName, '臨時解説');
    expect(service.active.single.headline, 'その後の状況を発表');
  });

  test('monthly VYSE52 does not replace an active warning', () {
    final service = JmaMegaquakeAdvisoryService();
    addTearDown(service.dispose);
    final now = DateTime.now().toUtc();
    service.ingestForTesting(
      JmaMegaquakeAdvisory(
        id: 'warn',
        eventId: '20260815010000',
        family: JmaMegaquakeFamily.nankai,
        telegramCode: 'VYSE50',
        keyword: JmaMegaquakeKeyword.megaquakeWarning,
        title: '南海トラフ地震臨時情報',
        serialName: '巨大地震警戒',
        serialCode: '120',
        reportTime: now,
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
    );
    service.ingestForTesting(
      JmaMegaquakeAdvisory(
        id: 'monthly',
        eventId: '20260815020000',
        family: JmaMegaquakeFamily.nankai,
        telegramCode: 'VYSE52',
        keyword: JmaMegaquakeKeyword.routineCommentary,
        title: '南海トラフ地震関連解説情報',
        serialName: '定例解説',
        serialCode: '200',
        reportTime: now,
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
    );

    expect(service.active.single.keyword, JmaMegaquakeKeyword.megaquakeWarning);
    expect(service.active.single.telegramCode, 'VYSE50');
  });

  test(
    'fetchNow stores an active VYSE50 warning from the eqvol feed',
    () async {
      final origin = DateTime.now().toUtc().subtract(
        const Duration(minutes: 1),
      );
      final xml = _vyse50Xml(
        reportTime: _jstStamp(origin),
        eventId: '20260815010000',
      );
      final client = MockClient((request) async {
        if (request.url.path.endsWith('eqvol.xml')) {
          return http.Response.bytes(
            utf8.encode(_feedXml()),
            200,
            headers: const {'content-type': 'application/xml; charset=utf-8'},
          );
        }
        if (request.url.path.endsWith('vyse50.xml')) {
          return http.Response.bytes(
            utf8.encode(xml),
            200,
            headers: const {'content-type': 'application/xml; charset=utf-8'},
          );
        }
        return http.Response('missing', 404);
      });
      final service = JmaMegaquakeAdvisoryService(client: client);
      addTearDown(service.dispose);

      await service.fetchNow();

      expect(service.active, hasLength(1));
      expect(service.active.single.eventId, '20260815010000');
      expect(
        service.active.single.keyword,
        JmaMegaquakeKeyword.megaquakeWarning,
      );
    },
  );

  testWidgets('sidebar shows keyword, source and headline', (tester) async {
    final service = JmaMegaquakeAdvisoryService();
    addTearDown(service.dispose);
    final advisory = service.parseDetailForTesting(
      _vyse50Xml(),
      id: 'https://example.test/20191107_VYSE50_1.xml',
    )!;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            height: 320,
            child: JmaMegaquakeSidebarPanel(
              advisory: advisory,
              scale: (value) => value,
            ),
          ),
        ),
      ),
    );

    expect(find.text('巨大地震警戒'), findsWidgets);
    expect(find.text('南海トラフ地震臨時情報（巨大地震警戒）'), findsOneWidget);
    expect(find.textContaining('JMA · VYSE50'), findsOneWidget);
    expect(find.textContaining('防災対応'), findsWidgets);
  });
}

String _feedXml() {
  return '''
<feed>
  <entry>
    <id>https://www.data.jma.go.jp/developer/xml/data/20260815_VYSE50_1.xml</id>
    <title>南海トラフ地震臨時情報</title>
    <updated>2026-08-14T17:00:00Z</updated>
    <link href="https://example.test/vyse50.xml"/>
  </entry>
</feed>
''';
}

String _jstStamp(DateTime utc) {
  final jst = utc.toUtc().add(const Duration(hours: 9));
  String two(int number) => number.toString().padLeft(2, '0');
  return '${jst.year}-${two(jst.month)}-${two(jst.day)}T'
      '${two(jst.hour)}:${two(jst.minute)}:${two(jst.second)}+09:00';
}

String _vyse50Xml({
  String status = '通常',
  String reportTime = '2019-11-07T14:04:00+09:00',
  String eventId = '20191107140400',
}) {
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<Report xmlns="http://xml.kishou.go.jp/jmaxml1/">
  <Control>
    <Title>南海トラフ地震臨時情報</Title>
    <DateTime>2019-11-07T05:04:24Z</DateTime>
    <Status>$status</Status>
    <PublishingOffice>気象庁</PublishingOffice>
  </Control>
  <Head>
    <Title>南海トラフ地震臨時情報（巨大地震警戒）</Title>
    <ReportDateTime>$reportTime</ReportDateTime>
    <TargetDateTime>$reportTime</TargetDateTime>
    <EventID>$eventId</EventID>
    <InfoType>発表</InfoType>
    <Serial/>
    <InfoKind>南海トラフ地震に関連する情報</InfoKind>
    <Headline>
      <Text>本日14時04分ころの地震と南海トラフ地震との関連性について検討した結果、巨大地震警戒を発表します。今後の政府や自治体などからの呼びかけ等に応じた防災対応をとってください。</Text>
    </Headline>
  </Head>
  <Body>
    <EarthquakeInfo type="南海トラフ地震に関連する情報">
      <InfoKind>南海トラフ地震臨時情報</InfoKind>
      <InfoSerial codeType="地震関連情報番号コード">
        <Name>巨大地震警戒</Name>
        <Code>120</Code>
      </InfoSerial>
      <Text>本日14時04分に、駿河湾を震源とするＭ8.0の地震が発生しました。気象庁では、南海トラフ沿いの地震に関する評価検討会を臨時に開催し、この地震はモーメントマグニチュード8.0の地震と評価されました。</Text>
    </EarthquakeInfo>
    <NextAdvisory>今後は、「南海トラフ地震関連解説情報」で地殻活動の状況等を発表します。次回の情報発表は、17時頃を予定しています。</NextAdvisory>
  </Body>
</Report>
''';
}

String _vyse50CancelXml({
  String reportTime = '2019-11-07T14:10:00+09:00',
  String eventId = '20191107140400',
}) {
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<Report>
  <Control>
    <Title>南海トラフ地震臨時情報</Title>
    <Status>通常</Status>
  </Control>
  <Head>
    <Title>南海トラフ地震臨時情報（巨大地震警戒）</Title>
    <ReportDateTime>$reportTime</ReportDateTime>
    <EventID>$eventId</EventID>
    <InfoType>取消</InfoType>
    <Headline><Text>取消します。</Text></Headline>
  </Head>
</Report>
''';
}

String _vyse51Xml({String serialCode = '210'}) {
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<Report xmlns="http://xml.kishou.go.jp/jmaxml1/">
  <Control>
    <Title>南海トラフ地震関連解説情報</Title>
    <Status>通常</Status>
  </Control>
  <Head>
    <Title>南海トラフ地震関連解説情報（第２号）</Title>
    <ReportDateTime>2019-11-07T14:10:00+09:00</ReportDateTime>
    <EventID>20191107140900</EventID>
    <InfoType>発表</InfoType>
    <Serial>2</Serial>
    <Headline>
      <Text>昨日発生した地震のその後の状況を発表します。</Text>
    </Headline>
  </Head>
  <Body>
    <EarthquakeInfo type="南海トラフ地震に関連する情報">
      <InfoKind>南海トラフ地震関連解説情報</InfoKind>
      <InfoSerial codeType="地震関連情報番号コード">
        <Name>臨時解説</Name>
        <Code>$serialCode</Code>
      </InfoSerial>
      <Text>その後も地震活動は活発な状態が続いています。</Text>
    </EarthquakeInfo>
    <NextAdvisory>次回の情報発表は、8日14時頃を予定しています。</NextAdvisory>
  </Body>
</Report>
''';
}

String _vyse52Xml() {
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<Report xmlns="http://xml.kishou.go.jp/jmaxml1/">
  <Control>
    <Title>南海トラフ地震関連解説情報</Title>
    <Status>通常</Status>
  </Control>
  <Head>
    <Title>南海トラフ地震関連解説情報</Title>
    <ReportDateTime>2019-11-07T14:12:00+09:00</ReportDateTime>
    <EventID>20191107141200</EventID>
    <InfoType>発表</InfoType>
    <Headline>
      <Text>定例会合における調査結果を発表します。</Text>
    </Headline>
  </Head>
  <Body>
    <EarthquakeInfo type="南海トラフ地震に関連する情報">
      <InfoKind>南海トラフ地震関連解説情報</InfoKind>
      <InfoSerial codeType="地震関連情報番号コード">
        <Name>定例解説</Name>
        <Code>200</Code>
      </InfoSerial>
      <Text>特段の変化は観測されていません。</Text>
    </EarthquakeInfo>
  </Body>
</Report>
''';
}

String _vyse60Xml() {
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<Report xmlns="http://xml.kishou.go.jp/jmaxml1/">
  <Control>
    <Title>北海道・三陸沖後発地震注意情報</Title>
    <Status>通常</Status>
  </Control>
  <Head>
    <Title>北海道・三陸沖後発地震注意情報</Title>
    <ReportDateTime>2019-11-07T14:04:00+09:00</ReportDateTime>
    <EventID>20191107140400</EventID>
    <InfoType>発表</InfoType>
    <Headline>
      <Text>北海道の根室沖から三陸沖でＭ7.0以上の地震が発生し、後発地震に注意してください。</Text>
    </Headline>
  </Head>
  <Body>
    <EarthquakeInfo type="北海道・三陸沖後発地震注意情報">
      <InfoKind>北海道・三陸沖後発地震注意情報</InfoKind>
      <Text>今後1週間程度、大規模な後発地震に注意してください。</Text>
    </EarthquakeInfo>
  </Body>
</Report>
''';
}
