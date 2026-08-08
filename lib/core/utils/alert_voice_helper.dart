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
    final report = event.reportNumber != null && event.reportNumber! > 0
        ? '第${event.reportNumber}报'
        : '';
    final location = _fallback(event.location, '震源附近');
    final mag = _magText(event.magnitude);
    final shindo = _legacyIntensityText(event, intensity);
    final depth = _depthText(event.depth);

    final parts = <String>[
      levelText,
      if (report.isNotEmpty) report,
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

    final grade = message.title.trim().isNotEmpty
        ? message.title.trim()
        : switch (message.grade) {
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
        : '$source$action$grade。预警区域：$areas。';
  }

  static String _generateEewText(
    UnifiedQuakeData event, {
    required String phase,
  }) {
    final source = _sourceLabel(event.source);
    if (event.isCanceled) {
      return '$source，紧急地震速报已取消。';
    }

    final isJmaEew = event.source == 'jmaEew';
    final isShakeAlert = event.source == 'sa';
    // 报次完全复用 UI 的 reportNumText。phase 只用于播报去重和调用路径，
    // 不再在语音中拼接“发布/更新”等动作词。
    final type = switch (true) {
      _ when isJmaEew => event.isWarn ? '紧急地震警报' : '紧急地震速报',
      _ when isShakeAlert => '',
      _ => '地震预警',
    };
    final location = _fallback(event.hypocenter, '震源附近');
    final mag = _magText(event.magnitude);
    // 深度直接复用统一事件给 UI 的格式化字段，避免语音另行四舍五入。
    final depth = event.depthText.trim();
    final maxIntensity = _unifiedIntensityText(event);
    final report = _reportText(event.reportNumText);
    final area = event.warnArea.trim().isEmpty ? '' : '预警区域：${event.warnArea}。';
    final parts = <String>[
      source,
      if (type.isNotEmpty) type,
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
      'nowQuakeCencIr' => '中国地震台网',
      'usgsEqlist' => '美国地质调查局',
      'sa' => '美国ShakeAlert地震预警',
      'globalQuake' || 'globalQuakeEew' => 'GlobalQuake',
      'fssnEqlist' => 'FSSN',
      'emscEqlist' || 'emsc' => '欧洲地中海地震中心',
      'hko' => '香港天文台',
      'bcsf' => '法国中央地震研究所',
      'gfz' => '德国地学研究中心',
      'usp' => '巴西圣保罗大学',
      'ningxia' => '宁夏自治区地震局',
      'guangxi' => '广西壮族自治区地震局',
      'shanxi' => '山西省地震局',
      'beijing' => '北京市地震局',
      'yunnan' => '云南省地震局',
      _ => source.isEmpty ? '地震信息源' : source,
    };
  }

  static String _reportText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    final number = RegExp(r'\d+').firstMatch(trimmed)?.group(0);
    if (number != null) return '第$number报';
    if (trimmed.contains('最终') || trimmed.contains('Final')) return '最终报';
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
