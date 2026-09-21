import 'dart:convert';

import '../../models/quake_message.dart';
import '../../models/whews_catalog.dart';
import '../../models/tsunami_message.dart';
import '../../models/unified_quake_data.dart';
import 'jma_voice_location.dart';

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
    final isJma = switch (event.source) {
      QuakeSourceType.wolfx ||
      QuakeSourceType.p2p ||
      QuakeSourceType.jma_fan => true,
      _ => false,
    };
    final location = _voiceLocation(event.location, isJma: isJma);
    final mag = _magText(event.magnitude);
    final shindo = _legacyIntensityText(event, intensity);
    final depth = _depthText(event.depth);
    return _sentence([
      levelText,
      location,
      if (mag.isNotEmpty) mag,
      if (shindo.isNotEmpty) shindo,
      if (depth.isNotEmpty) depth,
      if (countdown > 0) '预计$countdown秒后到达' else '地震波已经到达',
      if (report.isNotEmpty) report,
    ]);
  }

  static String generateUnifiedEventText(
    UnifiedQuakeData event, {
    required String phase,
  }) {
    final volcano = event.volcanoEvent;
    if (volcano != null) {
      final action = event.isCanceled
          ? '已取消'
          : (phase == 'first' ? '发布' : '更新');
      return '日本气象厅，$action火山情报。${volcano.displayLocation}。';
    }
    if (event.isEew) {
      return _generateEewText(event, phase: phase);
    }
    return _generateInfoText(event, phase: phase);
  }

  static String generateTsunamiText(
    TsunamiMessage message, {
    required bool isUpdate,
  }) {
    final source = message.source.voiceLabel;
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
    // 报次完全复用 UI 的 reportNumText。phase 只用于播报去重和调用路径，
    // 不再在语音中拼接“发布/更新”等动作词。
    final type = switch (true) {
      _ when isJmaEew => event.isWarn ? '紧急地震警报' : '紧急地震速报',
      _ => '地震预警',
    };
    final location = _voiceLocation(event.hypocenter, isJma: isJmaEew);
    final mag = _magText(event.magnitude);
    final maxIntensity = _unifiedIntensityText(event);
    final depth = _depthText(event.depth);
    final report = _reportText(event.reportNumText);
    return _sentence([
          type,
          location,
          if (mag.isNotEmpty) mag,
          if (maxIntensity.isNotEmpty) maxIntensity,
          if (depth.isNotEmpty) depth,
        ]) +
        _sentence([
          source,
          if (report.isNotEmpty) report,
          if (event.isFinal && !report.contains('最终')) '最终报',
        ]);
  }

  static String _generateInfoText(
    UnifiedQuakeData event, {
    required String phase,
  }) {
    final source = _sourceLabel(event.source);
    if (event.isCanceled) {
      return '$source，地震信息已取消。';
    }

    final title = event.isJmaLpgm
        ? '长周期地震动情报'
        : event.titleText.contains('矩心矩张量')
        ? '震源机制解'
        : event.source == 'nowQuakeCencIr'
        ? '烈度速报'
        : event.source == 'jmaEqlist'
        ? _jmaInfoTitle(event.titleText)
        : '地震信息';
    final report = _infoReportText(event);
    final isObservationBulletin =
        event.source == 'jmaEqlist' &&
        _isJmaObservationBulletin(event.titleText);
    final hasObservationLocation =
        event.source == 'jmaEqlist' && _isUnknownJmaLocation(event.hypocenter);
    final observations = hasObservationLocation || isObservationBulletin
        ? _jmaObservedAreas(event.warnArea, event.maxIntensity)
        : (text: '', includesMaximum: false);
    final location = hasObservationLocation
        ? observations.text
        : _voiceLocation(event.hypocenter, isJma: event.source == 'jmaEqlist');
    final mag = _magText(event.magnitude);
    final depth = isObservationBulletin && event.depth == 0
        ? ''
        : _depthText(event.depth);
    final intensity = _unifiedIntensityText(event);

    return _sentence([
          phase == 'first' ? title : '$title更新',
          if (location.isNotEmpty) location,
          if (mag.isNotEmpty) mag,
          if (intensity.isNotEmpty &&
              !(hasObservationLocation && observations.includesMaximum))
            intensity,
          if (depth.isNotEmpty) depth,
        ]) +
        (!hasObservationLocation && observations.text.isNotEmpty
            ? _sentence([observations.text])
            : '') +
        _sentence([source, if (report.isNotEmpty) report]);
  }

  static String _sourceLabel(String source) {
    final catalogSource = unifiedCatalogSources[source];
    if (catalogSource != null) return catalogSource.displayName;
    return switch (source) {
      'jmaEew' || 'jmaEqlist' => '日本气象厅',
      'cwaEew' || 'cwaEqlist' => '中央气象署',
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
      'whews_bmkg' => '印度尼西亚气象气候与地球物理局',
      'geonet' || 'whews_geonet' => '新西兰地球科学局',
      'whews_tmd' => '泰国气象局',
      'whews_ingv' => '意大利国家地球物理与火山学研究所',
      'whews_nrcan' => '加拿大自然资源部',
      'whews_mmd' => '马来西亚气象局',
      'whews_phivolcs' => '菲律宾火山与地震研究所',
      'whews_sgc' => '哥伦比亚地质局',
      'whews_ga' => '澳大利亚地质局',
      'whews_cenais' => '古巴国家地震研究中心',
      _ => _unadaptedSourceLabel(source),
    };
  }

  static bool _isUnadaptedVoiceSource(String source) {
    return source.startsWith('unadapted_') ||
        (source.startsWith('whews_') &&
            !unifiedCatalogSources.containsKey(source));
  }

  static String _unadaptedSourceLabel(String source) {
    if (!_isUnadaptedVoiceSource(source)) {
      return source.isEmpty ? '地震信息源' : source;
    }
    if (source.startsWith('unadapted_')) {
      final rest = source.substring('unadapted_'.length).trim();
      return rest.isEmpty ? '地震信息源' : rest;
    }
    if (source.startsWith('whews_')) {
      final rest = source.substring('whews_'.length).trim();
      return rest.isEmpty ? '地震信息源' : rest;
    }
    return source.isEmpty ? '地震信息源' : source;
  }

  static String _infoReportText(UnifiedQuakeData event) {
    final text = event.reportNumText.trim().replaceAll('報', '报');
    if (text.isEmpty) {
      // These adapters carry review status in the title, not reportNumText.
      for (final status in ['正式测定', '自动测定', '已核实', '待核实']) {
        if (event.titleText.contains(status)) return status;
      }
      return '';
    }

    // JMA 情报不播报次；仅保留取消/订正等状态。
    if (!event.isEew && event.source == 'jmaEqlist') {
      if (RegExp(r'^第\d+报').hasMatch(text)) {
        return RegExp(r'（([^）]+)）').firstMatch(text)?.group(1)?.trim() ?? '';
      }
      return text;
    }

    return text;
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
    final prefix = event.isEew ? '预计最大' : '最大';
    return event.useShindo
        ? '$prefix震度${_intensityReading(value)}'
        : '$prefix烈度${_intensityReading(value)}';
  }

  static String _legacyIntensityText(QuakeMessage event, double intensity) {
    if (event.jmaShindo != null && event.jmaShindo!.trim().isNotEmpty) {
      return '最大震度${_intensityReading(event.jmaShindo!.trim())}';
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
    if (!depth.isFinite || depth < 0) return '';
    if (depth == 0) return '深度很浅。';
    final value = depth == depth.roundToDouble()
        ? depth.toStringAsFixed(0)
        : depth.toString();
    return '深度$value公里。';
  }

  static String _jmaInfoTitle(String title) => switch (title.trim()) {
    '震度速報' || '震度速报' => '震度速报',
    '震源に関する情報' => '震源信息',
    '震度・震源に関する情報' || '震源・震度に関する情報' => '震源震度信息',
    '各地の震度に関する情報' || '各地の震度情報' => '各地震度信息',
    '遠地地震に関する情報' || '遠地地震情報' => '远地地震信息',
    '遠地噴火に関する情報' => '远地火山喷发信息',
    _ => '地震信息',
  };

  static bool _isJmaObservationBulletin(String title) =>
      const {'震度速報', '震度速报', '各地の震度に関する情報', '各地の震度情報'}.contains(title.trim());

  static bool _isUnknownJmaLocation(String name) => const {
    '',
    '-',
    '--',
    '不明',
    '不詳',
    '調査中',
    '调查中',
    '震源調査中',
    '震源调查中',
    '震源待定',
    'unknown',
  }.contains(name.trim().toLowerCase());

  static ({String text, bool includesMaximum}) _jmaObservedAreas(
    String encoded,
    String maximum,
  ) {
    const empty = (text: '', includesMaximum: false);
    if (encoded.trim().isEmpty) return empty;
    final dynamic decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException {
      return empty;
    }
    if (decoded is! List) return empty;
    const levels = ['0', '1', '2', '3', '4', '5弱', '5强', '6弱', '6强', '7'];
    final areas = <String, ({String intensity, int rank, int order})>{};
    for (final item in decoded.whereType<Map>()) {
      final name = item['name'];
      if (name is! String || _isUnknownJmaLocation(name)) continue;
      final intensity = _intensityReading('${item['intensity'] ?? ''}'.trim());
      final rank = levels.indexOf(intensity);
      final key = name.trim();
      final previous = areas[key];
      if (previous == null || rank > previous.rank) {
        areas[key] = (
          intensity: intensity,
          rank: rank,
          order: previous?.order ?? areas.length,
        );
      }
    }
    // Work on a derived list only; never reorder or overwrite event data.
    final ranked = areas.entries.toList()
      ..sort((a, b) {
        final byIntensity = b.value.rank.compareTo(a.value.rank);
        return byIntensity != 0
            ? byIntensity
            : a.value.order.compareTo(b.value.order);
      });
    final groups = <int, List<String>>{};
    for (final area in ranked) {
      (groups[area.value.rank] ??= []).add(jmaVoiceLocation(area.key));
    }
    final phrases = groups.entries.map((group) {
      final names = group.value.join('、');
      return group.key < 0
          ? '震度尚未明确的报告地区：$names'
          : '观测到震度${levels[group.key]}的地区：$names';
    });
    final maximumRank = levels.indexOf(_intensityReading(maximum.trim()));
    return (
      text: phrases.join('。'),
      includesMaximum: maximumRank >= 0 && groups.containsKey(maximumRank),
    );
  }

  static String _fallback(String value, String fallback) {
    final trimmed = value.trim();
    return trimmed.isEmpty || trimmed == '-' || trimmed == '--'
        ? fallback
        : trimmed;
  }

  static String _voiceLocation(String value, {required bool isJma}) {
    final location = _fallback(value, '震源待定');
    return isJma ? jmaVoiceLocation(location) : location;
  }

  static String _intensityReading(String value) => switch (value) {
    '5-' || '5弱' => '5弱',
    '5+' || '5強' || '5强' => '5强',
    '6-' || '6弱' => '6弱',
    '6+' || '6強' || '6强' => '6强',
    'I' || 'Ⅰ' => '1',
    'II' || 'Ⅱ' => '2',
    'III' || 'Ⅲ' => '3',
    'IV' || 'Ⅳ' => '4',
    'V' || 'Ⅴ' => '5',
    'VI' || 'Ⅵ' => '6',
    'VII' || 'Ⅶ' => '7',
    'VIII' || 'Ⅷ' => '8',
    'IX' || 'Ⅸ' => '9',
    'X' || 'Ⅹ' => '10',
    'XI' || 'Ⅺ' => '11',
    'XII' || 'Ⅻ' => '12',
    _ => value,
  };

  static String _sentence(List<String> parts) =>
      '${parts.map((part) => part.replaceAll(RegExp(r'[。，,.]+$'), '').trim()).where((part) => part.isNotEmpty).join('，')}。';
}
