import 'dart:async';
import 'dart:isolate';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'windows_preference_files.dart';
import 'replay_history_files.dart';
import 'native_replay_history_files_io.dart';
import '../models/station_history_frame.dart';
import '../models/unified_quake_data.dart';

/// Runs the existing Windows preference backend serially outside the UI isolate.
class WindowsPreferencesWorker extends SharedPreferencesStorePlatform {
  WindowsPreferencesWorker._(this.supportPath);

  final String supportPath;

  final ReceivePort _responses = ReceivePort();
  final Completer<void> _ready = Completer<void>();
  final Map<int, Completer<Object?>> _pending = {};
  Isolate? _isolate;
  SendPort? _requests;
  int _sequence = 0;
  bool _closed = false;

  static Future<WindowsPreferencesWorker> start(String supportPath) async {
    final worker = WindowsPreferencesWorker._(supportPath);
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
    if (_closed) {
      return;
    }
    _closed = true;
    final error = StateError('Windows preferences worker stopped: $message');
    if (!_ready.isCompleted) {
      _ready.completeError(error);
    }
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

  Future<Object?> readHistory(String key) =>
      _request('history', ['flutter.$key']);

  Future<Object?> replayFileOperation(String operation, List<Object?> args) =>
      _request('replay-$operation', args);

  Future<Map<String, dynamic>?> readHistorySnapshot(String key) async {
    final value = await _request('history-snapshot', ['flutter.$key']);
    return value == null ? null : Map<String, dynamic>.from(value as Map);
  }

  Future<bool> writeHistoryWithSnapshot(
    String key,
    String value,
    Map<String, dynamic> snapshot,
  ) async =>
      await _request('history-with-snapshot', ['flutter.$key', value, snapshot])
          as bool;

  Future<bool> writeHistory(String key, Object value) =>
      setValue(value is List ? 'StringList' : 'String', 'flutter.$key', value);

  Future<bool> removeHistory(String key) => remove('flutter.$key');

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
    if (_closed) {
      return;
    }
    await _request('close');
    _closed = true;
    _responses.close();
    _isolate?.kill(priority: Isolate.immediate);
  }
}

Future<void> _preferencesMain((SendPort, String) bootstrap) async {
  final (responses, supportPath) = bootstrap;
  final requests = ReceivePort();
  final backend = WindowsPreferenceFiles(supportPath);
  final root = '$supportPath/replay_history/v3';
  final files = NativeReplayHistoryFiles.supported
      ? NativeReplayHistoryFiles(root)
      : ReplayHistoryFiles(root);
  try {
    responses.send(['ready', requests.sendPort]);
    await for (final message in requests) {
      final operation = message[0] as String;
      final id = message[1] as int;
      final args = message[2] as List;
      try {
        final result = switch (operation) {
          'replay-read' =>
            (await files.record(args[0] as String))?['value'] ??
                await backend.readHistory('flutter.${args[0]}'),
          'replay-snapshot' =>
            (await files.record(args[0] as String))?['snapshot'] ??
                await backend.readHistorySnapshot('flutter.${args[0]}'),
          'replay-write' => await files.writeRecord(
            args[0] as String,
            args[1],
            args[2] as Map?,
          ),
          'replay-remove' => await files.remove(args[0] as String),
          'replay-report-write' => await files.writeReport(
            args[0] as String,
            args[1] as Map,
          ),
          'replay-report-read' => UnifiedQuakeData.fromMap(
            await files.readReport(args[0] as String, args[1] as String),
          ),
          'replay-frame-write' => await files.writeFrame(
            args[0] as String,
            args[1] as Map,
          ),
          'replay-frame-read' => StationHistoryFrame.fromMap(
            await files.readFrame(args[0] as String),
          ),
          'replay-frame-remove' => await files.remove(
            args[0] as String,
            frame: true,
          ),
          'set' => await backend.setValue(args[1] as String, args[2] as Object),
          'remove' => await backend.remove(args[0] as String),
          'clear' => await backend.clear(
            args[0] as String,
            args[1] as Set<String>?,
          ),
          'get' => await backend.getAll(
            args[0] as String,
            args[1] as Set<String>?,
          ),
          'history' => await backend.readHistory(args[0] as String),
          'history-snapshot' => await backend.readHistorySnapshot(
            args[0] as String,
          ),
          'history-with-snapshot' => await backend.writeHistoryWithSnapshot(
            args[0] as String,
            args[1] as String,
            Map<String, dynamic>.from(args[2] as Map),
          ),
          'close' => true,
          _ => throw StateError('Unknown preference operation: $operation'),
        };
        if (operation == 'close' && files is NativeReplayHistoryFiles) {
          files.dispose();
        }
        responses.send(['ok', id, result]);
        if (operation == 'close') {
          requests.close();
          return;
        }
      } catch (error, stack) {
        responses.send(['error', id, error.toString(), stack.toString()]);
      }
    }
  } finally {
    if (files is NativeReplayHistoryFiles) {
      files.dispose();
    }
  }
}
