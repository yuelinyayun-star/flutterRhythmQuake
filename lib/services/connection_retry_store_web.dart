import 'dart:convert';
import 'dart:js_interop';
import 'connection_retry_store.dart';

ConnectionRetryStore createConnectionRetryStore(String namespace) =>
    BrowserConnectionRetryStore(namespace);

@JS('window.localStorage')
external _LocalStorage get _storage;

extension type _LocalStorage(JSObject _) implements JSObject {
  external JSString? getItem(JSString key);
  external void setItem(JSString key, JSString value);
}

class BrowserConnectionRetryStore implements ConnectionRetryStore {
  BrowserConnectionRetryStore(this.namespace);
  final String namespace;
  @override
  Future<T> update<T>(
    String fingerprint,
    T Function(Map<String, dynamic>) action,
  ) => Future<T>.sync(() {
    final key = '$namespace.$fingerprint';
    final stored = _storage.getItem(key.toJS)?.toDart;
    final value = stored == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(stored) as Map);
    final result = action(value);
    _storage.setItem(key.toJS, jsonEncode(value).toJS);
    return result;
  });
}
