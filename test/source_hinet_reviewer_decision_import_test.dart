import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_hinet_evidence_review_report.dart';
import '../tools/build_source_hinet_reviewer_decision_staging_report.dart';
import '../tools/import_source_hinet_reviewer_decision.dart';

void main() {
  test('reviewer decision importer rejects pending evidence cases', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'source_hinet_reviewer_decision_import_pending_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
    final decisions = _pendingDecisionsJson();
    final staging = _pendingEvidenceStaging(
      tempDir,
      '20260623_tokachi_southeast_offshore_m34_hinet',
    );

    final errors = validateSourceHinetReviewerDecisionInput(
      decisionsJson: decisions,
      stagingJson: staging,
      inputJson: _validPayload(
        caseId: '20260623_tokachi_southeast_offshore_m34_hinet',
      ),
    );
    expect(
      errors,
      contains(
        'case_not_reviewer_decision_eligible:'
        '20260623_tokachi_southeast_offshore_m34_hinet',
      ),
    );
  });

  test('reviewer decision importer accepts eligible accepted payload', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'source_hinet_reviewer_decision_import_validate_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
    final decisions = _pendingDecisionsJson();
    final staging = _eligibleStaging(tempDir);

    final errors = validateSourceHinetReviewerDecisionInput(
      decisionsJson: decisions,
      stagingJson: staging,
      inputJson: _validPayload(),
    );
    expect(errors, isEmpty);
  });

  test('reviewer decision importer accepts eligible rejected payload', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'source_hinet_reviewer_decision_import_reject_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
    final decisions = _pendingDecisionsJson();
    final staging = _eligibleStaging(tempDir);
    final payload = _validPayload()
      ..['decisionStatus'] = 'rejected_constrained_reference'
      ..['acceptedForConstrainedReferenceSplit'] = false;

    final errors = validateSourceHinetReviewerDecisionInput(
      decisionsJson: decisions,
      stagingJson: staging,
      inputJson: payload,
    );
    expect(errors, isEmpty);
  });

  test('reviewer decision importer rejects auth material and unsafe flags', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'source_hinet_reviewer_decision_import_invalid_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
    final decisions = _pendingDecisionsJson();
    final staging = _eligibleStaging(tempDir);
    final payload = _validPayload()
      ..['reviewedAtUtc'] = '<fill-reviewed-at-utc>'
      ..['cookie'] = 'do-not-store'
      ..['splitAssignmentAllowed'] = true
      ..['metricPromotionAllowed'] = true;

    final errors = validateSourceHinetReviewerDecisionInput(
      decisionsJson: decisions,
      stagingJson: staging,
      inputJson: payload,
    );
    expect(errors, contains('input_contains_sensitive_auth_material'));
    expect(errors, contains('unresolved_placeholder:reviewedAtUtc'));
    expect(errors, contains('reviewed_at_not_parseable'));
    expect(errors, contains('split_assignment_allowed_must_be_false'));
    expect(errors, contains('metric_promotion_allowed_must_be_false'));
  });

  test('reviewer decision dry-run does not mutate decisions', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'source_hinet_reviewer_decision_import_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    final decisionFile = File('${tempDir.path}/decisions.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(_pendingDecisionsJson())}\n',
      );
    final stagingFile = File('${tempDir.path}/staging.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(_eligibleStaging(tempDir))}\n',
      );
    final inputFile = File('${tempDir.path}/decision.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(_validPayload())}\n',
      );
    final before = decisionFile.readAsStringSync();

    final command = Platform.isWindows ? 'cmd' : 'dart';
    final arguments = [
      if (Platform.isWindows) ...['/c', 'dart'],
      'run',
      'tools/import_source_hinet_reviewer_decision.dart',
      '--decisions',
      decisionFile.path,
      '--staging',
      stagingFile.path,
      '--input',
      inputFile.path,
      '--dry-run',
    ];
    final result = Process.runSync(command, arguments);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout.toString(), contains('dry-run'));
    expect(decisionFile.readAsStringSync(), before);
  });

  test('reviewer decision import updates only decision ledger', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'source_hinet_reviewer_decision_import_write_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    final decisionFile = File('${tempDir.path}/decisions.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(_pendingDecisionsJson())}\n',
      );
    final stagingFile = File('${tempDir.path}/staging.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(_eligibleStaging(tempDir))}\n',
      );
    final inputFile = File('${tempDir.path}/decision.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(_validPayload())}\n',
      );

    final command = Platform.isWindows ? 'cmd' : 'dart';
    final arguments = [
      if (Platform.isWindows) ...['/c', 'dart'],
      'run',
      'tools/import_source_hinet_reviewer_decision.dart',
      '--decisions',
      decisionFile.path,
      '--staging',
      stagingFile.path,
      '--input',
      inputFile.path,
    ];
    final result = Process.runSync(command, arguments);
    expect(result.exitCode, 0, reason: result.stderr.toString());

    final updated =
        jsonDecode(decisionFile.readAsStringSync()) as Map<String, Object?>;
    final cases = (updated['cases'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    final decision = cases.firstWhere(
      (entry) => entry['caseId'] == _validPayload()['caseId'],
    );
    expect(decision['decisionStatus'], 'accepted_constrained_reference');
    expect(decision['acceptedForConstrainedReferenceSplit'], isTrue);
    final importMeta = (decision['decisionImport'] as Map)
        .cast<String, Object?>();
    expect(importMeta['splitAssignmentAllowed'], isFalse);
    expect(importMeta['metricPromotionAllowed'], isFalse);
  });
}

Map<String, Object?> _eligibleStaging(Directory tempDir) {
  final evidenceReview = buildSourceHinetEvidenceReviewReportJson();
  final cases = (evidenceReview['cases'] as List)
      .map((entry) => (entry as Map).cast<String, Object?>())
      .toList(growable: false);
  cases[0]
    ..['combinedEvidenceStatus'] = 'authenticated_hinet_export_row_ready'
    ..['readyEvidenceTypes'] = ['authenticated_hinet_export_row'];
  evidenceReview['cases'] = cases;
  final tempFile = File('${tempDir.path}/evidence.json')
    ..writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(evidenceReview)}\n',
    );
  final decisionsFile = _pendingDecisionsFile(tempDir);
  return buildSourceHinetReviewerDecisionStagingReportJson(
    evidenceReviewPath: tempFile.path,
    decisionPath: decisionsFile.path,
  );
}

Map<String, Object?> _pendingEvidenceStaging(
  Directory tempDir,
  String pendingCaseId,
) {
  final evidenceReview = buildSourceHinetEvidenceReviewReportJson();
  final cases = (evidenceReview['cases'] as List)
      .map((entry) => (entry as Map).cast<String, Object?>())
      .toList(growable: false);
  for (final entry in cases) {
    if (entry['caseId'] != pendingCaseId) continue;
    entry
      ..['combinedEvidenceStatus'] = 'pending_evidence'
      ..['readyEvidenceTypes'] = <String>[];
  }
  evidenceReview['cases'] = cases;
  final tempFile = File('${tempDir.path}/pending_evidence.json')
    ..writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(evidenceReview)}\n',
    );
  final decisionsFile = _pendingDecisionsFile(tempDir);
  return buildSourceHinetReviewerDecisionStagingReportJson(
    evidenceReviewPath: tempFile.path,
    decisionPath: decisionsFile.path,
  );
}

Map<String, Object?> _pendingDecisionsJson() {
  final decisions =
      jsonDecode(
            File(
              'docs/data/hinet_truth_quality_review_decisions.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  decisions['cases'] = (decisions['cases'] as List)
      .map((entry) {
        final item = (entry as Map).cast<String, Object?>();
        return {
          ...item,
          'decisionStatus': 'pending_manual_review',
          'acceptedForConstrainedReferenceSplit': false,
          'reviewedAtUtc': null,
          'reviewer': null,
          'evidence': <String>[],
        }..remove('decisionImport');
      })
      .toList(growable: false);
  return decisions;
}

File _pendingDecisionsFile(Directory tempDir) {
  return File('${tempDir.path}/decisions.json')..writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(_pendingDecisionsJson())}\n',
  );
}

Map<String, Object?> _validPayload({
  String caseId = '20260622_iwate_east_offshore_m30_hinet',
}) => {
  'caseId': caseId,
  'decisionStatus': 'accepted_constrained_reference',
  'reviewedAtUtc': '2026-06-27T01:00:00Z',
  'reviewer': 'manual-reviewer',
  'evidenceType': 'authenticated_hinet_export_row',
  'evidence': [
    'Authenticated Hi-net/JMA event-level row matches the reference case.',
  ],
  'notes': 'Accepted for constrained source-estimation reference review only.',
  'acceptedForConstrainedReferenceSplit': true,
  'splitAssignmentAllowed': false,
  'metricPromotionAllowed': false,
};
