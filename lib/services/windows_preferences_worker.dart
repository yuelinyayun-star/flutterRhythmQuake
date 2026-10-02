import 'dart:async';
import 'dart:isolate';

import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';

/// Runs the existing Windows preference backend serially outside the UI isolate.
class WindowsPreferencesWorker extends SharedPreferencesStorePlatform {
  WindowsPreferencesWorker._();

  final ReceivePort _responses = ReceivePort();
  final Completer<void> _ready = Completer<void>();
  final Map<int, Completer<Object?>> _pending = {};
  Isolate? _isolate;
  SendPort? _requests;
  int _sequence = 0;
  bool _closed = false;

  static Future<WindowsPreferencesWorker> start(String supportPath) async {
    final worker = WindowsPreferencesWorker._();
    worker._responses.listen(worker._receive);
    try {
      worker._isolate = await Isolate.spawn(
        _preferencesMain,
        (worker._responses.sendPort, supportPath),
        debugName: 'windows-preferences',
        onExit: worker._responses.sendPort,
        onError: worker._responses.sendPort,
      );
      await worker._ready.future;
      return worker;
    } catch (_) {
      worker._responses.close();
      worker._isolate?.kill(priority: Isolate.immediate);
      rethrow;
    }
  }

  void _receive(dynamic message) {
    if (message is List && message.first == 'ready') {
      _requests = message[1] as SendPort;
      _ready.complete();
      return;
    }
    if (message is List && message.length >= 3) {
      final completer = _pending.remove(message[1] as int);
      if (message.first == 'ok') {
        completer?.complete(message[2]);
      } else {
        completer?.completeError(
          StateError(message[2] as String),
          StackTrace.fromString(message[3] as String),
        );
      }
      return;
    }
    if (_closed) return;
    _closed = true;
    final error = StateError('Windows preferences worker stopped: $message');
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final completer in _pending.values) {
      completer.completeError(error);
    }
    _pending.clear();
    _responses.close();
  }

  Future<Object?> _request(String operation, [List<Object?> args = const []]) {
    if (_closed) {
      return Future.error(StateError('Preferences worker is closed'));
    }
    final id = ++_sequence;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _requests!.send([operation, id, args]);
    return completer.future;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      await _request('set', [valueType, key, value]) as bool;

  @override
  Future<bool> remove(String key) async =>
      await _request('remove', [key]) as bool;

  @override
  Future<bool> clear() => clearWithPrefix('flutter.');

  @override
  Future<bool> clearWithPrefix(String prefix) => clearWithParameters(
    ClearParameters(filter: PreferencesFilter(prefix: prefix)),
  );

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async =>
      await _request('clear', [
            parameters.filter.prefix,
            parameters.filter.allowList,
          ])
          as bool;

  @override
  Future<Map<String, Object>> getAll() => getAllWithPrefix('flutter.');

  @override
  Future<Map<String, Object>> getAllWithPrefix(String prefix) =>
      getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: prefix)),
      );

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async => Map<String, Object>.from(
    await _request('get', [
          parameters.filter.prefix,
          parameters.filter.allowList,
        ])
        as Map,
  );

  Future<void> close() async {
    if (_closed) return;
    await _request('close');
    _closed = true;
    _responses.close();
    _isolate?.kill(priority: Isolate.immediate);
  }
}

class _FixedPreferencePaths extends PathProviderWindows {
  _FixedPreferencePaths(this.supportPath);
  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

Future<void> _preferencesMain((SendPort, String) bootstrap) async {
  final (responses, supportPath) = bootstrap;
  final requests = ReceivePort();
  // The backend's path override keeps its original IO logic on the same file.
  final backend = SharedPreferencesWindows()
    // ignore: invalid_use_of_visible_for_testing_member
    ..pathProvider = _FixedPreferencePaths(supportPath);
  responses.send(['ready', requests.sendPort]);
  await for (final message in requests) {
    final operation = message[0] as String;
    final id = message[1] as int;
    final args = message[2] as List;
    try {
      final result = switch (operation) {
        'set' => await backend.setValue(
          args[0] as String,
          args[1] as String,
          args[2] as Object,
        ),
        'remove' => await backend.remove(args[0] as String),
        'clear' => await backend.clearWithParameters(
          ClearParameters(
            filter: PreferencesFilter(
              prefix: args[0] as String,
              allowList: args[1] as Set<String>?,
            ),
          ),
        ),
        'get' => await backend.getAllWithParameters(
          GetAllParameters(
            filter: PreferencesFilter(
              prefix: args[0] as String,
              allowList: args[1] as Set<String>?,
            ),
          ),
        ),
        'close' => true,
        _ => throw StateError('Unknown preference operation: $operation'),
      };
      responses.send(['ok', id, result]);
      if (operation == 'close') {
        requests.close();
        return;
      }
    } catch (error, stack) {
      responses.send(['error', id, error.toString(), stack.toString()]);
    }
  }
}
