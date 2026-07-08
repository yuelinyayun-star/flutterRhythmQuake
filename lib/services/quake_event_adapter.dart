import 'dart:convert';
import '../models/unified_quake_data.dart';
import '../models/quake_message.dart';
import '../core/utils/jma_seis_int_loc.dart';

class QuakeEventAdapter {
  static const _originWolfx = 0;
  static const _originP2p = 2;

  QuakeEventAdapter._();

  static String _apiTypeLabel(String source, int origin) {
    switch (source) {
      case 'jmaEew':
        return origin == 0
            ? 'Wolfx'
            : origin == 2
            ? 'NIED'
            : 'FAN';
      case 'cwaEew':
        return origin == 0 ? 'Wolfx' : 'FAN';
      case 'ceaEew':
        return origin == 0 ? 'Wolfx' : 'FAN';
      case 'scEew':
        return origin == 0 ? 'Wolfx' : 'FAN';
      case 'fjEew':
        return origin == 0 ? 'Wolfx' : 'FAN';
      case 'cqEew':
        return origin == 0 ? 'Wolfx' : 'FAN';
      case 'kmaEew':
        return 'FAN';
      case 'gqEew':
        return 'P2PQ';
      case 'jmaEqlist':
        return 'P2PQ';
      case 'cwaEqlist':
        return origin == 0 ? 'TREM' : 'FAN';
      case 'cencEqlist':
        return origin == 0 ? 'Wolfx' : 'FAN';
      case 'kmaEqlist':
        return 'FAN';
      case 'usgsEqlist':
        return 'FAN';
      case 'fssnEqlist':
        return 'FAN';
      case 'fssnCmt':
        return 'FAN';
      case 'hko':
        return 'FAN';
      case 'emsc':
        return 'FAN';
      case 'bcsf':
        return 'FAN';
      case 'gfz':
        return 'FAN';
      case 'usp':
        return 'FAN';
      case 'sa':
        return 'FAN';
      case 'ningxia':
      case 'guangxi':
      case 'shanxi':
      case 'beijing':
      case 'yunnan':
        return 'FAN';
      default:
        return '';
    }
  }

  static UnifiedQuakeData? convert(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) {
    final UnifiedQuakeData? result;
    switch (source) {
      case 'jmaEew':
        result = _jmaEew(source, data, origin);
        break;
      case 'cwaEew':
        result = _cwaEew(source, data, origin);
        break;
      case 'ceaEew':
        result = _ceaEew(source, data, origin);
        break;
      case 'scEew':
        result = _scEew(source, data, origin);
        break;
      case 'cqEew':
        result = _cqEew(source, data, origin);
        break;
      case 'fjEew':
        result = _fjEew(source, data, origin);
        break;
      case 'kmaEew':
        result = _kmaEew(source, data, origin);
        break;
      case 'sa':
        result = _sa(source, data, origin);
        break;
      case 'jmaEqlist':
        result = _jmaEqlist(source, data, origin);
        break;
      case 'cwaEqlist':
        result = _cwaEqlist(source, data, origin);
        break;
      case 'cencEqlist':
        result = _cencEqlist(source, data, origin);
        break;
      case 'kmaEqlist':
        result = _kmaEqlist(source, data, origin);
        break;
      case 'usgsEqlist':
        result = _usgsEqlist(source, data, origin);
        break;
      case 'fssnEqlist':
        result = _fssnEqlist(source, data, origin);
        break;
      case 'hko':
        result = _hko(source, data, origin);
        break;
      case 'emsc':
        result = _emsc(source, data, origin);
        break;
      case 'bcsf':
        result = _bcsf(source, data, origin);
        break;
      case 'gfz':
        result = _gfz(source, data, origin);
        break;
      case 'usp':
        result = _usp(source, data, origin);
        break;
      case 'ningxia':
        result = _ningxia(source, data, origin);
        break;
      case 'guangxi':
        result = _guangxi(source, data, origin);
        break;
      case 'shanxi':
        result = _shanxi(source, data, origin);
        break;
      case 'beijing':
        result = _beijing(source, data, origin);
        break;
      case 'yunnan':
        result = _yunnan(source, data, origin);
        break;
      case 'fssnCmt':
        result = _fssnCmt(source, data, origin);
        break;
      default:
        return null;
    }
    if (result == null) return null;
    final label = _apiTypeLabel(source, origin);
    if (label.isEmpty) return result;
    return result.copyWith(apiTypeLabel: label);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EEW 预警源
  // ═══════════════════════════════════════════════════════════════════════════

  static UnifiedQuakeData? _jmaEew(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) {
    if (data['isTraining'] == true) return null;
    if (data['isCancel'] == true) {
      return UnifiedQuakeData(
        source: source,
        origin: origin,
        eventId: '${data['EventID'] ?? data['eventId'] ?? ''}',
        isEew: true,
        timeZone: 9,
        titleText: '${_trainPrefix(data)}緊急地震速報（キャンセル）',
        reportNumText: origin == _originWolfx
            ? '第${data['Serial']}報'
            : '第${data['updates'] ?? 1}報',
        useShindo: true,
        maxIntensity: 'なし',
        className: 'dark-gray',
        hypocenter: '取り消されました',
        isCanceled: true,
      );
    }

    final isWarn = data['isWarn'] == true;
    final warnStr = isWarn ? '（警報）' : '';
    String title;
    if (origin == _originWolfx) {
      title = '${_trainPrefix(data)}${data['Title'] ?? '緊急地震速報$warnStr'}';
    } else {
      final infoTypeName = data['infoTypeName'] as String? ?? '';
      title =
          '${_trainPrefix(data)}緊急地震速報（${infoTypeName.isNotEmpty ? infoTypeName : (isWarn ? '警報' : '予報')}）';
    }

    final shindo = (data['MaxIntensity'] ?? data['jmaShindo']) as String?;
    final useShindo = true;
    final className = _setClassName(shindo, useShindo, false);
    final eventId = origin == _originWolfx
        ? '${data['EventID'] ?? ''}'
        : '${data['eventId'] ?? ''}';
    final reportNumText = origin == _originWolfx
        ? '第${data['Serial']}報${data['isFinal'] == true ? '（最終）' : ''}'
        : '第${data['updates'] ?? 1}報${data['isFinal'] == true ? '（最終）' : ''}';

    return UnifiedQuakeData(
      source: source,
      origin: origin,
      eventId: eventId,
      isEew: true,
      timeZone: 9,
      titleText: title,
      reportNumText: reportNumText,
      useShindo: useShindo,
      maxIntensity: _normalizeJmaShindo(shindo),
      className: className,
      hypocenter: '${data['Hypocenter'] ?? data['location'] ?? ''}',
      originTime: _parseTime(
        (data['OriginTime'] ?? data['originTime']) as String?,
        9,
      ),
      magnitude: _parseDouble(data['Magunitude'] ?? data['magnitude']) ?? -1,
      depth: _parseDouble(data['Depth'] ?? data['depth']) ?? -1,
      depthText: _formatDepthText(
        _parseDouble(data['Depth'] ?? data['depth']) ?? -1,
        9,
      ),
      lat: _parseDouble(data['Latitude'] ?? data['latitude']) ?? 0,
      lng: _parseDouble(data['Longitude'] ?? data['longitude']) ?? 0,
      isWarn: isWarn,
      isFinal: data['isFinal'] == true,
      isCanceled: false,
      isAssumption: data['isAssumption'] == true,
      warnArea: _parseJmaWarnArea(data, origin),
    );
  }

  static String _parseJmaWarnArea(Map<String, dynamic> data, int origin) {
    if (origin == _originWolfx) {
      final warnArea = data['WarnArea'];
      if (warnArea is! Map) return '';
      final chiiki = warnArea['Chiiki'];
      final shindo1 = warnArea['Shindo1'];
      if (chiiki is! List || shindo1 is! List) return '';
      final items = <Map<String, String>>[];
      for (int i = 0; i < chiiki.length && i < shindo1.length; i++) {
        final name = chiiki[i]?.toString() ?? '';
        final intensity = shindo1[i]?.toString() ?? '';
        if (name.isEmpty) continue;
        items.add({
          'name': name,
          'intensity': intensity,
          'className': _setClassName(intensity, true, false),
        });
      }
      return items.isNotEmpty ? json.encode(items) : '';
    }
    return '';
  }

  static UnifiedQuakeData? _cwaEew(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) {
    final shindoText = _stringValue(
      data['MaxIntensity'] ?? data['jmaShindo'] ?? data['maxIntensity'],
    );
    final useShindo = true;
    final className = _setClassName(shindoText, useShindo, false);
    final isCanceled = data['isCancel'] == true || data['cancel'] == true;
    final isWarn = _isCwaWarn(shindoText);
    final cancelTitle = shindoText == 'Cancel' || isCanceled;
    final eventId =
        _stringValue(
          data['EventID'] ?? data['ID'] ?? data['eventId'] ?? data['id'],
        ) ??
        '';
    final hypocenter =
        _stringValue(
          data['HypoCenter'] ??
              data['Hypocenter'] ??
              data['placeName'] ??
              data['location'],
        ) ??
        '';

    return UnifiedQuakeData(
      source: source,
      origin: origin,
      eventId: eventId,
      isEew: true,
      timeZone: 8,
      titleText: cancelTitle ? '中央氣象署 地震預警（キャンセル）' : '中央氣象署 地震預警',
      reportNumText: origin == _originWolfx
          ? '第${data['ReportNum']}報'
          : '第${data['updates'] ?? 1}報',
      useShindo: useShindo,
      maxIntensity: cancelTitle ? 'なし' : _normalizeJmaShindo(shindoText),
      className: cancelTitle ? 'dark-gray' : className,
      hypocenter: cancelTitle ? '取り消されました' : hypocenter,
      originTime: _parseTime(
        (data['OriginTime'] ?? data['originTime'] ?? data['shockTime'])
            as String?,
        8,
      ),
      reportTime: _parseTime(
        (data['ReportTime'] ??
                data['reportTime'] ??
                data['createTime'] ??
                data['shockTime'])
            as String?,
        8,
      ),
      magnitude: _parseDouble(data['Magunitude'] ?? data['magnitude']) ?? -1,
      depth: _parseDouble(data['Depth'] ?? data['depth']) ?? -1,
      depthText: _formatDepthText(
        _parseDouble(data['Depth'] ?? data['depth']) ?? -1,
        8,
      ),
      lat: _parseDouble(data['Latitude'] ?? data['latitude']) ?? 0,
      lng: _parseDouble(data['Longitude'] ?? data['longitude']) ?? 0,
      isWarn: isWarn,
      isFinal: data['isFinal'] == true || data['final'] == true,
      isCanceled: cancelTitle,
      isAssumption: false,
    );
  }

  static UnifiedQuakeData? _ceaEew(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) {
    final intensityRaw = origin == _originWolfx
        ? _parseDouble(data['MaxIntensity'])
        : _parseDouble(data['maxIntensity']);
    final isWarn = intensityRaw != null && intensityRaw >= 6.5;
    final reportNumText = origin == _originWolfx
        ? '第${(data['ReportNum'] ?? data['ReportCount']) ?? '1'}報'
        : '第${data['updates'] ?? 1}報';

    return UnifiedQuakeData(
      source: source,
      origin: origin,
      eventId: '${data['EventID'] ?? data['eventId'] ?? ''}',
      isEew: true,
      timeZone: 8,
      titleText: '中国地震预警网地震预警',
      reportNumText: reportNumText,
      useShindo: false,
      maxIntensity: intensityRaw != null
          ? intensityRaw.toStringAsFixed(1)
          : '-',
      className: _setClassName(intensityRaw?.toStringAsFixed(1), false, false),
      hypocenter:
          '${data['HypoCenter'] ?? data['Hypocenter'] ?? data['location'] ?? ''}',
      originTime: _parseTime(
        (data['OriginTime'] ?? data['originTime']) as String?,
        8,
      ),
      magnitude:
          _parseDouble(
            data['Magnitude'] ?? data['Magunitude'] ?? data['magnitude'],
          ) ??
          -1,
      depth: _parseDouble(data['Depth'] ?? data['depth']) ?? -1,
      depthText: _formatDepthText(
        _parseDouble(data['Depth'] ?? data['depth']) ?? -1,
        8,
      ),
      lat: _parseDouble(data['Latitude'] ?? data['latitude']) ?? 0,
      lng: _parseDouble(data['Longitude'] ?? data['longitude']) ?? 0,
      isWarn: isWarn,
      isFinal: data['isFinal'] == true,
      isCanceled: false,
      isAssumption: false,
    );
  }

  static UnifiedQuakeData? _scEew(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) {
    final intensityRaw = origin == _originWolfx
        ? _parseDouble(data['MaxIntensity'] ?? data['maxIntensity'])
        : _parseDouble(data['maxIntensity']);
    final isWarn = intensityRaw != null && intensityRaw >= 6.5;

    return UnifiedQuakeData(
      source: source,
      origin: origin,
      eventId: '${data['EventID'] ?? data['eventId'] ?? ''}',
      isEew: true,
      timeZone: 8,
      titleText: '四川省地震局地震预警',
      reportNumText: origin == _originWolfx
          ? '第${data['ReportNum'] ?? '1'}報'
          : '第${data['updates'] ?? 1}報',
      useShindo: false,
      maxIntensity: intensityRaw != null
          ? intensityRaw.toStringAsFixed(1)
          : '-',
      className: _setClassName(intensityRaw?.toStringAsFixed(1), false, false),
      hypocenter:
          '${data['HypoCenter'] ?? data['Hypocenter'] ?? data['location'] ?? ''}',
      originTime: _parseTime(
        (data['OriginTime'] ?? data['originTime']) as String?,
        8,
      ),
      magnitude:
          _parseDouble(
            data['Magnitude'] ?? data['Magunitude'] ?? data['magnitude'],
          ) ??
          -1,
      depth: _parseDouble(data['Depth'] ?? data['depth']) ?? -1,
      depthText: _formatDepthText(
        _parseDouble(data['Depth'] ?? data['depth']) ?? -1,
        8,
      ),
      lat: _parseDouble(data['Latitude'] ?? data['latitude']) ?? 0,
      lng: _parseDouble(data['Longitude'] ?? data['longitude']) ?? 0,
      isWarn: isWarn,
      isFinal: data['isFinal'] == true,
      isCanceled: false,
      isAssumption: false,
    );
  }

  static UnifiedQuakeData? _cqEew(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) {
    final intensityRaw = origin == _originWolfx
        ? _parseDouble(data['MaxIntensity'] ?? data['maxIntensity'])
        : _parseDouble(data['maxIntensity']);
    final isWarn = intensityRaw != null && intensityRaw >= 6.5;

    return UnifiedQuakeData(
      source: source,
      origin: origin,
      eventId: '${data['EventID'] ?? data['eventId'] ?? ''}',
      isEew: true,
      timeZone: 8,
      titleText: '重庆市地震局地震预警',
      reportNumText: origin == _originWolfx
          ? '第${data['ReportNum'] ?? '1'}報'
          : '第${data['updates'] ?? 1}報',
      useShindo: false,
      maxIntensity: intensityRaw != null
          ? intensityRaw.toStringAsFixed(1)
          : '-',
      className: _setClassName(intensityRaw?.toStringAsFixed(1), false, false),
      hypocenter:
          '${data['HypoCenter'] ?? data['Hypocenter'] ?? data['location'] ?? ''}',
      originTime: _parseTime(
        (data['OriginTime'] ?? data['originTime']) as String?,
        8,
      ),
      magnitude:
          _parseDouble(
            data['Magnitude'] ?? data['Magunitude'] ?? data['magnitude'],
          ) ??
          -1,
      depth: _parseDouble(data['Depth'] ?? data['depth']) ?? -1,
      depthText: _formatDepthText(
        _parseDouble(data['Depth'] ?? data['depth']) ?? -1,
        8,
      ),
      lat: _parseDouble(data['Latitude'] ?? data['latitude']) ?? 0,
      lng: _parseDouble(data['Longitude'] ?? data['longitude']) ?? 0,
      isWarn: isWarn,
      isFinal: data['isFinal'] == true,
      isCanceled: false,
      isAssumption: false,
    );
  }

  static UnifiedQuakeData? _fjEew(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) {
    final intensityRaw = origin == _originWolfx
        ? null
        : _parseDouble(data['maxIntensity']);
    final isWarn = intensityRaw != null && intensityRaw >= 6.5;

    return UnifiedQuakeData(
      source: source,
      origin: origin,
      eventId: '${data['EventID'] ?? data['eventId'] ?? ''}',
      isEew: true,
      timeZone: 8,
      titleText: '福建省地震局地震预警',
      reportNumText: origin == _originWolfx
          ? '第${data['ReportNum'] ?? '1'}報'
          : '第${data['updates'] ?? 1}報',
      useShindo: false,
      maxIntensity: intensityRaw != null
          ? intensityRaw.toStringAsFixed(1)
          : '-',
      className: _setClassName(intensityRaw?.toStringAsFixed(1), false, false),
      hypocenter:
          '${data['HypoCenter'] ?? data['Hypocenter'] ?? data['location'] ?? ''}',
      originTime: _parseTime(
        (data['OriginTime'] ?? data['originTime']) as String?,
        8,
      ),
      magnitude:
          _parseDouble(
            data['Magnitude'] ?? data['Magunitude'] ?? data['magnitude'],
          ) ??
          -1,
      depth: _parseDouble(data['Depth'] ?? data['depth']) ?? -1,
      depthText: _formatDepthText(
        _parseDouble(data['Depth'] ?? data['depth']) ?? -1,
        8,
      ),
      lat: _parseDouble(data['Latitude'] ?? data['latitude']) ?? 0,
      lng: _parseDouble(data['Longitude'] ?? data['longitude']) ?? 0,
      isWarn: isWarn,
      isFinal: data['isFinal'] == true,
      isCanceled: false,
      isAssumption: false,
    );
  }

  static UnifiedQuakeData? _kmaEew(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) {
    final intensityRaw = _parseDouble(data['maxIntensity']);
    final isWarn = intensityRaw != null && intensityRaw >= 6.5;

    return UnifiedQuakeData(
      source: source,
      origin: origin,
      eventId: '${data['eventId'] ?? ''}',
      isEew: true,
      timeZone: 9,
      titleText: '기상청 지진조기경보',
      reportNumText: '第${data['updates'] ?? 1}報',
      useShindo: false,
      maxIntensity: intensityRaw != null
          ? intensityRaw.toStringAsFixed(1)
          : '-',
      className: _setClassName(intensityRaw?.toStringAsFixed(1), false, false),
      hypocenter: '${data['location'] ?? ''}',
      originTime: _parseTime(data['originTime'] as String?, 9),
      magnitude: _parseDouble(data['magnitude']) ?? -1,
      depth: _parseDouble(data['depth']) ?? -1,
      depthText: _formatDepthText(_parseDouble(data['depth']) ?? -1, 9),
      lat: _parseDouble(data['latitude']) ?? 0,
      lng: _parseDouble(data['longitude']) ?? 0,
      isWarn: isWarn,
      isFinal: false,
      isCanceled: false,
      isAssumption: false,
    );
  }

  static UnifiedQuakeData? _sa(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) {
    final intensityRaw = _parseDouble(data['maxIntensity']);
    final isWarn = intensityRaw != null && intensityRaw >= 6.5;

    return UnifiedQuakeData(
      source: source,
      origin: origin,
      eventId: '${data['eventId'] ?? ''}',
      isEew: true,
      timeZone: -8,
      titleText: 'ShakeAlert Earthquake Early Warning',
      reportNumText: '第${data['updates'] ?? 1}報',
      useShindo: false,
      maxIntensity: intensityRaw != null
          ? intensityRaw.toStringAsFixed(1)
          : '-',
      className: _setClassName(intensityRaw?.toStringAsFixed(1), false, false),
      hypocenter: '${data['location'] ?? ''}',
      originTime: _parseTime(data['originTime'] as String?, -8),
      magnitude: _parseDouble(data['magnitude']) ?? -1,
      depth: _parseDouble(data['depth']) ?? -1,
      depthText: _formatDepthText(_parseDouble(data['depth']) ?? -1, -8),
      lat: _parseDouble(data['latitude']) ?? 0,
      lng: _parseDouble(data['longitude']) ?? 0,
      isWarn: isWarn,
      isFinal: false,
      isCanceled: false,
      isAssumption: false,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Eqlist 信息源
  // ═══════════════════════════════════════════════════════════════════════════

  static UnifiedQuakeData? _jmaEqlist(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) {
    if (origin == _originP2p) {
      return _p2pJmaEqlist(source, data);
    }
    return _wolfxJmaEqlist(source, data);
  }

  static UnifiedQuakeData? _wolfxJmaEqlist(
    String source,
    Map<String, dynamic> data,
  ) {
    final shindo = data['shindo'] as String?;
    final useShindo = true;
    final title = '${data['Title'] ?? '地震情報'}';
    final depthRaw =
        data['depth']?.toString().replaceAll('km', '').trim() ?? '';
    final depthVal = _parseDouble(depthRaw) ?? -1;

    return UnifiedQuakeData(
      source: source,
      origin: _originWolfx,
      eventId: '${data['EventID'] ?? data['md5'] ?? ''}',
      isEew: false,
      timeZone: 9,
      titleText: title,
      reportNumText: '',
      useShindo: useShindo,
      maxIntensity: _normalizeJmaShindo(shindo),
      className: _setClassName(shindo, useShindo, false),
      hypocenter: '${data['location'] ?? ''}',
      originTime: _parseTime((data['time_full'] ?? data['time']) as String?, 9),
      reportTime: _parseTime(data['ReportTime'] as String?, 9),
      magnitude: _parseDouble(data['magnitude']) ?? -1,
      depth: depthVal,
      depthText: _formatDepthText(depthVal, 9),
      lat: _parseDouble(data['latitude']) ?? 0,
      lng: _parseDouble(data['longitude']) ?? 0,
    );
  }

  static UnifiedQuakeData? _p2pJmaEqlist(
    String source,
    Map<String, dynamic> data,
  ) {
    final issue = data['issue'] as Map<String, dynamic>?;
    final earthquake = data['earthquake'] as Map<String, dynamic>?;
    if (issue == null) return null;

    final rawHypocenter = earthquake?['hypocenter'];
    final hypocenter = rawHypocenter is Map
        ? Map<String, dynamic>.from(rawHypocenter)
        : null;
    final hasHypocenter = _hasValidP2pHypocenter(hypocenter);
    final issueType = issue['type'] as String? ?? '';
    final isScalePrompt = issueType == 'ScalePrompt';
    final isDestination = issueType == 'Destination';

    final useShindo = true;
    String hypocent;
    double mag;
    String maxIntensityStr;

    if (isScalePrompt) {
      hypocent = hasHypocenter ? (hypocenter?['name']?.toString() ?? '') : '';
      mag = hasHypocenter ? _parseDouble(hypocenter?['magnitude']) ?? -1 : -1;
      final maxScale = _parseInt(earthquake?['maxScale']);
      maxIntensityStr = _p2pMaxScaleToShindo(maxScale);
      if (maxIntensityStr == '不明') {
        maxIntensityStr = _extractScalePromptShindo(data);
      }
    } else if (isDestination) {
      hypocent = hypocenter?['name']?.toString() ?? '';
      mag = _parseDouble(hypocenter?['magnitude']) ?? -1;
      final maxScale = _parseInt(earthquake?['maxScale']);
      maxIntensityStr = _p2pMaxScaleToShindo(maxScale);
    } else {
      hypocent = hypocenter?['name']?.toString() ?? '';
      mag = _parseDouble(hypocenter?['magnitude']) ?? -1;
      final maxScale = _parseInt(earthquake?['maxScale']);
      maxIntensityStr = _p2pMaxScaleToShindo(maxScale);
    }

    final timeStr = earthquake?['time'] as String? ?? issue['time'] as String?;
    final eventId =
        (earthquake?['time'] as String?)?.replaceAll('/', '-').trim() ??
        '${issue['eventId'] ?? data['_id'] ?? ''}';

    final warnArea = _parseP2pPoints(data);
    final double depth = hasHypocenter || !isScalePrompt
        ? _parseDouble(hypocenter?['depth']) ?? -1
        : -1;
    final double? lat = hasHypocenter || !isScalePrompt
        ? _parseDouble(hypocenter?['latitude'])
        : null;
    final double? lng = hasHypocenter || !isScalePrompt
        ? _parseDouble(hypocenter?['longitude'])
        : null;

    return UnifiedQuakeData(
      source: source,
      origin: _originP2p,
      eventId: eventId,
      isEew: false,
      timeZone: 9,
      titleText: _p2pTitleText(issueType),
      reportNumText: '',
      useShindo: useShindo,
      maxIntensity: _normalizeJmaShindo(maxIntensityStr),
      className: _setClassName(maxIntensityStr, useShindo, false),
      hypocenter: hypocent,
      originTime: _parseTime(timeStr, 9),
      reportTime: _parseTime(issue['time'] as String?, 9),
      magnitude: mag,
      depth: depth,
      depthText: _formatDepthText(depth, 9),
      lat: lat,
      lng: lng,
      warnArea: warnArea,
    );
  }

  static bool _hasValidP2pHypocenter(Map<String, dynamic>? hypocenter) {
    if (hypocenter == null) return false;
    final name = hypocenter['name']?.toString().trim() ?? '';
    final lat = _parseDouble(hypocenter['latitude']);
    final lng = _parseDouble(hypocenter['longitude']);
    return name.isNotEmpty &&
        !_isInvestigatingText(name) &&
        lat != null &&
        lng != null &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180;
  }

  static String _parseP2pPoints(Map<String, dynamic> data) {
    final points = data['points'] as List?;
    if (points == null || points.isEmpty) return '';

    final maxScaleByName = <String, int?>{};
    for (final p in points) {
      if (p is! Map<String, dynamic>) continue;
      final addr = p['addr']?.toString() ?? '';
      final isArea = p['isArea'] == true;
      final scale = _parseInt(p['scale']);

      String name;
      if (isArea) {
        name = addr;
      } else {
        name = JmaSeisIntLoc.getSectForStation(addr) ?? addr;
      }

      if (name.isNotEmpty) {
        final existing = maxScaleByName[name];
        if (existing == null || (scale ?? -1) > existing) {
          maxScaleByName[name] = scale;
        }
      }
    }
    final items = maxScaleByName.entries
        .map((entry) {
          final intensity = _p2pScaleToShindo(entry.value);
          final className = _setClassName(intensity, true, false);
          return {
            'name': entry.key,
            'intensity': intensity,
            'className': className,
          };
        })
        .toList(growable: false);
    return items.isNotEmpty ? json.encode(items) : '';
  }

  static String _p2pScaleToShindo(int? scale) {
    if (scale == null || scale <= 0) return '0';
    final s = scale / 10.0;
    if (s < 0.5) return "0";
    if (s < 1.5) return "1";
    if (s < 2.5) return "2";
    if (s < 3.5) return "3";
    if (s < 4.5) return "4";
    if (s < 5.0) return "5-";
    if (s < 5.5) return "5+";
    if (s < 6.0) return "6-";
    if (s < 6.5) return "6+";
    return "7";
  }

  static String _p2pMaxScaleToShindo(int? maxScale) {
    if (maxScale == null || maxScale <= 0) return '不明';
    return _p2pScaleToShindo(maxScale);
  }

  static String _p2pTitleText(String issueType) {
    switch (issueType) {
      case 'ScalePrompt':
        return '震度速報';
      case 'Destination':
        return '震源に関する情報';
      case 'ScaleAndDestination':
        return '震度・震源に関する情報';
      case 'DetailScale':
        return '各地の震度に関する情報';
      case 'Foreign':
        return '遠地地震に関する情報';
      case 'Other':
        return 'その他の情報';
      default:
        return '地震情報';
    }
  }

  static String _extractScalePromptShindo(Map<String, dynamic> data) {
    final points = data['points'] as List<dynamic>?;
    if (points == null || points.isEmpty) return '-';
    int maxScale = -1;
    for (final p in points) {
      final scale = _parseInt(p['scale']);
      if (scale != null && scale > maxScale) maxScale = scale;
    }
    if (maxScale < 0) return '-';
    return _p2pMaxScaleToShindo(maxScale);
  }

  static UnifiedQuakeData? _cwaEqlist(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) {
    final shindoText =
        (data['jmaShindo'] ?? data['maxIntensity']?.toString()) as String?;
    final useShindo = true;

    return UnifiedQuakeData(
      source: source,
      origin: origin,
      eventId: '${data['eventId'] ?? ''}',
      isEew: false,
      timeZone: 8,
      titleText: '中央氣象署 地震報告${_reviewSuffix(data['reviewType'] as String?)}',
      reportNumText: '',
      useShindo: useShindo,
      maxIntensity: _normalizeJmaShindo(shindoText),
      className: _setClassName(shindoText, useShindo, false),
      hypocenter: '${data['location'] ?? ''}',
      originTime: _parseTime(data['originTime'] as String?, 8),
      // 参照 kanameishi: CWA 用发震时间 + 5分钟估算报告时间。
      reportTime: _addMinutes(_parseTime(data['originTime'] as String?, 8), 5),
      magnitude: _parseDouble(data['magnitude']) ?? -1,
      depth: _parseDouble(data['depth']) ?? -1,
      depthText: _formatDepthText(_parseDouble(data['depth']) ?? -1, 8),
      lat: _parseDouble(data['latitude']) ?? 0,
      lng: _parseDouble(data['longitude']) ?? 0,
    );
  }

  static UnifiedQuakeData? _cencEqlist(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) {
    final rawReviewType =
        data['reviewType'] as String? ?? data['type'] as String?;
    final reviewType = rawReviewType == '正式测定'
        ? 'reviewed'
        : (rawReviewType == '自动测定' ? 'automatic' : rawReviewType);
    final reviewLabel = reviewType == 'reviewed' ? '正式测定' : '自动测定';
    final intensityRaw = _parseDouble(
      data['maxIntensity'] ?? data['intensity'],
    );
    final magnitude =
        _parseDouble(data['magnitude'] ?? data['Magnitude']) ?? -1;
    final depth = _parseDouble(data['depth'] ?? data['Depth']) ?? -1;
    final originTime = _parseTime(
      (data['originTime'] ?? data['shockTime'] ?? data['time']) as String?,
      8,
    );
    final lat = _parseDouble(data['latitude'] ?? data['Latitude']) ?? 0;
    final lng = _parseDouble(data['longitude'] ?? data['Longitude']) ?? 0;
    final reportTime = _parseTime(
      (origin == 0
              ? data['ReportTime']
              : data['createTime'] ?? data['updateTime'] ?? data['ReportTime'])
          as String?,
      8,
    );

    String maxIntensityStr;
    String className;
    if (intensityRaw != null && intensityRaw > 0) {
      maxIntensityStr = intensityRaw.toStringAsFixed(1);
      className = _setClassName(maxIntensityStr, false, false);
    } else {
      final calcIntensity = _calcIntensity(magnitude, depth);
      maxIntensityStr = calcIntensity > 0
          ? calcIntensity.toStringAsFixed(1)
          : '-';
      className = _setClassName(maxIntensityStr, false, false);
    }

    return UnifiedQuakeData(
      source: source,
      origin: origin,
      eventId: _cencInfoEventId(data, originTime, lat, lng),
      isEew: false,
      timeZone: 8,
      titleText: '中国地震台网地震信息',
      reportNumText: reviewLabel,
      useShindo: false,
      maxIntensity: maxIntensityStr,
      className: className,
      hypocenter:
          '${data['location'] ?? data['placeName'] ?? data['HypoCenter'] ?? ''}',
      originTime: originTime,
      // 参照 kanameishi: Wolfx(origin=0) 用 ReportTime，FAN(origin=1) 用 createTime
      reportTime: reportTime ?? originTime,
      magnitude: magnitude,
      depth: depth,
      depthText: _formatDepthText(depth, 8),
      lat: lat,
      lng: lng,
    );
  }

  static String _cencInfoEventId(
    Map<String, dynamic> data,
    DateTime? originTime,
    double lat,
    double lng,
  ) {
    final eventId = '${data['eventId'] ?? data['EventID'] ?? ''}'.trim();
    if (eventId.isNotEmpty) return eventId;

    // Wolfx cenc_eqlist 没有稳定 eventId；md5 是更新校验，不能作为事件身份。
    // 用发震时间 + 坐标锁定同一地震，避免 automatic/reviewed md5 变化导致重复事件。
    final timeKey =
        originTime?.toIso8601String() ??
        '${data['originTime'] ?? data['shockTime'] ?? data['time'] ?? ''}';
    final latKey = lat.toStringAsFixed(3);
    final lngKey = lng.toStringAsFixed(3);
    if (timeKey.trim().isNotEmpty && (lat != 0 || lng != 0)) {
      return 'cenc_${timeKey}_${latKey}_$lngKey';
    }

    final location = '${data['location'] ?? data['placeName'] ?? ''}'.trim();
    final magnitude = '${data['magnitude'] ?? data['Magnitude'] ?? ''}'.trim();
    if (timeKey.trim().isNotEmpty && location.isNotEmpty) {
      return 'cenc_${timeKey}_${location}_M$magnitude';
    }

    return '${data['md5'] ?? data['ID'] ?? ''}';
  }

  static UnifiedQuakeData? _kmaEqlist(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) {
    final intensityRaw = _parseDouble(data['maxIntensity']);
    final magnitude = _parseDouble(data['magnitude']) ?? -1;
    final depth = _parseDouble(data['depth']) ?? -1;

    String maxIntensityStr;
    String className;
    if (intensityRaw != null && intensityRaw > 0) {
      maxIntensityStr = intensityRaw.toStringAsFixed(1);
      className = _setClassName(maxIntensityStr, false, false);
    } else {
      final calcIntensity = _calcIntensity(magnitude, depth);
      maxIntensityStr = calcIntensity > 0
          ? calcIntensity.toStringAsFixed(1)
          : '-';
      className = _setClassName(maxIntensityStr, false, false);
    }

    return UnifiedQuakeData(
      source: source,
      origin: origin,
      eventId: '${data['eventId'] ?? ''}',
      isEew: false,
      timeZone: 9,
      titleText: '기상청 지진정보${_reviewSuffix(data['reviewType'] as String?)}',
      reportNumText: '',
      useShindo: false,
      maxIntensity: maxIntensityStr,
      className: className,
      hypocenter: '${data['location'] ?? ''}',
      originTime: _parseTime(data['originTime'] as String?, 9),
      reportTime: _parseTime(data['createTime'] as String?, 9),
      magnitude: magnitude,
      depth: depth,
      depthText: _formatDepthText(depth, 9),
      lat: _parseDouble(data['latitude']) ?? 0,
      lng: _parseDouble(data['longitude']) ?? 0,
    );
  }

  static UnifiedQuakeData? _usgsEqlist(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) {
    final intensityRaw = _parseDouble(data['maxIntensity']);
    final magnitude = _parseDouble(data['magnitude']) ?? -1;
    final depth = _parseDouble(data['depth']) ?? -1;

    String maxIntensityStr;
    String className;
    if (intensityRaw != null && intensityRaw > 0) {
      maxIntensityStr = intensityRaw.toStringAsFixed(1);
      className = _setClassName(maxIntensityStr, false, false);
    } else {
      final calcIntensity = _calcIntensity(magnitude, depth);
      maxIntensityStr = calcIntensity > 0
          ? calcIntensity.toStringAsFixed(1)
          : '-';
      className = _setClassName(maxIntensityStr, false, false);
    }

    return UnifiedQuakeData(
      source: source,
      origin: origin,
      eventId: '${data['eventId'] ?? ''}',
      isEew: false,
      timeZone: 8,
      titleText: 'USGS 地震情报${_reviewSuffix(data['reviewType'] as String?)}',
      reportNumText: '',
      useShindo: false,
      maxIntensity: maxIntensityStr,
      className: className,
      hypocenter: '${data['location'] ?? ''}',
      originTime: _parseTime(data['originTime'] as String?, 8),
      // FAN API: USGS 有 updateTime，没有 createTime，fallback 到 shockTime
      reportTime:
          _parseTime(data['updateTime'] as String?, 8) ??
          _parseTime(data['shockTime'] as String?, 8),
      magnitude: magnitude,
      depth: depth,
      depthText: _formatDepthText(depth, 8),
      lat: _parseDouble(data['latitude']) ?? 0,
      lng: _parseDouble(data['longitude']) ?? 0,
    );
  }

  static UnifiedQuakeData? _fssnEqlist(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) {
    final intensityRaw = _parseDouble(data['maxIntensity']);
    final magnitude = _parseDouble(data['magnitude']) ?? -1;
    final depth = _parseDouble(data['depth']) ?? -1;

    String maxIntensityStr;
    String className;
    if (intensityRaw != null && intensityRaw > 0) {
      maxIntensityStr = intensityRaw.toStringAsFixed(1);
      className = _setClassName(maxIntensityStr, false, false);
    } else {
      final calcIntensity = _calcIntensity(magnitude, depth);
      maxIntensityStr = calcIntensity > 0
          ? calcIntensity.toStringAsFixed(1)
          : '-';
      className = _setClassName(maxIntensityStr, false, false);
    }

    return UnifiedQuakeData(
      source: source,
      origin: origin,
      eventId: '${data['eventId'] ?? ''}',
      isEew: false,
      timeZone: 8,
      titleText: 'FSSN 地震情报${_reviewSuffix(data['reviewType'] as String?)}',
      reportNumText: '',
      useShindo: false,
      maxIntensity: maxIntensityStr,
      className: className,
      hypocenter: '${data['location'] ?? ''}',
      originTime: _parseTime(data['originTime'] as String?, 8),
      // FAN API: FSSN 没有 createTime，fallback 到 shockTime
      reportTime:
          _parseTime(data['createTime'] as String?, 8) ??
          _parseTime(data['shockTime'] as String?, 8),
      magnitude: magnitude,
      depth: depth,
      depthText: _formatDepthText(depth, 8),
      lat: _parseDouble(data['latitude']) ?? 0,
      lng: _parseDouble(data['longitude']) ?? 0,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 独立信息源（仅 FAN）
  // ═══════════════════════════════════════════════════════════════════════════

  static UnifiedQuakeData? _hko(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) => _genericInfo(
    source: source,
    origin: origin,
    data: data,
    title: '香港天文台地震情报${_infoTitleSuffix(data)}',
    timeZone: 8,
  );

  static UnifiedQuakeData? _emsc(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) => _genericInfo(
    source: source,
    origin: origin,
    data: data,
    title: 'EMSC 地震情报${_infoTitleSuffix(data)}',
    timeZone: 8,
  );

  static UnifiedQuakeData? _bcsf(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) => _genericInfo(
    source: source,
    origin: origin,
    data: data,
    title: 'BCSF 地震情报${_infoTitleSuffix(data)}',
    timeZone: 8,
  );

  static UnifiedQuakeData? _gfz(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) => _genericInfo(
    source: source,
    origin: origin,
    data: data,
    title: 'GFZ 地震信息${_infoTitleSuffix(data)}',
    timeZone: 8,
  );

  static UnifiedQuakeData? _usp(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) => _genericInfo(
    source: source,
    origin: origin,
    data: data,
    title: 'USP 地震信息${_infoTitleSuffix(data)}',
    timeZone: 8,
  );

  static UnifiedQuakeData? _ningxia(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) => _genericInfo(
    source: source,
    origin: origin,
    data: data,
    title: '宁夏地震局地震信息${_infoTitleSuffix(data)}',
    timeZone: 8,
  );

  static UnifiedQuakeData? _guangxi(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) => _genericInfo(
    source: source,
    origin: origin,
    data: data,
    title: '广西地震局地震信息${_infoTitleSuffix(data)}',
    timeZone: 8,
  );

  static UnifiedQuakeData? _shanxi(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) => _genericInfo(
    source: source,
    origin: origin,
    data: data,
    title: '山西地震局地震信息${_infoTitleSuffix(data)}',
    timeZone: 8,
  );

  static UnifiedQuakeData? _beijing(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) => _genericInfo(
    source: source,
    origin: origin,
    data: data,
    title: '北京地震局地震信息${_infoTitleSuffix(data)}',
    timeZone: 8,
  );

  static UnifiedQuakeData? _yunnan(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) => _genericInfo(
    source: source,
    origin: origin,
    data: data,
    title: '云南地震局地震信息${_infoTitleSuffix(data)}',
    timeZone: 8,
  );

  static UnifiedQuakeData? _fssnCmt(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) {
    return UnifiedQuakeData(
      source: source,
      origin: origin,
      eventId: '${data['eventId'] ?? ''}',
      isEew: false,
      timeZone: 8,
      titleText: 'FSSN 地震矩心矩张量解',
      reportNumText: '',
      useShindo: false,
      maxIntensity: '-',
      className: 'gray',
      hypocenter: '${data['location'] ?? ''}',
      originTime: _parseTime(data['originTime'] as String?, 8),
      // FAN API: FSSN-CMT 没有 createTime，fallback 到 shockTime
      reportTime:
          _parseTime(data['createTime'] as String?, 8) ??
          _parseTime(data['shockTime'] as String?, 8),
      magnitude: _parseDouble(data['magnitude']) ?? -1,
      depth: _parseDouble(data['depth']) ?? -1,
      depthText: _formatDepthText(_parseDouble(data['depth']) ?? -1, 8),
      lat: _parseDouble(data['latitude']) ?? 0,
      lng: _parseDouble(data['longitude']) ?? 0,
      nodalPlane1: data['nodalPlane1']?.toString(),
      nodalPlane2: data['nodalPlane2']?.toString(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 通用信息源工厂
  // ═══════════════════════════════════════════════════════════════════════════

  static UnifiedQuakeData? _genericInfo({
    required String source,
    required int origin,
    required Map<String, dynamic> data,
    required String title,
    required int timeZone,
  }) {
    final intensityRaw = _parseDouble(data['maxIntensity']);
    final magnitude =
        _parseDouble(data['magnitude'] ?? data['magnitudel']) ?? -1;
    final depth = _parseDouble(data['depth']) ?? -1;
    final eventId =
        _stringValue(data['eventId'] ?? data['id'] ?? data['ID']) ?? '';
    final location =
        _stringValue(
          data['location'] ??
              data['placeName'] ??
              data['HypoCenter'] ??
              data['title'],
        ) ??
        '';
    final originTimeText = _stringValue(
      data['originTime'] ?? data['shockTime'] ?? data['time'],
    );
    final reportTimeText = _stringValue(
      data['createTime'] ?? data['updateTime'] ?? data['reportTime'],
    );

    String maxIntensityStr;
    String className;
    if (intensityRaw != null && intensityRaw > 0) {
      maxIntensityStr = intensityRaw.toStringAsFixed(1);
      className = _setClassName(maxIntensityStr, false, false);
    } else {
      final calcIntensity = _calcIntensity(magnitude, depth);
      maxIntensityStr = calcIntensity > 0
          ? calcIntensity.toStringAsFixed(1)
          : '-';
      className = _setClassName(maxIntensityStr, false, false);
    }

    return UnifiedQuakeData(
      source: source,
      origin: origin,
      eventId: eventId,
      isEew: false,
      timeZone: timeZone,
      titleText: title,
      reportNumText: '',
      useShindo: false,
      maxIntensity: maxIntensityStr,
      className: className,
      hypocenter: location,
      originTime: _parseTime(originTimeText, timeZone),
      reportTime: _parseTime(reportTimeText, timeZone),
      magnitude: magnitude,
      depth: depth,
      depthText: _formatDepthText(depth, timeZone),
      lat: _parseDouble(data['latitude']) ?? 0,
      lng: _parseDouble(data['longitude']) ?? 0,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 辅助方法
  // ═══════════════════════════════════════════════════════════════════════════

  /// 给 DateTime 加指定分钟数（参照 kanameishi CWA 的 shockTime + 5min）
  static DateTime? _addMinutes(DateTime? dt, int minutes) {
    return dt?.add(Duration(minutes: minutes));
  }

  static String _setClassName(
    String? intensityStr,
    bool useShindo,
    bool isCanceled,
  ) {
    if (isCanceled) return 'dark-gray';

    if (useShindo && intensityStr != null) {
      final num = _jmaShindoToNum(intensityStr);
      return _intensityToClassName(num, useShindo: true);
    }

    final val = double.tryParse(intensityStr ?? '');
    if (val == null) return 'gray';
    return _intensityToClassName(val, useShindo: false);
  }

  static String _intensityToClassName(
    double intensity, {
    bool useShindo = false,
  }) {
    if (useShindo) {
      if (intensity >= 7.0) return 'purple';
      if (intensity >= 6.5) return 'dark-red';
      if (intensity >= 6.0) return 'red';
      if (intensity >= 5.5) return 'dark-orange';
      if (intensity >= 5.0) return 'orange';
      if (intensity >= 4.0) return 'yellow';
      if (intensity >= 3.0) return 'green';
      if (intensity >= 2.0) return 'blue';
      if (intensity >= 1.0) return 'gray';
      return 'dark-gray';
    }
    final level = intensity.round();
    if (level >= 10) return 'purple';
    if (level == 9) return 'red';
    if (level == 8) return 'dark-orange';
    if (level == 7) return 'orange';
    if (level == 6) return 'yellow';
    if (level == 5) return 'green';
    if (level == 4) return 'blue';
    if (level == 3) return 'sky-blue';
    if (level == 2) return 'gray';
    if (level == 1) return 'dark-gray';
    return 'gray';
  }

  static double _jmaShindoToNum(String shindo) {
    final trimmed = shindo.trim();
    switch (trimmed) {
      case '0':
        return 0;
      case '1':
        return 1.0;
      case '2':
        return 2.0;
      case '3':
        return 3.0;
      case '4':
        return 4.0;
      case '5':
        return 5.0;
      case '5弱':
      case '5-':
        return 5.0;
      case '5強':
      case '5强':
      case '5+':
        return 5.5;
      case '6':
        return 6.0;
      case '6弱':
      case '6-':
        return 6.0;
      case '6強':
      case '6强':
      case '6+':
        return 6.5;
      case '7':
        return 7.0;
      default:
        final cleaned = trimmed
            .replaceAll('強', '+')
            .replaceAll('强', '+')
            .replaceAll('弱', '-')
            .replaceAll('−', '-')
            .replaceAll('＋', '+')
            .replaceAll('級', '');
        switch (cleaned) {
          case '5-':
            return 5.0;
          case '5+':
            return 5.5;
          case '6-':
            return 6.0;
          case '6+':
            return 6.5;
          default:
            return 0;
        }
    }
  }

  static String _normalizeJmaShindo(String? shindo) {
    if (shindo == null || shindo.isEmpty) return '-';
    final trimmed = shindo.trim();
    if (_isUnknownJmaShindo(trimmed)) return '-';
    if (trimmed == '0') return '0';
    if (trimmed == '1') return '1';
    if (trimmed == '2') return '2';
    if (trimmed == '3') return '3';
    if (trimmed == '4') return '4';
    if (trimmed == '5') return '5';
    if (trimmed == '5弱' || trimmed == '5-' || trimmed == '5−') return '5-';
    if (trimmed == '5強' ||
        trimmed == '5强' ||
        trimmed == '5+' ||
        trimmed == '5＋') {
      return '5+';
    }
    if (trimmed == '6') return '6';
    if (trimmed == '6弱' || trimmed == '6-' || trimmed == '6−') return '6-';
    if (trimmed == '6強' ||
        trimmed == '6强' ||
        trimmed == '6+' ||
        trimmed == '6＋') {
      return '6+';
    }
    if (trimmed == '7') return '7';
    final cleaned = trimmed
        .replaceAll('強', '+')
        .replaceAll('强', '+')
        .replaceAll('弱', '-')
        .replaceAll('−', '-')
        .replaceAll('＋', '+')
        .replaceAll('級', '');
    if (cleaned == '5-') return '5-';
    if (cleaned == '5+') return '5+';
    if (cleaned == '6-') return '6-';
    if (cleaned == '6+') return '6+';
    return shindo;
  }

  static String? _stringValue(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static bool _isUnknownJmaShindo(String? shindo) {
    if (shindo == null) return true;
    return _isInvestigatingText(shindo);
  }

  static bool _isInvestigatingText(String text) {
    final s = text.trim().toLowerCase();
    if (s.isEmpty) return true;
    return s == '-' ||
        s == '不明' ||
        s == '不詳' ||
        s == '調査中' ||
        s == '调查中' ||
        s == '震度調査中' ||
        s == '震度调查中' ||
        s == 'unknown';
  }

  static String _trainPrefix(Map<String, dynamic> data) {
    if (data['isTraining'] == true) return '【訓練】';
    return '';
  }

  static bool _isCwaWarn(String? shindoText) {
    if (shindoText == null || shindoText.isEmpty) return false;
    if (shindoText == 'Cancel' || shindoText == 'なし') return false;
    final num = _jmaShindoToNum(shindoText);
    return num >= 5.0;
  }

  static String _infoTitleSuffix(Map<String, dynamic> data) {
    final verify = data['verify']?.toString();
    if (verify == 'Y' || verify == '已核实') return '已核实';
    if (verify == 'N' || verify == '待核实') return '待核实';
    if (verify == 'passed' || verify == 'reviewed') return '正式测定';
    if (verify == 'unverified' || verify == 'automatic') return '自动测定';

    final reviewType =
        data['reviewType']?.toString() ?? data['type']?.toString();
    if (reviewType == '已核实') return '已核实';
    if (reviewType == '待核实') return '待核实';
    if (reviewType == 'reviewed' || reviewType == '正式测定') return '正式测定';
    if (reviewType == 'automatic' || reviewType == '自动测定') return '自动测定';
    return '';
  }

  static String _reviewSuffix(String? reviewType) {
    if (reviewType == 'reviewed' || reviewType == '正式测定') return '正式测定';
    if (reviewType == 'automatic' || reviewType == '自动测定') return '自动测定';
    return '';
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _parseTime(String? timeStr, int timeZoneOffset) {
    if (timeStr == null || timeStr.isEmpty) return null;
    try {
      final normalized = timeStr.replaceAll('/', '-');
      return DateTime.parse(normalized);
    } catch (_) {
      return null;
    }
  }

  static String _formatDepthText(double depth, int timeZone) {
    if (depth < 0) return '';
    if (timeZone == 9 && depth == 0) return '深さ: ごく浅い';
    if (timeZone == 9) return '深さ: ${depth.toInt()}km';
    return '深度: ${depth.toInt()}km';
  }

  static int _calcIntensity(double magnitude, double depth) {
    if (magnitude <= 0 || depth < 0) return 0;
    final val = 0.92 + 1.63 * magnitude - 3.49 * _log10(depth + 7);
    return val.clamp(0, 12).round();
  }

  static double _log10(double x) {
    if (x <= 0) return 0;
    return _ln(x) / _ln(10);
  }

  static double _ln(double x) {
    double result = 0;
    double term = (x - 1) / (x + 1);
    double termSquared = term * term;
    double current = term;
    int n = 1;
    while (current.abs() > 1e-10) {
      result += current / n;
      current *= termSquared;
      n += 2;
    }
    return 2 * result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 历史列表转换（参考 kanameishi setHistory）
  // ═══════════════════════════════════════════════════════════════════════════

  static List<QuakeMessage> convertWolfxJmaEqlist(Map<String, dynamic> data) {
    final items = <QuakeMessage>[];
    final keys = data.keys.where((k) => k.startsWith('No'));
    for (final key in keys) {
      final entry = data[key];
      if (entry is! Map<String, dynamic>) continue;
      final depthRaw =
          entry['depth']?.toString().replaceAll('km', '').trim() ?? '';
      final depthVal = _parseDouble(depthRaw) ?? -1;
      final shindo = entry['shindo'] as String?;
      if (_isUnknownJmaShindo(shindo)) continue;
      final location = '${entry['location'] ?? ''}'.trim();
      if (_isInvestigatingText(location)) continue;
      final timeFull = (entry['time_full'] ?? entry['time']) as String?;
      items.add(
        QuakeMessage(
          source: QuakeSourceType.wolfx,
          eventId: '${entry['EventID'] ?? entry['md5'] ?? ''}',
          location: location,
          magnitude: _parseDouble(entry['magnitude']) ?? -1,
          latitude: _parseDouble(entry['latitude']) ?? 0,
          longitude: _parseDouble(entry['longitude']) ?? 0,
          depth: depthVal,
          originTime: _parseTime(timeFull, 9) ?? DateTime.now(),
          jmaShindo: _normalizeJmaShindo(shindo),
          isHistory: true,
          isTest: false,
          isInfoEvent: true,
          infoTypeName: '${entry['Title'] ?? '地震情報'}',
        ),
      );
    }
    return items;
  }

  static List<QuakeMessage> convertWolfxCencEqlist(Map<String, dynamic> data) {
    final items = <QuakeMessage>[];
    final keys = data.keys.where((k) => k.startsWith('No'));
    for (final key in keys) {
      final entry = data[key];
      if (entry is! Map<String, dynamic>) continue;
      final intensityRaw = _parseDouble(
        entry['intensity'] ?? entry['maxIntensity'],
      );
      final magnitude =
          _parseDouble(entry['magnitude'] ?? entry['Magnitude']) ?? -1;
      final depth = _parseDouble(entry['depth'] ?? entry['Depth']) ?? -1;
      final rawType =
          entry['type']?.toString() ?? entry['reviewType']?.toString() ?? '';
      final reviewType = rawType == '正式测定'
          ? 'reviewed'
          : (rawType == '自动测定' ? 'automatic' : rawType);
      items.add(
        QuakeMessage(
          source: QuakeSourceType.cenc,
          eventId: _cencInfoEventId(
            entry,
            _parseTime((entry['originTime'] ?? entry['time']) as String?, 8),
            _parseDouble(entry['latitude'] ?? entry['Latitude']) ?? 0,
            _parseDouble(entry['longitude'] ?? entry['Longitude']) ?? 0,
          ),
          location: '${entry['location'] ?? entry['placeName'] ?? ''}',
          magnitude: magnitude,
          latitude: _parseDouble(entry['latitude'] ?? entry['Latitude']) ?? 0,
          longitude:
              _parseDouble(entry['longitude'] ?? entry['Longitude']) ?? 0,
          depth: depth,
          originTime:
              _parseTime(
                (entry['originTime'] ?? entry['time']) as String?,
                8,
              ) ??
              DateTime.now(),
          maxIntensity: intensityRaw?.round() ?? 0,
          isHistory: true,
          isTest: false,
          isInfoEvent: true,
          infoTypeName: reviewType == 'reviewed' ? '正式测定' : '自动测定',
        ),
      );
    }
    return items;
  }
}
