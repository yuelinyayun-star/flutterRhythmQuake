import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_nied_station_layer_role_audit.dart';

void main() {
  test('NIED station layer role audit records surface default policy', () {
    final report = buildNiedStationLayerRoleAuditJson(
      probeRoot: null,
      maxProbeFrames: 0,
    );

    expect(report['schemaVersion'], 'nied_station_layer_role_audit_v1');

    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['productionBehaviorChanged'], isTrue);
    expect(
      policy['currentRoutingRule'],
      'all scan-mapped stations default to jma_s',
    );
    expect(
      policy['supersededRoutingRule'],
      'network contains "kik" => jma_b, otherwise jma_s',
    );

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['stationCount'], 1749);
    expect(summary['scanMappedStationCount'], 1630);

    final networkCounts = (summary['networkCounts'] as Map)
        .cast<String, Object?>();
    expect(networkCounts['K-NET'], 1047);
    expect(networkCounts['KiK-net'], 702);

    final layerCounts = (summary['currentPrimaryLayerCounts'] as Map)
        .cast<String, Object?>();
    expect(layerCounts['jma_s'], 1749);
    expect(layerCounts['jma_b'], 0);
    final scanMappedLayerCounts =
        (summary['scanMappedCurrentPrimaryLayerCounts'] as Map)
            .cast<String, Object?>();
    expect(scanMappedLayerCounts['jma_s'], 1630);
    expect(scanMappedLayerCounts['jma_b'], isNull);

    final stations = (report['stations'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    final aic001 = stations.singleWhere((row) => row['code'] == 'AIC001');
    final aich04 = stations.singleWhere((row) => row['code'] == 'AICH04');
    expect(aic001['currentPrimaryLayer'], 'jma_s');
    expect(aic001['networkInferredPhysicalRole'], 'surface');
    expect(aich04['currentPrimaryLayer'], 'jma_s');
    expect(aich04['legacyNetworkInferredPrimaryLayer'], 'jma_b');
    expect(aich04['networkInferredPhysicalRole'], 'borehole');

    final output = File('.dart_tool/nied_station_layer_role_audit/report.json')
      ..parent.createSync(recursive: true);
    output.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
    final markdown = File(
      'docs/baselines/nied_station_layer_role_audit.generated.md',
    )..parent.createSync(recursive: true);
    markdown.writeAsStringSync(niedStationLayerRoleAuditMarkdown(report));
  });
}
