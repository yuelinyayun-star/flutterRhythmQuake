import 'dart:async';

import '../core/event_detection/event_detection_models.dart';
import '../models/unified_quake_data.dart';

enum ObsAutomationInputKind { unifiedEvent, networkDetection, stationChange }

enum ObsAutomationInputFieldFamily { common, unified, station }

enum ObsAutomationInputValueType { text, number, boolean, choice }

class ObsAutomationInputFieldDefinition {
  const ObsAutomationInputFieldDefinition({
    required this.key,
    required this.label,
    required this.family,
    this.valueType = ObsAutomationInputValueType.text,
    this.options = const {},
  });

  final String key;
  final String label;
  final ObsAutomationInputFieldFamily family;
  final ObsAutomationInputValueType valueType;
  final Map<String, String> options;
}

const obsAutomationInputFields = <ObsAutomationInputFieldDefinition>[
  ObsAutomationInputFieldDefinition(
    key: 'inputKind',
    label: '输入类型',
    family: ObsAutomationInputFieldFamily.common,
    valueType: ObsAutomationInputValueType.choice,
    options: {
      'unifiedEvent': '统一 UI',
      'networkDetection': '台网检出',
      'stationChange': '单测站变化',
    },
  ),
  ObsAutomationInputFieldDefinition(
    key: 'phase',
    label: '输入阶段',
    family: ObsAutomationInputFieldFamily.common,
    valueType: ObsAutomationInputValueType.choice,
    options: {
      'added': '进入',
      'updated': '更新',
      'canceled': '取消',
      'removed': '结束或过期',
      'candidate': '候选',
      'confirmed': '确认',
      'enhanced': '增强',
      'strong': '强震',
      'weakened': '减弱',
      'ended': '结束或恢复',
      'rejected': '拒绝',
      'rising': '开始上升',
      'triggered': '首次触发',
      'intensityIncreased': '震度增强',
      'intensityDecreased': '震度减弱',
    },
  ),
  ObsAutomationInputFieldDefinition(
    key: 'occurredAt',
    label: '输入时间',
    family: ObsAutomationInputFieldFamily.common,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'eventId',
    label: '事件编号',
    family: ObsAutomationInputFieldFamily.common,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'network',
    label: '台网',
    family: ObsAutomationInputFieldFamily.station,
    valueType: ObsAutomationInputValueType.choice,
    options: {
      'nied': 'NIED',
      'kma': 'KMA',
      'trem': 'TREM',
      'snet': 'S-Net',
      'palert': 'P-Alert',
      'fdsn': 'FDSN/SeedLink',
      'seisjs': 'Wolfx SeisJS',
    },
  ),
  ObsAutomationInputFieldDefinition(
    key: 'source',
    label: 'API 来源',
    family: ObsAutomationInputFieldFamily.unified,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'agency',
    label: '发布机构',
    family: ObsAutomationInputFieldFamily.unified,
    valueType: ObsAutomationInputValueType.choice,
    options: {
      'jma': 'JMA',
      'cwa': 'CWA',
      'cea': 'CEA',
      'sichuan': '四川省地震局',
      'fujian': '福建省地震局',
      'chongqing': '重庆市地震局',
      'kma': 'KMA',
      'shakeAlert': 'ShakeAlert',
      'globalQuake': 'GlobalQuake',
      'cenc': 'CENC',
      'usgs': 'USGS',
      'fssn': 'FSSN',
      'hko': 'HKO',
      'emsc': 'EMSC',
      'bcsf': 'BCSF',
      'gfz': 'GFZ',
      'usp': 'USP',
      'geonet': 'GeoNet',
      'bmkg': 'BMKG',
      'tmd': 'TMD',
      'ingv': 'INGV',
      'nrcan': 'NRCan',
      'mmd': 'MMD',
      'phivolcs': 'PHIVOLCS',
      'sgc': 'SGC',
      'ga': 'GA',
      'cenais': 'CENAIS',
      'gsras': 'GSRAS',
      'bgs': 'BGS',
      'ipma': 'IPMA',
      'ssn': 'SSN',
      'afad': 'AFAD',
      'sed': 'SED',
      'noa': 'NOA',
      'scsn': 'SCSN',
      'iag': 'IAG',
      'igp': 'IGP',
      'nepal': 'NEPAL',
      'ipgp': 'IPGP',
      'infp': 'INFP',
      'isc': 'ISC',
      'knmi': 'KNMI',
      'ncedc': 'NCEDC',
      'lmu': 'LMU',
      'koeri': 'KOERI',
      'csn': 'CSN',
      'igepn': 'IGEPN',
      'earlyEst': 'Early-est',
      'ningxia': '宁夏地震局',
      'guangxi': '广西地震局',
      'shanxi': '山西地震局',
      'beijing': '北京地震局',
      'yunnan': '云南地震局',
    },
  ),
  ObsAutomationInputFieldDefinition(
    key: 'reviewType',
    label: '测定类型',
    family: ObsAutomationInputFieldFamily.unified,
    valueType: ObsAutomationInputValueType.choice,
    options: {'automatic': '自动测定', 'reviewed': '正式测定'},
  ),
  ObsAutomationInputFieldDefinition(
    key: 'eventType',
    label: '事件类型',
    family: ObsAutomationInputFieldFamily.unified,
    valueType: ObsAutomationInputValueType.choice,
    options: {
      'eew': '地震预警',
      'earthquake': '地震信息',
      'tsunami': '海啸信息',
      'volcano': '火山信息',
      'ashfall': '降灰预报',
      'cmt': 'CMT',
    },
  ),
  ObsAutomationInputFieldDefinition(
    key: 'isEew',
    label: '是否 EEW',
    family: ObsAutomationInputFieldFamily.unified,
    valueType: ObsAutomationInputValueType.boolean,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'magnitude',
    label: '震级',
    family: ObsAutomationInputFieldFamily.unified,
    valueType: ObsAutomationInputValueType.number,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'estimatedIntensity',
    label: '最大震度/烈度',
    family: ObsAutomationInputFieldFamily.unified,
    valueType: ObsAutomationInputValueType.number,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'reportNumber',
    label: '报数',
    family: ObsAutomationInputFieldFamily.unified,
    valueType: ObsAutomationInputValueType.number,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'reportText',
    label: '报数/测定文字',
    family: ObsAutomationInputFieldFamily.unified,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'title',
    label: '标题',
    family: ObsAutomationInputFieldFamily.unified,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'uiTitle',
    label: 'UI 顶部标题',
    family: ObsAutomationInputFieldFamily.unified,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'uiPrimaryText',
    label: 'UI 主文本',
    family: ObsAutomationInputFieldFamily.unified,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'uiSecondaryText',
    label: 'UI 副文本',
    family: ObsAutomationInputFieldFamily.unified,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'uiCompactSecondaryText',
    label: 'UI 紧凑副文本',
    family: ObsAutomationInputFieldFamily.unified,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'uiTimeText',
    label: 'UI 时间',
    family: ObsAutomationInputFieldFamily.unified,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'uiBadgeLabel',
    label: 'UI 徽章名称',
    family: ObsAutomationInputFieldFamily.unified,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'uiBadgeValue',
    label: 'UI 徽章内容',
    family: ObsAutomationInputFieldFamily.unified,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'uiApiTypeLabel',
    label: 'UI API 标识',
    family: ObsAutomationInputFieldFamily.unified,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'uiNotificationBody',
    label: 'UI 完整文本',
    family: ObsAutomationInputFieldFamily.unified,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'hypocenter',
    label: '震中名称',
    family: ObsAutomationInputFieldFamily.unified,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'depth',
    label: '深度',
    family: ObsAutomationInputFieldFamily.unified,
    valueType: ObsAutomationInputValueType.number,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'latitude',
    label: '纬度',
    family: ObsAutomationInputFieldFamily.common,
    valueType: ObsAutomationInputValueType.number,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'longitude',
    label: '经度',
    family: ObsAutomationInputFieldFamily.common,
    valueType: ObsAutomationInputValueType.number,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'isFinal',
    label: '是否最终报',
    family: ObsAutomationInputFieldFamily.unified,
    valueType: ObsAutomationInputValueType.boolean,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'isCanceled',
    label: '是否取消报',
    family: ObsAutomationInputFieldFamily.unified,
    valueType: ObsAutomationInputValueType.boolean,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'isWarn',
    label: '是否警报',
    family: ObsAutomationInputFieldFamily.unified,
    valueType: ObsAutomationInputValueType.boolean,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'apiType',
    label: 'API 标识',
    family: ObsAutomationInputFieldFamily.unified,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'originTime',
    label: '发震时间',
    family: ObsAutomationInputFieldFamily.unified,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'reportTime',
    label: '发布时间',
    family: ObsAutomationInputFieldFamily.unified,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'stationId',
    label: '测站编号',
    family: ObsAutomationInputFieldFamily.station,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'stationName',
    label: '测站名称',
    family: ObsAutomationInputFieldFamily.station,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'currentStationIntensity',
    label: '当前测站震度',
    family: ObsAutomationInputFieldFamily.station,
    valueType: ObsAutomationInputValueType.number,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'currentStationRawIntensity',
    label: '当前测站原始烈度',
    family: ObsAutomationInputFieldFamily.station,
    valueType: ObsAutomationInputValueType.number,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'previousStationIntensity',
    label: '上一测站震度',
    family: ObsAutomationInputFieldFamily.station,
    valueType: ObsAutomationInputValueType.number,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'previousStationRawIntensity',
    label: '上一测站原始烈度',
    family: ObsAutomationInputFieldFamily.station,
    valueType: ObsAutomationInputValueType.number,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'detectedStationCount',
    label: '检出测站数',
    family: ObsAutomationInputFieldFamily.station,
    valueType: ObsAutomationInputValueType.number,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'networkMaxIntensity',
    label: '台网最大震度',
    family: ObsAutomationInputFieldFamily.station,
    valueType: ObsAutomationInputValueType.number,
  ),
  ObsAutomationInputFieldDefinition(
    key: 'networkMaxRawIntensity',
    label: '台网原始最大烈度',
    family: ObsAutomationInputFieldFamily.station,
    valueType: ObsAutomationInputValueType.number,
  ),
];

enum ObsUnifiedEventPhase { added, updated, canceled, removed }

enum ObsNetworkDetectionPhase {
  candidate,
  confirmed,
  enhanced,
  strong,
  weakened,
  ended,
  rejected,
}

enum ObsStationChangePhase {
  rising,
  triggered,
  strong,
  intensityIncreased,
  intensityDecreased,
  ended,
}

class ObsStationInputSample {
  const ObsStationInputSample({
    required this.stationId,
    required this.stationName,
    required this.active,
    required this.intensityLevel,
    required this.observedAt,
    this.intensity,
    this.latitude,
    this.longitude,
    this.rising = false,
    this.strong = false,
  });

  final String stationId;
  final String stationName;
  final bool active;
  final int intensityLevel;
  final double? intensity;
  final double? latitude;
  final double? longitude;
  final DateTime observedAt;
  final bool rising;
  final bool strong;
}

class ObsAutomationInputEvent {
  const ObsAutomationInputEvent._({
    required this.kind,
    required this.occurredAt,
    this.unifiedPhase,
    this.unifiedEvent,
    this.network,
    this.networkPhase,
    this.stationPhase,
    this.stationId,
    this.stationName,
    this.previousIntensityLevel,
    this.intensityLevel,
    this.previousIntensity,
    this.intensity,
    this.latitude,
    this.longitude,
    this.detectedStationCount,
    this.maxIntensity,
    this.eventId,
  });

  factory ObsAutomationInputEvent.unified({
    required ObsUnifiedEventPhase phase,
    required UnifiedQuakeData event,
    DateTime? occurredAt,
  }) {
    return ObsAutomationInputEvent._(
      kind: ObsAutomationInputKind.unifiedEvent,
      occurredAt: occurredAt ?? DateTime.now(),
      unifiedPhase: phase,
      unifiedEvent: event,
      eventId: event.eventId,
    );
  }

  factory ObsAutomationInputEvent.networkDetection({
    required String network,
    required ObsNetworkDetectionPhase phase,
    required DateTime occurredAt,
    String? eventId,
    int? detectedStationCount,
    int? maxIntensity,
  }) {
    return ObsAutomationInputEvent._(
      kind: ObsAutomationInputKind.networkDetection,
      occurredAt: occurredAt,
      network: network,
      networkPhase: phase,
      eventId: eventId,
      detectedStationCount: detectedStationCount,
      maxIntensity: maxIntensity,
    );
  }

  factory ObsAutomationInputEvent.stationChange({
    required String network,
    required ObsStationChangePhase phase,
    required ObsStationInputSample current,
    ObsStationInputSample? previous,
  }) {
    return ObsAutomationInputEvent._(
      kind: ObsAutomationInputKind.stationChange,
      occurredAt: current.observedAt,
      network: network,
      stationPhase: phase,
      stationId: current.stationId,
      stationName: current.stationName,
      previousIntensityLevel: previous?.intensityLevel,
      intensityLevel: current.intensityLevel,
      previousIntensity: previous?.intensity,
      intensity: current.intensity,
      latitude: current.latitude,
      longitude: current.longitude,
    );
  }

  final ObsAutomationInputKind kind;
  final DateTime occurredAt;
  final ObsUnifiedEventPhase? unifiedPhase;
  final UnifiedQuakeData? unifiedEvent;
  final String? network;
  final ObsNetworkDetectionPhase? networkPhase;
  final ObsStationChangePhase? stationPhase;
  final String? stationId;
  final String? stationName;
  final int? previousIntensityLevel;
  final int? intensityLevel;
  final double? previousIntensity;
  final double? intensity;
  final double? latitude;
  final double? longitude;
  final int? detectedStationCount;
  final int? maxIntensity;
  final String? eventId;
}

class ObsAutomationInputService {
  ObsAutomationInputService._() {
    _controller = StreamController<ObsAutomationInputEvent>.broadcast(
      sync: true,
      onCancel: _clearTrackingWhenUnused,
    );
  }

  static final ObsAutomationInputService _instance =
      ObsAutomationInputService._();

  factory ObsAutomationInputService() => _instance;

  late final StreamController<ObsAutomationInputEvent> _controller;
  final Map<String, Map<String, ObsStationInputSample>> _stationStates = {};
  final Map<String, EventDetection> _networkDetections = {};
  final Map<String, int> _legacyNetworkMaxIntensity = {};
  final Map<String, ObsAutomationInputEvent> _pendingStationIntensity = {};
  Timer? _stationIntensityFlushTimer;

  Stream<ObsAutomationInputEvent> get events => _controller.stream;
  bool get hasListeners => _controller.hasListener;

  void emitUnifiedEvent(UnifiedQuakeData event, ObsUnifiedEventPhase phase) {
    if (!hasListeners) return;
    _controller.add(
      ObsAutomationInputEvent.unified(phase: phase, event: event),
    );
  }

  void ingestEventDetection(String network, EventDetection detection) {
    if (!hasListeners) return;
    final normalizedNetwork = _normalizeNetwork(network);
    final previous = _networkDetections[normalizedNetwork];
    _networkDetections[normalizedNetwork] = detection;

    final phase = _networkPhaseFor(detection, previous);
    if (phase == null) return;
    _controller.add(
      ObsAutomationInputEvent.networkDetection(
        network: normalizedNetwork,
        phase: phase,
        occurredAt: detection.observedAt,
        eventId: detection.eventId,
        detectedStationCount: detection.memberStationIds.length,
        maxIntensity: detection.maxIntensity,
      ),
    );
  }

  void ingestLegacyNetworkDetection({
    required String network,
    required int maxIntensity,
    required DateTime observedAt,
  }) {
    if (!hasListeners) return;
    final normalizedNetwork = _normalizeNetwork(network);
    final previous = _legacyNetworkMaxIntensity[normalizedNetwork];
    _legacyNetworkMaxIntensity[normalizedNetwork] = maxIntensity;
    final phase = previous == null
        ? (maxIntensity >= 4
              ? ObsNetworkDetectionPhase.strong
              : ObsNetworkDetectionPhase.confirmed)
        : maxIntensity >= 4 && previous < 4
        ? ObsNetworkDetectionPhase.strong
        : maxIntensity > previous
        ? ObsNetworkDetectionPhase.enhanced
        : maxIntensity < previous
        ? ObsNetworkDetectionPhase.weakened
        : null;
    if (phase == null) return;
    _controller.add(
      ObsAutomationInputEvent.networkDetection(
        network: normalizedNetwork,
        phase: phase,
        occurredAt: observedAt,
        maxIntensity: maxIntensity,
      ),
    );
  }

  void endLegacyNetworkDetection({
    required String network,
    required DateTime observedAt,
  }) {
    if (!hasListeners) return;
    final normalizedNetwork = _normalizeNetwork(network);
    if (_legacyNetworkMaxIntensity.remove(normalizedNetwork) == null) return;
    _controller.add(
      ObsAutomationInputEvent.networkDetection(
        network: normalizedNetwork,
        phase: ObsNetworkDetectionPhase.ended,
        occurredAt: observedAt,
      ),
    );
  }

  void ingestStationSnapshot(
    String network,
    Iterable<ObsStationInputSample> samples,
  ) {
    if (!hasListeners) return;
    final normalizedNetwork = _normalizeNetwork(network);
    final current = <String, ObsStationInputSample>{};
    for (final sample in samples) {
      current[sample.stationId] = sample;
    }

    final previous = _stationStates[normalizedNetwork];
    _stationStates[normalizedNetwork] = current;
    if (previous == null) return;

    for (final entry in current.entries) {
      final oldSample = previous[entry.key];
      if (oldSample == null) {
        if (entry.value.active) {
          _publishStationLifecycle(
            ObsAutomationInputEvent.stationChange(
              network: normalizedNetwork,
              phase: entry.value.strong
                  ? ObsStationChangePhase.strong
                  : entry.value.rising
                  ? ObsStationChangePhase.rising
                  : ObsStationChangePhase.triggered,
              current: entry.value,
            ),
          );
        }
        continue;
      }
      _emitStationEdge(normalizedNetwork, oldSample, entry.value);
    }

    for (final entry in previous.entries) {
      if (current.containsKey(entry.key) || !entry.value.active) continue;
      final ended = ObsStationInputSample(
        stationId: entry.value.stationId,
        stationName: entry.value.stationName,
        active: false,
        intensityLevel: -1,
        intensity: null,
        latitude: entry.value.latitude,
        longitude: entry.value.longitude,
        observedAt: DateTime.now(),
      );
      _publishStationLifecycle(
        ObsAutomationInputEvent.stationChange(
          network: normalizedNetwork,
          phase: ObsStationChangePhase.ended,
          current: ended,
          previous: entry.value,
        ),
      );
    }
  }

  void ingestStationSample(String network, ObsStationInputSample sample) {
    if (!hasListeners) return;
    final normalizedNetwork = _normalizeNetwork(network);
    final states = _stationStates.putIfAbsent(
      normalizedNetwork,
      () => <String, ObsStationInputSample>{},
    );
    final previous = states[sample.stationId];
    states[sample.stationId] = sample;
    if (previous == null) return;
    _emitStationEdge(normalizedNetwork, previous, sample);
  }

  void clearStationNetwork(String network) {
    final normalizedNetwork = _normalizeNetwork(network);
    _stationStates.remove(normalizedNetwork);
    _legacyNetworkMaxIntensity.remove(normalizedNetwork);
    _networkDetections.remove(normalizedNetwork);
    _pendingStationIntensity.removeWhere(
      (key, _) => key.startsWith('$normalizedNetwork:'),
    );
  }

  void _emitStationEdge(
    String network,
    ObsStationInputSample previous,
    ObsStationInputSample current,
  ) {
    if (!previous.active && current.active) {
      _publishStationLifecycle(
        ObsAutomationInputEvent.stationChange(
          network: network,
          phase: current.strong
              ? ObsStationChangePhase.strong
              : current.rising
              ? ObsStationChangePhase.rising
              : ObsStationChangePhase.triggered,
          current: current,
          previous: previous,
        ),
      );
      return;
    }
    if (previous.active && !current.active) {
      _publishStationLifecycle(
        ObsAutomationInputEvent.stationChange(
          network: network,
          phase: ObsStationChangePhase.ended,
          current: current,
          previous: previous,
        ),
      );
      return;
    }
    if (!current.active) return;
    if (!previous.strong && current.strong) {
      _publishStationLifecycle(
        ObsAutomationInputEvent.stationChange(
          network: network,
          phase: ObsStationChangePhase.strong,
          current: current,
          previous: previous,
        ),
      );
      return;
    }
    if (current.intensityLevel == previous.intensityLevel) return;
    final phase = current.intensityLevel > previous.intensityLevel
        ? ObsStationChangePhase.intensityIncreased
        : ObsStationChangePhase.intensityDecreased;
    final event = ObsAutomationInputEvent.stationChange(
      network: network,
      phase: phase,
      current: current,
      previous: previous,
    );
    _pendingStationIntensity['$network:${current.stationId}'] = event;
    _stationIntensityFlushTimer ??= Timer(
      const Duration(milliseconds: 500),
      _flushStationIntensityChanges,
    );
  }

  void _publishStationLifecycle(ObsAutomationInputEvent event) {
    _pendingStationIntensity.remove('${event.network}:${event.stationId}');
    _controller.add(event);
  }

  void _flushStationIntensityChanges() {
    _stationIntensityFlushTimer = null;
    if (!hasListeners) {
      _pendingStationIntensity.clear();
      return;
    }
    final pending = _pendingStationIntensity.values.toList(growable: false);
    _pendingStationIntensity.clear();
    for (final event in pending) {
      _controller.add(event);
    }
  }

  ObsNetworkDetectionPhase? _networkPhaseFor(
    EventDetection current,
    EventDetection? previous,
  ) {
    final direct = switch (current.state) {
      EventDetectionState.candidate => ObsNetworkDetectionPhase.candidate,
      EventDetectionState.confirmed => ObsNetworkDetectionPhase.confirmed,
      EventDetectionState.strong => ObsNetworkDetectionPhase.strong,
      EventDetectionState.ended => ObsNetworkDetectionPhase.ended,
      EventDetectionState.rejected => ObsNetworkDetectionPhase.rejected,
      EventDetectionState.idle => null,
    };
    if (previous == null || previous.state != current.state) return direct;
    if (!current.hasActiveEvent) return null;
    if (current.maxIntensity > previous.maxIntensity ||
        current.memberStationIds.length > previous.memberStationIds.length) {
      return ObsNetworkDetectionPhase.enhanced;
    }
    if (current.maxIntensity < previous.maxIntensity ||
        current.memberStationIds.length < previous.memberStationIds.length) {
      return ObsNetworkDetectionPhase.weakened;
    }
    return null;
  }

  String _normalizeNetwork(String network) => network.trim().toLowerCase();

  void _clearTrackingWhenUnused() {
    if (hasListeners) return;
    _stationIntensityFlushTimer?.cancel();
    _stationIntensityFlushTimer = null;
    _stationStates.clear();
    _networkDetections.clear();
    _legacyNetworkMaxIntensity.clear();
    _pendingStationIntensity.clear();
  }

  void resetForTest() {
    _stationIntensityFlushTimer?.cancel();
    _stationIntensityFlushTimer = null;
    _stationStates.clear();
    _networkDetections.clear();
    _legacyNetworkMaxIntensity.clear();
    _pendingStationIntensity.clear();
  }
}
