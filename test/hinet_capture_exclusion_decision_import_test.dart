import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/import_hinet_capture_exclusion_decision.dart';

void main() {
  test('capture exclusion decision importer accepts reviewed payload', () {
    final decisions = _pendingDecisionsCopy();

    final payload = _validPayload();

    final errors = validateHinetCaptureExclusionDecisionInput(
      decisionsJson: decisions,
      inputJson: payload,
    );
    expect(errors, isEmpty);
  });

  test('capture exclusion decision importer rejects placeholders', () {
    final decisions = _pendingDecisionsCopy();
    final payload = _validPayload()
      ..['reviewedAtUtc'] = '<fill-reviewed-at-utc>';

    final errors = validateHinetCaptureExclusionDecisionInput(
      decisionsJson: decisions,
      inputJson: payload,
    );
    expect(errors, contains('unresolved_placeholder:reviewedAtUtc'));
    expect(errors, contains('reviewed_at_not_parseable'));
  });

  test('capture exclusion decision importer rejects auth material', () {
    final decisions = _pendingDecisionsCopy();
    final payload = _validPayload()..['cookie'] = 'do-not-store';

    final errors = validateHinetCaptureExclusionDecisionInput(
      decisionsJson: decisions,
      inputJson: payload,
    );
    expect(errors, contains('input_contains_sensitive_auth_material'));
  });

  test('capture exclusion decision dry-run does not mutate decisions', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'hinet_capture_exclusion_import_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    final decisionFile = File('${tempDir.path}/decisions.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(_pendingDecisionsCopy())}\n',
      );
    final inputFile = File('${tempDir.path}/exclusion.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(_validPayload())}\n',
      );
    final before = decisionFile.readAsStringSync();

    final command = Platform.isWindows ? 'cmd' : 'dart';
    final arguments = [
      if (Platform.isWindows) ...['/c', 'dart'],
      'run',
      'tools/import_hinet_capture_exclusion_decision.dart',
      '--decisions',
      decisionFile.path,
      '--input',
      inputFile.path,
      '--dry-run',
    ];
    final result = Process.runSync(command, arguments);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout.toString(), contains('dry-run'));
    expect(decisionFile.readAsStringSync(), before);
  });
}

Map<String, Object?> _pendingDecisionsCopy() {
  final decisions =
      jsonDecode(
        File(
          'docs/data/hinet_capture_provenance_review_decisions.json',
        ).readAsStringSync(),
      )
      as Map<String, Object?>;
  final cases = (decisions['cases'] as List)
      .map((entry) => (entry as Map).cast<String, Object?>())
      .toList(growable: true);
  cases[0]
    ..['decisionStatus'] = 'pending_capture_repair_or_exclusion'
    ..['reviewedAtUtc'] = null
    ..['reviewer'] = null
    ..['exclusionApproved'] = false
    ..['excludedFiles'] = <String>[]
    ..['exclusionReason'] = null;
  decisions['cases'] = cases;
  return decisions;
}

Map<String, Object?> _validPayload() => {
  '_captureIssue': {'captureFailedGifCount': 1, 'captureMissingFrameCount': 1},
  'caseId': '20260620_iwate_offshore_m34_ref',
  'decisionStatus': 'capture_frame_exclusion_approved',
  'reviewedAtUtc': '2026-06-26T12:00:00Z',
  'reviewer': 'manual-reviewer',
  'exclusionApproved': true,
  'excludedFiles': ['20260620212727.jma_b.gif', 'missing_frame_1'],
  'exclusionReason':
      'Reviewer confirmed this constrained split can exclude one missing GIF.',
};
