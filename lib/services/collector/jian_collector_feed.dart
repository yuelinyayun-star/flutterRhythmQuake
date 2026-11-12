import 'dart:async';
import '../sources/api_json_decoder.dart';
import '../sources/source_socket.dart';
import '../sources/source_connection_lifecycle.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../models/jian_sources.dart';
import '../../models/unified_quake_data.dart';
import '../jian_auth_service.dart';
import '../jian_auth_retry_policy.dart';
import '../native_jian_connection.dart';
import '../sources/source_socket_error.dart';
import '../quake_event_adapter.dart';

typedef CollectorSocketFactory =
    WebSocketChannel Function(Uri uri, {Map<String, dynamic>? headers});

/// The collector owns exactly one authenticated /all connection. It does not
/// instantiate SourceManager, query catalog history, or connect to GQ.
class JianCollectorFeed {
  JianCollectorFeed({
    required this.credential,
    required this.onEvent,
    required this.onStatus,
    JianAuthService? auth,
    CollectorSocketFactory? socketFactory,
    DateTime Function()? now,
    JianAuthRetryPolicy? retryPolicy,
  }) : _auth = auth ?? JianAuthService(),
       _socketFactory = socketFactory ?? _openSocket,
       _retryPolicy = retryPolicy ?? JianAuthRetryPolicy(),
       _now = now ?? DateTime.now;
  static WebSocketChannel _openSocket(
    Uri uri, {
    Map<String, dynamic>? headers,
  }) => connectSourceSocket(
    uri,
    headers: headers,
    connectTimeout: const Duration(seconds: 20),
  );
  final String credential;
  final void Function(UnifiedQuakeData) onEvent;
  final void Function(String) onStatus;
  final JianAuthService _auth;
  final CollectorSocketFactory _socketFactory;
  final DateTime Function() _now;
  final JianAuthRetryPolicy _retryPolicy;
  WebSocketChannel? _socket;
  final _closing = SourceConnectionBarrier();
  final _watchdog = SourceActivityWatchdog(const Duration(seconds: 30));
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  Timer? _heartbeat;
  bool _running = false;
  int _generation = 0;
  int _endpointIndex = 0;
  Uri get activeEndpoint => Uri.parse(
    (NativeJianConnection.prepare({
              'op': 'endpoint',
              'index': _endpointIndex,
              'path': '/all',
            })
            as Map)['url']
        as String,
  );

  void start() {
    if (_running) return;
    _running = true;
    _endpointIndex = 0;
    unawaited(_open());
  }

  Future<void> _open() async {
    if (!_running) return;
    final generation = ++_generation;
    onStatus('connecting');
    if (!_running || generation != _generation) return;
    try {
      await _closing.wait();
      if (!_running || generation != _generation) return;
      JianAuthRetryState retryState;
      try {
        retryState = await _retryPolicy.read(credential);
      } catch (_) {
        throw const JianAuthException('retry_storage');
      }
      if (!_running || generation != _generation) return;
      if (retryState.blocked)
        throw const JianAuthException('auth_retry_exhausted');
      final wait = retryState.nextAttemptAt?.difference(_now());
      if (wait != null && wait > Duration.zero) {
        onStatus('retry_in_${(wait.inMilliseconds / 1000).ceil()}s');
        _retry = Timer(wait, () {
          if (_running && generation == _generation) unawaited(_open());
        });
        return;
      }
      final destination = activeEndpoint;
      _auth.selectApiEndpoint(destination);
      final access = await _auth.accessTokenCredential(credential);
      if (!_running || generation != _generation) return;
      if (access.expiresAt == null ||
          !access.expiresAt!.isAfter(
            _now().toUtc().add(const Duration(seconds: 30)),
          )) {
        throw const JianAuthException('expired_access_token');
      }
      final socket = _socketFactory(
        destination,
        headers: {'Authorization': 'Bearer ${access.token}'},
      );
      _socket = socket;
      var lastReceived = _now();
      var confirmedAuth = false;
      _subscription = socket.stream.listen(
        (message) {
          if (!_running || generation != _generation) return;
          lastReceived = _now();
          final receivedAt = lastReceived.toUtc();
          Map<String, dynamic> frame;
          try {
            frame = Map<String, dynamic>.from(
              (message is String
                      ? decodeApiJson(message)
                      : decodeApiJsonBytes(message as List<int>))
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
            unawaited(_authFailed(generation, error));
            return;
          }
          if (!confirmedAuth &&
              (frame['type'] == 'all' ||
                  (jianEarthquakeSources.containsKey(frame['type']) &&
                      frame['Data'] is Map))) {
            confirmedAuth = true;
            unawaited(
              _retryPolicy.accepted(credential, retryState.revision).catchError(
                (Object _) {
                  onStatus('retry_state_update_failed');
                },
              ),
            );
          }
          List<UnifiedQuakeData> events;
          try {
            events = decodeFrame(frame, receivedAt: receivedAt).toList();
          } catch (_) {
            onStatus('invalid_report');
            return;
          }
          for (final event in events) {
            if (!_running || generation != _generation) return;
            onEvent(event);
          }
        },
        onDone: () => _transportFailed(generation),
        onError: (Object error) => _transportFailed(generation, error),
      );
      await sourceReady(socket.ready, const Duration(seconds: 20));
      if (!access.expiresAt!.isAfter(_now().toUtc()))
        throw const JianAuthException('expired_access_token');
      if (!_running || generation != _generation) return;
      onStatus('connected');
      if (!_running || generation != _generation) return;
      _watchdog.reset(_now());
      _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!_running || generation != _generation) return;
        if (_watchdog.mayDeclareStale(_now()) &&
            _now().difference(lastReceived) > const Duration(seconds: 90)) {
          _failed(generation);
        } else {
          try {
            socket.sink.add('ping');
          } catch (_) {
            _failed(generation);
          }
        }
      });
    } on JianAuthException catch (error) {
      if (!_running || generation != _generation) return;
      onStatus(error.code);
      await _authFailed(generation, error);
    } catch (error) {
      _transportFailed(generation, error);
    }
  }

  void _transportFailed(int generation, [Object? error]) {
    if (!_running || generation != _generation) return;
    final auth = JianAuthService.transportAuthFailure(
      error == null ? _socket?.closeCode : sourceSocketStatusCode(error),
    );
    if (auth != null) {
      unawaited(_authFailed(generation, auth));
    } else {
      _failed(generation);
    }
  }

  Future<void> _authFailed(int generation, JianAuthException error) async {
    if (!_running || generation != _generation) return;
    if (!JianAuthRetryPolicy.isTokenRejection(error.code)) {
      _failed(
        generation,
        retry: error.retryable,
        switchEndpoint: const {'network', 'server'}.contains(error.code),
      );
      return;
    }
    final stoppedGeneration = generation + 1;
    _failed(generation, retry: false);
    JianAuthRetryState state;
    try {
      state = await _retryPolicy.rejected(credential, error.code, _now());
    } catch (_) {
      if (_running && stoppedGeneration == _generation)
        onStatus('retry_storage');
      return;
    }
    if (!_running || stoppedGeneration != _generation) return;
    if (state.blocked) {
      onStatus(state.code ?? 'auth_retry_exhausted');
      return;
    }
    onStatus('retry_in_300s');
    final wait = state.nextAttemptAt!.difference(_now());
    _retry = Timer(wait.isNegative ? Duration.zero : wait, () {
      if (_running && stoppedGeneration == _generation) unawaited(_open());
    });
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

  void _failed(
    int generation, {
    bool retry = true,
    bool switchEndpoint = true,
  }) {
    if (!_running || generation != _generation) return;
    ++_generation;
    if (retry && switchEndpoint) {
      final plan =
          NativeJianConnection.prepare({
                'op': 'retry',
                'index': _endpointIndex,
                'failures': 0,
                'cooldownMs': 300000,
                'switchEndpoint': true,
              })
              as Map;
      _endpointIndex = plan['index'] as int;
    }
    unawaited(
      _closeCurrent().catchError((Object _) {
        _running = false;
        _retry?.cancel();
        onStatus('shutdown_unconfirmed');
      }),
    );
    onStatus(retry ? 'retry_in_300s' : 'credential_action_required');
    if (retry && _running) {
      _retry = Timer(const Duration(minutes: 5), () => unawaited(_open()));
    }
  }

  Future<void> stop() async {
    _running = false;
    ++_generation;
    await _closeCurrent();
    _auth.close();
  }

  Future<void> _closeCurrent() async {
    _retry?.cancel();
    _retry = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    final subscription = _subscription;
    final socket = _socket;
    _subscription = null;
    _socket = null;
    if (socket != null)
      _closing.close(() async {
        final closed = socket.sink.close();
        cancelSourceSubscription(subscription);
        await closed;
      });
    await _closing.wait();
  }
}
