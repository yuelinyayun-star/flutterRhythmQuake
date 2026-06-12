import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class FdsnMotionSample {
  final String source;
  final String network;
  final String station;
  final String channel;
  final double? pga;
  final double? pgv;
  final double? intensity;
  final bool active;
  final DateTime timestamp;

  const FdsnMotionSample({
    required this.source,
    required this.network,
    required this.station,
    required this.channel,
    required this.timestamp,
    this.pga,
    this.pgv,
    this.intensity,
    this.active = false,
  });

  String get code => '$network.$station';
}

class FdsnSeedLinkStream {
  final String source;
  final String host;
  final int port;
  final String network;
  final String station;
  final String selector;

  const FdsnSeedLinkStream({
    required this.source,
    required this.host,
    required this.port,
    required this.network,
    required this.station,
    required this.selector,
  });
}

class FdsnMotionService {
  static final FdsnMotionService _instance = FdsnMotionService._();
  factory FdsnMotionService() => _instance;
  FdsnMotionService._();

  static const List<FdsnSeedLinkStream> defaultStreams = [
    FdsnSeedLinkStream(
      source: 'EarthScope',
      host: 'rtserve.earthscope.org',
      port: 18000,
      network: 'IU',
      station: 'ANMO',
      selector: 'BH?',
    ),
    FdsnSeedLinkStream(
      source: 'EarthScope',
      host: 'rtserve.earthscope.org',
      port: 18000,
      network: 'IU',
      station: 'COLA',
      selector: 'BH?',
    ),
    FdsnSeedLinkStream(
      source: 'EarthScope',
      host: 'rtserve.earthscope.org',
      port: 18000,
      network: 'II',
      station: 'PFO',
      selector: 'BH?',
    ),
    FdsnSeedLinkStream(
      source: 'GEOFON',
      host: 'geofon.gfz.de',
      port: 18000,
      network: 'GE',
      station: 'ACRG',
      selector: 'BH?',
    ),
    FdsnSeedLinkStream(
      source: 'GEOFON',
      host: 'geofon.gfz.de',
      port: 18000,
      network: 'GE',
      station: 'MORC',
      selector: 'BH?',
    ),
    FdsnSeedLinkStream(
      source: 'GEOFON',
      host: 'geofon.gfz.de',
      port: 18000,
      network: 'GE',
      station: 'WLF',
      selector: 'BH?',
    ),
  ];

  final _controller = StreamController<FdsnMotionSample>.broadcast();
  Stream<FdsnMotionSample> get sampleStream => _controller.stream;

  final List<_SeedLinkConnection> _connections = [];
  bool _running = false;

  void Function(bool connected)? onStatusChanged;

  void connect({List<FdsnSeedLinkStream> streams = defaultStreams}) {
    if (_running) return;
    _running = true;

    final groups = <String, List<FdsnSeedLinkStream>>{};
    for (final stream in streams) {
      groups.putIfAbsent('${stream.host}:${stream.port}', () => []).add(stream);
    }

    for (final entry in groups.entries) {
      final first = entry.value.first;
      final connection = _SeedLinkConnection(
        host: first.host,
        port: first.port,
        streams: entry.value,
        onSample: _controller.add,
        onStatusChanged: _emitStatus,
      );
      _connections.add(connection);
      connection.start();
    }
  }

  void disconnect() {
    _running = false;
    for (final connection in _connections) {
      connection.stop();
    }
    _connections.clear();
    onStatusChanged?.call(false);
  }

  void _emitStatus() {
    onStatusChanged?.call(_connections.any((c) => c.isConnected));
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}

class _SeedLinkConnection {
  static const int _packetSize = 520;

  final String host;
  final int port;
  final List<FdsnSeedLinkStream> streams;
  final void Function(FdsnMotionSample sample) onSample;
  final VoidCallback onStatusChanged;

  Socket? _socket;
  Timer? _reconnectTimer;
  bool _running = false;
  bool _connected = false;
  final List<int> _buffer = [];

  _SeedLinkConnection({
    required this.host,
    required this.port,
    required this.streams,
    required this.onSample,
    required this.onStatusChanged,
  });

  bool get isConnected => _connected;

  void start() {
    if (_running) return;
    _running = true;
    _connect();
  }

  void stop() {
    _running = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _socket?.destroy();
    _socket = null;
    _setConnected(false);
  }

  Future<void> _connect() async {
    if (!_running || _socket != null) return;
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 12),
      );
      _socket = socket;
      _setConnected(true);
      _sendSelections(socket);
      socket.listen(
        _handleBytes,
        onDone: _handleClosed,
        onError: (error) {
          debugPrint('SeedLink $host:$port error: $error');
          _handleClosed();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('SeedLink $host:$port connect failed: $e');
      _handleClosed();
    }
  }

  void _sendSelections(Socket socket) {
    for (final stream in streams) {
      _sendLine(socket, 'STATION ${stream.station} ${stream.network}');
      _sendLine(socket, 'SELECT ${stream.selector}');
    }
    _sendLine(socket, 'END');
  }

  void _sendLine(Socket socket, String line) {
    socket.add(ascii.encode('$line\r'));
  }

  void _handleBytes(Uint8List bytes) {
    _buffer.addAll(bytes);

    while (true) {
      final start = _findSeedLinkHeader(_buffer);
      if (start < 0) {
        if (_buffer.length > _packetSize) {
          _buffer.removeRange(0, _buffer.length - 8);
        }
        return;
      }
      if (start > 0) {
        _buffer.removeRange(0, start);
      }
      if (_buffer.length < _packetSize) return;

      final packet = Uint8List.fromList(_buffer.sublist(0, _packetSize));
      _buffer.removeRange(0, _packetSize);
      _handlePacket(packet);
    }
  }

  int _findSeedLinkHeader(List<int> data) {
    for (var i = 0; i <= data.length - 8; i++) {
      if (data[i] != 0x53 || data[i + 1] != 0x4c) continue; // SL
      var ok = true;
      for (var j = i + 2; j < i + 8; j++) {
        final b = data[j];
        final isHex = (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x46);
        if (!isHex) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  void _handlePacket(Uint8List packet) {
    final record = packet.sublist(8);
    final header = _MiniSeedHeader.tryParse(record);
    if (header == null) return;

    var source = '';
    for (final stream in streams) {
      if (stream.network == header.network &&
          stream.station == header.station) {
        source = stream.source;
        break;
      }
    }

    onSample(
      FdsnMotionSample(
        source: source,
        network: header.network,
        station: header.station,
        channel: header.channel,
        timestamp: header.startTime,
        active: true,
      ),
    );
  }

  void _handleClosed() {
    _socket?.destroy();
    _socket = null;
    _setConnected(false);
    if (!_running || _reconnectTimer != null) return;
    _reconnectTimer = Timer(const Duration(seconds: 10), () {
      _reconnectTimer = null;
      _connect();
    });
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    onStatusChanged();
  }
}

class _MiniSeedHeader {
  final String network;
  final String station;
  final String channel;
  final DateTime startTime;

  const _MiniSeedHeader({
    required this.network,
    required this.station,
    required this.channel,
    required this.startTime,
  });

  static _MiniSeedHeader? tryParse(Uint8List record) {
    if (record.length < 48) return null;

    final station = _asciiField(record, 8, 5);
    final channel = _asciiField(record, 15, 3);
    final network = _asciiField(record, 18, 2);
    if (station.isEmpty || channel.isEmpty || network.isEmpty) return null;

    final data = ByteData.sublistView(record);
    final bigEndian = _detectBigEndian(data);
    final endian = bigEndian ? Endian.big : Endian.little;
    final year = data.getUint16(20, endian);
    final dayOfYear = data.getUint16(22, endian);
    final hour = record[24];
    final minute = record[25];
    final second = record[26];
    final tenthMillis = data.getUint16(28, endian);

    DateTime startTime;
    try {
      startTime = DateTime.utc(year, 1, 1)
          .add(Duration(days: dayOfYear - 1))
          .add(
            Duration(
              hours: hour,
              minutes: minute,
              seconds: second,
              microseconds: tenthMillis * 100,
            ),
          );
    } catch (_) {
      startTime = DateTime.now().toUtc();
    }

    return _MiniSeedHeader(
      network: network,
      station: station,
      channel: channel,
      startTime: startTime,
    );
  }

  static bool _detectBigEndian(ByteData data) {
    final yearBig = data.getUint16(20, Endian.big);
    if (yearBig >= 1900 && yearBig <= 2200) return true;
    return false;
  }

  static String _asciiField(Uint8List bytes, int start, int length) {
    return ascii.decode(bytes.sublist(start, start + length)).trim();
  }
}
