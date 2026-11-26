import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../models/fssn_station_frame.dart';
import 'native_fssn_stations.dart';
import 'source_socket.dart';

/// Owns only the map overlay. The existing FSSN earthquake feed is independent.
class FssnStationMapService extends ValueNotifier<FssnStationFrame?> {
  FssnStationMapService({
    http.Client Function()? createClient,
    WebSocketChannel Function(Uri)? connect,
    this.retryDelay = const Duration(seconds: 3),
  }) : _createClient = createClient ?? http.Client.new,
       _connect = connect ?? connectSourceSocket,
       super(null);

  final http.Client Function() _createClient;
  final WebSocketChannel Function(Uri) _connect;
  final Duration retryDelay;
  http.Client? _client;
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _subscription;
  NativeFssnStations? _decoder;
  Timer? _retry;
  bool _running = false;
  bool _disposed = false;
  int _generation = 0;
  static bool get supported => NativeFssnStations.supported;

  void start() {
    if (_running || _disposed || !supported) return;
    _running = true;
    unawaited(_open(++_generation));
  }

  Future<void> _open(int generation) async {
    final client = _createClient();
    _client = client;
    try {
      final response = await client
          .get(Uri.parse('https://seisdata.fanstudio.tech/api/stations'))
          .timeout(const Duration(seconds: 20));
      if (!_isCurrent(generation)) return;
      if (response.statusCode != 200) {
        throw http.ClientException('FSSN layout HTTP ${response.statusCode}');
      }
      // The original response and binary frame go directly to Rust.
      _decoder = NativeFssnStations(response.bodyBytes);
      final socket = _connect(
        Uri.parse('wss://seisdata.fanstudio.tech/ws/overlay'),
      );
      _socket = socket;
      _subscription = socket.stream.listen(
        (data) {
          if (!_isCurrent(generation)) return;
          try {
            if (data is! List<int>) {
              throw const FormatException('FSSN overlay must be binary');
            }
            final frame = _decoder!.process(
              data is Uint8List ? data : Uint8List.fromList(data),
            );
            value = frame;
          } catch (error) {
            _failed(generation, error);
          }
        },
        onError: (Object error) => _failed(generation, error),
        onDone: () => _failed(generation, 'socket closed'),
        cancelOnError: true,
      );
      await socket.ready.timeout(const Duration(seconds: 20));
    } catch (error) {
      _failed(generation, error);
    } finally {
      if (identical(_client, client)) _client = null;
      client.close();
    }
  }

  bool _isCurrent(int generation) =>
      _running && !_disposed && generation == _generation;

  void _failed(int generation, Object error) {
    if (!_isCurrent(generation)) return;
    debugPrint('FSSN station map: $error');
    final nextGeneration = ++_generation;
    _release();
    value = null;
    if (!_isCurrent(nextGeneration)) return;
    _retry = Timer(retryDelay, () {
      _retry = null;
      if (_isCurrent(nextGeneration)) unawaited(_open(nextGeneration));
    });
  }

  void _release() {
    _retry?.cancel();
    _retry = null;
    _client?.close();
    _client = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_socket?.sink.close());
    _socket = null;
    _decoder?.dispose();
    _decoder = null;
  }

  void stop() {
    _running = false;
    _generation++;
    _release();
    if (!_disposed) value = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    stop();
    _disposed = true;
    super.dispose();
  }
}
