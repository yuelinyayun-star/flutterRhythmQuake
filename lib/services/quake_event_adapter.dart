import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/source_payload.dart';
import '../models/unified_quake_data.dart';
import '../models/cmt_moment_tensor.dart';
import '../models/cmt_solution_metadata.dart';
import '../models/quake_message.dart';
import '../models/whews_catalog.dart';
import '../models/jian_sources.dart';
import '../utils/catalog_location.dart';
import '../models/volcano_event_data.dart';
import '../core/intensity_calculator.dart';
import '../core/utils/jma_seis_int_loc.dart';
import '../core/utils/quake_time.dart';
import '../utils/kma_location.dart';

class QuakeEventAdapter {
  static const _originWolfx = 0;
  static const _originFan = 1;
  static const _originP2p = 2;
  static const _originWhews = 3;

  QuakeEventAdapter._();

  static const jianOrigin = 4;

  /// Jian has its own wire contract, but emits the same agency identities as
  /// the other APIs. Never mutate raw data or manufacture a report timestamp.
  static UnifiedQuakeData? convertJian(
    String type,
    Map<String, dynamic> raw, {
    bool isHistory = false,
    bool isSnapshot = false,
  }) {
    final source = jianEarthquakeSources[type];
    if (source == null || raw['isTraining'] == true) return null;
    final id = _stringValue(raw['id']);
    if (id == null || id.isEmpty) return null;
    final eew = jianEewTypes.contains(type);
    final japanese = type == 'jma' || type == 'jma-eew';
    final korean = type == 'kma' || type == 'kma-eew';
    final useShindo = japanese || type == 'cwa' || type == 'cwa-eew';
    final zone = japanese || korean ? 9 : 8;
    final originTime = _parseTime(raw['originTime'], zone);
    final reportTime = _parseTime(raw['reportTime'], zone);
    final canceled = raw['isCancel'] == true || raw['infoType'] == '取消';
    final magnitude = raw['magnitudeUnknown'] == true
        ? -1.0
        : (_catalogNumber(raw['magnitude']) ?? -1.0);
    var depth = _catalogNumber(raw['depth']) ?? -1.0;
    if (korean && depth == 0) depth = -1;
    final lat = _catalogNumber(raw['latitude']);
    final lng = _catalogNumber(raw['longitude']);
    final hasLocation =
        raw['hypocenterUnknown'] != true && hasCatalogCoordinates(lat, lng);
    final originalLocation = _stringValue(raw['placeName']) ?? '';
    final location = korean
        ? (_stringValue(raw['placename_zh']) ??
              kmaDisplayLocation(originalLocation, lat, lng))
        : japanese
        ? originalLocation
        : catalogDisplayLocation(originalLocation, lat, lng);
    final intensityValue = raw['intensity'] ?? raw['maxMMI'];
    final intensity = useShindo
        ? _normalizeJmaShindo(_stringValue(intensityValue))
        : parseReportedIntensity(intensityValue)?.toString() ??
              (eew ? '-' : _whewsFallbackIntensity(magnitude, depth));
    final serial = _parseInt(raw['serial'] ?? raw['number']);
    final review = _stringValue(raw['infoTypeName']) ?? '';
    final sourceType = jianSourceType(source)!;
    final title = switch (type) {
      'jma-eew' =>
        '緊急地震速報（${canceled
            ? 'キャンセル'
            : raw['isWarn'] == true
            ? '警報'
            : '予報'}）',
      'jma' => _stringValue(raw['title']) ?? '地震情報',
      'cwa-eew' => '中央氣象署 地震預警',
      'cwa' => '中央氣象署 地震報告',
      'cea' || 'cea-pr' => '中国地震预警网地震预警',
      'kma-eew' => '韩国气象厅地震预警',
      'sa' => 'ShakeAlert Earthquake Early Warning',
      'cenc' => '中国地震台网地震信息',
      _ => '${sourceType.displayName}地震信息',
    };
    final areaData = raw[eew ? 'warnArea' : 'intensityAreas'];
    final areas = <Map<String, dynamic>>[];
    if (areaData is List) {
      for (final area in areaData.whereType<Map>()) {
        final name = _stringValue(area['name']);
        final value = _stringValue(area['intensityTo'] ?? area['intensity']);
        if (name == null || value == null) continue;
        areas.add({
          'name': name,
          'intensity': value,
          'className': _setClassName(value, true, false),
        });
      }
    }
    return UnifiedQuakeData(
      source: source,
      origin: jianOrigin,
      eventId: id,
      isEew: eew,
      timeZone: zone,
      titleText: title,
      reportNumText: type == 'cenc'
          ? review
          : serial == null
          ? ''
          : '第$serial報${raw['isFinal'] == true ? '（最終）' : ''}',
      useShindo: useShindo,
      maxIntensity: canceled ? '-' : intensity,
      className: canceled
          ? 'dark-gray'
          : _setClassName(intensity, useShindo, false),
      hypocenter: raw['hypocenterUnknown'] == true ? '' : location,
      originTime: originTime,
      reportTime: reportTime,
      magnitude: magnitude,
      depth: depth,
      depthText: _formatDepthText(depth, zone),
      lat: hasLocation ? lat : null,
      lng: hasLocation ? lng : null,
      isWarn: raw['isWarn'] == true,
      isFinal: raw['isFinal'] == true,
      isCanceled: canceled,
      isAssumption: raw['isPLUM'] == true,
      warnArea: canceled || areas.isEmpty ? '' : jsonEncode(areas),
      apiTypeLabel: 'Jian Project',
      isJmaLpgm: type == 'jma' && raw['telegram'] == 'VXSE62',
      isHistory: isHistory,
      isSnapshot: isSnapshot,
      hasReportSequence: serial != null,
      useSourceTimeForExpiry: true,
      sourcePayload: snapshotSourcePayload(raw),
    );
  }

  static String _apiTypeLabel(String source, int origin) {
    if (origin == _originWhews) return 'WHEWS';
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
        return origin == 0 ? 'USGS' : 'FAN';
      case 'fssnEqlist':
        return 'FAN';
      case 'fssnCmt':
        return 'FAN';
      case 'cencCmt':
        return 'CENC';
      case 'usgsCmt':
        return 'USGS';
      case 'jmaCmt':
        return 'JMA';
      case 'fnetCmt':
        return 'F-net';
      case 'hinetAquaCmt':
        return 'Hi-net';
      case 'hko':
        return 'FAN';
      case 'emsc':
        return origin == 0 ? 'EMSC' : 'FAN';
      case 'bcsf':
        return 'FAN';
      case 'gfz':
        return 'FAN';
      case 'usp':
        return 'FAN';
      case 'geonet':
        return origin == _originWhews ? 'WHEWS' : 'FAN';
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
    final payload = snapshotSourcePayload(data);
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
      case 'geonet':
        result = _geonet(source, data, origin);
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
      case 'cencCmt':
        result = _cencCmt(source, data, origin);
        break;
      case 'usgsCmt':
        result = _usgsCmt(source, data, origin);
        break;
      case 'jmaCmt':
        result = _jmaCmt(source, data, origin);
        break;
      case 'fnetCmt':
        result = _fnetCmt(source, data, origin);
        break;
      case 'hinetAquaCmt':
        result = _hinetAquaCmt(source, data, origin);
        break;
      default:
        result = convertUnadapted(apiName: source, origin: origin, data: data);
    }
    if (result == null) return null;
    if (_isUnadaptedSourceKey(result.source)) {
      return result.copyWith(sourcePayload: payload);
    }
    final label = _apiTypeLabel(source, origin);
    return result.copyWith(
      apiTypeLabel: label.isEmpty ? result.apiTypeLabel : label,
      sourcePayload: payload,
    );
  }

  /// Converts WHEWS frames into the same logical source slots used by FAN.
  /// The input map is copied; raw values are not rewritten in place.
  static UnifiedQuakeData? convertWhews(
    String source,
    Map<String, dynamic> raw,
  ) {
    final payload = snapshotSourcePayload(raw);
    return _convertWhews(source, raw)?.copyWith(sourcePayload: payload);
  }

  static UnifiedQuakeData? _convertWhews(
    String source,
    Map<String, dynamic> raw,
  ) {
    final data = <String, dynamic>{...raw};
    final sourceKey = source.trim().toLowerCase().replaceAll('-', '_');
    data['eventId'] ??= data['id'];
    data['originTime'] ??= data['shockTime'];
    data['reportTime'] ??= data['updateTime'] ?? data['createTime'];
    data['location'] ??= data['placeName'];
    data['latitude'] ??= data['lat'];
    data['longitude'] ??= data['lng'];
    data['magnitude'] ??= data['mag'];
    data['depth'] ??= data['depthKm'];
    data['maxIntensity'] ??= data['epiIntensity'];
    data['jmaShindo'] ??= data['epiIntensity'];
    data['updates'] ??= data['serial'];
    data['reviewType'] ??= data['infoTypeName'];

    if (sourceKey == 'jma_eew') {
      data['isCancel'] ??= data['cancel'];
      data['isFinal'] ??= data['final'];
      data['isWarn'] ??= data['infoTypeName']?.toString().contains('警報');
      data['MaxIntensity'] ??= data['epiIntensity'];
      data['EventID'] ??= data['id'];
      data['OriginTime'] ??= data['shockTime'];
      data['Magunitude'] ??= data['magnitude'];
      data['Depth'] ??= data['depth'];
      data['Latitude'] ??= data['latitude'];
      data['Longitude'] ??= data['longitude'];
      data['Hypocenter'] ??= data['placeName'];
      data['Serial'] ??= data['updates'];
    }

    switch (sourceKey) {
      case 'jma_eew':
        return convert('jmaEew', data, _originWhews);
      case 'cwa_eew':
        return convert('cwaEew', data, _originWhews);
      case 'cea':
      case 'cea_pr':
        return convert('ceaEew', data, _originWhews);
      case 'kma_eew':
        data['maxIntensity'] ??= data['maxMmi'];
        return convert('kmaEew', data, _originWhews);
      case 'sa_eew':
        data['maxIntensity'] ??= data['maxMmi'];
        return convert('sa', data, _originWhews);
      case 'jma':
        return _whewsJmaInfo(data);
      case 'cwa':
        return convert('cwaEqlist', data, _originWhews);
      case 'cenc':
        return convert('cencEqlist', data, _originWhews);
      case 'kma':
        return convert('kmaEqlist', data, _originWhews);
      case 'usgs':
        return convert('usgsEqlist', data, _originWhews);
      case 'emsc':
        return convert('emsc', data, _originWhews);
      case 'hko':
        return convert('hko', data, _originWhews);
      case 'bcsf':
        return convert('bcsf', data, _originWhews);
      case 'gfz':
        return convert('gfz', data, _originWhews);
      case 'usp':
        return convert('usp', data, _originWhews);
      case 'beijing':
        return convert('beijing', data, _originWhews);
      case 'yunnan':
        return convert('yunnan', data, _originWhews);
      case 'ningxia':
        return convert('ningxia', data, _originWhews);
      case 'guangxi':
        return convert('guangxi', data, _originWhews);
      case 'shanxi':
        return convert('shanxi', data, _originWhews);
      case 'va':
        return _whewsVolcanoInfo(data);
      default:
        return _whewsGenericInfo(sourceKey, data).copyWith(
          sourcePayload: Map<String, dynamic>.unmodifiable(raw),
        );
    }
  }

  static UnifiedQuakeData _whewsJmaInfo(Map<String, dynamic> data) {
    final intensityDetails = _parseWhewsJmaIntensities(data['intensities']);
    final rawShindo = _stringValue(data['jmaShindo'] ?? data['maxIntensity']);
    final shindo = _isUnknownJmaShindo(rawShindo)
        ? intensityDetails.maxIntensity
        : rawShindo;
    final normalizedShindo = _normalizeJmaShindo(shindo);
    final rawHypocenter =
        _stringValue(data['location'] ?? data['placeName']) ?? '';
    final hypocenter = _isInvestigatingText(rawHypocenter) ? '' : rawHypocenter;
    final rawLat = _parseDouble(data['latitude']);
    final rawLng = _parseDouble(data['longitude']);
    final hasMapLocation =
        hypocenter.isNotEmpty && _hasValidJmaCoordinates(rawLat, rawLng);
    final magnitude = _validMagnitude(data['magnitude']);
    final depth = _parseJmaDepth(data['depth']);
    final infoTypeName = _stringValue(data['infoTypeName']) ?? '';
    final isCanceled = data['cancel'] == true || infoTypeName == '取消';
    final reportTime =
        _parseTime(data['createTime'], 9) ??
        _parseTime(data['reportTime'], 9) ??
        _parseTime(data['updateTime'], 9);
    return UnifiedQuakeData(
      source: 'jmaEqlist',
      origin: _originWhews,
      eventId: _stringValue(data['eventId'] ?? data['id']) ?? '',
      isEew: false,
      timeZone: 9,
      titleText: _stringValue(data['title']) ?? '地震情報',
      reportNumText: _whewsJmaReportText(data, infoTypeName),
      useShindo: true,
      maxIntensity: normalizedShindo,
      className: isCanceled
          ? 'dark-gray'
          : _setClassName(normalizedShindo, true, false),
      hypocenter: hypocenter,
      originTime: _whewsJmaOriginTime(data, reportTime),
      reportTime: reportTime,
      magnitude: magnitude,
      depth: depth,
      depthText: _formatDepthText(depth, 9),
      lat: hasMapLocation ? rawLat : null,
      lng: hasMapLocation ? rawLng : null,
      isCanceled: isCanceled,
      warnArea: isCanceled ? '' : intensityDetails.warnArea,
      apiTypeLabel: 'WHEWS',
    );
  }

  static DateTime? _whewsJmaOriginTime(
    Map<String, dynamic> data,
    DateTime? reportTime,
  ) {
    final origin =
        _parseTime(data['shockTime'], 9) ?? _parseTime(data['originTime'], 9);
    if (origin != null) return origin;
    if (data['title'] != '震度速報' || reportTime == null) return null;

    // VXSE51 has no Earthquake/OriginTime. Its official Headline describes
    // the observed shaking time; use the report only to resolve year/month.
    final headline = (_stringValue(data['headline']) ?? '').replaceAllMapped(
      RegExp('[０-９]'),
      (match) => String.fromCharCode(match[0]!.codeUnitAt(0) - 0xfee0),
    );
    final match = RegExp(
      r'(\d{1,2})日\s*(\d{1,2})時\s*(\d{1,2})分ころ',
    ).firstMatch(headline);
    if (match == null) return null;
    final day = int.parse(match[1]!);
    final hour = int.parse(match[2]!);
    final minute = int.parse(match[3]!);
    if (day < 1 || day > 31 || hour > 23 || minute > 59) return null;
    for (final month in [reportTime.month, reportTime.month - 1]) {
      final candidate = DateTime(reportTime.year, month, day, hour, minute);
      if (candidate.day != day) continue;
      final age = reportTime.difference(candidate);
      if (!age.isNegative && age <= const Duration(days: 1)) return candidate;
    }
    return null;
  }

  static String _whewsJmaReportText(
    Map<String, dynamic> data,
    String infoTypeName,
  ) {
    // JMA 情报与 EEW 分开：信息不带报次，只保留取消/订正等状态词。
    if (infoTypeName.isEmpty || infoTypeName == '発表') return '';
    return infoTypeName;
  }

  static ({String warnArea, String? maxIntensity}) _parseWhewsJmaIntensities(
    dynamic rawIntensities,
  ) {
    if (rawIntensities is! List) {
      return (warnArea: '', maxIntensity: null);
    }

    final areaIntensities = <String, String>{};
    String? overallMax;

    void keepMax(String name, String? rawIntensity) {
      final normalized = _normalizeJmaShindo(rawIntensity);
      final rank = _jmaShindoRank(normalized);
      if (rank < 0) return;

      if (name.isNotEmpty) {
        final previous = areaIntensities[name];
        if (previous == null || rank > _jmaShindoRank(previous)) {
          areaIntensities[name] = normalized;
        }
      }
      if (overallMax == null || rank > _jmaShindoRank(overallMax!)) {
        overallMax = normalized;
      }
    }

    for (final rawPref in rawIntensities) {
      if (rawPref is! Map) continue;
      final pref = Map<String, dynamic>.from(rawPref);
      final areas = pref['areas'];
      var retainedArea = false;
      if (areas is List) {
        for (final rawArea in areas) {
          if (rawArea is! Map) continue;
          final area = Map<String, dynamic>.from(rawArea);
          final name = _stringValue(area['area'] ?? area['name']) ?? '';
          final intensity =
              _knownJmaShindo(area['maxIntensity']) ??
              _maxJmaIntensityInNode(area);
          if (name.isNotEmpty && intensity != null) {
            keepMax(name, intensity);
            retainedArea = true;
          } else {
            keepMax('', intensity);
          }
        }
      }

      if (!retainedArea) {
        final prefName = _stringValue(pref['pref'] ?? pref['name']) ?? '';
        final prefIntensity =
            _knownJmaShindo(pref['maxIntensity']) ??
            _maxJmaIntensityInNode(pref);
        keepMax(prefName, prefIntensity);
      }
    }

    final items = areaIntensities.entries
        .map(
          (entry) => {
            'name': entry.key,
            'intensity': entry.value,
            'className': _setClassName(entry.value, true, false),
          },
        )
        .toList(growable: false);
    return (
      warnArea: items.isEmpty ? '' : json.encode(items),
      maxIntensity: overallMax,
    );
  }

  static String? _maxJmaIntensityInNode(dynamic node) {
    String? maximum;

    void visit(dynamic value) {
      if (value is Map) {
        for (final key in const ['maxIntensity', 'intensity']) {
          final candidate = _knownJmaShindo(value[key]);
          if (candidate != null &&
              (maximum == null ||
                  _jmaShindoRank(candidate) > _jmaShindoRank(maximum!))) {
            maximum = candidate;
          }
        }
        for (final child in value.values) {
          if (child is Map || child is List) visit(child);
        }
      } else if (value is List) {
        for (final child in value) {
          visit(child);
        }
      }
    }

    visit(node);
    return maximum;
  }

  static String? _knownJmaShindo(dynamic value) {
    final raw = _stringValue(value);
    if (_isUnknownJmaShindo(raw)) return null;
    final normalized = _normalizeJmaShindo(raw);
    return _jmaShindoRank(normalized) >= 0 ? normalized : null;
  }

  static int _jmaShindoRank(String value) {
    return const [
      '0',
      '1',
      '2',
      '3',
      '4',
      '5-',
      '5+',
      '6-',
      '6+',
      '7',
    ].indexOf(_normalizeJmaShindo(value));
  }

  static bool _hasValidJmaCoordinates(double? lat, double? lng) {
    if (lat == null || lng == null || !lat.isFinite || !lng.isFinite) {
      return false;
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;
    return lat != 0 || lng != 0;
  }

  static double _validMagnitude(dynamic value) {
    final magnitude = _parseDouble(value);
    return magnitude != null && magnitude.isFinite && magnitude > 0
        ? magnitude
        : -1;
  }

  static double _parseJmaDepth(dynamic value) {
    final numeric = _parseDouble(value);
    if (numeric != null && numeric.isFinite && numeric >= 0) return numeric;
    final text = _stringValue(value)?.toLowerCase() ?? '';
    if (text == 'ごく浅い' || text == 'very shallow') return 0;
    return -1;
  }

  static UnifiedQuakeData _whewsVolcanoInfo(Map<String, dynamic> data) {
    String text(String key) => _stringValue(data[key]) ?? '';
    final reportTime = _parseTime(text('reportTime'), 9);
    final targetTime = _parseTime(text('targetTime'), 9);
    final windTime = _parseTime(text('windTime'), 9);
    final latitude = _parseDouble(data['latitude']);
    final longitude = _parseDouble(data['longitude']);
    final winds = <VolcanoWindProfile>[];
    final rawWinds = data['winds'];
    if (rawWinds is List) {
      for (final rawWind in rawWinds) {
        if (rawWind is! Map) continue;
        winds.add(
          VolcanoWindProfile(
            heightFt: _parseDouble(rawWind['heightFt']),
            degree: _parseDouble(rawWind['degree']),
            speedKt: _parseDouble(rawWind['speedKt']),
          ),
        );
      }
    }
    final volcano = VolcanoEventData(
      updates: _parseDouble(data['updates'])?.round() ?? 0,
      kindCode: text('kindCode'),
      kindName: text('kindName'),
      infoKind: text('infoKind'),
      infoTypeName: text('infoTypeName'),
      title: text('title'),
      volcanoName: text('volcanoName'),
      volcanoCode: text('volcanoCode'),
      latitude: latitude,
      longitude: longitude,
      elevation: _parseDouble(data['elevation']),
      craterName: text('craterName'),
      headline: text('headline'),
      activity: text('activity'),
      prevention: text('prevention'),
      nextAdvisory: text('nextAdvisory'),
      plumeDirection: text('plumeDirection'),
      plumeHeight: _parseDouble(data['plumeHeight']),
      plumeHeightSea: _parseDouble(data['plumeHeightSea']),
      observation: text('observation'),
      reportTime: reportTime,
      targetTime: targetTime,
      windTime: windTime,
      winds: List.unmodifiable(winds),
      publishingOffice: text('publishingOffice'),
    );
    final hasMapLocation = volcano.hasMapLocation;
    return UnifiedQuakeData(
      source: 'whews_va',
      origin: _originWhews,
      eventId: text('id'),
      isEew: false,
      timeZone: 9,
      titleText: '日本气象厅火山情报',
      reportNumText: _whewsVolcanoReportText(volcano),
      useShindo: false,
      maxIntensity: '',
      className: _whewsVolcanoClassName(volcano),
      hypocenter: volcano.displayLocation,
      originTime: targetTime ?? reportTime,
      reportTime: reportTime,
      magnitude: -1,
      depth: -1,
      lat: hasMapLocation ? latitude : null,
      lng: hasMapLocation ? longitude : null,
      isCanceled: volcano.isCanceled,
      apiTypeLabel: 'WHEWS',
      volcanoEvent: volcano,
    );
  }

  static String _whewsVolcanoReportText(VolcanoEventData volcano) {
    final kind = volcano.kindName.trim();
    final status = volcano.infoTypeName.trim();
    if (kind.isEmpty) return status;
    if (status.isEmpty || status == '発表') return kind;
    return '$kind $status';
  }

  static String _whewsVolcanoClassName(VolcanoEventData volcano) {
    if (volcano.isCanceled) return 'dark-gray';
    return switch (volcano.kindCode) {
      'VFVO52' => 'red',
      'VFVO50' || 'VFVO54' || 'VFVO55' => 'orange',
      _ => 'yellow',
    };
  }

  @visibleForTesting
  static String whewsCatalogReportText(Map<String, dynamic> data) {
    final raw = _stringValue(data['infoTypeName'])?.trim() ?? '';
    if (raw.isEmpty) return '';
    if (raw == '正式测定' || raw.contains('正式')) return '正式';
    if (raw == '自动测定' || raw.contains('自动')) return '自动';
    final slash = raw.indexOf('/');
    final mode = (slash >= 0 ? raw.substring(0, slash) : raw).toLowerCase();
    return switch (mode) {
      'manual' || 'reviewed' => '正式',
      'automatic' || 'auto' => '自动',
      _ => '',
    };
  }

  static UnifiedQuakeData _whewsGenericInfo(
    String source,
    Map<String, dynamic> data,
  ) {
    final sourceType = whewsCatalogSources['whews_$source'];
    if (sourceType == null) {
      return convertUnadapted(
        apiName: source,
        origin: _originWhews,
        data: data,
        sourceKey: 'whews_${_normalizeSourceKey(source)}',
      );
    }

    final depth = _catalogNumber(data['depth']) ?? _catalogNumber(data['depthKm']) ?? -1;
    final magnitude = _catalogNumber(data['magnitude']) ?? _catalogNumber(data['mag']) ?? -1;
    final reportedIntensity = parseReportedIntensity(data['maxIntensity']);
    final maxIntensity = reportedIntensity != null
        ? (reportedIntensity == reportedIntensity.roundToDouble()
              ? reportedIntensity.toInt().toString() : reportedIntensity.toString())
        : _whewsFallbackIntensity(magnitude, depth);
    final lat = _catalogNumber(data['latitude']) ?? _catalogNumber(data['lat']);
    final lng = _catalogNumber(data['longitude']) ?? _catalogNumber(data['lng']);
    final hasLocation = hasCatalogCoordinates(lat, lng);
    final location = _stringValue(data['location']) ??
        _stringValue(data['placeName']) ?? '';
    return UnifiedQuakeData(
      source: 'whews_$source',
      origin: _originWhews,
      eventId: _stringValue(data['id']) ?? _stringValue(data['eventId']) ?? '',
      isEew: false,
      timeZone: 8,
      titleText: _stringValue(data['title']) ?? '${sourceType.displayName}地震信息',
      reportNumText: whewsCatalogReportText(data),
      useShindo: false,
      maxIntensity: maxIntensity,
      className: _setClassName(maxIntensity, false, false),
      hypocenter: catalogDisplayLocation(location, lat, lng),
      originTime: _parseTime(data['shockTime'], 8) ?? _parseTime(data['originTime'], 8),
      reportTime: _parseTime(data['updateTime'], 8) ??
          _parseTime(data['createTime'], 8) ?? _parseTime(data['reportTime'], 8),
      magnitude: magnitude,
      depth: depth,
      depthText: _formatDepthText(depth, 8),
      lat: hasLocation ? lat : null,
      lng: hasLocation ? lng : null,
      isCanceled: data['cancel'] == true || data['isCancel'] == true,
      apiTypeLabel: 'WHEWS',
    );
  }

  static double? _catalogNumber(dynamic value) {
    final number = _parseDouble(value);
    return number != null && number.isFinite ? number : null;
  }

  /// Converts a feed that has no dedicated adapter.
  ///
  /// Card title uses [data['title']], matching adapted WHEWS generic sources.
  /// The corner API label uses the confirmed transport API for aggregator
  /// feeds, or [data['title']] for direct HTTP feeds.
  static UnifiedQuakeData convertUnadapted({
    required String apiName,
    required int origin,
    required Map<String, dynamic> data,
    String? sourceKey,
  }) {
    final titleFromPayload = _unadaptedTitleFromPayload(data);
    final title = titleFromPayload;
    final apiTypeLabel = _unadaptedApiTypeLabel(
      origin,
      titleFromPayload: titleFromPayload,
    );
    final normalizedApi = _normalizeSourceKey(apiName);
    final key =
        sourceKey ??
        (origin == _originWhews
            ? 'whews_$normalizedApi'
            : 'unadapted_$normalizedApi');
    final payload = Map<String, dynamic>.from(data);
    // Keep hypocenter on the location/placeName fields. Do not fall back to
    // title, which may hold the institution name.
    payload['location'] = _stringValue(
      data['location'] ?? data['placeName'] ?? data['HypoCenter'],
    );
    payload.remove('title');
    final event = _genericInfo(
      source: key,
      origin: origin,
      data: payload,
      title: title,
      timeZone: 8,
    )!;
    final reportText = origin == _originWhews
        ? whewsCatalogReportText(data)
        : _unadaptedReportText(data);
    return event.copyWith(
      apiTypeLabel: apiTypeLabel,
      reportNumText: reportText,
    );
  }

  static String _normalizeSourceKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  static String? _unadaptedTransportApiLabel(int origin) {
    return switch (origin) {
      _originWolfx => 'Wolfx',
      _originFan => 'FAN',
      _originP2p => 'P2PQ',
      _originWhews => 'WHEWS',
      _ => null,
    };
  }

  static String _unadaptedApiTypeLabel(
    int origin, {
    required String titleFromPayload,
  }) {
    final transportApi = _unadaptedTransportApiLabel(origin);
    if (transportApi != null) return transportApi;
    return titleFromPayload;
  }

  /// Card title uses [data['title']], matching adapted WHEWS generic sources.
  static String _unadaptedTitleFromPayload(Map<String, dynamic> data) {
    return _stringValue(data['title']) ?? '';
  }

  static String _unadaptedReportText(Map<String, dynamic> data) {
    return whewsCatalogReportText(data);
  }

  static bool _isUnadaptedSourceKey(String source) {
    return source.startsWith('unadapted_') ||
        (source.startsWith('whews_') &&
            !whewsCatalogSources.containsKey(source) && source != 'whews_va');
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
        originTime: _parseTime(
          data['OriginTime'] ?? data['originTime'] ?? data['shockTime'],
          9,
        ),
        reportTime: _parseTime(
          data['ReportTime'] ??
              data['reportTime'] ??
              data['createTime'] ??
              data['updateTime'],
          9,
        ),
        magnitude: _parseDouble(data['Magunitude'] ?? data['magnitude']) ?? -1,
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
      eventId: _regionalEewBaseEventId(data),
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
      eventId: _regionalEewBaseEventId(data),
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
    final whewsIntensity = origin == _originWhews
        ? _stringValue(
            data['maxMmiLabel'] ?? data['maxIntensity'] ?? data['maxMmi'],
          )
        : null;
    final intensityRaw = _parseIntensityValue(
      origin == _originWhews
          ? data['maxMmi'] ?? data['maxIntensity'] ?? data['maxMmiLabel']
          : data['maxIntensity'],
    );
    final isWarn = intensityRaw != null && intensityRaw >= 6.5;
    final maxIntensity = whewsIntensity?.isNotEmpty == true
        ? whewsIntensity!
        : intensityRaw != null
        ? intensityRaw.toStringAsFixed(1)
        : '-';
    final originTimeValue = origin == _originWhews
        ? data['shockTime'] ?? data['originTime']
        : data['originTime'];

    return UnifiedQuakeData(
      source: source,
      origin: origin,
      eventId: '${data['eventId'] ?? ''}',
      isEew: true,
      timeZone: 9,
      titleText: '기상청 지진조기경보',
      reportNumText: '第${data['updates'] ?? 1}報',
      useShindo: false,
      maxIntensity: maxIntensity,
      className: _setClassName(maxIntensity, false, false),
      hypocenter: '${data['location'] ?? ''}',
      originTime: _parseTime(originTimeValue, 9),
      reportTime: origin == _originWhews
          ? _parseTime(
              data['reportTime'] ?? data['updateTime'] ?? data['createTime'],
              9,
            )
          : null,
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
    // FAN documents /sa shockTime as UTC+8. WHEWS carries the same FAN
    // contract; this path does not contain a native UTC-8 wall-clock field.
    const timeZone = 8;

    return UnifiedQuakeData(
      source: source,
      origin: origin,
      eventId: '${data['eventId'] ?? ''}',
      isEew: true,
      timeZone: timeZone,
      titleText: 'ShakeAlert Earthquake Early Warning',
      reportNumText: '第${data['updates'] ?? 1}報',
      useShindo: false,
      maxIntensity: intensityRaw != null
          ? intensityRaw.toStringAsFixed(1)
          : '-',
      className: _setClassName(intensityRaw?.toStringAsFixed(1), false, false),
      hypocenter: '${data['location'] ?? ''}',
      originTime: _parseTime(data['originTime'] as String?, timeZone),
      reportTime: _parseTime(
        data['reportTime'] ?? data['updateTime'] ?? data['createTime'],
        timeZone,
      ),
      magnitude: _parseDouble(data['magnitude']) ?? -1,
      depth: _parseDouble(data['depth']) ?? -1,
      depthText: _formatDepthText(_parseDouble(data['depth']) ?? -1, timeZone),
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
    var title = '${data['Title'] ?? '地震情報'}';
    final isVolcanoWolfx =
        _isForeignVolcanoEruption(data['Title']) ||
        _isForeignVolcanoEruption(data['Comments']) ||
        _isForeignVolcanoEruption(data['location']);
    if (isVolcanoWolfx) {
      title = '遠地噴火に関する情報';
    } else if (title == '遠地地震情報' || title == '遠地地震') {
      title = '遠地地震に関する情報';
    }
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
    final hypocenterName = hypocenter?['name']?.toString().trim() ?? '';
    final hasHypocenterName =
        hypocenterName.isNotEmpty && !_isInvestigatingText(hypocenterName);
    final rawLat = _parseDouble(hypocenter?['latitude']);
    final rawLng = _parseDouble(hypocenter?['longitude']);
    final hasMapLocation =
        hasHypocenterName && _hasValidJmaCoordinates(rawLat, rawLng);
    final issueType = issue['type'] as String? ?? '';
    final isScalePrompt = issueType == 'ScalePrompt';
    final isDestination = issueType == 'Destination';

    final useShindo = true;
    String hypocent;
    double mag;
    String maxIntensityStr;

    if (isScalePrompt) {
      hypocent = hasHypocenterName ? hypocenterName : '';
      mag = hasHypocenterName ? _validMagnitude(hypocenter?['magnitude']) : -1;
      final maxScale = _parseInt(earthquake?['maxScale']);
      maxIntensityStr = _p2pMaxScaleToShindo(maxScale);
      if (maxIntensityStr == '不明') {
        maxIntensityStr = _extractScalePromptShindo(data);
      }
    } else if (isDestination) {
      hypocent = hasHypocenterName ? hypocenterName : '';
      mag = _validMagnitude(hypocenter?['magnitude']);
      final maxScale = _parseInt(earthquake?['maxScale']);
      maxIntensityStr = _p2pMaxScaleToShindo(maxScale);
    } else {
      hypocent = hasHypocenterName ? hypocenterName : '';
      mag = _validMagnitude(hypocenter?['magnitude']);
      final maxScale = _parseInt(earthquake?['maxScale']);
      maxIntensityStr = _p2pMaxScaleToShindo(maxScale);
    }

    final timeStr = earthquake?['time'] as String? ?? issue['time'] as String?;
    final eventId =
        (earthquake?['time'] as String?)?.replaceAll('/', '-').trim() ??
        '${issue['eventId'] ?? data['_id'] ?? ''}';

    final warnArea = _parseP2pPoints(data);
    final double depth = hasHypocenterName
        ? _parseJmaDepth(hypocenter?['depth'])
        : -1;
    final double? lat = hasMapLocation ? rawLat : null;
    final double? lng = hasMapLocation ? rawLng : null;

    return UnifiedQuakeData(
      source: source,
      origin: _originP2p,
      eventId: eventId,
      isEew: false,
      timeZone: 9,
      titleText: _p2pTitleText(issueType, data),
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

  static bool _isForeignVolcanoEruption(dynamic text) {
    if (text == null) return false;
    final s = text.toString();
    if (s.isEmpty) return false;
    return s.contains('大規模な噴火') ||
        (s.contains('噴火') && (s.contains('火山') || s.contains('VAAC')));
  }

  static String _p2pTitleText(String issueType, [Map<String, dynamic>? data]) {
    if (issueType == 'Foreign') {
      final comments = data?['comments'];
      final commentText = comments is Map
          ? '${comments['freeFormComment'] ?? ''} ${comments['forecast'] ?? ''}'
          : '';
      final eq = data?['earthquake'];
      final eqComment = eq is Map ? '${eq['freeFormComment'] ?? ''}' : '';
      if (_isForeignVolcanoEruption(commentText) ||
          _isForeignVolcanoEruption(eqComment)) {
        return '遠地噴火に関する情報';
      }
      return '遠地地震に関する情報';
    }
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
      titleText: '中央氣象署 地震報告',
      reportNumText: '',
      useShindo: useShindo,
      maxIntensity: _normalizeJmaShindo(shindoText),
      className: _setClassName(shindoText, useShindo, false),
      hypocenter: '${data['location'] ?? ''}',
      originTime: _parseTime(data['originTime'] as String?, 8),
      // WHEWS 提供真实 updateTime；旧来源继续保留原有 +5 分钟兼容逻辑。
      reportTime: origin == _originWhews
          ? _parseTime(data['reportTime'] ?? data['updateTime'], 8)
          : _addMinutes(_parseTime(data['originTime'] as String?, 8), 5),
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
    final reviewLabel = reviewType == 'reviewed'
        ? '正式测定'
        : reviewType == 'automatic'
        ? '自动测定'
        : '';
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
    final rawIntensityText = _stringValue(
      data['maxIntensity'] ?? data['intensity'],
    );
    if (origin == _originWhews) {
      maxIntensityStr = rawIntensityText?.isNotEmpty == true
          ? rawIntensityText!
          : _whewsFallbackIntensity(magnitude, depth);
      className = _setClassName(maxIntensityStr, false, false);
    } else if (intensityRaw != null && intensityRaw > 0) {
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
    final rawIntensityText = _stringValue(data['maxIntensity']);
    final intensityRaw = _parseIntensityValue(data['maxIntensity']);
    final magnitude = _parseDouble(data['magnitude']) ?? -1;
    final depth = _parseDouble(data['depth']) ?? -1;
    final timeZone = origin == _originWhews ? 8 : 9;
    final latitude = _parseDouble(data['latitude']);
    final longitude = _parseDouble(data['longitude']);

    String maxIntensityStr;
    String className;
    if (origin == _originWhews) {
      maxIntensityStr = rawIntensityText?.isNotEmpty == true
          ? rawIntensityText!
          : _whewsFallbackIntensity(magnitude, depth);
      className = _setClassName(maxIntensityStr, false, false);
    } else if (intensityRaw != null && intensityRaw > 0) {
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
      timeZone: timeZone,
      titleText: '기상청 지진정보${_reviewSuffix(data['reviewType'] as String?)}',
      reportNumText: '',
      useShindo: false,
      maxIntensity: maxIntensityStr,
      className: className,
      hypocenter: kmaDisplayLocation(
        '${data['location'] ?? ''}',
        latitude,
        longitude,
      ),
      originTime: _parseTime(data['originTime'] ?? data['shockTime'], timeZone),
      reportTime: _parseTime(
        origin == _originWhews
            ? data['reportTime'] ?? data['updateTime']
            : data['createTime'],
        timeZone,
      ),
      magnitude: magnitude,
      depth: depth,
      depthText: _formatDepthText(depth, timeZone),
      lat: latitude ?? 0,
      lng: longitude ?? 0,
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
    final timeZone = origin == _originWolfx ? QuakeTime.systemTimeZoneHours : 8;

    String maxIntensityStr;
    String className;
    final rawIntensityText = _stringValue(data['maxIntensity']);
    if (origin == _originWhews) {
      maxIntensityStr = rawIntensityText?.isNotEmpty == true
          ? rawIntensityText!
          : _whewsFallbackIntensity(magnitude, depth);
      className = _setClassName(maxIntensityStr, false, false);
    } else if (intensityRaw != null && intensityRaw > 0) {
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
      timeZone: timeZone,
      titleText: 'USGS 地震情报${_reviewSuffix(data['reviewType'] as String?)}',
      reportNumText: '',
      useShindo: false,
      maxIntensity: maxIntensityStr,
      className: className,
      hypocenter: '${data['location'] ?? ''}',
      originTime: _parseTime(data['originTime'] as String?, timeZone),
      // FAN API: USGS 有 updateTime，没有 createTime，fallback 到 shockTime
      reportTime:
          _parseTime(data['updateTime'] as String?, timeZone) ??
          _parseTime(data['shockTime'] as String?, timeZone),
      magnitude: magnitude,
      depth: depth,
      depthText: _formatDepthText(depth, timeZone),
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
    title: '香港天文台地震情报${_hkoTitleSuffix(data)}',
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
    title: 'EMSC 地震情报',
    // WHEWS/FAN fields follow FAN_API's UTC+8 contract. Direct EMSC uses
    // ISO instants and is localized to the device by _parseTime.
    timeZone: origin == _originWolfx ? QuakeTime.systemTimeZoneHours : 8,
  );

  static UnifiedQuakeData? _bcsf(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) => _genericInfo(
    source: source,
    origin: origin,
    data: data,
    title: 'BCSF 地震情报',
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
    title: 'GFZ 地震信息',
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
    title: 'USP 地震信息',
    timeZone: 8,
  );

  static UnifiedQuakeData? _geonet(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) => _whewsGenericInfo('geonet', data).copyWith(
    origin: origin,
    sourcePayload: Map<String, dynamic>.unmodifiable(data),
  );

  static UnifiedQuakeData? _ningxia(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) => _genericInfo(
    source: source,
    origin: origin,
    data: data,
    title: '宁夏地震局地震信息',
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
    title: '广西地震局地震信息',
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
    title: '山西地震局地震信息',
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
    title: '北京地震局地震信息',
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
    title: '云南地震局地震信息',
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
      // FAN API 推送的 fssn-cmt 含 centroidDepth 字段，之前未解析，此处补全
      centroidDepth: _parseDouble(data['centroidDepth']),
      momentTensor: _cmtMomentTensor(data),
      cmtMetadata: _cmtMetadata(data),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CENC 震源机制解（CMT）
  // ═══════════════════════════════════════════════════════════════════════════

  /// CENC 大震震源机制 CMT 产品适配器
  ///
  /// 数据来源：data.earthquake.cn 大震震源机制 CMT 产品（HTML 表格，由
  /// [CencCmtService] 轮询并解析为 Map）。包含断层面参数、矩心深度、
  /// Mw 矩震级等字段。自动产出与人工复核两套目录由 Service 合并，
  /// 人工复核优先；通过 [reviewType] 区分，[reportNumText] 显示
  /// "自动测定"/"正式测定"。
  ///
  /// 字段说明：
  /// - [depth]：震源深度（速报值），用于 UI 显示与烈度估算
  /// - [centroidDepth]：矩心深度（CMT 反演值），用于 beachball 下方标注
  static UnifiedQuakeData? _cencCmt(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) {
    final reviewType = data['reviewType']?.toString() ?? '';
    final reportNumText = reviewType == 'reviewed'
        ? '正式'
        : reviewType == 'automatic'
        ? '自动'
        : '';
    return UnifiedQuakeData(
      source: source,
      origin: origin,
      eventId: '${data['eventId'] ?? ''}',
      isEew: false,
      timeZone: 8,
      titleText: 'CENC 地震矩心矩张量解',
      reportNumText: reportNumText,
      useShindo: false,
      maxIntensity: '-',
      className: 'gray',
      hypocenter: '${data['location'] ?? ''}',
      originTime: _parseTime(data['originTime'] as String?, 8),
      reportTime: _parseTime(data['reportTime'] as String?, 8),
      magnitude: _parseDouble(data['magnitude']) ?? -1,
      depth: _parseDouble(data['depth']) ?? -1,
      depthText: _formatDepthText(_parseDouble(data['depth']) ?? -1, 8),
      lat: _parseDouble(data['latitude']) ?? 0,
      lng: _parseDouble(data['longitude']) ?? 0,
      nodalPlane1: data['nodalPlane1']?.toString(),
      nodalPlane2: data['nodalPlane2']?.toString(),
      centroidDepth: _parseDouble(data['centroidDepth']),
      momentTensor: _cmtMomentTensor(data),
      cmtMetadata: _cmtMetadata(data),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // USGS 震源机制解（CMT）
  // ═══════════════════════════════════════════════════════════════════════════

  /// USGS 矩心矩张量解（CMT）适配器
  ///
  /// 数据来源：USGS FDSN API 的 moment-tensor 产品（由 [UsgsCmtService]
  /// 轮询并解析为 Map）。包含断层面参数、矩心深度、Mw 矩震级等字段。
  /// 通过 [reviewType] 区分 reviewed/automatic，[reportNumText] 显示
  /// "正式测定"/"自动测定"。
  ///
  /// 字段说明：
  /// - [depth]：震源深度（feature.geometry.coordinates[2]），用于 UI 显示与烈度估算
  /// - [centroidDepth]：矩心深度（derived-depth），用于 beachball 下方标注
  static UnifiedQuakeData? _usgsCmt(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) {
    final timeZone = QuakeTime.systemTimeZoneHours;
    final reviewType = data['reviewType']?.toString() ?? '';
    final reportNumText = reviewType == 'reviewed'
        ? '正式'
        : reviewType == 'automatic'
        ? '自动'
        : '';
    return UnifiedQuakeData(
      source: source,
      origin: origin,
      eventId: '${data['eventId'] ?? ''}',
      isEew: false,
      timeZone: timeZone,
      titleText: 'USGS 地震矩心矩张量解',
      reportNumText: reportNumText,
      useShindo: false,
      maxIntensity: '-',
      className: 'gray',
      hypocenter: '${data['location'] ?? ''}',
      originTime: _parseTime(data['originTime'] as String?, timeZone),
      magnitude: _parseDouble(data['magnitude']) ?? -1,
      depth: _parseDouble(data['depth']) ?? -1,
      depthText: _formatDepthText(_parseDouble(data['depth']) ?? -1, timeZone),
      lat: _parseDouble(data['latitude']) ?? 0,
      lng: _parseDouble(data['longitude']) ?? 0,
      nodalPlane1: data['nodalPlane1']?.toString(),
      nodalPlane2: data['nodalPlane2']?.toString(),
      centroidDepth: _parseDouble(data['centroidDepth']),
      momentTensor: _cmtMomentTensor(data),
      cmtMetadata: _cmtMetadata(data),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // JMA 震源机制解（CMT）
  // ═══════════════════════════════════════════════════════════════════════════

  /// JMA CMT 解（精査後）适配器
  ///
  /// 数据来源：気象庁 CMT 解リスト（HTML 表格，由 [JmaCmtService]
  /// 轮询并解析为 Map）。仅人工复核（精査後），翌日以后发布。
  /// 包含断层面参数、Mw 矩震级等字段。列表页无矩心深度（留空）。
  static UnifiedQuakeData? _jmaCmt(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) {
    return UnifiedQuakeData(
      source: source,
      origin: origin,
      eventId: '${data['eventId'] ?? ''}',
      isEew: false,
      timeZone: 9,
      titleText: 'JMA 地震矩心矩张量解',
      reportNumText: '',
      useShindo: false,
      maxIntensity: '-',
      className: 'gray',
      hypocenter: '${data['location'] ?? ''}',
      originTime: _parseTime(data['originTime'] as String?, 9),
      magnitude: _parseDouble(data['magnitude']) ?? -1,
      depth: _parseDouble(data['depth']) ?? -1,
      depthText: _formatDepthText(_parseDouble(data['depth']) ?? -1, 9),
      lat: _parseDouble(data['latitude']) ?? 0,
      lng: _parseDouble(data['longitude']) ?? 0,
      nodalPlane1: data['nodalPlane1']?.toString(),
      nodalPlane2: data['nodalPlane2']?.toString(),
      centroidDepth: _parseDouble(data['centroidDepth']),
      momentTensor: _cmtMomentTensor(data),
      cmtMetadata: _cmtMetadata(data),
    );
  }

  /// F-net CMT 解（震源机制解）适配器
  ///
  /// 数据来源：防災科学技術研究所 F-net 地震のメカニズム情報
  /// （HTML 表格，由 [FnetCmtService] 轮询并解析为 Map）。
  /// 震后约10分钟自动发布，工作日人工复核。
  /// 两步获取：列表页(sret.php)获取基本参数，详细页(tdmt.php)获取断层面参数和日文区域名。
  /// 时间为 UT（UTC），status_color_2=自动, status_color_1=正式。
  static UnifiedQuakeData? _fnetCmt(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) {
    final reviewType = data['reviewType']?.toString() ?? 'auto';
    return UnifiedQuakeData(
      source: source,
      origin: origin,
      eventId: '${data['eventId'] ?? ''}',
      isEew: false,
      // F-net raw origin time is UT, but the CMT UI follows the Japanese
      // NIED catalog display convention (UTC+9).
      timeZone: 9,
      titleText: 'F-net 地震矩心矩张量解',
      reportNumText: reviewType == 'reviewed' ? '正式' : '自动',
      useShindo: false,
      maxIntensity: '-',
      className: 'gray',
      hypocenter: '${data['location'] ?? ''}',
      originTime: _parseTime(data['originTime'] as String?, 9),
      magnitude: _parseDouble(data['magnitude']) ?? -1,
      depth: _parseDouble(data['depth']) ?? -1,
      depthText: _formatDepthText(_parseDouble(data['depth']) ?? -1, 9),
      lat: _parseDouble(data['latitude']) ?? 0,
      lng: _parseDouble(data['longitude']) ?? 0,
      nodalPlane1: data['nodalPlane1']?.toString(),
      nodalPlane2: data['nodalPlane2']?.toString(),
      centroidDepth: _parseDouble(data['centroidDepth']),
      momentTensor: _cmtMomentTensor(data),
      cmtMetadata: _cmtMetadata(data),
    );
  }

  /// Hi-net AQUA CMT 解适配器
  ///
  /// 数据来源：防災科学技術研究所 Hi-net AQUA 震源メカニズム解カタログ
  /// （HTML 表格，由 [HinetAquaCmtService] 轮询并解析为 Map）。
  /// 震后约100-600秒自动发布。
  /// 目录页包含完整 CMT 参数：断层面参数、日文区域名、矩心深度、Mw。
  /// 时间为 JST，已由 Service 转换为 UTC。
  static UnifiedQuakeData? _hinetAquaCmt(
    String source,
    Map<String, dynamic> data,
    int origin,
  ) {
    final reviewType = data['reviewType']?.toString() ?? 'auto';
    return UnifiedQuakeData(
      source: source,
      origin: origin,
      eventId: '${data['eventId'] ?? ''}',
      isEew: false,
      timeZone: 9,
      titleText: 'Hi-net AQUA 地震矩心矩张量解',
      reportNumText: reviewType == 'reviewed' ? '正式' : '自动',
      useShindo: false,
      maxIntensity: '-',
      className: 'gray',
      hypocenter: '${data['location'] ?? ''}',
      originTime: _parseTime(data['originTime'] as String?, 9),
      magnitude: _parseDouble(data['magnitude']) ?? -1,
      depth: _parseDouble(data['depth']) ?? -1,
      depthText: _formatDepthText(_parseDouble(data['depth']) ?? -1, 9),
      lat: _parseDouble(data['latitude']) ?? 0,
      lng: _parseDouble(data['longitude']) ?? 0,
      nodalPlane1: data['nodalPlane1']?.toString(),
      nodalPlane2: data['nodalPlane2']?.toString(),
      centroidDepth: _parseDouble(data['centroidDepth']),
      momentTensor: _cmtMomentTensor(data),
      cmtMetadata: _cmtMetadata(data),
    );
  }

  static CmtMomentTensor? _cmtMomentTensor(Map<String, dynamic> data) {
    final raw = data['momentTensor'];
    if (raw is! Map) return null;
    switch (data['momentTensorConvention']?.toString()) {
      case 'rtp':
        return CmtMomentTensor.fromRtpMap(raw);
      case 'ned':
        return CmtMomentTensor.fromNedMap(raw);
      default:
        return null;
    }
  }

  static CmtSolutionMetadata? _cmtMetadata(Map<String, dynamic> data) {
    final raw = data['cmtMetadata'];
    final metadata = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final rawTensor = data['momentTensor'];
    if (rawTensor is Map) {
      metadata['rawMomentTensor'] = rawTensor;
      metadata['momentTensorConvention'] = data['momentTensorConvention']
          ?.toString();
    }
    return metadata.isEmpty ? null : CmtSolutionMetadata.fromMap(metadata);
  }
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
    final rawIntensityText = _stringValue(data['maxIntensity']);
    if (origin == _originWhews) {
      maxIntensityStr = rawIntensityText?.isNotEmpty == true
          ? rawIntensityText!
          : _whewsFallbackIntensity(magnitude, depth);
      className = _setClassName(maxIntensityStr, false, false);
    } else if (intensityRaw != null && intensityRaw > 0) {
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

    final val = _parseIntensityValue(intensityStr);
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

  // 四川、福建报文将报号作为 "_<report>" 后缀附在事件 ID 上。
  static String _regionalEewBaseEventId(Map<String, dynamic> data) {
    final eventId = _stringValue(data['EventID'] ?? data['eventId']) ?? '';
    return eventId.split('_').first;
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

  static String _hkoTitleSuffix(Map<String, dynamic> data) {
    final verify = data['verify']?.toString();
    if (verify == 'Y' || verify == '已核实') return '已核实';
    if (verify == 'N' || verify == '待核实') return '待核实';
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

  static double? _parseIntensityValue(dynamic value) {
    final numeric = _parseDouble(value);
    if (numeric != null) return numeric;
    final text = value?.toString().trim().toUpperCase() ?? '';
    if (text.isEmpty) return null;
    final normalized = text.replaceFirst(RegExp(r'^MMI\s*'), '').trim();
    const romanLevels = <String, double>{
      'I': 1,
      'II': 2,
      'III': 3,
      'IV': 4,
      'V': 5,
      'VI': 6,
      'VII': 7,
      'VIII': 8,
      'IX': 9,
      'X': 10,
      'XI': 11,
      'XII': 12,
      'Ⅰ': 1,
      'Ⅱ': 2,
      'Ⅲ': 3,
      'Ⅳ': 4,
      'Ⅴ': 5,
      'Ⅵ': 6,
      'Ⅶ': 7,
      'Ⅷ': 8,
      'Ⅸ': 9,
      'Ⅹ': 10,
      'Ⅺ': 11,
      'Ⅻ': 12,
    };
    return romanLevels[normalized];
  }

  static double? parseReportedIntensity(dynamic value) {
    final intensity = _parseIntensityValue(value);
    return intensity != null && intensity.isFinite &&
        intensity >= 0 && intensity <= 12 ? intensity : null;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Read only publication fields actually used by the supported feed schemas.
  /// Older history snapshots may predate publication-time normalization.
  static DateTime? savedReportTime(Map<String, dynamic> payload, int timeZone) {
    var body = payload;
    if (body['Data'] is Map) {
      body = Map<String, dynamic>.from(body['Data'] as Map);
    } else if (body['data'] is Map) {
      body = Map<String, dynamic>.from(body['data'] as Map);
    }
    final issue = body['issue'];
    return _parseTime(
      body['ReportTime'] ?? body['reportTime'] ?? body['createTime'] ??
          body['updateTime'] ?? (issue is Map ? issue['time'] : null),
      timeZone,
    );
  }

  static DateTime? _parseTime(dynamic value, int timeZoneOffset) {
    if (value == null) return null;
    if (value is num) {
      final milliseconds = value.abs() >= 100000000000
          ? value.toInt()
          : (value * 1000).toInt();
      final utc = DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
        isUtc: true,
      );
      final sourceClock = utc.add(Duration(hours: timeZoneOffset));
      return DateTime(
        sourceClock.year,
        sourceClock.month,
        sourceClock.day,
        sourceClock.hour,
        sourceClock.minute,
        sourceClock.second,
        sourceClock.millisecond,
        sourceClock.microsecond,
      );
    }
    final timeStr = value.toString().trim();
    if (timeStr.isEmpty) return null;
    final normalized = timeStr.replaceAll('/', '-');
    if (RegExp(r'[zZ]|[-+]\d{2}:\d{2}$').hasMatch(normalized)) {
      try {
        final parsed = DateTime.parse(normalized);
        final utc = parsed.isUtc ? parsed : parsed.toUtc();
        final sourceClock = utc.add(Duration(hours: timeZoneOffset));
        return DateTime(
          sourceClock.year,
          sourceClock.month,
          sourceClock.day,
          sourceClock.hour,
          sourceClock.minute,
          sourceClock.second,
          sourceClock.millisecond,
          sourceClock.microsecond,
        );
      } catch (_) {
        return null;
      }
    }
    final match = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2})(?:\.(\d+))?)?)?',
    ).firstMatch(normalized);
    if (match != null) {
      var millisecond = 0;
      final fraction = match.group(7);
      if (fraction != null && fraction.isNotEmpty) {
        final padded = fraction.padRight(3, '0').substring(0, 3);
        millisecond = int.parse(padded);
      }
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4) ?? '0'),
        int.parse(match.group(5) ?? '0'),
        int.parse(match.group(6) ?? '0'),
        millisecond,
      );
    }
    try {
      final parsed = DateTime.parse(normalized);
      return DateTime(
        parsed.year,
        parsed.month,
        parsed.day,
        parsed.hour,
        parsed.minute,
        parsed.second,
        parsed.millisecond,
        parsed.microsecond,
      );
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

  // WHEWS 缺少烈度时，与 FAN/HTTP 信息源使用同一套 CSIS 估算。
  static String _whewsFallbackIntensity(double magnitude, double depth) {
    if (magnitude <= 0 || depth < 0) return '-';
    return IntensityCalculator.calcCsisLevel(
      magnitude,
      depth,
      0,
    ).toStringAsFixed(1);
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
