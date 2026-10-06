import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/jian_sources.dart';
import '../../models/unified_quake_data.dart';
import '../jian_auth_service.dart';
import '../quake_event_adapter.dart';

/// The collector owns exactly one authenticated /all connection. It does not
/// instantiate SourceManager, query catalog history, or connect to GQ.
class JianCollectorFeed {
  JianCollectorFeed({
    required this.credential,
    required this.onEvent,
    required this.onStatus,
    JianAuthService? auth,
  }) : _auth = auth ?? JianAuthService();
  final String credential;
  final void Function(UnifiedQuakeData) onEvent;
  final void Function(String) onStatus;
  final JianAuthService _auth;
  WebSocket? _socket;
  Timer? _retry;
  Timer? _heartbeat;
  bool _running = false;
  int _generation = 0;

  void start() {
    if (_running) return;
    _running = true;
    unawaited(_open());
  }

  Future<void> _open() async {
    final generation = ++_generation;
    onStatus('connecting');
    try {
      final access = await _auth.accessToken(credential);
      if (!_running || generation != _generation) return;
      final socket =
          await WebSocket.connect(
                'wss://api.sismotide.top/all',
                headers: {'Authorization': 'Bearer $access'},
              )
              .then((socket) {
                if (!_running || generation != _generation) {
                  unawaited(socket.close());
                  throw StateError('Obsolete connection');
                }
                return socket;
              })
              .timeout(const Duration(seconds: 20));
      if (!_running || generation != _generation) {
        await socket.close();
        return;
      }
      _socket = socket;
      var lastReceived = DateTime.now();
      onStatus('connected');
      socket.listen(
        (message) {
          lastReceived = DateTime.now();
          final receivedAt = lastReceived.toUtc();
          if (!_running || generation != _generation) return;
          Map<String, dynamic> frame;
          try {
            frame = Map<String, dynamic>.from(
              jsonDecode(
                    message is String
                        ? message
                        : utf8.decode(message as List<int>),
                  )
                  as Map,
            );
          } catch (_) {
            onStatus('invalid_json');
            return;
          }
          if (frame['ok'] == false ||
              frame['type'] == 'error' ||
              frame['error'] != null) {
            final error = JianAuthException.fromResponse(frame);
            onStatus(error.code);
            _failed(generation, retry: error.retryable);
            return;
          }
          List<UnifiedQuakeData> events;
          try {
            events = decodeFrame(frame, receivedAt: receivedAt).toList();
          } catch (_) {
            onStatus('invalid_report');
            return;
          }
          for (final event in events) {
            onEvent(event);
          }
        },
        onDone: () => _failed(generation),
        onError: (Object _) => _failed(generation),
      );
      _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
        if (DateTime.now().difference(lastReceived) >
            const Duration(seconds: 90)) {
          _failed(generation);
        } else {
          socket.add('ping');
        }
      });
    } on JianAuthException catch (error) {
      onStatus(error.code);
      _failed(generation, retry: error.retryable);
    } catch (_) {
      _failed(generation);
    }
  }

  static Iterable<UnifiedQuakeData> decodeFrame(
    Map<String, dynamic> frame, {
    DateTime? receivedAt,
  }) sync* {
    // Source adapters do not stamp local receipt time; this feed owns admission.
    final arrival = (receivedAt ?? DateTime.now()).toUtc();
    final type = frame['type'];
    if (type == 'all') {
      for (final entry in frame.entries) {
        final match = RegExp(r'^source[:：](.+)$').firstMatch(entry.key);
        if (match == null || entry.value is! Map) continue;
        final payload = (entry.value as Map)['Data'];
        final name = match.group(1)!;
        if (!jianEewTypes.contains(name) || payload is! Map) continue;
        final event = QuakeEventAdapter.convertJian(
          name,
          Map<String, dynamic>.from(payload),
          isSnapshot: true,
        );
        if (event != null) yield event.copyWith(arrivedAt: arrival);
      }
    } else if (type is String &&
        jianEewTypes.contains(type) &&
        frame['Data'] is Map) {
      final event = QuakeEventAdapter.convertJian(
        type,
        Map<String, dynamic>.from(frame['Data'] as Map),
      );
      if (event != null) yield event.copyWith(arrivedAt: arrival);
    }
  }

  void _failed(int generation, {bool retry = true}) {
    if (!_running || generation != _generation) return;
    ++_generation;
    _heartbeat?.cancel();
    unawaited(_socket?.close());
    _socket = null;
    onStatus(retry ? 'retry_in_300s' : 'credential_action_required');
    if (retry) {
      _retry = Timer(const Duration(minutes: 5), () => unawaited(_open()));
    }
  }

  Future<void> stop() async {
    _running = false;
    ++_generation;
    _retry?.cancel();
    _heartbeat?.cancel();
    await _socket?.close();
    _auth.close();
  }
}
