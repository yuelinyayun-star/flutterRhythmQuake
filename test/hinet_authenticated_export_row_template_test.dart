import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_hinet_authenticated_export_row_templates.dart';
import '../tools/import_hinet_authenticated_export_row.dart';

void main() {
  test('authenticated export row templates mirror pending rows safely', () {
    final report = buildHinetAuthenticatedExportRowTemplatesJson();

    expect(
      report['schemaVersion'],
      'hinet_authenticated_export_row_templates_v1',
    );
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);
    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['rowTemplateCount'], 0);
    expect(summary['manualReviewRequiredCount'], 0);
    expect(summary['automaticClearanceCount'], 0);
    expect(summary['credentialFieldCount'], 0);

    final templates = (report['templates'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(templates, isEmpty);
  });

  test('generated scratch template is not importable until filled', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'hinet_authenticated_export_row_templates_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    buildHinetAuthenticatedExportRowTemplatesJson(
      templateDirectory: tempDir.path,
    );

    // Build function is report-only; exercise the CLI output shape via the
    // checked-in template payload contract instead of writing files here.
    final templatePayload = {
      'caseId': '20260623_tokachi_southeast_offshore_m34_hinet',
      'sourceType': 'hinet_jma_unified_catalog',
      'sourceUrl': 'https://hinetwww11.bosai.go.jp/auth/JMA/?LANG=en',
      'sourceVersionOrPageDate': '<fill-authenticated-page-date-or-version>',
      'checkedAtUtc': '<fill-checked-at-utc>',
      'reviewer': '<fill-reviewer-id>',
      'originTimeJst': '<fill-catalog-origin-time-jst>',
      'latitude': null,
      'longitude': null,
      'depthKm': null,
      'magnitude': null,
      'region': '<fill-catalog-region>',
      'rawRowText': '<fill-verbatim-event-row-text>',
    };
    final rowsJson =
        jsonDecode(
              File(
                'docs/data/hinet_authenticated_export_rows.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;

    final errors = validateHinetAuthenticatedExportRowInput(
      rowsJson: rowsJson,
      inputJson: templatePayload,
    );

    expect(errors, contains('unresolved_placeholder:sourceVersionOrPageDate'));
    expect(errors, contains('checked_at_not_parseable'));
    expect(errors, contains('numeric_field_required:latitude'));
  });
}
