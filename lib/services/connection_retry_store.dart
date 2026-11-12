import 'connection_retry_store_web.dart'
    if (dart.library.io) 'connection_retry_store_io.dart'
    as platform;

abstract class ConnectionRetryStore {
  Future<T> update<T>(
    String fingerprint,
    T Function(Map<String, dynamic>) action,
  );
}

class MemoryConnectionRetryStore implements ConnectionRetryStore {
  final _records = <String, Map<String, dynamic>>{};
  @override
  Future<T> update<T>(
    String fingerprint,
    T Function(Map<String, dynamic>) action,
  ) =>
      Future<T>.sync(() => action(_records.putIfAbsent(fingerprint, () => {})));
}

ConnectionRetryStore createConnectionRetryStore(String namespace) =>
    platform.createConnectionRetryStore(namespace);
