import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/intensity_calculator.dart';
import '../../models/quake_message.dart';
import '../../models/source_status.dart';
import '../../models/unified_quake_data.dart';
import '../../utils/fe_regions.dart';
import 'base_source.dart';
import 'global_quake_first_report_filter.dart';

class GlobalQuakeService extends BaseSourceService {
  static final GlobalQuakeService _instance = GlobalQuakeService._internal();

  factory GlobalQuakeService() => _instance;

  GlobalQuakeService._internal();

  static const enabledPreferenceKey = 'global_quake_bridge_enabled';
  static const primaryHostPreferenceKey = 'global_quake_primary_host';
  static const primaryPortPreferenceKey = 'global_quake_primary_port';
  static const secondaryHostPreferenceKey = 'global_quake_secondary_host';
  static const secondaryPortPreferenceKey = 'global_quake_secondary_port';
  static const firstReportMagnitudeThresholdPreferenceKey =
      'global_quake_first_report_magnitude_threshold';
  static const defaultPrimaryHost = 'server.globalquake.net';
  static const defaultSecondaryHost = 'server-backup.globalquake.net';
  static const defaultPort = 38000;

  static final Uint8List _handshakeBytes = _hex(
    'aced0005737200326e65742e676c6f62616c7175616b652e6170692e7061636b6574732e73797374656d2e48616e647368616b655061636b6574000000000000000002000249000d636f6d70617456657273696f6e4c000c636c69656e74436f6e6669677400344c6e65742f676c6f62616c7175616b652f6170692f646174612f73797374656d2f536572766572436c69656e74436f6e6669673b78700000000f737200326e65742e676c6f62616c7175616b652e6170692e646174612e73797374656d2e536572766572436c69656e74436f6e66696700000000000000000200025a000e65617274687175616b65446174615a000b73746174696f6e4461746178700100',
  );
  static final Uint8List _firstHeartbeatBytes = _hex(
    '737200326e65742e676c6f62616c7175616b652e6170692e7061636b6574732e73797374656d2e4865617274626561745061636b657400000000000000000200007870',
  );
  static final Uint8List _nextHeartbeatBytes = _hex('7371007e0005');

  final _stateController = StreamController<void>.broadcast();
  final _decoder = _JavaObjectStreamDecoder();
  final _firstReportMagnitudeFilter = GlobalQuakeFirstReportMagnitudeFilter();

  Socket? _socket;
  StreamSubscription<Uint8List>? _socketSub;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _enabled = false;
  bool _manualClose = true;
  bool _sentFirstHeartbeat = false;
  SourceStatus _status = SourceStatus.disconnected;
  String? _lastError;
  String? _lastLog;
  UnifiedQuakeData? _lastEvent;
  String _primaryHost = defaultPrimaryHost;
  int _primaryPort = defaultPort;
  String _secondaryHost = defaultSecondaryHost;
  int _secondaryPort = defaultPort;
  int _endpointIndex = 0;

  @override
  String get name => 'GlobalQuake';

  @override
  bool get autoStart => false;

  Stream<void> get onDebugStateChanged => _stateController.stream;
  bool get isEnabled => _enabled;
  SourceStatus get status => _status;
  String? get lastError => _lastError;
  String? get lastLog => _lastLog;
  UnifiedQuakeData? get lastEvent => _lastEvent;
  int? get processId => null;
  String get localWsUrl => 'tcp://$activeHost:$activePort';
  bool get isSupported => true;
  String get primaryHost => _primaryHost;
  int get primaryPort => _primaryPort;
  String get secondaryHost => _secondaryHost;
  int get secondaryPort => _secondaryPort;
  String get activeHost => _endpoints[_endpointIndex % _endpoints.length].host;
  int get activePort => _endpoints[_endpointIndex % _endpoints.length].port;
  double get firstReportMagnitudeThreshold =>
      _firstReportMagnitudeFilter.threshold;

  List<_GlobalQuakeEndpoint> get _endpoints {
    final primary = _GlobalQuakeEndpoint(_primaryHost, _primaryPort);
    final secondary = _GlobalQuakeEndpoint(_secondaryHost, _secondaryPort);
    if (primary == secondary) return [primary];
    return [primary, secondary];
  }

  void configureServers({
    required String primaryHost,
    required int primaryPort,
    required String secondaryHost,
    required int secondaryPort,
  }) {
    _primaryHost = _normalizeHost(primaryHost, defaultPrimaryHost);
    _primaryPort = _normalizePort(primaryPort);
    _secondaryHost = _normalizeHost(secondaryHost, defaultSecondaryHost);
    _secondaryPort = _normalizePort(secondaryPort);
    _endpointIndex = 0;
    _notifyState();
    if (_enabled) {
      unawaited(_reconnectNow());
    }
  }

  void configureFirstReportMagnitudeFilter(double threshold) {
    _firstReportMagnitudeFilter.configure(threshold);
    _notifyState();
  }

  @override
  void connect() {
    if (_enabled && _status == SourceStatus.connected) return;
    _enabled = true;
    _manualClose = false;
    _lastError = null;
    _endpointIndex = 0;
    _setStatus(SourceStatus.connecting);
    unawaited(_connect());
  }

  @override
  void disconnect() {
    _enabled = false;
    _manualClose = true;
    _reconnectTimer?.cancel();
    unawaited(_closeSocket(SourceStatus.disconnected));
  }

  Future<void> _connect() async {
    if (!isSupported) {
      _lastError = 'GlobalQuake direct link is supported only on IO platforms.';
      _setStatus(SourceStatus.error);
      return;
    }

    final endpoint = _endpoints[_endpointIndex % _endpoints.length];
    try {
      await _closeSocket(null);
      _decoder.reset();
      _sentFirstHeartbeat = false;
      _lastLog = 'Connecting to ${endpoint.host}:${endpoint.port}';
      _notifyState();
      final socket = await Socket.connect(
        endpoint.host,
        endpoint.port,
        timeout: const Duration(seconds: 10),
      );
      _socket = socket;
      socket.add(_handshakeBytes);
      await socket.flush();
      _socketSub = socket.listen(
        _handleBytes,
        onError: (Object error) {
          _lastError = error.toString();
          _setStatus(SourceStatus.error);
          _scheduleReconnect(advanceEndpoint: true);
        },
        onDone: () {
          if (_manualClose || !_enabled) return;
          _lastError = 'GlobalQuake socket closed';
          _setStatus(SourceStatus.disconnected);
          _scheduleReconnect(advanceEndpoint: true);
        },
        cancelOnError: true,
      );
      _startHeartbeat();
      _setStatus(SourceStatus.connected);
      _lastLog = 'Connected to ${endpoint.host}:${endpoint.port}';
    } catch (e) {
      _lastError = 'Connect ${endpoint.host}:${endpoint.port} failed: $e';
      _setStatus(SourceStatus.error);
      _scheduleReconnect(advanceEndpoint: true);
    }
  }

  void _handleBytes(Uint8List bytes) {
    try {
      final objects = _decoder.add(bytes);
      for (final object in objects) {
        if (object.className.endsWith('.HandshakeSuccessfulPacket')) {
          _lastLog = 'Handshake accepted by $activeHost:$activePort';
          _notifyState();
        } else if (object.className.endsWith('.TerminationPacket')) {
          _lastError = 'GlobalQuake terminated: ${object.fields['cause']}';
          _setStatus(SourceStatus.error);
        } else if (object.className.endsWith('.HypocenterDataPacket')) {
          final event = _toUnifiedEvent(object);
          if (event != null) {
            _lastEvent = event;
            emitUnified(event);
            _notifyState();
          }
        }
      }
    } catch (e) {
      _lastError = 'GlobalQuake parse error: $e';
      _notifyState();
    }
  }

  UnifiedQuakeData? _toUnifiedEvent(_JavaObject packet) {
    final data = packet.fields['data'];
    if (data is! _JavaObject) return null;

    final eventId = _uuidToString(data.fields['uuid']) ?? '';
    if (eventId.isEmpty) return null;
    final revision = _asInt(data.fields['revisionID']) ?? 1;
    final lat = _asDouble(data.fields['lat']);
    final lon = _asDouble(data.fields['lon']);
    final depth = _asDouble(data.fields['depth']) ?? -1;
    final magnitude = _asDouble(data.fields['magnitude']) ?? -1;
    final filterDecision = _firstReportMagnitudeFilter.evaluate(
      eventId: eventId,
      magnitude: magnitude,
    );
    if (filterDecision.isFirstReceivedReport &&
        _firstReportMagnitudeFilter.threshold > 0) {
      _lastLog = filterDecision.allowed
          ? 'GQ first report accepted: $eventId M${magnitude.toStringAsFixed(1)}'
          : 'GQ first report filtered: $eventId M${magnitude.toStringAsFixed(1)}';
      _notifyState();
    }
    if (!filterDecision.allowed) return null;
    final region = data.fields['region']?.toString().trim();
    final originInstant = _fromEpochMs(data.fields['origin']);
    final reportInstant = _fromEpochMs(data.fields['lastUpdate']);
    final timeZone = DateTime.now().timeZoneOffset.inMinutes ~/ 60;
    final originTime = originInstant?.toLocal();
    final reportTime = reportInstant?.toLocal();
    final quality = _qualitySummary(packet.fields['advancedHypocenterData']);
    final hypocenter = _localizedRegion(lat, lon, region);
    final maxIntensity = IntensityCalculator.calcCsisLevel(magnitude, depth, 0);
    final raw = QuakeMessage(
      source: QuakeSourceType.usgs,
      eventId: eventId,
      location: hypocenter,
      magnitude: magnitude,
      latitude: lat ?? 0,
      longitude: lon ?? 0,
      depth: depth,
      originTime: originTime ?? DateTime.now(),
      reportTime: reportTime,
      timeZone: timeZone,
      infoTypeName: 'GlobalQuake 地震预警',
      reviewType: quality,
      isInfoEvent: false,
      isWarn: magnitude >= 5.5,
      maxIntensity: maxIntensity,
      reportNumber: revision,
      reportNumText: '第$revision报',
    );

    return UnifiedQuakeData(
      source: 'globalQuakeEew',
      origin: 3,
      eventId: eventId,
      isEew: true,
      timeZone: timeZone,
      titleText: 'GlobalQuake 地震预警',
      reportNumText: '第$revision报',
      useShindo: false,
      maxIntensity: maxIntensity.toString(),
      className: _classNameForIntensity(maxIntensity),
      hypocenter: hypocenter,
      originTime: originTime,
      reportTime: reportTime,
      magnitude: magnitude,
      depth: depth,
      depthText: _depthText(depth, quality),
      lat: lat,
      lng: lon,
      isWarn: magnitude >= 5.5,
      isFinal: false,
      apiTypeLabel: 'GlobalQuake',
      rawEvent: raw,
      arrivedAt: DateTime.now(),
    );
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final socket = _socket;
      if (socket == null) return;
      socket.add(
        _sentFirstHeartbeat ? _nextHeartbeatBytes : _firstHeartbeatBytes,
      );
      _sentFirstHeartbeat = true;
    });
  }

  void _scheduleReconnect({required bool advanceEndpoint}) {
    if (_manualClose || !_enabled) return;
    if (advanceEndpoint) {
      _endpointIndex = (_endpointIndex + 1) % _endpoints.length;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (_enabled && !_manualClose) {
        _setStatus(SourceStatus.connecting);
        unawaited(_connect());
      }
    });
  }

  Future<void> _reconnectNow() async {
    _reconnectTimer?.cancel();
    _setStatus(SourceStatus.connecting);
    await _connect();
  }

  Future<void> _closeSocket(SourceStatus? nextStatus) async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _socketSub?.cancel();
    _socketSub = null;
    final socket = _socket;
    _socket = null;
    socket?.destroy();
    if (nextStatus != null) {
      _setStatus(nextStatus);
    }
  }

  String? _qualitySummary(dynamic advanced) {
    if (advanced is! _JavaObject) return null;
    final quality = advanced.fields['qualityData'];
    if (quality is! _JavaObject) return null;
    final errOrigin = _asDouble(quality.fields['errOrigin']);
    final errDepth = _asDouble(quality.fields['errDepth']);
    final errNS = _asDouble(quality.fields['errNS']);
    final errEW = _asDouble(quality.fields['errEW']);
    final pct = _asDouble(quality.fields['pct']);
    final stations = _asInt(quality.fields['stations']);
    final grade = _qualityGrade(
      errOrigin: errOrigin,
      errDepth: errDepth,
      errNS: errNS,
      errEW: errEW,
      stations: stations,
      pct: pct,
    );
    if (grade == null && stations == null) return null;
    final parts = <String>[
      if (grade != null) '质量 $grade',
      if (stations != null) '$stations站',
    ];
    return parts.join(' / ');
  }

  String? _qualityGrade({
    required double? errOrigin,
    required double? errDepth,
    required double? errNS,
    required double? errEW,
    required int? stations,
    required double? pct,
  }) {
    final ordinals = <int>[
      if (errDepth != null)
        _qualityOrdinal(errDepth, const [8, 20, 40, 100, 200, 450], true),
      if (errOrigin != null)
        _qualityOrdinal(errOrigin, const [1.2, 3, 9, 20, 40, 100], true),
      if (errNS != null)
        _qualityOrdinal(errNS, const [5, 12, 24, 60, 150, 400], true),
      if (errEW != null)
        _qualityOrdinal(errEW, const [5, 12, 24, 60, 150, 400], true),
      if (stations != null)
        _qualityOrdinal(stations.toDouble(), const [16, 12, 9, 6, 5, 4], false),
      if (pct != null)
        _qualityOrdinal(pct, const [90, 80, 65, 55, 50, 40], false),
    ];
    if (ordinals.isEmpty) return null;
    var worst = 0;
    for (final ordinal in ordinals) {
      if (ordinal > worst) worst = ordinal;
    }
    return const ['S', 'A', 'B', 'C', 'D', 'E', 'F'][worst.clamp(0, 6)];
  }

  int _qualityOrdinal(
    double value,
    List<double> thresholds,
    bool smallerBetter,
  ) {
    var ordinal = 0;
    for (final threshold in thresholds) {
      if (smallerBetter ? value > threshold : value < threshold) {
        ordinal++;
      }
    }
    return ordinal.clamp(0, 6);
  }

  String _localizedRegion(double? lat, double? lon, String? fallback) {
    if (lat != null && lon != null) {
      final mapped = getFEName(lat, lon).trim();
      if (mapped.isNotEmpty) return mapped;
    }
    final fallbackText = fallback?.trim() ?? '';
    return fallbackText.isNotEmpty ? fallbackText : 'GlobalQuake';
  }

  String _depthText(double depth, String? quality) {
    final depthText = depth >= 0 ? '${depth.toStringAsFixed(0)}km' : '';
    if (quality == null || quality.isEmpty) return depthText;
    if (depthText.isEmpty) return quality;
    return '$depthText · $quality';
  }

  DateTime? _fromEpochMs(dynamic value) {
    final ms = _asInt(value);
    if (ms == null || ms <= 0) return null;
    // GlobalQuake sends epoch milliseconds, which already identify an
    // absolute instant. Keep it UTC until the event is localized for display.
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  String _classNameForIntensity(int intensity) {
    if (intensity <= 0) return 'gray';
    if (intensity <= 2) return 'sky-blue';
    if (intensity <= 4) return 'blue';
    if (intensity <= 5) return 'green';
    if (intensity <= 6) return 'yellow';
    if (intensity <= 7) return 'orange';
    if (intensity <= 8) return 'dark-orange';
    if (intensity <= 9) return 'red';
    return 'purple';
  }

  String _normalizeHost(String value, String fallback) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  int _normalizePort(int value) {
    if (value <= 0 || value > 65535) return defaultPort;
    return value;
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  String? _uuidToString(dynamic value) {
    if (value is! _JavaObject) return null;
    final most = _asInt(value.fields['mostSigBits']);
    final least = _asInt(value.fields['leastSigBits']);
    if (most == null || least == null) return null;
    final hex = (_u64Hex(most) + _u64Hex(least)).toLowerCase();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  String _u64Hex(int value) {
    final unsigned = BigInt.from(value).toUnsigned(64);
    return unsigned.toRadixString(16).padLeft(16, '0');
  }

  void _setStatus(SourceStatus status) {
    _status = status;
    onStatusChanged?.call(status);
    _notifyState();
  }

  void _notifyState() {
    if (!_stateController.isClosed) {
      _stateController.add(null);
    }
  }

  @override
  void dispose() {
    disconnect();
    _stateController.close();
    super.dispose();
  }

  static Uint8List _hex(String value) {
    final out = Uint8List(value.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(value.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}

class _GlobalQuakeEndpoint {
  const _GlobalQuakeEndpoint(this.host, this.port);

  final String host;
  final int port;

  @override
  bool operator ==(Object other) =>
      other is _GlobalQuakeEndpoint && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

class _JavaObjectStreamDecoder {
  Uint8List _bytes = Uint8List(0);
  int _offset = 0;
  bool _headerRead = false;
  final List<dynamic> _handles = [];

  void reset() {
    _bytes = Uint8List(0);
    _offset = 0;
    _headerRead = false;
    _handles.clear();
  }

  List<_JavaObject> add(Uint8List chunk) {
    _bytes = Uint8List.fromList([..._bytes.sublist(_offset), ...chunk]);
    _offset = 0;
    final objects = <_JavaObject>[];
    while (true) {
      final mark = _offset;
      final handlesMark = List<dynamic>.of(_handles);
      try {
        if (!_headerRead) {
          if (_remaining < 4) break;
          final magic = _readU2();
          final version = _readU2();
          if (magic != 0xaced || version != 5) {
            throw FormatException('Invalid Java stream header');
          }
          _headerRead = true;
        }
        if (_remaining <= 0) break;
        final value = _readContent();
        if (value is _JavaObject) {
          objects.add(value);
        }
      } on _NeedMore {
        _offset = mark;
        _handles
          ..clear()
          ..addAll(handlesMark);
        break;
      }
    }
    if (_offset > 0) {
      _bytes = _bytes.sublist(_offset);
      _offset = 0;
    }
    return objects;
  }

  int get _remaining => _bytes.length - _offset;

  dynamic _readContent() {
    final tc = _readU1();
    switch (tc) {
      case 0x70:
        return null;
      case 0x71:
        return _handle(_readU4());
      case 0x72:
        return _readClassDescBody();
      case 0x73:
        return _readObjectBody();
      case 0x74:
        return _readNewString();
      case 0x75:
        return _readArrayBody();
      case 0x77:
        final len = _readU1();
        return _JavaBlockData(_readBytes(len));
      case 0x7a:
        final len = _readU4();
        return _JavaBlockData(_readBytes(len));
      case 0x79:
        _handles.clear();
        return _readContent();
      default:
        throw FormatException(
          'Unsupported Java serialization token 0x${tc.toRadixString(16)}',
        );
    }
  }

  _JavaClassDesc _readClassDesc() {
    final value = _readContent();
    if (value is _JavaClassDesc) return value;
    throw FormatException('Expected Java class descriptor');
  }

  _JavaClassDesc _readClassDescBody() {
    final className = _readUtf();
    _readI8();
    final desc = _JavaClassDesc(className);
    _handles.add(desc);
    desc.flags = _readU1();
    final fieldCount = _readU2();
    for (var i = 0; i < fieldCount; i++) {
      final typeCode = String.fromCharCode(_readU1());
      final name = _readUtf();
      String? typeName;
      if (typeCode == 'L' || typeCode == '[') {
        final type = _readContent();
        typeName = type?.toString();
      }
      desc.fields.add(_JavaField(typeCode, name, typeName));
    }
    while (true) {
      final tc = _readU1();
      if (tc == 0x78) break;
      _offset--;
      _readContent();
    }
    final superDesc = _readContent();
    if (superDesc is _JavaClassDesc) {
      desc.superDesc = superDesc;
    }
    return desc;
  }

  String _readNewString() {
    final text = _readUtf();
    _handles.add(text);
    return text;
  }

  _JavaObject _readObjectBody() {
    final desc = _readClassDesc();
    final object = _JavaObject(desc.className);
    _handles.add(object);
    for (final current in desc.hierarchy) {
      for (final field in current.fields) {
        object.fields[field.name] = _readField(field.typeCode);
      }
      if ((current.flags & 0x01) != 0) {
        _skipCustomData();
      }
    }
    return object;
  }

  dynamic _readArrayBody() {
    final desc = _readClassDesc();
    final list = <dynamic>[];
    _handles.add(list);
    final length = _readU4();
    final type = desc.className.length > 1 ? desc.className[1] : 'L';
    for (var i = 0; i < length; i++) {
      list.add(_readField(type));
    }
    return list;
  }

  dynamic _readField(String typeCode) {
    switch (typeCode) {
      case 'B':
        return _readU1();
      case 'C':
        return _readU2();
      case 'D':
        return _readF8();
      case 'F':
        return _readF4();
      case 'I':
        return _readI4();
      case 'J':
        return _readI8();
      case 'S':
        return _readI2();
      case 'Z':
        return _readU1() != 0;
      case 'L':
      case '[':
        return _readContent();
      default:
        throw FormatException('Unsupported Java field type $typeCode');
    }
  }

  void _skipCustomData() {
    while (true) {
      final tc = _readU1();
      if (tc == 0x78) return;
      if (tc == 0x77) {
        _readBytes(_readU1());
      } else if (tc == 0x7a) {
        _readBytes(_readU4());
      } else {
        _offset--;
        _readContent();
      }
    }
  }

  dynamic _handle(int wireHandle) {
    final index = wireHandle - 0x7e0000;
    if (index < 0 || index >= _handles.length) {
      throw FormatException(
        'Invalid Java handle 0x${wireHandle.toRadixString(16)}',
      );
    }
    return _handles[index];
  }

  int _readU1() {
    if (_remaining < 1) throw const _NeedMore();
    return _bytes[_offset++];
  }

  int _readU2() {
    final b = _readBytes(2);
    return (b[0] << 8) | b[1];
  }

  int _readI2() {
    final value = _readU2();
    return value >= 0x8000 ? value - 0x10000 : value;
  }

  int _readU4() {
    final b = _readBytes(4);
    return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
  }

  int _readI4() {
    final value = _readU4();
    return value >= 0x80000000 ? value - 0x100000000 : value;
  }

  int _readI8() {
    final b = _readBytes(8);
    var value = BigInt.zero;
    for (final byte in b) {
      value = (value << 8) | BigInt.from(byte);
    }
    if ((b[0] & 0x80) != 0) {
      value -= BigInt.one << 64;
    }
    return value.toInt();
  }

  double _readF4() {
    final b = _readBytes(4);
    return ByteData.sublistView(
      Uint8List.fromList(b),
    ).getFloat32(0, Endian.big);
  }

  double _readF8() {
    final b = _readBytes(8);
    return ByteData.sublistView(
      Uint8List.fromList(b),
    ).getFloat64(0, Endian.big);
  }

  String _readUtf() {
    final len = _readU2();
    return utf8.decode(_readBytes(len), allowMalformed: true);
  }

  List<int> _readBytes(int count) {
    if (_remaining < count) throw const _NeedMore();
    final out = _bytes.sublist(_offset, _offset + count);
    _offset += count;
    return out;
  }
}

class _JavaClassDesc {
  _JavaClassDesc(this.className);

  final String className;
  int flags = 0;
  final List<_JavaField> fields = [];
  _JavaClassDesc? superDesc;

  List<_JavaClassDesc> get hierarchy {
    final parent = superDesc;
    return [if (parent != null) ...parent.hierarchy, this];
  }
}

class _JavaField {
  const _JavaField(this.typeCode, this.name, this.typeName);

  final String typeCode;
  final String name;
  final String? typeName;
}

class _JavaObject {
  _JavaObject(this.className);

  final String className;
  final Map<String, dynamic> fields = {};
}

class _JavaBlockData {
  const _JavaBlockData(this.bytes);

  final List<int> bytes;
}

class _NeedMore implements Exception {
  const _NeedMore();
}
