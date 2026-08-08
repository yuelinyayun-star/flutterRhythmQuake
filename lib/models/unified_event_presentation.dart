import 'unified_quake_data.dart';

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
    required this.timeText,
    required this.intensityLabel,
    required this.intensityValue,
    required this.apiTypeLabel,
  });

  final String title;
  final String primaryText;
  final String secondaryText;
  final String timeText;
  final String intensityLabel;
  final String intensityValue;
  final String apiTypeLabel;

  factory UnifiedEventPresentation.fromEvent(UnifiedQuakeData event) {
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
        timeText: eventTime != null
            ? eventTime.toLocal().toString().substring(5, 19)
            : '--:--:--',
        intensityLabel: '火山',
        intensityValue: '火山',
        apiTypeLabel: event.apiTypeLabel,
      );
    }
    final isScalePrompt = event.magnitude < 0 && event.hypocenter.isEmpty;
    final title = event.reportNumText.isNotEmpty
        ? '${event.titleText} ${event.reportNumText}'
        : event.titleText;
    final primaryText = isScalePrompt ? '震源 調査中' : event.hypocenter;
    final magnitudeText = isScalePrompt
        ? '規模 調査中'
        : event.isAssumption
        ? '仮定震源要素'
        : event.magnitude >= 0
        ? 'M${event.magnitude.toStringAsFixed(1)}'
        : 'M--';
    final depthText = isScalePrompt || event.isAssumption
        ? ''
        : event.depthText.isNotEmpty
        ? event.depthText
        : event.depth >= 0
        ? '深度 ${event.depth.toInt()}km'
        : '深度 --';
    final secondaryText = depthText.isNotEmpty
        ? '$magnitudeText  ·  $depthText'
        : magnitudeText;
    final timeText = event.originTime != null
        ? event.originTime!.toLocal().toString().substring(5, 19)
        : '--:--:--';
    final intensityValue = event.useShindo
        ? event.maxIntensity
        : unifiedRomanIntensityLabel(event.maxIntensity);

    return UnifiedEventPresentation(
      title: title,
      primaryText: primaryText,
      secondaryText: secondaryText,
      timeText: timeText,
      intensityLabel: event.useShindo ? '震度' : '烈度',
      intensityValue: intensityValue,
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
