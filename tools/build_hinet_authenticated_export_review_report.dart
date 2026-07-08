import 'dart:convert';
import 'dart:io';

const _defaultRequestPath = 'docs/data/hinet_authenticated_export_request.json';
const _defaultRowsPath = 'docs/data/hinet_authenticated_export_rows.json';
const _defaultDecisionPath =
    'docs/data/hinet_truth_quality_review_decisions.json';
const _defaultOutput =
    '.dart_tool/hinet_authenticated_export_review/report.json';
const _defaultMarkdown =
    'docs/baselines/hinet_authenticated_export_review.generated.md';

void main(List<String> args) {
  final requestPath = _argument(args, '--requests') ?? _defaultRequestPath;
  final rowsPath = _argument(args, '--rows') ?? _defaultRowsPath;
  final decisionPath = _argument(args, '--decisions') ?? _defaultDecisionPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = _AuthenticatedExportReviewReport.build(
    requestFile: File(requestPath),
    rowsFile: File(rowsPath),
    decisionFile: File(decisionPath),
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote Hi-net authenticated export review report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report.errors.isNotEmpty) {
    exitCode = 1;
  }
}

Map<String, Object?> buildHinetAuthenticatedExportReviewJson({
  String requestPath = _defaultRequestPath,
  String rowsPath = _defaultRowsPath,
  String decisionPath = _defaultDecisionPath,
}) {
  return _AuthenticatedExportReviewReport.build(
    requestFile: File(requestPath),
    rowsFile: File(rowsPath),
    decisionFile: File(decisionPath),
  ).toJson();
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

class _AuthenticatedExportReviewReport {
  final String requestPath;
  final String rowsPath;
  final String decisionPath;
  final List<_ExportReviewCase> cases;
  final List<String> errors;
  final List<String> warnings;

  const _AuthenticatedExportReviewReport({
    required this.requestPath,
    required this.rowsPath,
    required this.decisionPath,
    required this.cases,
    required this.errors,
    required this.warnings,
  });

  factory _AuthenticatedExportReviewReport.build({
    required File requestFile,
    required File rowsFile,
    required File decisionFile,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    final requests = _AuthenticatedExportRequests.read(requestFile, errors);
    final decisions = _ReviewDecisions.read(decisionFile, errors);
    final rows = _AuthenticatedExportRows.read(rowsFile, errors);

    final cases = <_ExportReviewCase>[];
    final requestCaseIds = requests.byCaseId.keys.toSet();
    final rowCaseIds = rows.rows.map((item) => item.caseId).toSet();
    if (requestCaseIds.length != rowCaseIds.length ||
        !requestCaseIds.containsAll(rowCaseIds)) {
      errors.add('authenticated_export_rows_do_not_match_requests');
    }

    for (final row in rows.rows) {
      cases.add(
        _ExportReviewCase.fromRow(
          row,
          requests.byCaseId[row.caseId],
          decisions.byCaseId[row.caseId],
          rows.requiredFields,
          rows.acceptedSourceTypes,
        ),
      );
    }

    for (final caseId in requestCaseIds) {
      if (!rowCaseIds.contains(caseId)) {
        errors.add('authenticated_export_row_missing:$caseId');
      }
    }

    cases.sort((left, right) => left.caseId.compareTo(right.caseId));

    return _AuthenticatedExportReviewReport(
      requestPath: requestFile.path,
      rowsPath: rowsFile.path,
      decisionPath: decisionFile.path,
      cases: cases,
      errors: errors,
      warnings: warnings,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': 'hinet_authenticated_export_review_v1',
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'status': errors.isEmpty ? 'pass' : 'fail',
      'requestPath': requestPath,
      'rowsPath': rowsPath,
      'decisionPath': decisionPath,
      'summary': {
        'rowCount': cases.length,
        'pendingExportCount': cases
            .where((item) => item.rowStatus == 'pending_export')
            .length,
        'submittedForReviewCount': cases
            .where((item) => item.rowStatus == 'submitted_for_review')
            .length,
        'rejectedCount': cases
            .where((item) => item.rowStatus == 'rejected')
            .length,
        'validSubmittedRowCount': cases
            .where((item) => item.submittedRowValid)
            .length,
        'decisionEvidenceReadyCount': cases
            .where((item) => item.decisionEvidenceReady)
            .length,
        'pendingDecisionCount': cases
            .where((item) => item.decisionStatus == 'pending_manual_review')
            .length,
        'acceptedDecisionCount': cases
            .where((item) => item.acceptedForConstrainedReferenceSplit)
            .length,
        'validationErrorCount': cases.fold<int>(
          0,
          (total, item) => total + item.validationErrors.length,
        ),
      },
      'errors': errors,
      'warnings': warnings,
      'cases': cases.map((item) => item.toJson()).toList(),
    };
  }

  String toMarkdown() {
    final json = toJson();
    final summary = (json['summary'] as Map).cast<String, Object?>();
    final buffer = StringBuffer()
      ..writeln('# Hi-net Authenticated Export Review')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Request file: `$requestPath`')
      ..writeln('- Rows file: `$rowsPath`')
      ..writeln('- Decision file: `$decisionPath`')
      ..writeln('- Rows: `${summary['rowCount']}`')
      ..writeln('- Pending exports: `${summary['pendingExportCount']}`')
      ..writeln(
        '- Submitted for review: `${summary['submittedForReviewCount']}`',
      )
      ..writeln('- Rejected: `${summary['rejectedCount']}`')
      ..writeln(
        '- Valid submitted rows: `${summary['validSubmittedRowCount']}`',
      )
      ..writeln(
        '- Decision-evidence ready: '
        '`${summary['decisionEvidenceReadyCount']}`',
      )
      ..writeln('- Pending decisions: `${summary['pendingDecisionCount']}`')
      ..writeln('- Accepted decisions: `${summary['acceptedDecisionCount']}`')
      ..writeln()
      ..writeln('## Validation')
      ..writeln()
      ..writeln(
        errors.isEmpty
            ? '- Errors: none'
            : '- Errors: `${errors.join('`, `')}`',
      )
      ..writeln(
        warnings.isEmpty
            ? '- Warnings: none'
            : '- Warnings: `${warnings.join('`, `')}`',
      )
      ..writeln()
      ..writeln('## Cases')
      ..writeln()
      ..writeln(
        '| Case | Row status | Submitted valid | Evidence ready | Decision | Errors |',
      )
      ..writeln('| --- | --- | --- | --- | --- | --- |');
    for (final item in cases) {
      buffer.writeln(
        '| `${item.caseId}` | `${item.rowStatus}` | '
        '${item.submittedRowValid ? 'yes' : 'no'} | '
        '${item.decisionEvidenceReady ? 'yes' : 'no'} | '
        '`${item.decisionStatus}` | '
        '`${item.validationErrors.join('`, `')}` |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Decision')
      ..writeln()
      ..writeln(
        '- This report does not modify '
        '`docs/data/hinet_truth_quality_review_decisions.json`.',
      )
      ..writeln(
        '- A valid submitted row only becomes `decisionEvidenceReady=true`; '
        'a reviewer still has to explicitly copy it into the decision ledger.',
      );
    return buffer.toString();
  }
}

class _ExportReviewCase {
  final String caseId;
  final String rowStatus;
  final String decisionStatus;
  final bool acceptedForConstrainedReferenceSplit;
  final bool submittedRowValid;
  final bool decisionEvidenceReady;
  final List<String> validationErrors;
  final Map<String, Object?>? evidenceCandidate;

  const _ExportReviewCase({
    required this.caseId,
    required this.rowStatus,
    required this.decisionStatus,
    required this.acceptedForConstrainedReferenceSplit,
    required this.submittedRowValid,
    required this.decisionEvidenceReady,
    required this.validationErrors,
    required this.evidenceCandidate,
  });

  factory _ExportReviewCase.fromRow(
    _ExportRow row,
    _ExportRequest? request,
    _Decision? decision,
    Set<String> requiredFields,
    Set<String> acceptedSourceTypes,
  ) {
    final validationErrors = <String>[];
    if (request == null) {
      validationErrors.add('request_missing_for_row:${row.caseId}');
    }
    if (decision == null) {
      validationErrors.add('decision_missing_for_row:${row.caseId}');
    }

    var submittedRowValid = false;
    Map<String, Object?>? evidenceCandidate;
    if (row.status == 'pending_export') {
      if (row.submittedRow != null) {
        validationErrors.add('pending_row_must_not_have_submitted_row');
      }
    } else if (row.status == 'rejected') {
      if (row.rejectionReason == null || row.rejectionReason!.trim().isEmpty) {
        validationErrors.add('rejected_row_missing_rejection_reason');
      }
    } else if (row.status == 'submitted_for_review') {
      if (row.submittedRow == null) {
        validationErrors.add('submitted_row_missing_payload');
      } else {
        validationErrors.addAll(
          _submittedRowErrors(
            row.submittedRow!,
            row.caseId,
            requiredFields,
            acceptedSourceTypes,
          ),
        );
        submittedRowValid = validationErrors.isEmpty;
        if (submittedRowValid) {
          evidenceCandidate = {
            'type': 'authenticated_hinet_export_row',
            'sourceType': row.submittedRow!['sourceType'],
            'sourceUrl': row.submittedRow!['sourceUrl'],
            'sourceVersionOrPageDate':
                row.submittedRow!['sourceVersionOrPageDate'],
            'checkedAtUtc': row.submittedRow!['checkedAtUtc'],
            'reviewer': row.submittedRow!['reviewer'],
            'originTimeJst': row.submittedRow!['originTimeJst'],
            'latitude': row.submittedRow!['latitude'],
            'longitude': row.submittedRow!['longitude'],
            'depthKm': row.submittedRow!['depthKm'],
            'magnitude': row.submittedRow!['magnitude'],
            'region': row.submittedRow!['region'],
            'rawRowText': row.submittedRow!['rawRowText'],
          };
        }
      }
    } else {
      validationErrors.add('unsupported_row_status:${row.status}');
    }

    final decisionStatus = decision?.decisionStatus ?? 'missing_decision';
    return _ExportReviewCase(
      caseId: row.caseId,
      rowStatus: row.status,
      decisionStatus: decisionStatus,
      acceptedForConstrainedReferenceSplit:
          decision?.acceptedForConstrainedReferenceSplit ?? false,
      submittedRowValid: submittedRowValid,
      decisionEvidenceReady:
          submittedRowValid &&
          decisionStatus == 'pending_manual_review' &&
          !(decision?.acceptedForConstrainedReferenceSplit ?? false),
      validationErrors: validationErrors,
      evidenceCandidate: evidenceCandidate,
    );
  }

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'rowStatus': rowStatus,
    'decisionStatus': decisionStatus,
    'acceptedForConstrainedReferenceSplit':
        acceptedForConstrainedReferenceSplit,
    'submittedRowValid': submittedRowValid,
    'decisionEvidenceReady': decisionEvidenceReady,
    'validationErrors': validationErrors,
    'evidenceCandidate': evidenceCandidate,
  };
}

List<String> _submittedRowErrors(
  Map<String, Object?> row,
  String outerCaseId,
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
  if (row['caseId'] != outerCaseId) {
    errors.add('submitted_case_id_mismatch');
  }
  final sourceType = row['sourceType']?.toString();
  if (sourceType != null && !acceptedSourceTypes.contains(sourceType)) {
    errors.add('unsupported_source_type:$sourceType');
  }
  if (row['sourceUrl']?.toString().startsWith('https://') != true) {
    errors.add('source_url_must_be_https');
  }
  if (DateTime.tryParse(row['checkedAtUtc']?.toString() ?? '') == null) {
    errors.add('checked_at_not_parseable');
  }
  if (DateTime.tryParse(row['originTimeJst']?.toString() ?? '') == null) {
    errors.add('origin_time_not_parseable');
  }
  for (final field in const ['latitude', 'longitude', 'depthKm', 'magnitude']) {
    if (row[field] is! num) {
      errors.add('numeric_field_required:$field');
    }
  }
  return errors;
}

class _AuthenticatedExportRequests {
  final Map<String, _ExportRequest> byCaseId;

  const _AuthenticatedExportRequests(this.byCaseId);

  static _AuthenticatedExportRequests read(File file, List<String> errors) {
    if (!file.existsSync()) {
      errors.add('authenticated_export_request_missing:${file.path}');
      return const _AuthenticatedExportRequests({});
    }
    final data = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    if (data['schemaVersion'] != 'hinet_authenticated_export_request_v1') {
      errors.add('unexpected_authenticated_export_request_schema');
    }
    return _AuthenticatedExportRequests({
      for (final raw in _list(data['requests']))
        _map(raw)['caseId'].toString(): _ExportRequest(_map(raw)),
    });
  }
}

class _ExportRequest {
  final Map<String, Object?> json;

  const _ExportRequest(this.json);
}

class _AuthenticatedExportRows {
  final Set<String> acceptedSourceTypes;
  final Set<String> requiredFields;
  final List<_ExportRow> rows;

  const _AuthenticatedExportRows({
    required this.acceptedSourceTypes,
    required this.requiredFields,
    required this.rows,
  });

  static _AuthenticatedExportRows read(File file, List<String> errors) {
    if (!file.existsSync()) {
      errors.add('authenticated_export_rows_missing:${file.path}');
      return const _AuthenticatedExportRows(
        acceptedSourceTypes: {},
        requiredFields: {},
        rows: [],
      );
    }
    final data = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    if (data['schemaVersion'] != 'hinet_authenticated_export_rows_v1') {
      errors.add('unexpected_authenticated_export_rows_schema');
    }
    return _AuthenticatedExportRows(
      acceptedSourceTypes: _list(
        data['acceptedSourceTypes'],
      ).map((item) => item.toString()).toSet(),
      requiredFields: _list(
        data['submittedRowRequiredFields'],
      ).map((item) => item.toString()).toSet(),
      rows: _list(
        data['rows'],
      ).map((item) => _ExportRow.fromJson(_map(item))).toList(growable: false),
    );
  }
}

class _ExportRow {
  final String caseId;
  final String status;
  final Map<String, Object?>? submittedRow;
  final String? rejectionReason;

  const _ExportRow({
    required this.caseId,
    required this.status,
    required this.submittedRow,
    required this.rejectionReason,
  });

  factory _ExportRow.fromJson(Map<String, Object?> json) {
    final rawSubmitted = json['submittedRow'];
    return _ExportRow(
      caseId: json['caseId']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      submittedRow: rawSubmitted is Map
          ? rawSubmitted.cast<String, Object?>()
          : null,
      rejectionReason: json['rejectionReason']?.toString(),
    );
  }
}

class _ReviewDecisions {
  final Map<String, _Decision> byCaseId;

  const _ReviewDecisions(this.byCaseId);

  static _ReviewDecisions read(File file, List<String> errors) {
    if (!file.existsSync()) {
      errors.add('review_decisions_missing:${file.path}');
      return const _ReviewDecisions({});
    }
    final data = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    if (data['schemaVersion'] != 'hinet_truth_quality_review_decisions_v1') {
      errors.add('unexpected_review_decisions_schema');
    }
    return _ReviewDecisions({
      for (final raw in _list(data['cases']))
        _map(raw)['caseId'].toString(): _Decision.fromJson(_map(raw)),
    });
  }
}

class _Decision {
  final String decisionStatus;
  final bool acceptedForConstrainedReferenceSplit;

  const _Decision({
    required this.decisionStatus,
    required this.acceptedForConstrainedReferenceSplit,
  });

  factory _Decision.fromJson(Map<String, Object?> json) => _Decision(
    decisionStatus: json['decisionStatus']?.toString() ?? 'missing_decision',
    acceptedForConstrainedReferenceSplit:
        json['acceptedForConstrainedReferenceSplit'] == true,
  );
}

List<Object?> _list(Object? value) => value is List ? value : const [];

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};
