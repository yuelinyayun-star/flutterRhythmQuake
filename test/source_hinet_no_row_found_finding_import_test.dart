import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/import_source_hinet_no_row_found_finding.dart';

void main() {
  test('no-row-found finding importer accepts valid pending case payload', () {
    final findingsJson =
        jsonDecode(
              File(
                'docs/data/source_hinet_no_row_found_findings.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final inputJson = {
      'caseId': '20260622_iwate_east_offshore_m30_hinet',
      'sourceType': 'hinet_jma_unified_catalog',
      'sourceUrl': 'https://hinetwww11.bosai.go.jp/auth/JMA/?LANG=en',
      'checkedAtUtc': '2026-06-27T00:00:00Z',
      'reviewer': 'reviewer-id',
      'queryWindowJst': '2026-06-22T11:21:50..2026-06-22T11:31:50',
      'searchResult': 'no_event_row_found',
      'searchedOriginTimeJst': '2026-06-22T11:26:50',
      'searchedLatitude': 39.91,
      'searchedLongitude': 142.347,
      'searchedMagnitude': 3.0,
      'notes': 'Authenticated event-level search returned no matching row.',
    };

    final errors = validateSourceHinetNoRowFoundFindingInput(
      findingsJson: findingsJson,
      inputJson: inputJson,
    );
    expect(errors, isEmpty);
  });

  test(
    'no-row-found finding importer rejects auth material and placeholders',
    () {
      final findingsJson =
          jsonDecode(
                File(
                  'docs/data/source_hinet_no_row_found_findings.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final inputJson = {
        'caseId': '20260622_iwate_east_offshore_m30_hinet',
        'sourceType': 'hinet_jma_unified_catalog',
        'sourceUrl': 'http://example.invalid',
        'checkedAtUtc': '<fill-checked-at-utc>',
        'reviewer': '<fill-reviewer-id>',
        'queryWindowJst': 'not-a-range',
        'searchResult': 'row_found',
        'searchedOriginTimeJst': '<fill-searched-origin-time-or-window>',
        'searchedLatitude': null,
        'searchedLongitude': null,
        'searchedMagnitude': null,
        'notes': '<fill-search-notes>',
        'cookie': 'do-not-store',
      };

      final errors = validateSourceHinetNoRowFoundFindingInput(
        findingsJson: findingsJson,
        inputJson: inputJson,
      );
      expect(errors, contains('input_contains_sensitive_auth_material'));
      expect(errors, contains('source_url_must_be_https'));
      expect(errors, contains('unresolved_placeholder:checkedAtUtc'));
      expect(errors, contains('unresolved_placeholder:reviewer'));
      expect(errors, contains('query_window_must_be_range'));
      expect(errors, contains('search_result_must_be_no_event_row_found'));
      expect(errors, contains('numeric_field_required:searchedLatitude'));
    },
  );

  test('no-row-found finding importer validates query target', () {
    final findingsJson =
        jsonDecode(
              File(
                'docs/data/source_hinet_no_row_found_findings.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final payload = {
      '_queryTarget': {
        'caseId': '20260622_iwate_east_offshore_m30_hinet',
        'queryWindowJst': '2026-06-22T11:21:50..2026-06-22T11:31:50',
        'targetLatitude': 39.91,
        'targetLongitude': 142.347,
        'targetMagnitude': 3.0,
      },
      'caseId': '20260622_iwate_east_offshore_m30_hinet',
      'sourceType': 'hinet_jma_unified_catalog',
      'sourceUrl': 'https://hinetwww11.bosai.go.jp/auth/JMA/?LANG=en',
      'checkedAtUtc': '2026-06-27T01:30:00Z',
      'reviewer': 'reviewer-id',
      'queryWindowJst': '2026-06-22T11:21:50..2026-06-22T11:31:50',
      'searchResult': 'no_event_row_found',
      'searchedOriginTimeJst': '2026-06-22T11:26:50',
      'searchedLatitude': 39.91,
      'searchedLongitude': 142.347,
      'searchedMagnitude': 3.0,
      'notes': 'Authenticated event-level search returned no matching row.',
    };

    final errors = validateSourceHinetNoRowFoundFindingInput(
      findingsJson: findingsJson,
      inputJson: payload,
    );
    expect(errors, isEmpty);

    final wrongPayload = {
      ...payload,
      'caseId': '20260622_tomakomai_south_offshore_m35_hinet',
      'queryWindowJst': '2026-06-22T20:32:47..2026-06-22T20:42:47',
      'searchedLatitude': 35.0,
      'searchedLongitude': 139.0,
      'searchedMagnitude': 5.5,
    };
    final wrongErrors = validateSourceHinetNoRowFoundFindingInput(
      findingsJson: findingsJson,
      inputJson: wrongPayload,
    );
    expect(
      wrongErrors,
      contains(
        'query_target_case_mismatch:20260622_iwate_east_offshore_m30_hinet',
      ),
    );
    expect(wrongErrors, contains('query_window_does_not_match_target'));
    expect(wrongErrors, contains('searched_location_outside_target_tolerance'));
    expect(
      wrongErrors,
      contains('searched_magnitude_outside_target_tolerance'),
    );
  });
}
