import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/import_hinet_authenticated_export_row.dart';

void main() {
  test(
    'authenticated export row importer accepts valid pending case payload',
    () {
      final rowsJson = _pendingRowsJson();

      final errors = validateHinetAuthenticatedExportRowInput(
        rowsJson: rowsJson,
        inputJson: const {
          'caseId': '20260622_iwate_east_offshore_m30_hinet',
          'sourceType': 'hinet_jma_unified_catalog',
          'sourceUrl': 'https://hinetwww11.bosai.go.jp/auth/JMA/?LANG=en',
          'sourceVersionOrPageDate': '2026-06-26 authenticated page',
          'checkedAtUtc': '2026-06-26T10:45:00Z',
          'reviewer': 'reviewer-id',
          'originTimeJst': '2026-06-22T11:26:50',
          'latitude': 39.91,
          'longitude': 142.347,
          'depthKm': 42.4,
          'magnitude': 3.0,
          'region': 'Iwate east offshore',
          'rawRowText': '2026-06-22 11:26:50 39.91 142.347 42.4 M3.0',
        },
      );

      expect(errors, isEmpty);
    },
  );

  test('authenticated export row importer rejects auth material', () {
    final rowsJson = _pendingRowsJson();

    final errors = validateHinetAuthenticatedExportRowInput(
      rowsJson: rowsJson,
      inputJson: const {
        'caseId': '20260622_iwate_east_offshore_m30_hinet',
        'sourceType': 'hinet_jma_unified_catalog',
        'sourceUrl': 'https://hinetwww11.bosai.go.jp/auth/JMA/?LANG=en',
        'sourceVersionOrPageDate': '2026-06-26 authenticated page',
        'checkedAtUtc': '2026-06-26T10:45:00Z',
        'reviewer': 'reviewer-id',
        'originTimeJst': '2026-06-22T11:26:50',
        'latitude': 39.91,
        'longitude': 142.347,
        'depthKm': 42.4,
        'magnitude': 3.0,
        'region': 'Iwate east offshore',
        'rawRowText': '2026-06-22 11:26:50 39.91 142.347 42.4 M3.0',
        'password': 'must-not-be-imported',
      },
    );

    expect(errors, contains('input_contains_sensitive_auth_material'));
  });

  test('authenticated export row importer validates query target', () {
    final rowsJson = _pendingRowsJson();
    final payload = {
      '_queryTarget': {
        'caseId': '20260622_iwate_east_offshore_m30_hinet',
        'queryWindowJst': {
          'start': '2026-06-22T11:21:50',
          'end': '2026-06-22T11:31:50',
        },
        'targetLatitude': 39.91,
        'targetLongitude': 142.347,
        'targetMagnitude': 3.0,
      },
      'caseId': '20260622_iwate_east_offshore_m30_hinet',
      'sourceType': 'hinet_jma_unified_catalog',
      'sourceUrl': 'https://hinetwww11.bosai.go.jp/auth/JMA/?LANG=en',
      'sourceVersionOrPageDate': '2026-06-27 authenticated page',
      'checkedAtUtc': '2026-06-27T01:30:00Z',
      'reviewer': 'reviewer-id',
      'originTimeJst': '2026-06-22T11:26:50',
      'latitude': 39.91,
      'longitude': 142.347,
      'depthKm': 42.4,
      'magnitude': 3.0,
      'region': 'Iwate east offshore',
      'rawRowText': '2026-06-22 11:26:50 39.91 142.347 42.4 M3.0',
    };

    final errors = validateHinetAuthenticatedExportRowInput(
      rowsJson: rowsJson,
      inputJson: payload,
    );
    expect(errors, isEmpty);

    final wrongRow = {
      ...payload,
      'originTimeJst': '2026-06-22T12:26:50',
      'latitude': 35.0,
      'longitude': 139.0,
      'magnitude': 5.5,
    };
    final wrongErrors = validateHinetAuthenticatedExportRowInput(
      rowsJson: rowsJson,
      inputJson: wrongRow,
    );
    expect(wrongErrors, contains('origin_time_outside_query_window'));
    expect(wrongErrors, contains('row_location_outside_target_tolerance'));
    expect(wrongErrors, contains('row_magnitude_outside_target_tolerance'));
  });
}

Map<String, Object?> _pendingRowsJson() {
  final rowsJson =
      jsonDecode(
            File(
              'docs/data/hinet_authenticated_export_rows.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  rowsJson['rows'] = (rowsJson['rows'] as List)
      .map((entry) {
        final row = (entry as Map).cast<String, Object?>();
        return {
          ...row,
          'status': 'pending_export',
          'submittedRow': null,
          'rejectionReason': null,
          'decisionImpact': 'none_pending_only',
        };
      })
      .toList(growable: false);
  return rowsJson;
}
