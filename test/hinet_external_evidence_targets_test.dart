import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Hi-net external evidence targets stay pending and source-bound', () {
    final file = File('docs/data/hinet_external_evidence_targets.json');
    expect(file.existsSync(), isTrue);

    final data = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    expect(data['schemaVersion'], 'hinet_external_evidence_targets_v1');
    expect(
      data['policy'],
      allOf(
        contains('pending external-evidence collection only'),
        contains('must not accept user-provided Hi-net text'),
        contains('EQuake source estimates as catalog truth'),
      ),
    );
    final sourceAvailabilityChecks = (data['sourceAvailabilityChecks'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(sourceAvailabilityChecks.length, 4);
    expect(
      sourceAvailabilityChecks.map((entry) => entry['sourceType']).toSet(),
      {
        'hinet_public_hypomap',
        'hinet_preliminary_catalog',
        'hinet_jma_unified_catalog',
        'hinet_data_policy',
      },
    );
    expect(
      sourceAvailabilityChecks
          .where((entry) => entry['accessStatus'] == 'login_required')
          .map((entry) => entry['sourceType'])
          .toSet(),
      {'hinet_preliminary_catalog', 'hinet_jma_unified_catalog'},
    );
    expect(
      sourceAvailabilityChecks.every(
        (entry) => entry['catalogAcceptance'] != 'accepted_event_evidence',
      ),
      isTrue,
    );

    final targets = (data['targets'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(targets.length, 3);
    expect(targets.map((entry) => entry['caseId']).toSet(), {
      '20260622_iwate_east_offshore_m30_hinet',
      '20260622_tomakomai_south_offshore_m35_hinet',
      '20260623_tokachi_southeast_offshore_m34_hinet',
    });

    for (final target in targets) {
      expect(target['status'], 'pending_external_evidence');
      expect(target['currentTruthQuality'], 'hinet_user_provided_preliminary');
      expect(target['fixturePath'], isA<String>());
      expect(File(target['fixturePath']! as String).existsSync(), isTrue);
      expect(target['captureDirectory'], isA<String>());
      expect(target['originTimeJst'], isA<String>());
      expect(target['originTimeUtcPlus8'], isA<String>());
      expect(target['latitude'], isA<num>());
      expect(target['longitude'], isA<num>());
      expect(target['depthKm'], isA<num>());
      expect(target['magnitude'], isA<num>());
      expect(
        target['requiredEvidence'],
        containsAll([
          'revised_hinet_or_jma_final_catalog_link',
          'reviewer_and_review_timestamp',
        ]),
      );
      expect(
        target['unacceptableSources'],
        containsAll([
          'user_provided_screenshot_or_text_without_external_link',
          'equake_source_estimate_as_truth',
          'local_capture_only_evidence',
        ]),
      );
      expect(
        target['acceptableSources'].toString(),
        allOf(contains('Hi-net'), contains('JMA')),
      );
      final findings = (target['externalEvidenceFindings'] as List)
          .map((entry) => (entry as Map).cast<String, Object?>())
          .toList(growable: false);
      expect(findings, isNotEmpty);
      for (final finding in findings) {
        expect(finding['sourceType'], 'jma_daily_hypocenter_list');
        expect(
          finding['sourceUrl'],
          startsWith('https://www.data.jma.go.jp/eqev/data/daily_map/'),
        );
        expect(finding['matchStatus'], 'time_and_location_match_found');
        expect(
          finding['catalogAcceptance'],
          'not_sufficient_final_catalog_or_hinet_revised_source',
        );
        expect(finding['checkedAtUtc'], isA<String>());
        expect(finding['originTimeJst'], isA<String>());
        expect(finding['latitude'], isA<num>());
        expect(finding['longitude'], isA<num>());
        expect(finding['depthKm'], isA<num>());
        expect(finding['magnitude'], isA<num>());
      }
    }
  });

  test(
    'external evidence targets mirror fixture truth without accepting it',
    () {
      final data =
          jsonDecode(
                File(
                  'docs/data/hinet_external_evidence_targets.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final targets = (data['targets'] as List).map(
        (entry) => (entry as Map).cast<String, Object?>(),
      );

      for (final target in targets) {
        final fixture =
            jsonDecode(
                  File(target['fixturePath']! as String).readAsStringSync(),
                )
                as Map<String, Object?>;
        final truth = (fixture['truth'] as Map).cast<String, Object?>();
        final classification = (fixture['classification'] as Map)
            .cast<String, Object?>();
        final labels = (fixture['eventLabels'] as Map).cast<String, Object?>();

        expect(target['originTimeJst'], truth['originTimeJst']);
        expect(target['latitude'], truth['latitude']);
        expect(target['longitude'], truth['longitude']);
        expect(target['depthKm'], truth['depthKm']);
        expect(target['magnitude'], truth['magnitude']);
        expect(target['captureDirectory'], fixture['captureDirectory']);
        expect(target['currentTruthQuality'], classification['truthQuality']);
        expect(labels['catalogTruthVerified'], isFalse);
        expect(labels['includeInDetectionMetrics'], isFalse);
        expect(fixture['splitStatus'], 'validation_reference');
      }
    },
  );

  test('daily JMA findings are not the accepted review evidence', () {
    final targetData =
        jsonDecode(
              File(
                'docs/data/hinet_external_evidence_targets.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final reviewData =
        jsonDecode(
              File(
                'docs/data/hinet_truth_quality_review_decisions.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final targets = (targetData['targets'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    final decisions = {
      for (final rawCase in reviewData['cases'] as List)
        ((rawCase as Map)['caseId'] as String): rawCase.cast<String, Object?>(),
    };

    for (final target in targets) {
      final decision = decisions[target['caseId']]!;
      expect(decision['decisionStatus'], 'accepted_constrained_reference');
      expect(decision['acceptedForConstrainedReferenceSplit'], isTrue);
      expect(
        decision['decisionImport'],
        containsPair('evidenceType', 'authenticated_hinet_export_row'),
      );
      final findings = (target['externalEvidenceFindings'] as List).map(
        (entry) => (entry as Map).cast<String, Object?>(),
      );
      expect(
        findings.every(
          (entry) =>
              entry['catalogAcceptance'] ==
              'not_sufficient_final_catalog_or_hinet_revised_source',
        ),
        isTrue,
      );
    }
  });

  test('authenticated Hi-net export request is event-row scoped', () {
    final targetData =
        jsonDecode(
              File(
                'docs/data/hinet_external_evidence_targets.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final exportData =
        jsonDecode(
              File(
                'docs/data/hinet_authenticated_export_request.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    expect(
      exportData['schemaVersion'],
      'hinet_authenticated_export_request_v1',
    );
    expect(exportData['policy'], contains('must not contain credentials'));

    final targetCaseIds = {
      for (final rawTarget in targetData['targets'] as List)
        (rawTarget as Map)['caseId'] as String,
    };
    final requests = (exportData['requests'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(requests.length, 6);
    expect(
      requests.map((entry) => entry['caseId']).toSet(),
      containsAll(targetCaseIds),
    );

    final requiredFields = (exportData['requiredExportFields'] as List)
        .map((entry) => entry.toString())
        .toSet();
    expect(
      requiredFields,
      containsAll({
        'sourceUrl',
        'sourceVersionOrPageDate',
        'checkedAtUtc',
        'reviewer',
        'rawRowText',
      }),
    );
    expect(
      exportData['rejectionRules'],
      containsAll([
        'reject_if_row_is_only_public_hypomap',
        'reject_if_row_is_only_jma_daily_hypocenter_list',
        'reject_if_row_is_equake_estimate',
      ]),
    );

    for (final request in requests) {
      expect(request['status'], 'pending_authenticated_export');
      expect(request['preferredSourceType'], 'hinet_jma_unified_catalog');
      expect(request['fallbackSourceType'], 'hinet_preliminary_catalog');
      final window = (request['queryWindowJst'] as Map).cast<String, Object?>();
      expect(DateTime.tryParse(window['start']! as String), isNotNull);
      expect(DateTime.tryParse(window['end']! as String), isNotNull);
      expect(request['targetLatitude'], isA<num>());
      expect(request['targetLongitude'], isA<num>());
      expect(request['targetDepthKm'], isA<num>());
      expect(request['targetMagnitude'], isA<num>());
    }
  });

  test(
    'authenticated Hi-net export rows are accepted only by review decision',
    () {
      final requestData =
          jsonDecode(
                File(
                  'docs/data/hinet_authenticated_export_request.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final rowData =
          jsonDecode(
                File(
                  'docs/data/hinet_authenticated_export_rows.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final reviewData =
          jsonDecode(
                File(
                  'docs/data/hinet_truth_quality_review_decisions.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;

      expect(rowData['schemaVersion'], 'hinet_authenticated_export_rows_v1');
      expect(rowData['policy'], contains('Pending rows are placeholders only'));
      expect(
        rowData['acceptedSourceTypes'],
        containsAll(['hinet_preliminary_catalog', 'hinet_jma_unified_catalog']),
      );

      final requestCaseIds = {
        for (final rawRequest in requestData['requests'] as List)
          (rawRequest as Map)['caseId'] as String,
      };
      final rows = (rowData['rows'] as List)
          .map((entry) => (entry as Map).cast<String, Object?>())
          .toList(growable: false);
      expect(rows.map((entry) => entry['caseId']).toSet(), requestCaseIds);

      final decisions = {
        for (final rawCase in reviewData['cases'] as List)
          ((rawCase as Map)['caseId'] as String): rawCase
              .cast<String, Object?>(),
      };
      final pendingRows = rows
          .where((entry) => entry['status'] == 'pending_export')
          .toList(growable: false);
      final submittedRows = rows
          .where((entry) => entry['status'] == 'submitted_for_review')
          .toList(growable: false);
      expect(pendingRows, isEmpty);
      expect(submittedRows, hasLength(6));

      for (final row in pendingRows) {
        expect(row['submittedRow'], isNull);
        expect(row['rejectionReason'], isNull);
        expect(row['decisionImpact'], 'none_pending_only');
      }
      for (final row in submittedRows) {
        expect(row['submittedRow'], isA<Map>());
        expect(row['rejectionReason'], isNull);
        expect(row['decisionImpact'], 'none_review_required');
      }
      for (final row in rows) {
        final decision = decisions[row['caseId']]!;
        expect(decision['decisionStatus'], 'accepted_constrained_reference');
        expect(decision['acceptedForConstrainedReferenceSplit'], isTrue);
        expect(
          decision['decisionImport'],
          containsPair('evidenceType', 'authenticated_hinet_export_row'),
        );
      }
    },
  );

  test('submitted authenticated export rows require source-bound fields', () {
    final rowData =
        jsonDecode(
              File(
                'docs/data/hinet_authenticated_export_rows.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final requiredFields = (rowData['submittedRowRequiredFields'] as List)
        .map((entry) => entry.toString())
        .toSet();
    final acceptedSourceTypes = (rowData['acceptedSourceTypes'] as List)
        .map((entry) => entry.toString())
        .toSet();

    final validSubmittedRow = <String, Object?>{
      'caseId': '20260622_iwate_east_offshore_m30_hinet',
      'sourceType': 'hinet_jma_unified_catalog',
      'sourceUrl': 'https://hinetwww11.bosai.go.jp/auth/JMA/?LANG=en',
      'sourceVersionOrPageDate': '2026-06-26 authenticated page',
      'checkedAtUtc': '2026-06-26T06:00:00Z',
      'reviewer': 'reviewer-id',
      'originTimeJst': '2026-06-22T11:26:50',
      'latitude': 39.91,
      'longitude': 142.347,
      'depthKm': 42.4,
      'magnitude': 3.0,
      'region': 'Iwate east offshore',
      'rawRowText': '2026-06-22 11:26:50 39.91 142.347 42.4 M3.0',
    };
    expect(
      _submittedExportRowErrors(
        validSubmittedRow,
        requiredFields,
        acceptedSourceTypes,
      ),
      isEmpty,
    );

    final missingRawText = Map<String, Object?>.from(validSubmittedRow)
      ..remove('rawRowText');
    expect(
      _submittedExportRowErrors(
        missingRawText,
        requiredFields,
        acceptedSourceTypes,
      ),
      contains('missing_required_field:rawRowText'),
    );

    final unsupportedSource = Map<String, Object?>.from(validSubmittedRow)
      ..['sourceType'] = 'jma_daily_hypocenter_list';
    expect(
      _submittedExportRowErrors(
        unsupportedSource,
        requiredFields,
        acceptedSourceTypes,
      ),
      contains('unsupported_source_type:jma_daily_hypocenter_list'),
    );
  });
}

List<String> _submittedExportRowErrors(
  Map<String, Object?> row,
  Set<String> requiredFields,
  Set<String> acceptedSourceTypes,
) {
  final errors = <String>[];
  for (final field in requiredFields) {
    final value = row[field];
    if (value == null || (value is String && value.trim().isEmpty)) {
      errors.add('missing_required_field:$field');
    }
  }
  final sourceType = row['sourceType']?.toString();
  if (sourceType != null && !acceptedSourceTypes.contains(sourceType)) {
    errors.add('unsupported_source_type:$sourceType');
  }
  if (row['sourceUrl']?.toString().startsWith('http') != true) {
    errors.add('source_url_not_http');
  }
  if (DateTime.tryParse(row['checkedAtUtc']?.toString() ?? '') == null) {
    errors.add('checked_at_not_parseable');
  }
  if (DateTime.tryParse(row['originTimeJst']?.toString() ?? '') == null) {
    errors.add('origin_time_not_parseable');
  }
  return errors;
}
