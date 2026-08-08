import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:webview_windows/webview_windows.dart';

import 'fan_socket_connection.dart';

bool get fanBrowserSocketSupported => Platform.isWindows;

Future<bool> shouldUseFanBrowserSocket(Uri uri) async {
  if (!Platform.isWindows) return false;
  try {
    final addresses = await InternetAddress.lookup(
      uri.host,
    ).timeout(const Duration(seconds: 3));
    return addresses.any(_isTunFakeIpAddress);
  } catch (_) {
    return false;
  }
}

bool _isTunFakeIpAddress(InternetAddress address) {
  if (address.type != InternetAddressType.IPv4) return false;
  final bytes = address.rawAddress;
  return bytes.length == 4 &&
      bytes[0] == 198 &&
      (bytes[1] == 18 || bytes[1] == 19);
}

FanSocketConnection createFanBrowserSocket(Uri uri) {
  return _WindowsFanBrowserSocket(uri);
}

class _WindowsFanBrowserSocket implements FanSocketConnection {
  _WindowsFanBrowserSocket(this.uri) {
    unawaited(_initialize());
  }

  final Uri uri;
  final Completer<void> _readyCompleter = Completer<void>();
  final StreamController<Object?> _streamController =
      StreamController<Object?>();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  WebviewController? _controller;
  bool _opened = false;
  bool _closed = false;
  bool _streamClosed = false;
  String? _lastWebSocketError;

  @override
  String get transportName => 'WebView2';

  @override
  Future<void> get ready => _readyCompleter.future;

  @override
  Stream<Object?> get stream => _streamController.stream;

  Future<void> _initialize() async {
    if (!Platform.isWindows) {
      _failUnavailable('Windows WebView2 is unavailable on this platform');
      return;
    }

    try {
      final version = await WebviewController.getWebViewVersion();
      if (version == null || version.isEmpty) {
        _failUnavailable('WebView2 Runtime is not installed');
        return;
      }
      debugPrint('[FAN WebView2] runtime: $version');

      final controller = WebviewController();
      _controller = controller;
      await controller.initialize();
      if (_closed) {
        await controller.dispose();
        return;
      }
      await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await controller.setFpsLimit(1);

      _subscriptions.add(
        controller.webMessage.listen(
          _handleWebMessage,
          onError: (Object error) {
            _failUnavailable('WebView2 message bridge failed: $error');
          },
        ),
      );
      _subscriptions.add(
        controller.onLoadError.listen((error) {
          _failUnavailable('WebView2 page load failed: $error');
        }),
      );

      await controller.loadStringContent(_buildHtml(uri));
    } catch (error) {
      _failUnavailable('WebView2 initialization failed: $error');
    }
  }

  void _handleWebMessage(Object? message) {
    if (_closed) return;
    final payload = _objectMap(message);
    final type = payload['type']?.toString() ?? '';
    switch (type) {
      case 'open':
        _opened = true;
        if (!_readyCompleter.isCompleted) {
          _readyCompleter.complete();
        }
        break;
      case 'message':
        _streamController.add(payload['data']?.toString() ?? '');
        break;
      case 'error':
        _lastWebSocketError =
            payload['message']?.toString() ?? 'Browser WebSocket error';
        break;
      case 'close':
        final code = payload['code'];
        final reason = payload['reason']?.toString() ?? '';
        if (!_opened && !_readyCompleter.isCompleted) {
          final message =
              _lastWebSocketError ??
              'Browser WebSocket closed before opening '
                  '(code=$code, reason=$reason)';
          // 连接前由浏览器侧关闭时，交给 FAN 服务的 WebView2 回退状态机处理。
          // 不能包装成普通 StateError，否则服务无法切回 Dart 原生传输。
          _readyCompleter.completeError(
            FanBrowserSocketUnavailableException(message),
          );
        }
        _closeStream();
        break;
    }
  }

  void _failUnavailable(String message) {
    if (_closed) return;
    final error = FanBrowserSocketUnavailableException(message);
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.completeError(error);
    } else if (!_streamClosed) {
      _streamController.addError(error);
    }
    _closeStream();
  }

  @override
  Future<void> send(String message) async {
    if (_closed || !_opened) {
      throw StateError('FAN browser WebSocket is not open');
    }
    final controller = _controller;
    if (controller == null) {
      throw StateError('FAN WebView2 controller is unavailable');
    }
    await controller.postWebMessage(
      jsonEncode({'action': 'send', 'data': message}),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final controller = _controller;
    if (controller != null) {
      try {
        await controller.postWebMessage(jsonEncode({'action': 'close'}));
      } catch (_) {}
    }
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {}
    }
    _controller = null;
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.completeError(
        StateError('FAN browser WebSocket was closed before opening'),
      );
    }
    _closeStream();
  }

  void _closeStream() {
    if (_streamClosed) return;
    _streamClosed = true;
    unawaited(_streamController.close());
  }

  static Map<String, Object?> _objectMap(Object? value) {
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    if (value is String) {
      try {
        return _objectMap(jsonDecode(value));
      } catch (_) {}
    }
    return const {};
  }

  static String _buildHtml(Uri uri) {
    final encodedUrl = jsonEncode(uri.toString());
    return '''
<!doctype html>
<html>
<head><meta charset="utf-8"></head>
<body>
<script>
(function() {
  var socket = null;

  function post(payload) {
    if (window.chrome && window.chrome.webview) {
      window.chrome.webview.postMessage(payload);
    }
  }

  window.chrome.webview.addEventListener('message', function(event) {
    var command = event.data;
    if (typeof command === 'string') {
      try { command = JSON.parse(command); } catch (_) { return; }
    }
    if (!command || !command.action) return;
    if (command.action === 'send') {
      if (socket && socket.readyState === WebSocket.OPEN) {
        socket.send(String(command.data));
      }
    } else if (command.action === 'close') {
      if (socket) socket.close();
    }
  });

  try {
    socket = new WebSocket($encodedUrl);
    socket.onopen = function() {
      post({type: 'open'});
    };
    socket.onmessage = function(event) {
      post({type: 'message', data: String(event.data)});
    };
    socket.onerror = function() {
      post({type: 'error', message: 'Browser WebSocket connection error'});
    };
    socket.onclose = function(event) {
      post({
        type: 'close',
        code: event.code,
        reason: event.reason || '',
        wasClean: event.wasClean
      });
    };
  } catch (error) {
    post({type: 'error', message: String(error)});
    post({type: 'close', code: 0, reason: String(error), wasClean: false});
  }
})();
</script>
</body>
</html>
''';
  }
}
