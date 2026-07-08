import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('JMA reference event candidates stay pending and reference-only', () {
    final file = File('docs/data/jma_reference_event_candidates.json');
    final data = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

    expect(data['schemaVersion'], 1);
    expect(data['datasetId'], 'jma_reference_event_candidates_v1');

    final events = (data['events'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(events, isNotEmpty);

    for (final event in events) {
      expect(event['source'], 'jma_source_and_intensity_information');
      final hasCapture = event['captureDirectory'] != null;
      if (hasCapture) {
        expect(event['status'], contains('capture_associated'));
      } else {
        expect(event['status'], contains('pending_capture'));
      }
      expect(event['truthQuality'], contains('pending_final_catalog'));
      expect(event['eventLabels'], contains('reference_only'));
      expect(
        event['eventLabels'],
        contains(hasCapture ? 'capture_associated' : 'pending_capture'),
      );

      final eqscReport = event['eqscReport'];
      final equakeReport = event['equakeReport'];
      final p2pquakeReport = event['p2pquakeReport'];
      expect(
        eqscReport != null || equakeReport != null || p2pquakeReport != null,
        isTrue,
        reason: '${event['eventId']} must retain final reference metadata',
      );
      if (eqscReport != null) {
        expect(eqscReport, isA<Map>());
        expect((eqscReport as Map)['isFinal'], isTrue);
      }
      if (equakeReport != null) {
        expect(equakeReport, isA<Map>());
        expect((equakeReport as Map)['isFinal'], isA<bool>());
        expect(equakeReport['source'], contains('EQuake'));
      }
      if (p2pquakeReport != null) {
        expect(p2pquakeReport, isA<Map>());
        expect((p2pquakeReport as Map)['source'], contains('P2PQuake'));
      }
    }

    final iwateM46 = events.singleWhere(
      (event) => event['eventId'] == '20260625_iwate_offshore_m46_jma_eqsc9',
    );
    expect(iwateM46['originTimeUtcPlus8'], '2026-06-26T00:11:51+08:00');
    expect(iwateM46['maxShindo'], 3);
    expect(iwateM46['magnitude'], 4.6);

    final yamanashiM26 = events.singleWhere(
      (event) =>
          event['eventId'] == '20260626_yamanashi_central_west_m26_jma_equake5',
    );
    expect(yamanashiM26['originTimeUtcPlus8'], '2026-06-26T14:41:13+08:00');
    expect(yamanashiM26['originTimeJst'], '2026-06-26T15:41:13+09:00');
    expect(yamanashiM26['maxShindo'], 1);
    expect(yamanashiM26['magnitude'], 2.6);
    expect(yamanashiM26['eventLabels'], contains('equake_reference'));
    final equakeReport = yamanashiM26['equakeReport'] as Map;
    expect(equakeReport['triggeredStationCount'], 102);
    expect(equakeReport['qualityRank'], 'A');
    expect(equakeReport['phaseCounts'], {'p': 29, 's': 57, 'other': 16});

    final yamanashiM56 = events.singleWhere(
      (event) =>
          event['eventId'] ==
          '20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21',
    );
    expect(yamanashiM56['originTimeUtcPlus8'], '2026-06-26T21:29:02+08:00');
    expect(yamanashiM56['originTimeJst'], '2026-06-26T22:29:02+09:00');
    expect(yamanashiM56['maxShindo'], 6);
    expect(yamanashiM56['maxShindoLabel'], '6-');
    expect(yamanashiM56['magnitude'], 5.6);
    expect(yamanashiM56['eventLabels'], contains('equake_non_final_snapshot'));
    expect(yamanashiM56['eventLabels'], contains('capture_associated'));
    expect(
      yamanashiM56['captureDirectory'],
      'tmp/captures/20260626_yamanashi_east_fuji_five_lakes_m56_jma_p2p',
    );
    final strongEquakeReport = yamanashiM56['equakeReport'] as Map;
    expect(strongEquakeReport['reportNumber'], 21);
    expect(strongEquakeReport['isFinal'], isFalse);
    expect(strongEquakeReport['magnitude'], 5.8);
    expect(strongEquakeReport['depthKm'], 17);
    expect(strongEquakeReport['observedMaxShindoLabel'], '5+');

    final yamanashiM33 = events.singleWhere(
      (event) =>
          event['eventId'] ==
          '20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8',
    );
    expect(yamanashiM33['originTimeUtcPlus8'], '2026-06-26T22:17:46+08:00');
    expect(yamanashiM33['originTimeJst'], '2026-06-26T23:17:46+09:00');
    expect(yamanashiM33['maxShindo'], 3);
    expect(yamanashiM33['magnitude'], 3.3);
    expect(yamanashiM33['eventLabels'], contains('aftershock_sequence'));
    expect(yamanashiM33['eventLabels'], contains('capture_associated'));
    expect(
      yamanashiM33['captureDirectory'],
      'tmp/captures/20260626_yamanashi_east_fuji_five_lakes_m33_jma_p2p',
    );
    final aftershockEquakeReport = yamanashiM33['equakeReport'] as Map;
    expect(aftershockEquakeReport['reportNumber'], 8);
    expect(aftershockEquakeReport['isFinal'], isTrue);
    expect(aftershockEquakeReport['triggeredStationCount'], 230);
    expect(aftershockEquakeReport['phaseCounts'], {
      'p': 90,
      's': 109,
      'other': 31,
    });

    final yamanashiM26P2p = events.singleWhere(
      (event) =>
          event['eventId'] ==
          '20260626_yamanashi_east_fuji_five_lakes_m26_jma_p2p',
    );
    expect(yamanashiM26P2p['originTimeJst'], '2026-06-26T23:04:00+09:00');
    expect(yamanashiM26P2p['latitude'], 35.6);
    expect(yamanashiM26P2p['longitude'], 139.0);
    expect(yamanashiM26P2p['depthKm'], 20);
    expect(yamanashiM26P2p['magnitude'], 2.6);
    expect(yamanashiM26P2p['maxShindo'], 1);
    expect(yamanashiM26P2p['eventLabels'], contains('capture_associated'));
    final m26P2pReport = yamanashiM26P2p['p2pquakeReport'] as Map;
    expect(m26P2pReport['id'], '6a3e8776e88ee598246bee20');
    expect(m26P2pReport['pointCount'], 2);

    final yamanashiM24P2p = events.singleWhere(
      (event) =>
          event['eventId'] ==
          '20260627_yamanashi_east_fuji_five_lakes_m24_jma_p2p',
    );
    expect(yamanashiM24P2p['originTimeJst'], '2026-06-27T00:33:00+09:00');
    expect(yamanashiM24P2p['originTimeUtcPlus8'], '2026-06-26T23:33:00+08:00');
    expect(yamanashiM24P2p['latitude'], 35.5);
    expect(yamanashiM24P2p['longitude'], 139.0);
    expect(yamanashiM24P2p['depthKm'], 20);
    expect(yamanashiM24P2p['magnitude'], 2.4);
    expect(yamanashiM24P2p['maxShindo'], 1);
    expect(yamanashiM24P2p['eventLabels'], contains('capture_associated'));
    final m24P2pReport = yamanashiM24P2p['p2pquakeReport'] as Map;
    expect(m24P2pReport['id'], '6a3e9c45e88ee598246bee24');
    expect(m24P2pReport['pointCount'], 1);
  });
}
