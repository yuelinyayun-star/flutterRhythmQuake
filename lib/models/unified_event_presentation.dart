import '../core/intensity_calculator.dart';
import '../core/cwa_intensity_prediction.dart';
import '../core/cwa_report_intensities.dart';
import '../core/utils/quake_time.dart';
import 'jma_lpgm_bulletin.dart' show jmaLpgmObservationTitle;
import 'unified_quake_data.dart';

// Replay changes the visible API label, while retaining the original adapter
// origin. Use that identity for the same presentation rules as live reports.
String _eewPresentationApi(UnifiedQuakeData event) => event.isReplay
    ? switch (event.origin) {
        1 => 'FAN',
        3 => 'WHEWS',
        4 => 'Jian Project',
        _ => event.apiTypeLabel,
      }
    : event.apiTypeLabel;

CwaIntensityForecast? cwaForecastForEvent(UnifiedQuakeData event) {
  final raw = event.sourcePayload;
  if (!(event.source == 'cwaEew' || event.source == 'cwaEqlist') ||
      event.isCanceled ||
      event.isAssumption ||
      raw?['isCancel'] == true ||
      raw?['cancel'] == true ||
      raw?['isTraining'] == true ||
      event.lat == null ||
      event.lng == null) {
    return null;
  }
  // Missing correction means the explicitly unadjusted local model, not an
  // inferred upstream correction. A supplied invalid correction is rejected.
  final hasAdjustment = raw?.containsKey('pgaAdj') == true;
  final adjustment = hasAdjustment
      ? double.tryParse(raw!['pgaAdj'].toString())
      : 1.0;
  if (adjustment == null) return null;
  return CwaIntensityPrediction.predict(
    magnitude: event.magnitude,
    depth: event.depth,
    lat: event.lat!,
    lng: event.lng!,
    adjustment: adjustment,
    warnAreaJson: event.warnArea,
  );
}

/// Only structured CWA areas count as observed map data.
bool cwaObservedFillAvailable(UnifiedQuakeData event) {
  if (event.source != 'cwaEqlist' || event.isEew || event.isCanceled) {
    return false;
  }
  return CwaReportIntensities.fromWarnArea(event.warnArea).isNotEmpty;
}

/// Only the newly connected CWA badge paths use local missing-value estimates.
({int rank, bool estimated})? cwaEewBadgeIntensity(UnifiedQuakeData event) {
  if (event.source != 'cwaEew' ||
      !event.isEew ||
      event.isCanceled ||
      event.isAssumption ||
      event.sourcePayload?['isCancel'] == true ||
      event.sourcePayload?['cancel'] == true ||
      event.sourcePayload?['isTraining'] == true ||
      !const {
        'FAN',
        'Jian Project',
        'WHEWS',
      }.contains(_eewPresentationApi(event))) {
    return null;
  }
  final reported = CwaIntensityPrediction.parseRank(event.maxIntensity);
  if (reported != null) return (rank: reported, estimated: false);
  if (!const {
    '',
    '-',
    '--',
    '不明',
    '未知',
    'unknown',
  }.contains(event.maxIntensity.trim())) {
    return null;
  }
  if (event.sourcePayload == null && event.displayEstimateResolved) {
    final savedRank = CwaIntensityPrediction.parseRank(
      event.displayEstimatedIntensity,
    );
    return savedRank == null ? null : (rank: savedRank, estimated: true);
  }
  final forecast = cwaForecastForEvent(event);
  return forecast == null
      ? null
      : (rank: forecast.maximumRank, estimated: true);
}

/// New API badges reuse FAN's CSIS estimate without replacing source values.
int? estimatedNewApiEewBadgeIntensity(UnifiedQuakeData event) {
  final raw = event.sourcePayload;
  if (!const {'Jian Project', 'WHEWS'}.contains(_eewPresentationApi(event)) ||
      !event.isEew ||
      event.useShindo ||
      event.isCanceled ||
      event.isAssumption ||
      raw?['isCancel'] == true ||
      raw?['cancel'] == true ||
      raw?['isTraining'] == true ||
      !const {'', '-'}.contains(event.maxIntensity.trim()) ||
      !event.magnitude.isFinite ||
      event.magnitude <= 0 ||
      !event.depth.isFinite ||
      event.depth < 0) {
    return null;
  }
  if (raw == null && event.displayEstimateResolved) {
    return int.tryParse(event.displayEstimatedIntensity ?? '');
  }
  return IntensityCalculator.calcCsisLevel(event.magnitude, event.depth, 0);
}

/// Display metadata for history summaries, calculated before raw bodies are
/// deferred to disk (including any supplied CWA PGA adjustment).
String? estimatedEewIntensityValue(UnifiedQuakeData event) {
  final cwa = cwaEewBadgeIntensity(event);
  if (cwa != null && cwa.estimated) {
    return CwaIntensityPrediction.labels[cwa.rank];
  }
  return estimatedNewApiEewBadgeIntensity(event)?.toString();
}

/// Reuse existing badge estimates without changing reported fields. CWA ranks
/// must be resolved to their weak/strong label, never spoken as rank numbers.
String unifiedEewIntensityValue(UnifiedQuakeData event) {
  final cwa = cwaEewBadgeIntensity(event);
  if (cwa != null) return CwaIntensityPrediction.labels[cwa.rank];
  return estimatedNewApiEewBadgeIntensity(event)?.toString() ??
      event.maxIntensity.trim();
}

String unifiedRomanIntensityLabel(String value) {
  final parsed = double.tryParse(value.trim());
  if (parsed == null) return value;
  final level = parsed.round().clamp(1, 12);
  const labels = [
    '',
    'I',
    'II',
    'III',
    'IV',
    'V',
    'VI',
    'VII',
    'VIII',
    'IX',
    'X',
    'XI',
    'XII',
  ];
  return labels[level];
}

/// WHEWS 普通情报的烈度展示规则：上游明确给出 0 时视为无效，改用
/// 本地震中烈度估算。其他 WHEWS 烈度值和所有其他来源都保留原值。
String? forcedInfoIntensityValue(UnifiedQuakeData event) {
  final isWhews =
      event.origin == 3 || event.apiTypeLabel.trim().toUpperCase() == 'WHEWS';
  if (!isWhews ||
      event.isEew ||
      event.useShindo ||
      event.isCanceled ||
      event.isAssumption ||
      event.isVolcanoEvent ||
      double.tryParse(event.maxIntensity.trim()) != 0) {
    return null;
  }
  if (!event.magnitude.isFinite ||
      event.magnitude <= 0 ||
      !event.depth.isFinite ||
      event.depth < 0) {
    return null;
  }
  return IntensityCalculator.calcCsisLevel(
    event.magnitude,
    event.depth,
    0,
  ).toString();
}

String infoIntensityDisplayValue(UnifiedQuakeData event) {
  final estimated = forcedInfoIntensityValue(event);
  if (estimated == null) {
    return event.useShindo
        ? event.maxIntensity
        : unifiedRomanIntensityLabel(event.maxIntensity);
  }
  return unifiedRomanIntensityLabel(estimated);
}

/// 统一地震信息卡与系统通知共同使用的展示文本。
class UnifiedEventPresentation {
  const UnifiedEventPresentation({
    required this.title,
    required this.primaryText,
    required this.secondaryText,
    required this.compactSecondaryText,
    required this.timeText,
    required this.intensityLabel,
    required this.intensityValue,
    required this.apiTypeLabel,
    this.detailText = '',
  });

  final String title;
  final String primaryText;
  final String secondaryText;
  final String compactSecondaryText;
  final String timeText;
  final String intensityLabel;
  final String intensityValue;
  final String apiTypeLabel;
  final String detailText;

  factory UnifiedEventPresentation.fromEvent(
    UnifiedQuakeData event, {
    Map<String, String>? sourceSummary,
  }) {
    if (event.source == 'usgsDyfi') {
      final properties = event.sourcePayload?['properties'];
      final responses = properties is Map
          ? properties['numResp'] ?? properties['num-responses']
          : null;
      final detail = '收到 ${responses ?? '未知'} 份报告';
      return UnifiedEventPresentation(
        title: _displayTitle(event),
        primaryText: event.hypocenter,
        secondaryText: detail,
        compactSecondaryText: detail,
        timeText:
            '更新 ${QuakeTime.formatSourceClockInSystem(event.reportTime, 0)}',
        intensityLabel: 'CDI',
        intensityValue: event.maxIntensity,
        apiTypeLabel: event.apiTypeLabel,
      );
    }
    if (event.source == 'sasmex') {
      final raw = event.sourcePayload;
      final rawSeverity = _sasmexText(
        raw?['severity'] ?? sourceSummary?['severity'],
      );
      final severity = rawSeverity ?? '';
      final severityLabel = switch (severity.trim().toLowerCase()) {
        'minor' => '轻微',
        'moderate' => '中等',
        'severe' => '严重',
        _ => severity.isEmpty ? '未知' : severity,
      };
      final messageType = _sasmexText(
        raw?['msgType'] ?? sourceSummary?['msgType'],
      );
      final statusText =
          '类型：${messageType ?? '未知'} · 严重性：${rawSeverity ?? '未知'}';
      final details = <String>[
        for (final field in const {
          'region': '原始地点',
          'title': '上游标题',
          'event': '上游事件',
          'description': '原始描述',
          'severity': '原始严重性',
          'intensidad': '上游强度文字',
          'grado': 'grado 原值',
          'severidad': 'severidad 原值',
          'msgType': '消息类型',
          'sent': '发布时间原文',
          'updated': '更新时间原文',
          'circle': '震中圆原文',
        }.entries)
          if (_sasmexText(raw?[field.key]) case final String value)
            '${field.value}：$value',
      ];
      return UnifiedEventPresentation(
        title: _displayTitle(event),
        primaryText: event.hypocenter.isEmpty ? '地点未知' : event.hypocenter,
        secondaryText: statusText,
        compactSecondaryText: statusText,
        timeText:
            '发布 ${QuakeTime.formatSourceClockInSystem(event.originTime, event.timeZone)}',
        intensityLabel: '严重性',
        intensityValue: severityLabel,
        apiTypeLabel: event.apiTypeLabel,
        detailText: details.join('\n'),
      );
    }
    if (event.isJmaLpgm) {
      return UnifiedEventPresentation(
        title: jmaLpgmObservationTitle,
        primaryText: event.hypocenter,
        secondaryText: event.depthText.isNotEmpty
            ? '${event.magnitude >= 0 ? 'M${event.magnitude.toStringAsFixed(1)}' : 'M--'}  ·  ${event.depthText}'
            : (event.magnitude >= 0
                  ? 'M${event.magnitude.toStringAsFixed(1)}'
                  : 'M--'),
        compactSecondaryText: event.depthText.isNotEmpty
            ? '${event.magnitude >= 0 ? 'M${event.magnitude.toStringAsFixed(1)}' : 'M--'}  ·  ${event.depthText}'
            : (event.magnitude >= 0
                  ? 'M${event.magnitude.toStringAsFixed(1)}'
                  : 'M--'),
        timeText: QuakeTime.formatSourceClockInSystem(
          event.originTime,
          event.timeZone,
        ),
        intensityLabel: '长周期',
        intensityValue: '长周期',
        apiTypeLabel: event.apiTypeLabel,
      );
    }
    final volcano = event.volcanoEvent;
    if (volcano != null) {
      final title = event.reportNumText.isNotEmpty
          ? '${event.titleText} ${event.reportNumText}'
          : event.titleText;
      final eventTime = volcano.targetTime ?? volcano.reportTime;
      return UnifiedEventPresentation(
        title: title,
        primaryText: volcano.displayLocation,
        secondaryText: volcano.displayDetail,
        compactSecondaryText: volcano.compactDisplayDetail,
        timeText: QuakeTime.formatSourceClockInSystem(
          eventTime,
          event.timeZone,
          includeZoneLabel: true,
        ),
        intensityLabel: '火山',
        intensityValue: '火山',
        apiTypeLabel: event.apiTypeLabel,
      );
    }
    final hypocenterInvestigating = _isInvestigatingHypocenter(
      event.hypocenter,
    );
    final magnitudeInvestigating = event.magnitude < 0;
    final isFullInvestigation =
        hypocenterInvestigating && magnitudeInvestigating;
    final title = _displayTitle(event);
    final primaryText = hypocenterInvestigating ? '震源 調査中' : event.hypocenter;
    final magnitudeText = magnitudeInvestigating
        ? '規模 調査中'
        : event.isAssumption
        ? '仮定震源要素'
        : event.magnitude >= 0
        ? 'M${event.magnitude.toStringAsFixed(1)}'
        : 'M--';
    final depthText =
        isFullInvestigation || magnitudeInvestigating || event.isAssumption
        ? ''
        : event.depthText.isNotEmpty
        ? event.depthText
        : event.depth >= 0
        ? '深度 ${event.depth.toInt()}km'
        : '深度 --';
    final secondaryText = event.plumMissingParametersText ?? (depthText.isNotEmpty
        ? '$magnitudeText  ·  $depthText'
        : magnitudeText);
    final timeText = QuakeTime.formatSourceClockInSystem(
      event.originTime,
      event.timeZone,
    );
    final intensityValue = infoIntensityDisplayValue(event);

    final isForeignVolcano = event.titleText.contains('遠地噴火');
    final intensityLabel = isForeignVolcano
        ? '噴火'
        : event.source == 'usgsShakeMap'
        ? 'MMI'
        : (event.useShindo ? '震度' : '烈度');
    final displayIntensityValue =
        isForeignVolcano && (intensityValue == '不明' || intensityValue == '-')
        ? '噴火'
        : intensityValue;

    return UnifiedEventPresentation(
      title: title,
      primaryText: primaryText,
      secondaryText: secondaryText,
      compactSecondaryText: secondaryText,
      timeText: timeText,
      intensityLabel: intensityLabel,
      intensityValue: displayIntensityValue,
      apiTypeLabel: event.apiTypeLabel,
    );
  }

  String get notificationBody => [
    primaryText,
    secondaryText,
    '$intensityLabel $intensityValue',
    timeText,
    if (apiTypeLabel.isNotEmpty) apiTypeLabel,
  ].where((line) => line.trim().isNotEmpty).join('\n');
}

String? _sasmexText(Object? value) {
  if (value == null) return null;
  final text = value.toString();
  return text.trim().isEmpty ? null : text;
}

String _displayTitle(UnifiedQuakeData event) {
  final titleText = event.displayTitleText;
  final rawReport = event.reportNumText.trim();
  final report = !event.isEew && rawReport.toLowerCase() == 'reviewed'
      ? ''
      : rawReport;
  if (!event.isEew && event.source == 'cencEqlist') {
    const title = '中国地震台网地震信息';
    return report.isEmpty ? title : '$title $report';
  }
  if (report.isEmpty) return titleText;

  // JMA ordinary observation titles (also P2P/WHEWS) do not carry a report
  // serial. Keep revision/cancellation statuses and the underlying serial for
  // event ordering. Accept Chinese 报, Japanese 報 and fullwidth digits.
  if (!event.isEew &&
      const {'jmaEqlist', 'p2pJmaEqlist'}.contains(event.source)) {
    final serial = RegExp(r'^第\s*[0-9０-９]+\s*[報报](.*)$').firstMatch(report);
    if (serial != null) {
      final suffix = (serial.group(1) ?? '').trim();
      if (suffix.isEmpty) return titleText;
      final wrapped = RegExp(r'^[（(]([^）)]+)[）)]$').firstMatch(suffix);
      final status = wrapped?.group(1)?.trim() ?? suffix;
      return status.isEmpty ? titleText : '$titleText $status';
    }
  }

  return '$titleText $report';
}

bool _isInvestigatingHypocenter(String value) {
  final text = value.trim();
  return text.isEmpty ||
      text.contains('調査中') ||
      text.contains('调查中') ||
      text == '不明' ||
      text == '不詳' ||
      text.toLowerCase() == 'unknown';
}
