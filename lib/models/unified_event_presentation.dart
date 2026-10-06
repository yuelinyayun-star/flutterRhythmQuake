import '../core/intensity_calculator.dart';
import '../core/cwa_intensity_prediction.dart';
import '../core/cwa_report_intensities.dart';
import '../core/utils/quake_time.dart';
import 'unified_quake_data.dart';

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
      !const {'FAN', 'Jian Project', 'WHEWS'}.contains(event.apiTypeLabel)) {
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
  final forecast = cwaForecastForEvent(event);
  return forecast == null
      ? null
      : (rank: forecast.maximumRank, estimated: true);
}

/// New API badges reuse FAN's CSIS estimate without replacing source values.
int? estimatedNewApiEewBadgeIntensity(UnifiedQuakeData event) {
  final raw = event.sourcePayload;
  if (!const {'Jian Project', 'WHEWS'}.contains(event.apiTypeLabel) ||
      !event.isEew ||
      event.useShindo ||
      event.isCanceled ||
      event.isAssumption ||
      event.isHistory ||
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
  return IntensityCalculator.calcCsisLevel(event.magnitude, event.depth, 0);
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
  });

  final String title;
  final String primaryText;
  final String secondaryText;
  final String compactSecondaryText;
  final String timeText;
  final String intensityLabel;
  final String intensityValue;
  final String apiTypeLabel;

  factory UnifiedEventPresentation.fromEvent(UnifiedQuakeData event) {
    if (event.isJmaLpgm) {
      final title = event.reportNumText.isNotEmpty
          ? '${event.titleText} ${event.reportNumText}'
          : event.titleText;
      return UnifiedEventPresentation(
        title: title,
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
        timeText: QuakeTime.formatUnifiedOriginClock(event),
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
    final secondaryText = depthText.isNotEmpty
        ? '$magnitudeText  ·  $depthText'
        : magnitudeText;
    final timeText = QuakeTime.formatUnifiedOriginClock(event);
    final intensityValue = event.useShindo
        ? event.maxIntensity
        : unifiedRomanIntensityLabel(event.maxIntensity);

    final isForeignVolcano = event.titleText.contains('遠地噴火');
    final intensityLabel = isForeignVolcano
        ? '噴火'
        : (event.useShindo ? '震度' : '烈度');
    final displayIntensityValue = isForeignVolcano && (intensityValue == '不明' || intensityValue == '-')
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

String _displayTitle(UnifiedQuakeData event) {
  final report = event.reportNumText.trim();
  if (report.isEmpty) return event.titleText;

  // JMA 情报（含 P2P / WHEWS）不拼报次；取消/订正等状态仍显示。
  if (!event.isEew && event.source == 'jmaEqlist') {
    if (RegExp(r'^第\d+報').hasMatch(report)) {
      final status = RegExp(r'（([^）]+)）').firstMatch(report)?.group(1)?.trim();
      if (status != null && status.isNotEmpty) {
        return '${event.titleText} $status';
      }
      return event.titleText;
    }
  }

  return '${event.titleText} $report';
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
