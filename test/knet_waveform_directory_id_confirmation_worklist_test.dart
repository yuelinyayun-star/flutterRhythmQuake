import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('directory id confirmation worklist tracks provisional overlaps', () {
    final reportFile = File(
      '.dart_tool/knet_waveform_directory_id_confirmation_worklist/report.json',
    );
    if (!reportFile.existsSync()) {
      markTestSkipped(
        'Missing directory id confirmation worklist. Run '
        '`dart run tools/build_knet_waveform_directory_id_confirmation_worklist.dart`.',
      );
      return;
    }

    final report =
        jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
    expect(
      report['schemaVersion'],
      'knet_waveform_directory_id_confirmation_worklist_v1',
    );
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['itemCount'], 8);
    expect(summary['directoryIdUnconfirmedCount'], 8);
    expect(summary['captureOnlyCount'], 0);

    final items = (report['items'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(items.first['caseId'], '20260621_iwate_offshore_m33_eq8');
    expect(items.first['priority'], 0);
    expect(items.first['readiness'], 'candidate_directory_id_unconfirmed');
    expect(items, hasLength(8));
    expect(
      items.map((item) => item['caseId']).toSet(),
      containsAll(<String>[
        '20260621_iwate_offshore_m33_eq8',
        '20260622_kushiro_offshore_m30_jma',
        '20260624_fukushima_aizu_m32_jma_eq5',
        '20260625_iwate_offshore_m32_jma',
        '20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21',
        '20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8',
        '20260627_fukushima_aizu_m36_jma_equake17',
        '20260628_iwate_offshore_m41_jma',
      ]),
    );
  });
}
