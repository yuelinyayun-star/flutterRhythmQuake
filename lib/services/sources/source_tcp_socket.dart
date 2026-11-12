import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../debug/network_diagnostic.dart';

import 'native_tcp_socket.dart';

/// The byte-stream contract used by GQ and SeedLink, not a partial Socket
/// implementation. Source framing, subscription and reconnect policy stay out.
abstract class SourceTcpSocket extends Stream<Uint8List> {
  void add(List<int> bytes);
  Future<void> flush();
  void destroy();
  Future<void> get done;
}

class DartSourceTcpSocket extends SourceTcpSocket {
  DartSourceTcpSocket(this.socket) {
    if (NetworkDiagnostic.active) {
      NetworkDiagnostic.event('dart_tcp', _diagnosticId, 'connected', {
        'remoteAddress': socket.remoteAddress.address,
        'remotePort': socket.remotePort,
        'localPort': socket.port,
        'tls': socket is SecureSocket,
      });
    }
    unawaited(socket.done.catchError((Object _) {}));
  }
  final Socket socket;
  final int _diagnosticId = NetworkDiagnostic.active
      ? NetworkDiagnostic.nextId()
      : 0;
  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      (NetworkDiagnostic.active
              ? socket.transform(
                  StreamTransformer<Uint8List, Uint8List>.fromHandlers(
                    handleData: (bytes, sink) {
                      NetworkDiagnostic.event(
                        'dart_tcp',
                        _diagnosticId,
                        'receive',
                        {},
                        bytes,
                      );
                      sink.add(bytes);
                    },
                    handleError: (error, stack, sink) {
                      NetworkDiagnostic.event(
                        'dart_tcp',
                        _diagnosticId,
                        'error',
                        {'error': error.toString()},
                      );
                      sink.addError(error, stack);
                    },
                    handleDone: (sink) {
                      NetworkDiagnostic.event(
                        'dart_tcp',
                        _diagnosticId,
                        'peer_closed',
                        {},
                      );
                      sink.close();
                    },
                  ),
                )
              : socket)
          .listen(
            onData,
            onError: onError,
            onDone: onDone,
            cancelOnError: cancelOnError,
          );
  @override
  void add(List<int> bytes) {
    NetworkDiagnostic.event(
      'dart_tcp',
      _diagnosticId,
      'send_queued',
      {},
      bytes,
    );
    socket.add(bytes);
  }

  @override
  Future<void> flush() => socket.flush();
  @override
  void destroy() {
    NetworkDiagnostic.event('dart_tcp', _diagnosticId, 'destroy', {});
    socket.destroy();
  }

  @override
  Future<void> get done => socket.done;
}

Future<SourceTcpSocket> connectSourceTcpSocket(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 12),
}) async {
  if (!NativeTcpSocket.supported || host.contains('%')) {
    return DartSourceTcpSocket(
      await Socket.connect(host, port, timeout: timeout),
    );
  }
  return connectNativeTcpSocket(host, port, timeout: timeout);
}

/// DNS uses the existing OS/Dart resolver. TCP attempts use the shared native
/// reactor, with the SDK's 250 ms address-racing interval (25 ms on loopback).
Future<SourceTcpSocket> connectNativeTcpSocket(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 12),
  String authority = '',
}) async {
  if (port < 1 || port > 65535) throw ArgumentError.value(port, 'port');
  final watch = Stopwatch()..start();
  final parsed = InternetAddress.tryParse(host);
  final addresses = parsed == null
      ? await InternetAddress.lookup(host).timeout(timeout)
      : [parsed];
  if (addresses.isEmpty) throw SocketException('No addresses for $host');
  final result = Completer<SourceTcpSocket>();
  final attempts = <NativeTcpSocket>[];
  Timer? stagger;
  var index = 0, outstanding = 0;
  Object? lastError;
  final deadline = Timer(
    timeout - watch.elapsed > Duration.zero
        ? timeout - watch.elapsed
        : Duration.zero,
    () {
      if (!result.isCompleted) {
        result.completeError(
          TimeoutException('TCP connect timed out', timeout),
        );
      }
    },
  );
  void launch() {
    if (result.isCompleted || index >= addresses.length) return;
    stagger?.cancel();
    final address = addresses[index++];
    outstanding++;
    try {
      final socket = NativeTcpSocket.open(
        address,
        port,
        authority: authority,
        timeout: timeout - watch.elapsed > Duration.zero
            ? timeout - watch.elapsed
            : const Duration(milliseconds: 1),
      );
      attempts.add(socket);
      unawaited(
        socket.ready.then<void>(
          (_) {
            outstanding--;
            if (!result.isCompleted) {
              result.complete(socket);
            } else {
              socket.destroy();
            }
          },
          onError: (Object error) {
            outstanding--;
            socket.destroy();
            lastError = error;
            if (result.isCompleted) return;
            if (index < addresses.length) {
              launch();
            } else if (outstanding == 0) {
              result.completeError(lastError!);
            }
          },
        ),
      );
    } catch (error) {
      outstanding--;
      lastError = error;
      if (index < addresses.length) {
        launch();
      } else if (outstanding == 0 && !result.isCompleted) {
        result.completeError(error);
      }
      return;
    }
    if (!result.isCompleted && index < addresses.length) {
      stagger = Timer(
        Duration(milliseconds: address.isLoopback ? 25 : 250),
        launch,
      );
    }
  }

  launch();
  SourceTcpSocket? winner;
  try {
    return winner = await result.future;
  } finally {
    deadline.cancel();
    stagger?.cancel();
    for (final socket in attempts) {
      if (!identical(socket, winner)) socket.destroy();
    }
  }
}
