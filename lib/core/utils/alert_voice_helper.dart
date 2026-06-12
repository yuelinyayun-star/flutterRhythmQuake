import '../../models/quake_message.dart';
import '../../models/tsunami_message.dart';
import '../../models/unified_quake_data.dart';

class AlertVoiceHelper {
  static String generateLegacyAlertText(
    QuakeMessage event,
    int countdown,
    double intensity,
  ) {
    final levelText = event.isWarn || intensity >= 5.0 ? '紧急地震警报' : '地震速报';
    final location = _fallback(event.location, '震源附近');
    final mag = _magText(event.magnitude);
    final shindo = _legacyIntensityText(event, intensity);
    final depth = _depthText(event.depth);

    final parts = <String>[
      levelText,
      '$location发生地震。',
      if (mag.isNotEmpty) mag,
      if (depth.isNotEmpty) depth,
      if (shindo.isNotEmpty) shindo,
    ];

    if (countdown > 0) {
      parts.add('预计地震波将在$countdown秒后到达。');
    } else {
      parts.add('地震波已经到达。');
    }
    return parts.join('，');
  }

  static String generateUnifiedEventText(
    UnifiedQuakeData event, {
    required String phase,
  }) {
    if (event.isEew) {
      return _generateEewText(event, phase: phase);
    }
    return _generateInfoText(event, phase: phase);
  }

  static String generateTsunamiText(
    TsunamiMessage message, {
    required bool isUpdate,
  }) {
    final source = message.source == TsunamiSource.jma ? '日本气象厅' : '国家海洋预报台';
    if (!message.isActive) {
      if (message.title.contains('信息') || message.titleText.contains('信息')) {
        return '$source，发布${message.title.isNotEmpty ? message.title : "海啸信息"}。';
      }
      return '$source，海啸预警已经解除。';
    }

    final grade = switch (message.grade) {
      TsunamiGrade.majorWarning => '大海啸警报',
      TsunamiGrade.warning => '海啸警报',
      TsunamiGrade.watch => '海啸注意报',
      TsunamiGrade.none => '海啸预警解除',
    };
    final action = isUpdate ? '更新' : '发布';
    final areas = message.areas
        .where(
          (area) => area.grade != TsunamiGrade.none && area.name.isNotEmpty,
        )
        .take(3)
        .map((area) => area.name)
        .join('、');
    return areas.isEmpty
        ? '$source$action$grade。'
        : '$source$action$grade。対象区域：$areas。';
  }

  static String _generateEewText(
    UnifiedQuakeData event, {
    required String phase,
  }) {
    final source = _sourceLabel(event.source);
    if (event.isCanceled) {
      return '$source，紧急地震速报已取消。';
    }

    final type = event.isWarn ? '紧急地震警报' : '紧急地震速报';
    final phaseText = switch (phase) {
      'first' => '发布',
      'final' => '最终报',
      'warn' => '警报更新',
      'caution' => '注意信息',
      _ => '更新',
    };
    final location = _fallback(event.hypocenter, '震源附近');
    final mag = _magText(event.magnitude);
    final depth = _depthText(event.depth);
    final maxIntensity = _unifiedIntensityText(event);
    final report = _reportText(event.reportNumText);
    final area = event.warnArea.trim().isEmpty ? '' : '预警区域：${event.warnArea}。';

    final parts = <String>[
      source,
      '$type$phaseText。',
      if (report.isNotEmpty) report,
      '$location发生地震。',
      if (mag.isNotEmpty) mag,
      if (depth.isNotEmpty) depth,
      if (maxIntensity.isNotEmpty) maxIntensity,
      if (area.isNotEmpty) area,
    ];
    return parts.join('，');
  }

  static String _generateInfoText(
    UnifiedQuakeData event, {
    required String phase,
  }) {
    final source = _sourceLabel(event.source);
    if (event.isCanceled) {
      return '$source，地震信息已取消。';
    }

    final action = phase == 'first' ? '发布地震信息' : '更新地震信息';
    final title = _fallback(event.titleText, '地震信息');
    final location = _fallback(event.hypocenter, '震源附近');
    final mag = _magText(event.magnitude);
    final depth = _depthText(event.depth);
    final intensity = _unifiedIntensityText(event);

    final parts = <String>[
      source,
      action,
      title,
      '$location。',
      if (mag.isNotEmpty) mag,
      if (depth.isNotEmpty) depth,
      if (intensity.isNotEmpty) intensity,
    ];
    return parts.join('，');
  }

  static String _sourceLabel(String source) {
    return switch (source) {
      'jmaEew' || 'jmaEqlist' => '日本气象厅',
      'cwaEew' || 'cwaEqlist' => '台湾中央气象署',
      'ceaEew' => '中国地震预警网',
      'scEew' => '四川省地震局',
      'fjEew' => '福建省地震局',
      'cqEew' => '重庆市地震局',
      'kmaEew' || 'kmaEqlist' => '韩国气象厅',
      'cencEqlist' => '中国地震台网',
      'usgsEqlist' => 'USGS',
      'fssnEqlist' => 'FSSN',
      'emscEqlist' || 'emsc' => 'EMSC',
      _ => source.isEmpty ? '地震信息源' : source,
    };
  }

  static String _reportText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    final number = RegExp(r'\d+').firstMatch(trimmed)?.group(0);
    if (number != null) return '第$number报。';
    if (trimmed.contains('最终') || trimmed.contains('Final')) return '最终报。';
    return '';
  }

  static String _unifiedIntensityText(UnifiedQuakeData event) {
    final value = event.maxIntensity.trim();
    if (value.isEmpty || value == '-' || value == '--') return '';
    return event.useShindo ? '最大震度$value。' : '最大烈度$value。';
  }

  static String _legacyIntensityText(QuakeMessage event, double intensity) {
    if (event.jmaShindo != null && event.jmaShindo!.trim().isNotEmpty) {
      return '最大震度${event.jmaShindo}.';
    }
    if (event.maxIntensity != null && event.maxIntensity! > 0) {
      return '最大烈度${event.maxIntensity}.';
    }
    if (intensity > 0) {
      return '预计烈度${intensity.toStringAsFixed(2)}。';
    }
    return '';
  }

  static String _magText(double magnitude) {
    if (magnitude <= 0) return '';
    return '震级${magnitude.toStringAsFixed(1)}。';
  }

  static String _depthText(double depth) {
    if (depth < 0) return '';
    if (depth == 0) return '深度很浅。';
    return '深度${depth.round()}公里。';
  }

  static String _fallback(String value, String fallback) {
    final trimmed = value.trim();
    return trimmed.isEmpty || trimmed == '-' || trimmed == '--'
        ? fallback
        : trimmed;
  }
}
