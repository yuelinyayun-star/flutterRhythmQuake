import 'dart:convert';
import 'dart:io';

const _defaultAvailabilityPath = 'docs/data/jma_catalog_availability.json';
const _defaultReadinessReport =
    '.dart_tool/source_estimation_split_assignment_readiness/report.json';
const _defaultOutput = '.dart_tool/jma_catalog_availability_report/report.json';
const _defaultMarkdown = 'docs/baselines/jma_catalog_availability.generated.md';

void main(List<String> args) {
  final availabilityPath =
      _argument(args, '--availability') ?? _defaultAvailabilityPath;
  final readinessPath =
      _argument(args, '--readiness') ?? _defaultReadinessReport;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = _JmaCatalogAvailabilityReport.build(
    availabilityFile: File(availabilityPath),
    readinessReport: File(readinessPath),
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote JMA catalog availability report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report.errors.isNotEmpty) {
    exitCode = 1;
  }
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

Map<String, Object?> buildJmaCatalogAvailabilityReportJson({
  String availabilityPath = _defaultAvailabilityPath,
  String readinessPath = _defaultReadinessReport,
}) {
  return _JmaCatalogAvailabilityReport.build(
    availabilityFile: File(availabilityPath),
    readinessReport: File(readinessPath),
  ).toJson();
}

class _JmaCatalogAvailabilityReport {
  final String availabilityPath;
  final String readinessReportPath;
  final _CatalogAvailability? availability;
  final String readinessStatus;
  final List<_JmaCatalogBlocker> blockers;
  final List<String> errors;
  final List<String> warnings;

  const _JmaCatalogAvailabilityReport({
    required this.availabilityPath,
    required this.readinessReportPath,
    required this.availability,
    required this.readinessStatus,
    required this.blockers,
    required this.errors,
    required this.warnings,
  });

  factory _JmaCatalogAvailabilityReport.build({
    required File availabilityFile,
    required File readinessReport,
  }) {
    final errors = <String>[];
    final warnings = <String>[];

    _CatalogAvailability? availability;
    if (!availabilityFile.existsSync()) {
      errors.add('jma_catalog_availability_missing:${availabilityFile.path}');
    } else {
      try {
        availability = _CatalogAvailability.fromJson(
          _map(jsonDecode(availabilityFile.readAsStringSync())),
        );
        errors.addAll(availability.validate());
      } catch (error) {
        errors.add('jma_catalog_availability_parse_failed:$error');
      }
    }

    var readinessStatus = 'missing';
    final blockers = <_JmaCatalogBlocker>[];
    if (!readinessReport.existsSync()) {
      errors.add('readiness_report_missing:${readinessReport.path}');
    } else {
      final readiness =
          jsonDecode(readinessReport.readAsStringSync())
              as Map<String, Object?>;
      readinessStatus = readiness['status']?.toString() ?? 'unknown';
      if (readinessStatus != 'pass') {
        errors.add('readiness_report_not_pass:$readinessStatus');
      }
      for (final rawCase in _list(readiness['cases'])) {
        final readinessCase = _map(rawCase);
        final hasPendingJmaCatalogLink = _list(readinessCase['conditions']).any(
          (condition) {
            final item = _map(condition);
            return item['name'] == 'review_jma_catalog_link' &&
                item['status'] != 'complete';
          },
        );
        if (!hasPendingJmaCatalogLink) continue;
        blockers.add(
          _JmaCatalogBlocker.fromReadinessCase(
            readinessCase,
            availability,
            errors,
          ),
        );
      }
    }

    blockers.sort((left, right) => left.caseId.compareTo(right.caseId));

    if (availability != null) {
      for (final blocker in blockers) {
        if (blocker.eventYear == null) {
          errors.add(
            'jma_catalog_blocker_origin_year_missing:${blocker.caseId}',
          );
        } else if (blocker.coveredByAvailableCatalog &&
            !blocker.linkedToVersionedCatalog) {
          errors.add(
            'jma_catalog_link_actionable_but_missing:${blocker.caseId}',
          );
        }
      }
    }

    return _JmaCatalogAvailabilityReport(
      availabilityPath: availabilityFile.path,
      readinessReportPath: readinessReport.path,
      availability: availability,
      readinessStatus: readinessStatus,
      blockers: blockers,
      errors: errors,
      warnings: warnings,
    );
  }

  Map<String, Object?> toJson() {
    final unavailable = blockers
        .where(
          (blocker) => blocker.status == 'external_catalog_not_yet_available',
        )
        .length;
    final actionable = blockers
        .where((blocker) => blocker.status == 'catalog_available_link_missing')
        .length;
    return {
      'schemaVersion': 'jma_catalog_availability_report_v1',
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'status': errors.isEmpty ? 'pass' : 'fail',
      'availabilityPath': availabilityPath,
      'readinessReportPath': readinessReportPath,
      'readinessStatus': readinessStatus,
      'availability': availability?.toJson(),
      'summary': {
        'jmaCatalogBlockerCount': blockers.length,
        'externalCatalogNotYetAvailableCount': unavailable,
        'catalogAvailableLinkMissingCount': actionable,
        'linkedToVersionedCatalogCount': blockers
            .where((blocker) => blocker.linkedToVersionedCatalog)
            .length,
      },
      'errors': errors,
      'warnings': warnings,
      'blockers': blockers.map((blocker) => blocker.toJson()).toList(),
    };
  }

  String toMarkdown() {
    final json = toJson();
    final summary = json['summary'] as Map<String, Object?>;
    final buffer = StringBuffer()
      ..writeln('# JMA Catalog Availability')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Availability manifest: `$availabilityPath`')
      ..writeln('- Readiness report: `$readinessReportPath`')
      ..writeln('- Readiness status: `$readinessStatus`');
    if (availability != null) {
      buffer
        ..writeln('- Availability as of: `${availability!.asOf}`')
        ..writeln(
          '- Latest official final catalog year: '
          '`${availability!.latestAvailableFinalCatalogYear}`',
        )
        ..writeln(
          '- Latest official final catalog period end: '
          '`${availability!.latestAvailableFinalCatalogPeriodEnd}`',
        );
      final evidence = availability!.latestAvailableFinalCatalogEvidence;
      if (evidence != null) {
        buffer
          ..writeln(
            '- Latest-year evidence checked at: `${evidence.checkedAtUtc}`',
          )
          ..writeln('- Latest-year evidence source: `${evidence.sourceUrl}`')
          ..writeln(
            '- Observed missing final-catalog year links: '
            '`${evidence.observedMissingYearLinks.join('`, `')}`',
          );
      }
    }
    buffer
      ..writeln(
        '- JMA catalog blockers: `${summary['jmaCatalogBlockerCount']}`',
      )
      ..writeln(
        '- External catalog not yet available: '
        '`${summary['externalCatalogNotYetAvailableCount']}`',
      )
      ..writeln(
        '- Catalog available but link missing: '
        '`${summary['catalogAvailableLinkMissingCount']}`',
      )
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
      ..writeln('## Blockers')
      ..writeln()
      ..writeln(
        '| Case | Origin JST | Truth source | Catalog linked | Status | Evidence |',
      )
      ..writeln('| --- | --- | --- | --- | --- | --- |');
    for (final blocker in blockers) {
      buffer.writeln(
        '| `${blocker.caseId}` | `${blocker.originTimeJst ?? ''}` | '
        '`${blocker.truthSource}` | '
        '${blocker.linkedToVersionedCatalog ? 'yes' : 'no'} | '
        '`${blocker.status}` | ${blocker.evidence} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Decision')
      ..writeln()
      ..writeln(
        '- Recent JMA source-and-intensity cases stay reference-only until a '
        'versioned final catalog covers the event year and '
        '`tools/link_jma_catalog.dart` links a matching record.',
      )
      ..writeln(
        '- This report must fail once a blocker is within the available final '
        'catalog range but still lacks a linked catalog object.',
      );
    return buffer.toString();
  }
}

class _CatalogAvailability {
  final String schemaVersion;
  final String asOf;
  final String authority;
  final int latestAvailableFinalCatalogYear;
  final String latestAvailableFinalCatalogPeriodEnd;
  final _CatalogAvailabilityEvidence? latestAvailableFinalCatalogEvidence;
  final List<String> sourceUrls;
  final String policy;

  const _CatalogAvailability({
    required this.schemaVersion,
    required this.asOf,
    required this.authority,
    required this.latestAvailableFinalCatalogYear,
    required this.latestAvailableFinalCatalogPeriodEnd,
    required this.latestAvailableFinalCatalogEvidence,
    required this.sourceUrls,
    required this.policy,
  });

  factory _CatalogAvailability.fromJson(Map<String, Object?> json) {
    final evidenceJson = _map(json['latestAvailableFinalCatalogEvidence']);
    return _CatalogAvailability(
      schemaVersion: json['schemaVersion']?.toString() ?? '',
      asOf: json['asOf']?.toString() ?? '',
      authority: json['authority']?.toString() ?? '',
      latestAvailableFinalCatalogYear:
          (json['latestAvailableFinalCatalogYear'] as num?)?.toInt() ?? 0,
      latestAvailableFinalCatalogPeriodEnd:
          json['latestAvailableFinalCatalogPeriodEnd']?.toString() ?? '',
      latestAvailableFinalCatalogEvidence: evidenceJson.isEmpty
          ? null
          : _CatalogAvailabilityEvidence.fromJson(evidenceJson),
      sourceUrls: _list(
        json['sourceUrls'],
      ).map((entry) => entry.toString()).toList(growable: false),
      policy: json['policy']?.toString() ?? '',
    );
  }

  List<String> validate() {
    final errors = <String>[];
    if (schemaVersion != 'jma_catalog_availability_v1') {
      errors.add('invalid_jma_catalog_availability_schema:$schemaVersion');
    }
    if (latestAvailableFinalCatalogYear <= 0) {
      errors.add('invalid_latest_available_final_catalog_year');
    }
    if (sourceUrls.isEmpty) {
      errors.add('jma_catalog_availability_source_urls_missing');
    }
    if (DateTime.tryParse(latestAvailableFinalCatalogPeriodEnd) == null) {
      errors.add('invalid_latest_available_final_catalog_period_end');
    }
    if (latestAvailableFinalCatalogEvidence == null) {
      errors.add('jma_catalog_availability_evidence_missing');
    } else {
      errors.addAll(
        latestAvailableFinalCatalogEvidence!.validate(
          expectedLatestYear: latestAvailableFinalCatalogYear,
          sourceUrls: sourceUrls,
        ),
      );
    }
    return errors;
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'asOf': asOf,
    'authority': authority,
    'latestAvailableFinalCatalogYear': latestAvailableFinalCatalogYear,
    'latestAvailableFinalCatalogPeriodEnd':
        latestAvailableFinalCatalogPeriodEnd,
    'latestAvailableFinalCatalogEvidence': latestAvailableFinalCatalogEvidence
        ?.toJson(),
    'sourceUrls': sourceUrls,
    'policy': policy,
  };
}

class _CatalogAvailabilityEvidence {
  final String checkedAtUtc;
  final String sourceUrl;
  final int observedLatestYearLink;
  final List<int> observedMissingYearLinks;
  final String notes;

  const _CatalogAvailabilityEvidence({
    required this.checkedAtUtc,
    required this.sourceUrl,
    required this.observedLatestYearLink,
    required this.observedMissingYearLinks,
    required this.notes,
  });

  factory _CatalogAvailabilityEvidence.fromJson(Map<String, Object?> json) =>
      _CatalogAvailabilityEvidence(
        checkedAtUtc: json['checkedAtUtc']?.toString() ?? '',
        sourceUrl: json['sourceUrl']?.toString() ?? '',
        observedLatestYearLink:
            (json['observedLatestYearLink'] as num?)?.toInt() ?? 0,
        observedMissingYearLinks: _list(json['observedMissingYearLinks'])
            .whereType<num>()
            .map((entry) => entry.toInt())
            .toList(growable: false),
        notes: json['notes']?.toString() ?? '',
      );

  List<String> validate({
    required int expectedLatestYear,
    required List<String> sourceUrls,
  }) {
    final errors = <String>[];
    if (DateTime.tryParse(checkedAtUtc) == null) {
      errors.add('invalid_jma_catalog_availability_evidence_checked_at');
    }
    if (!sourceUrls.contains(sourceUrl)) {
      errors.add('jma_catalog_availability_evidence_source_not_in_manifest');
    }
    if (observedLatestYearLink != expectedLatestYear) {
      errors.add(
        'jma_catalog_availability_evidence_year_mismatch:'
        '$observedLatestYearLink!=$expectedLatestYear',
      );
    }
    if (observedMissingYearLinks.isEmpty) {
      errors.add('jma_catalog_availability_missing_year_links_not_recorded');
    }
    if (notes.trim().isEmpty) {
      errors.add('jma_catalog_availability_evidence_notes_missing');
    }
    return errors;
  }

  Map<String, Object?> toJson() => {
    'checkedAtUtc': checkedAtUtc,
    'sourceUrl': sourceUrl,
    'observedLatestYearLink': observedLatestYearLink,
    'observedMissingYearLinks': observedMissingYearLinks,
    'notes': notes,
  };
}

class _JmaCatalogBlocker {
  final String caseId;
  final String fixturePath;
  final String truthSource;
  final String? originTimeJst;
  final int? eventYear;
  final bool catalogTruthVerified;
  final bool linkedToVersionedCatalog;
  final bool coveredByAvailableCatalog;
  final String status;
  final String evidence;

  const _JmaCatalogBlocker({
    required this.caseId,
    required this.fixturePath,
    required this.truthSource,
    required this.originTimeJst,
    required this.eventYear,
    required this.catalogTruthVerified,
    required this.linkedToVersionedCatalog,
    required this.coveredByAvailableCatalog,
    required this.status,
    required this.evidence,
  });

  factory _JmaCatalogBlocker.fromReadinessCase(
    Map<String, Object?> readinessCase,
    _CatalogAvailability? availability,
    List<String> errors,
  ) {
    final fixturePath = readinessCase['fixturePath']?.toString() ?? '';
    final fixture = _readFixture(fixturePath, errors);
    final truth = _map(fixture?['truth']);
    final labels = _map(fixture?['eventLabels']);
    final originTimeJst = truth['originTimeJst']?.toString();
    final eventYear = _eventYear(originTimeJst);
    final linkedToVersionedCatalog =
        truth['source'] == 'jma_final_catalog' && truth.containsKey('catalog');
    final covered =
        availability != null &&
        eventYear != null &&
        eventYear <= availability.latestAvailableFinalCatalogYear;
    final status = linkedToVersionedCatalog
        ? 'linked_to_versioned_catalog'
        : covered
        ? 'catalog_available_link_missing'
        : 'external_catalog_not_yet_available';
    final evidence = availability == null
        ? 'availability_manifest_missing'
        : eventYear == null
        ? 'origin_year_missing'
        : covered
        ? 'event_year_is_within_available_final_catalog_range'
        : 'event_year_${eventYear}_after_latest_available_final_catalog_'
              '${availability.latestAvailableFinalCatalogYear}';

    return _JmaCatalogBlocker(
      caseId: readinessCase['caseId']?.toString() ?? '',
      fixturePath: fixturePath,
      truthSource: truth['source']?.toString() ?? '',
      originTimeJst: originTimeJst,
      eventYear: eventYear,
      catalogTruthVerified: labels['catalogTruthVerified'] == true,
      linkedToVersionedCatalog: linkedToVersionedCatalog,
      coveredByAvailableCatalog: covered,
      status: status,
      evidence: evidence,
    );
  }

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'fixturePath': fixturePath,
    'truthSource': truthSource,
    'originTimeJst': originTimeJst,
    'eventYear': eventYear,
    'catalogTruthVerified': catalogTruthVerified,
    'linkedToVersionedCatalog': linkedToVersionedCatalog,
    'coveredByAvailableCatalog': coveredByAvailableCatalog,
    'status': status,
    'evidence': evidence,
  };
}

Map<String, Object?>? _readFixture(String path, List<String> errors) {
  if (path.isEmpty) {
    errors.add('jma_catalog_blocker_fixture_path_missing');
    return null;
  }
  final file = File(path);
  if (!file.existsSync()) {
    errors.add('jma_catalog_blocker_fixture_missing:$path');
    return null;
  }
  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  } catch (error) {
    errors.add('jma_catalog_blocker_fixture_parse_failed:$path:$error');
    return null;
  }
}

int? _eventYear(String? originTimeJst) {
  if (originTimeJst == null || originTimeJst.length < 4) return null;
  return int.tryParse(originTimeJst.substring(0, 4));
}

Map<String, Object?> _map(Object? value) {
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}

List<Object?> _list(Object? value) {
  if (value is List) return value;
  return const [];
}
