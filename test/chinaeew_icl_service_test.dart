import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutterrhythmquake/models/source_status.dart';
import 'package:flutterrhythmquake/models/eew_event_group.dart';
import 'package:flutterrhythmquake/services/quake_event_adapter.dart';
import 'package:flutterrhythmquake/services/sources/chinaeew_icl_service.dart';

void main() {
  final listBody = File(
    'test/fixtures/chinaeew_icl/list.json',
  ).readAsStringSync();
  final detailBody = File(
    'test/fixtures/chinaeew_icl/98943021.json',
  ).readAsStringSync();

  test('captured ICL reports preserve original fields and EEW identity', () {
    final list = jsonDecode(listBody) as Map<String, dynamic>;
    final detail = jsonDecode(detailBody) as Map<String, dynamic>;
    final rawSummary = Map<String, dynamic>.from((list['data'] as List).first);
    final rawReport = Map<String, dynamic>.from((detail['data'] as List).last);
    final originalSummary = jsonEncode(rawSummary);
    final originalReport = jsonEncode(rawReport);

    final summary = QuakeEventAdapter.convertChinaEewIcl(
      rawSummary,
      isSnapshot: true,
    )!;
    final report = QuakeEventAdapter.convertChinaEewIcl(rawReport)!;
    expect(summary.isEew, isTrue);
    expect(summary.isSnapshot, isTrue);
    expect(summary.maxIntensity, '-');
    expect(report.source, 'iclEew');
    expect(report.origin, QuakeEventAdapter.chinaEewIclOrigin);
    expect(report.eventId, rawReport['eventId'].toString());
    expect(report.reportNumText, '第${rawReport['updates']}报');
    expect(report.maxIntensity, '4.7');
    expect(report.sourcePayload, rawReport);
    expect(jsonEncode(rawSummary), originalSummary);
    expect(jsonEncode(rawReport), originalReport);
  });

  test('uses reported ICL intensity when present in the captured list', () {
    final list = jsonDecode(listBody) as Map<String, dynamic>;
    final raw = Map<String, dynamic>.from(
      (list['data'] as List).whereType<Map>().firstWhere(
        (entry) => entry['epiIntensity'] != null,
      ),
    );
    final event = QuakeEventAdapter.convertChinaEewIcl(raw)!;
    expect(
      event.maxIntensity,
      (raw['epiIntensity'] as num).toDouble().toStringAsFixed(1),
    );
    expect(event.sourcePayload, raw);
  });

  test('both ICL adapters normalize the same captured report identically', () {
    final detail = jsonDecode(detailBody) as Map<String, dynamic>;
    final raw = Map<String, dynamic>.from((detail['data'] as List).last);
    final original = jsonEncode(raw);

    final direct = QuakeEventAdapter.convertChinaEewIcl(raw)!;
    final jian = QuakeEventAdapter.convertJianIcl({
      'type': 'update',
      'Data': raw,
    })!;

    expect(jian.source, direct.source);
    expect(jian.eventId, direct.eventId);
    expect(jian.titleText, direct.titleText);
    expect(jian.hypocenter, direct.hypocenter);
    expect(jian.originTime, direct.originTime);
    expect(jian.reportTime, direct.reportTime);
    expect(jian.reportNumText, direct.reportNumText);
    expect(jian.maxIntensity, direct.maxIntensity);
    expect(jian.isWarn, direct.isWarn);
    expect(jian.sourcePayload, raw);
    expect(jsonEncode(raw), original);
  });

  test('first ICL copy of a report stays in history for either arrival order', () {
    final detail = jsonDecode(detailBody) as Map<String, dynamic>;
    final raw = Map<String, dynamic>.from((detail['data'] as List).last);
    final direct = QuakeEventAdapter.convertChinaEewIcl(raw)!;
    final jian = QuakeEventAdapter.convertJianIcl({
      'type': 'update',
      'Data': raw,
    })!;

    for (final first in [direct, jian]) {
      final second = identical(first, direct) ? jian : direct;
      final group = EewEventGroup(
        eventId: first.eventId,
        reports: [first],
        firstArrivedAt: first.arrivedAt!,
      );
      final afterDuplicate = group.addReport(second);
      expect(afterDuplicate.reportCount, 1);
      expect(afterDuplicate.latest.origin, first.origin);
      expect(afterDuplicate.latest.sourcePayload, raw);
    }
  });

  test('a higher ICL report from the other adapter advances history', () {
    final detail = jsonDecode(detailBody) as Map<String, dynamic>;
    final reports = detail['data'] as List;
    final previous = QuakeEventAdapter.convertChinaEewIcl(
      Map<String, dynamic>.from(reports[reports.length - 2] as Map),
    )!;
    final latest = QuakeEventAdapter.convertJianIcl({
      'type': 'update',
      'Data': reports.last,
    })!;
    final group = EewEventGroup(
      eventId: previous.eventId,
      reports: [previous],
      firstArrivedAt: previous.arrivedAt!,
    ).addReport(latest);

    expect(group.reportCount, 2);
    expect(group.latest.reportNumText, latest.reportNumText);
    expect(group.latest.origin, QuakeEventAdapter.jianIclOrigin);
  });

  test(
    'first list poll establishes baseline without replaying old warnings',
    () async {
      final service = ChinaEewIclService();
      service.disconnect();
      final originalClient = service.client;
      service.client = MockClient(
        (_) async => http.Response(
          listBody,
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      addTearDown(() {
        service.disconnect();
        service.client.close();
        service.client = originalClient;
      });
      final emitted = <String>[];
      final subscription = service.onUnifiedEvent.listen(
        (event) => emitted.add(event.eventId),
      );
      addTearDown(subscription.cancel);
      final connected = service.onDebugStateChanged.firstWhere(
        (_) => service.status == SourceStatus.connected,
      );
      service.connect();
      await connected.timeout(const Duration(seconds: 5));
      expect(
        service.listedEvents,
        (jsonDecode(listBody)['data'] as List).length,
      );
      expect(service.latestListedEvent?.isSnapshot, isTrue);
      expect(service.receivedReports, 0);
      expect(emitted, isEmpty);
    },
  );
}
