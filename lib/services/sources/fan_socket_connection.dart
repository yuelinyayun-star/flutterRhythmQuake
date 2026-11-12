import 'dart:async';

abstract interface class FanSocketConnection {
  String get transportName;

  Future<void> get ready;

  Stream<Object?> get stream;

  Future<void> send(String message);

  Future<void> close();
}

abstract interface class FanSocketCloseDetails {
  int? get closeCode;
}
