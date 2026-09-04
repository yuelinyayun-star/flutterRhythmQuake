import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

const _events = <_EventConfig>[
  _EventConfig(
    eventId: '2011041214074228-37.0525-140.6435',
    folder: '2011041214074228near',
    regionName: '福岛县中通',
    relationship: 'same_source_family_as_current_jma_revised_geometry',
  ),
  _EventConfig(
    eventId: '2014112222081790-36.6928-137.8910',
    folder: '2014112222081790near',
    regionName: '长野县北部',
    relationship: 'same_source_family_as_current_jma_active_subfault_geometry',
  ),
  _EventConfig(
    eventId: '2016041421263443-32.7417-130.8087',
    folder: '2016041421263443near',
    regionName: '熊本地方',
    relationship: 'alternative_jma_source_process_to_current_nied_geometry',
  ),
  _EventConfig(
    eventId: '2016102114072257-35.3805-133.8562',
    folder: '2016102114072257near',
    regionName: '鸟取县中部',
    relationship: 'alternative_jma_source_process_to_current_nied_geometry',
  ),
  _EventConfig(
    eventId: '2016122821384904-36.7202-140.5742',
    folder: '2016122821384904near',
    regionName: '茨城县北部',
    relationship: 'same_source_family_as_current_jma_revised_geometry',
  ),
];

void main(List<String> arguments) {
  final auditRoot =
      _value(arguments, '--audit-root') ?? 'tmp/jma_source_process_audit';
  final rawRoot =
      _value(arguments, '--raw-root') ?? 'tmp/jma_source_process_raw';
  final outputDirectory = Directory(
    _value(arguments, '--output-dir') ??
        '.dart_tool/matsuzaki_2006_jma_source_process_audit',
  );
  final reports = <Map<String, Object?>>[];
  for (final config in _events) {
    final folder = Directory('$auditRoot/${config.folder}/${config.folder}');
    final eventFile = File('${folder.path}/01event.txt');
    final faultFile = File('${folder.path}/02fault.txt');
    final momentFile = File('${folder.path}/03mom.txt');
    final slipFile = File('${folder.path}/04slip.txt');
    final rawZip = File('$rawRoot/${config.folder}.zip');
    if (!eventFile.existsSync() ||
        !faultFile.existsSync() ||
        !momentFile.existsSync() ||
        !slipFile.existsSync() ||
        !rawZip.existsSync()) {
      throw StateError(
        'Missing extracted source-process files for ${config.eventId}.',
      );
    }
    final eventText = eventFile.readAsStringSync(encoding: utf8);
    final faultText = faultFile.readAsStringSync(encoding: utf8);
    final momentText = momentFile.readAsStringSync(encoding: utf8);
    final slipText = slipFile.readAsStringSync(encoding: utf8);
    final event = _parseEvent(eventText, config.eventId);
    final fault = _parseFault(faultText);
    final momentRelease = _parseMomentRelease(momentText);
    final slipDistribution = _parseSlip(slipText);
    final currentGeometry = Matsuzaki2006SourceBackedDistanceOverrides
        .eventGeometries
        .singleWhere((geometry) => geometry.eventId == config.eventId);
    final currentVariant = currentGeometry.variants.single;
    reports.add({
      'eventId': config.eventId,
      'regionName': config.regionName,
      'sourceUrl':
          'https://www.data.jma.go.jp/eqev/data/sourceprocess/data/${config.folder}.zip',
      'rawZip': rawZip.path,
      'rawZipSha256': sha256.convert(rawZip.readAsBytesSync()).toString(),
      'relationshipToCurrentGeometry': config.relationship,
      'eventFile': event,
      'faultFile': fault,
      'momentReleaseFile': momentRelease,
      'slipDistributionFile': slipDistribution,
      'currentGeometryVariantId': currentVariant.id,
      'currentGeometryRecord': currentGeometry.geometryRecord,
      'currentFaultPlanes': [
        for (final plane in currentVariant.faultPlanes) plane.toJson(),
      ],
      'geometryComparison': _compareGeometry(
        fault: fault,
        currentPlanes: [
          for (final plane in currentVariant.faultPlanes) plane.toJson(),
        ],
      ),
    });
  }
  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_jma_source_process_audit_v2',
    'purpose':
        'Audit official JMA source-process metadata and separate source families before any distance experiment.',
    'inputPolicy': {
      'rawZipModified': false,
      'sourceProcessIndexUsed': 'tmp/jma_sourceprocess_index.html',
      'productionAlgorithmChanged': false,
      'geometrySelectedByThisTool': false,
    },
    'events': reports,
    'osakaBoundary': {
      'eventId': '2018061807583414-34.8443-135.6217',
      'status': 'not_present_in_local_jma_sourceprocess_index_capture',
      'currentGeometryEvidence':
          'independent GNSS/aftershock/source-mechanism audit',
      'mustNotBeFilledByAnotherEvent': true,
    },
  };
  outputDirectory.createSync(recursive: true);
  File('${outputDirectory.path}/report.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    encoding: utf8,
  );
  File(
    '${outputDirectory.path}/report.md',
  ).writeAsStringSync(_markdown(reports), encoding: utf8);
  stdout.writeln('wrote ${outputDirectory.path}/report.json');
  stdout.writeln('wrote ${outputDirectory.path}/report.md');
}

Map<String, Object?> _parseEvent(String text, String eventId) {
  final location = RegExp(
    r'Lon=\s*([-+\d.]+)\s+Lat=\s*([-+\d.]+)\s+Dep=\s*([-+\d.]+)',
  ).firstMatch(text);
  final magnitude = RegExp(
    r'^M=\s*([-+\d.]+)',
    multiLine: true,
  ).firstMatch(text);
  if (location == null || magnitude == null) {
    throw FormatException('Cannot parse 01event.txt for $eventId.');
  }
  return {
    'eventId': eventId,
    'longitude': _double(location.group(1)!),
    'latitude': _double(location.group(2)!),
    'depthKm': _double(location.group(3)!),
    'magnitude': _double(magnitude.group(1)!),
    'type': RegExp(
      r'^Type=\s*(\S+)',
      multiLine: true,
    ).firstMatch(text)?.group(1),
    'stationCount': _int(
      RegExp(r'^Nsta=\s*(\d+)', multiLine: true).firstMatch(text)?.group(1),
    ),
    'lastUpdated': RegExp(
      r'^#Last updated:\s*(.+)$',
      multiLine: true,
    ).firstMatch(text)?.group(1),
    'seismicMomentNm': _scientific(
      RegExp(
        r'^Mo=\s*([-+\d.]+E[-+\d]+)',
        multiLine: true,
      ).firstMatch(text)?.group(1),
    ),
    'momentMagnitudeMw': _doubleOrNull(
      RegExp(
        r'^Mo=.*?Mw=\s*([-+\d.]+)',
        multiLine: true,
      ).firstMatch(text)?.group(1),
    ),
    'maximumSlipM': _doubleOrNull(
      RegExp(
        r'^Mo=.*?Mxslp=\s*([-+\d.]+)',
        multiLine: true,
      ).firstMatch(text)?.group(1),
    ),
    'waveformResidual': _doubleOrNull(
      RegExp(r'^Res=\s*([-+\d.]+)', multiLine: true).firstMatch(text)?.group(1),
    ),
  };
}

Map<String, Object?> _parseFault(String text) {
  final origin = RegExp(r'Xorg=\s*(\d+)\s+Worg=\s*(\d+)').firstMatch(text);
  final reference = RegExp(
    r'Lon=\s*([-+\d.]+)\s+Lat=\s*([-+\d.]+)\s+Dep=\s*([-+\d.]+)',
  ).firstMatch(text);
  final spacing = RegExp(
    r'Dx=\s*([-+\d.]+)\s+Dw=\s*([-+\d.]+)',
  ).firstMatch(text);
  final rows = <Map<String, Object?>>[];
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length < 10 ||
        int.tryParse(fields[0]) == null ||
        int.tryParse(fields[1]) == null) {
      continue;
    }
    final mark = int.tryParse(fields.last);
    if (mark == null) continue;
    rows.add({
      'x': int.parse(fields[0]),
      'w': int.parse(fields[1]),
      'longitude': _double(fields[2]),
      'latitude': _double(fields[3]),
      'depthKm': _double(fields[4]),
      'strikeDegrees': _double(fields[5]),
      'dipDegrees': _double(fields[6]),
      'rakeDegrees': _double(fields[7]),
      'active': mark == 1,
    });
  }
  final active = rows.where((row) => row['active'] == true).toList();
  int minInt(String key) =>
      active.map((row) => row[key]! as int).reduce(_minInt);
  int maxInt(String key) =>
      active.map((row) => row[key]! as int).reduce(_maxInt);
  double minDouble(String key) =>
      active.map((row) => row[key]! as double).reduce(_minDouble);
  double maxDouble(String key) =>
      active.map((row) => row[key]! as double).reduce(_maxDouble);
  return {
    'faultCount': _int(RegExp(r'Nfault=\s*(\d+)').firstMatch(text)?.group(1)),
    'originGrid': origin == null
        ? null
        : {'x': int.parse(origin.group(1)!), 'w': int.parse(origin.group(2)!)},
    'referencePoint': reference == null
        ? null
        : {
            'longitude': _double(reference.group(1)!),
            'latitude': _double(reference.group(2)!),
            'depthKm': _double(reference.group(3)!),
          },
    'gridSpacingKm': spacing == null
        ? null
        : {
            'alongStrikeKm': _double(spacing.group(1)!),
            'downDipKm': _double(spacing.group(2)!),
          },
    'allSubfaultCount': rows.length,
    'activeSubfaultCount': active.length,
    'activeXRange': active.isEmpty
        ? null
        : {'minimum': minInt('x'), 'maximum': maxInt('x')},
    'activeWRange': active.isEmpty
        ? null
        : {'minimum': minInt('w'), 'maximum': maxInt('w')},
    'activeDepthRangeKm': active.isEmpty
        ? null
        : {'minimum': minDouble('depthKm'), 'maximum': maxDouble('depthKm')},
    'activeStrikeDegrees': active
        .map((row) => row['strikeDegrees'])
        .toSet()
        .toList(),
    'activeDipDegrees': active.map((row) => row['dipDegrees']).toSet().toList(),
    'activeRakeDegrees': active
        .map((row) => row['rakeDegrees'])
        .toSet()
        .toList(),
    'activeSubfaultRows': active,
  };
}

Map<String, Object?> _parseMomentRelease(String text) {
  final interval = _doubleOrNull(
    RegExp(r'^Dt=\s*([-+\d.]+)', multiLine: true).firstMatch(text)?.group(1),
  );
  final lines = text.split(RegExp(r'\r?\n'));
  final histories = <Map<String, Object?>>[];
  for (var index = 0; index < lines.length; index++) {
    final faultMatch = RegExp(r'^#(\d+)\s*$').firstMatch(lines[index].trim());
    if (faultMatch == null || index + 2 >= lines.length) continue;
    if (!lines[index + 1].trim().startsWith('#mom')) continue;
    final values = lines[index + 2]
        .trim()
        .split(RegExp(r'\s+'))
        .where((value) => value.isNotEmpty)
        .map(double.parse)
        .toList();
    if (values.isEmpty) continue;
    final release = values.sublist(1);
    final nonZero = release.where((value) => value > 0).toList();
    histories.add({
      'faultNumber': int.parse(faultMatch.group(1)!),
      'firstWindowTriggerSeconds': values.first,
      'sampleCountIncludingTrigger': values.length,
      'releaseSampleCount': release.length,
      'nonZeroReleaseSampleCount': nonZero.length,
      'durationSeconds': interval == null ? null : release.length * interval,
      'nonZeroDurationSeconds': interval == null
          ? null
          : nonZero.length * interval,
      'maximumReleaseE18Nm': release.reduce(math.max),
      'sumReleaseE18Nm': release.fold<double>(0, (sum, value) => sum + value),
    });
  }
  return {
    'sampleIntervalSeconds': interval,
    'faultHistories': histories,
    'faultCount': histories.length,
  };
}

Map<String, Object?> _parseSlip(String text) {
  final rigidityRows = <Map<String, Object?>>[];
  final slipRows = <Map<String, Object?>>[];
  var inRigidity = false;
  var inSlip = false;
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trim();
    if (trimmed.startsWith('#Dep')) {
      inRigidity = true;
      inSlip = false;
      continue;
    }
    if (trimmed.startsWith('#x')) {
      inRigidity = false;
      inSlip = true;
      continue;
    }
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final fields = trimmed.split(RegExp(r'\s+'));
    if (inRigidity && fields.length >= 2) {
      final depth = double.tryParse(fields[0]);
      final rigidity = double.tryParse(fields[1]);
      if (depth != null && rigidity != null) {
        rigidityRows.add({'depthKm': depth, 'rigidityGPa': rigidity});
      }
    } else if (inSlip && fields.length >= 4) {
      final x = int.tryParse(fields[0]);
      final w = int.tryParse(fields[1]);
      if (x == null || w == null) continue;
      slipRows.add({
        'x': x,
        'w': w,
        'rakeDegrees': _doubleOrNull(fields[2]),
        'slipM': _doubleOrNull(fields[3]),
        'usedInInversion': fields[2] != '-' && fields[3] != '-',
      });
    }
  }
  final used = slipRows.where((row) => row['usedInInversion'] == true).toList();
  final slips = used.map((row) => row['slipM']! as double).toList();
  return {
    'rigidityRows': rigidityRows,
    'subfaultRowCount': slipRows.length,
    'usedSubfaultCount': used.length,
    'unusedSubfaultCount': slipRows.length - used.length,
    'maximumSlipM': slips.isEmpty ? null : slips.reduce(math.max),
    'meanUsedSlipM': slips.isEmpty
        ? null
        : slips.reduce((left, right) => left + right) / slips.length,
    'sumUsedSlipM': slips.isEmpty
        ? null
        : slips.fold<double>(0, (sum, value) => sum + value),
    'subfaultRows': slipRows,
  };
}

Map<String, Object?> _compareGeometry({
  required Map<String, Object?> fault,
  required List<Map<String, Object>> currentPlanes,
}) {
  final spacing = fault['gridSpacingKm'] as Map<String, Object?>?;
  final xRange = fault['activeXRange'] as Map<String, Object?>?;
  final wRange = fault['activeWRange'] as Map<String, Object?>?;
  if (spacing == null ||
      xRange == null ||
      wRange == null ||
      currentPlanes.isEmpty) {
    return {'status': 'insufficient_geometry_metadata'};
  }
  final sourceLength =
      ((xRange['maximum']! as int) - (xRange['minimum']! as int) + 1) *
      (spacing['alongStrikeKm']! as double);
  final sourceWidth =
      ((wRange['maximum']! as int) - (wRange['minimum']! as int) + 1) *
      (spacing['downDipKm']! as double);
  final sourceReference = fault['referencePoint'] as Map<String, Object?>?;
  final sourceDepthRange = fault['activeDepthRangeKm'] as Map<String, Object?>?;
  final sourceStrikes = (fault['activeStrikeDegrees']! as List<Object?>)
      .whereType<num>()
      .map((value) => value.toDouble())
      .toList();
  final sourceDips = (fault['activeDipDegrees']! as List<Object?>)
      .whereType<num>()
      .map((value) => value.toDouble())
      .toList();
  return {
    'status': 'comparison_only',
    'sourceActiveLengthKm': sourceLength,
    'sourceActiveWidthKm': sourceWidth,
    'sourceActiveDepthRangeKm': sourceDepthRange,
    'sourceReferencePoint': sourceReference,
    'sourceStrikeDegrees': sourceStrikes,
    'sourceDipDegrees': sourceDips,
    'sourceActiveSubfaultCount': fault['activeSubfaultCount'],
    'currentPlanes': [
      for (final plane in currentPlanes)
        _comparePlane(
          plane: plane,
          sourceLength: sourceLength,
          sourceWidth: sourceWidth,
          sourceReference: sourceReference,
          sourceDepthRange: sourceDepthRange,
          sourceStrikes: sourceStrikes,
          sourceDips: sourceDips,
        ),
    ],
    'interpretation':
        'Active subfault footprint and current rectangle are compared as separate source models; no geometry is selected or merged.',
  };
}

Map<String, Object?> _comparePlane({
  required Map<String, Object> plane,
  required double sourceLength,
  required double sourceWidth,
  required Map<String, Object?>? sourceReference,
  required Map<String, Object?>? sourceDepthRange,
  required List<double> sourceStrikes,
  required List<double> sourceDips,
}) {
  final currentReference = plane['referencePoint']! as Map<String, Object>;
  final currentUpperDepth = (plane['inferredUpperEdgeDepthKm']! as num)
      .toDouble();
  final currentLowerDepth =
      currentUpperDepth +
      (plane['widthKm']! as num).toDouble() *
          math.sin((plane['dipDegrees']! as num).toDouble() * math.pi / 180);
  final sourceStrike = sourceStrikes.length == 1 ? sourceStrikes.single : null;
  final sourceDip = sourceDips.length == 1 ? sourceDips.single : null;
  final currentStrike = (plane['upperEdgeAzimuthDegrees']! as num).toDouble();
  final currentDip = (plane['dipDegrees']! as num).toDouble();
  final sourceReferenceDepth = sourceReference?['depthKm'] as num?;
  final currentReferenceDepth = currentReference['depthKm']! as num;
  return {
    'id': plane['id'],
    'lengthKm': plane['lengthKm'],
    'widthKm': plane['widthKm'],
    'lengthDifferenceKm': (plane['lengthKm'] as num).toDouble() - sourceLength,
    'widthDifferenceKm': (plane['widthKm'] as num).toDouble() - sourceWidth,
    'upperEdgeDepthKm': currentUpperDepth,
    'lowerEdgeDepthKm': currentLowerDepth,
    'sourceDepthRangeKm': sourceDepthRange,
    'strikeDegrees': currentStrike,
    'sourceStrikeDegrees': sourceStrike,
    'undirectedStrikeDifferenceDegrees': sourceStrike == null
        ? null
        : _undirectedAngleDifference(currentStrike, sourceStrike),
    'dipDegrees': currentDip,
    'sourceDipDegrees': sourceDip,
    'dipDifferenceDegrees': sourceDip == null ? null : currentDip - sourceDip,
    'referencePoint': currentReference,
    'sourceReferencePoint': sourceReference,
    'referenceLatitudeDifferenceDegrees': sourceReference == null
        ? null
        : (currentReference['latitude']! as num).toDouble() -
              (sourceReference['latitude']! as num).toDouble(),
    'referenceLongitudeDifferenceDegrees': sourceReference == null
        ? null
        : (currentReference['longitude']! as num).toDouble() -
              (sourceReference['longitude']! as num).toDouble(),
    'referenceDepthDifferenceKm': sourceReferenceDepth == null
        ? null
        : currentReferenceDepth.toDouble() - sourceReferenceDepth.toDouble(),
  };
}

double _undirectedAngleDifference(double left, double right) {
  var difference = (left - right).abs() % 180;
  if (difference > 90) difference = 180 - difference;
  return difference;
}

double _double(String value) => double.parse(value);

int _int(String? value) => value == null ? 0 : int.parse(value);

int _minInt(int left, int right) => left < right ? left : right;

int _maxInt(int left, int right) => left > right ? left : right;

double _minDouble(double left, double right) => left < right ? left : right;

double _maxDouble(double left, double right) => left > right ? left : right;

double? _doubleOrNull(String? value) =>
    value == null || value == '-' ? null : double.tryParse(value);

double? _scientific(String? value) {
  if (value == null) return null;
  return double.tryParse(value);
}

String _markdown(List<Map<String, Object?>> reports) {
  final buffer = StringBuffer()
    ..writeln('# JMA 官方源过程原始包审计')
    ..writeln()
    ..writeln(
      '本报告读取 JMA 官方索引列出的近地源过程 ZIP，保留原始 ZIP 哈希，并解析 `01event.txt`、`02fault.txt`、`03mom.txt` 和 `04slip.txt`。它不选择几何，也不修改实验或生产算法。',
    )
    ..writeln()
    ..writeln(
      '| 事件 | JMA 深度 km | M/Mw | Mo (Nm) | 最大滑移 m | 网格原点 | 间距 km | 活跃范围 | 与当前几何关系 |',
    )
    ..writeln('|---|---:|---:|---:|---:|---|---|---|---|');
  for (final report in reports) {
    final event = report['eventFile']! as Map<String, Object?>;
    final fault = report['faultFile']! as Map<String, Object?>;
    final slip = report['slipDistributionFile']! as Map<String, Object?>;
    final origin = fault['originGrid'] as Map<String, Object?>?;
    final spacing = fault['gridSpacingKm'] as Map<String, Object?>?;
    final xRange = fault['activeXRange'] as Map<String, Object?>?;
    final wRange = fault['activeWRange'] as Map<String, Object?>?;
    buffer.writeln(
      '| `${report['eventId']}` | ${_fixed(event['depthKm'])} | '
      '${_fixed(event['magnitude'])}/${_fixed(event['momentMagnitudeMw'])} | '
      '${_scientificText(event['seismicMomentNm'])} | ${_fixed(event['maximumSlipM'])} | '
      '${origin == null ? '-' : '${origin['x']},${origin['w']}'} | '
      '${spacing == null ? '-' : '${_fixed(spacing['alongStrikeKm'])} x ${_fixed(spacing['downDipKm'])}'} | '
      '${xRange == null ? '-' : 'x ${xRange['minimum']}-${xRange['maximum']}, w ${wRange!['minimum']}-${wRange['maximum']}'} | '
      '`${report['relationshipToCurrentGeometry']}` |',
    );
    final moments = report['momentReleaseFile']! as Map<String, Object?>;
    final histories = moments['faultHistories']! as List<Object?>;
    buffer
      ..writeln()
      ..writeln('### `${report['eventId']}` 源过程统计')
      ..writeln()
      ..writeln(
        '- `03mom.txt`：采样间隔 ${_fixed(moments['sampleIntervalSeconds'])} s；fault 数 ${moments['faultCount']}；${_momentHistoryText(histories)}',
      )
      ..writeln(
        '- `04slip.txt`：刚度层数 ${((slip['rigidityRows']! as List<Object?>).length)}；子断层行 ${slip['subfaultRowCount']}；用于反演 ${slip['usedSubfaultCount']}；未用于反演 ${slip['unusedSubfaultCount']}；平均已用滑移 ${_fixed(slip['meanUsedSlipM'])} m；最大已用滑移 ${_fixed(slip['maximumSlipM'])} m。',
      )
      ..writeln(
        '- 几何差异仅作为来源核对：${_geometryComparisonText(report['geometryComparison'])}',
      );
  }
  buffer
    ..writeln()
    ..writeln('## 物理含义边界')
    ..writeln()
    ..writeln(
      '- `M` 是 JMA 目录震级，`Mo/Mw` 是波形源过程反演得到的地震矩/矩震级，二者不是同一个输入变量，不能直接替换烈度反演中的事件震级。',
    )
    ..writeln('- `03mom.txt` 描述断层模型内部的时间释放过程；它不能从测站烈度观测中直接得到，也不是 JMA 计测震度时间序列。')
    ..writeln(
      '- `04slip.txt` 的滑移、rake 和 rigidity 用于源过程/断层模型解释。当前实验没有把它们混入点源烈度前向式；几何差异报告也不选择模型。',
    )
    ..writeln('- `0` 或 `-` 的子断层表示假设网格中未用于反演的单元，不能补成零烈度、零滑移观测，也不能当作已观测站。');
  buffer
    ..writeln()
    ..writeln('## 来源分层')
    ..writeln()
    ..writeln('- 福岛、长野、茨城：JMA 源过程参数与当前 JMA 修订/有效单元几何属于同一来源族，可以作为同一来源的参数核对。')
    ..writeln(
      '- 熊本、鸟取：JMA 源过程文件与当前采用的 NIED 修订矩形是不同来源的不同模型，不能把两个模型的网格、走向、倾角或深度拼接。',
    )
    ..writeln(
      '- 大阪：没有在本地保存的 JMA 源过程索引中找到该事件条目；继续使用已有 GNSS、余震和震源机制独立审计，不用其他事件源过程包填充。',
    )
    ..writeln()
    ..writeln(
      '原始 ZIP 均保留在 `tmp/jma_source_process_raw`，报告 JSON 记录每个 ZIP 的 SHA-256。',
    );
  return buffer.toString();
}

String _fixed(Object? value) =>
    value is num ? value.toDouble().toStringAsFixed(3) : '-';

String _scientificText(Object? value) =>
    value is num ? value.toStringAsExponential(2) : '-';

String _momentHistoryText(List<Object?> histories) {
  if (histories.isEmpty) return '没有可解析的 fault 时间序列';
  return histories
      .map((history) {
        final row = history! as Map<String, Object?>;
        return 'fault ${row['faultNumber']} 首窗 ${_fixed(row['firstWindowTriggerSeconds'])} s，'
            '释放时长 ${_fixed(row['durationSeconds'])} s，最大 ${_fixed(row['maximumReleaseE18Nm'])} e18 Nm';
      })
      .join('；');
}

String _geometryComparisonText(Object? value) {
  final comparison = value as Map<String, Object?>;
  if (comparison['status'] != 'comparison_only') {
    return comparison['status']?.toString() ?? 'unknown';
  }
  final planes = comparison['currentPlanes']! as List<Object?>;
  return 'JMA 活跃足迹 ${_fixed(comparison['sourceActiveLengthKm'])} x '
      '${_fixed(comparison['sourceActiveWidthKm'])} km；当前实验矩形：${planes.map((plane) {
        final row = plane! as Map<String, Object?>;
        return '${row['id']} ${_fixed(row['lengthKm'])} x ${_fixed(row['widthKm'])} km '
            '(长度差 ${_fixed(row['lengthDifferenceKm'])}，宽度差 ${_fixed(row['widthDifferenceKm'])}，'
            '走向差 ${_fixed(row['undirectedStrikeDifferenceDegrees'])} 度，'
            '倾角差 ${_fixed(row['dipDifferenceDegrees'])} 度，'
            '参考深度差 ${_fixed(row['referenceDepthDifferenceKm'])} km)';
      }).join('，')}。';
}

class _EventConfig {
  const _EventConfig({
    required this.eventId,
    required this.folder,
    required this.regionName,
    required this.relationship,
  });

  final String eventId;
  final String folder;
  final String regionName;
  final String relationship;
}

String? _value(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index < 0 || index + 1 >= arguments.length) return null;
  return arguments[index + 1];
}
