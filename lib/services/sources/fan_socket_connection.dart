import 'dart:async';

abstract interface class FanSocketConnection {
  String get transportName;

  Future<void> get ready;

  Stream<Object?> get stream;

  Future<void> send(String message);

  Future<void> close();
}

class FanBrowserSocketUnavailableException implements Exception {
  const FanBrowserSocketUnavailableException(this.message);

  final String message;

  @override
  String toString() => 'FanBrowserSocketUnavailableException: $message';
}
