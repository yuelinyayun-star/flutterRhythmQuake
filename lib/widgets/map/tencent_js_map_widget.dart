import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile_webview;
import 'package:webview_windows/webview_windows.dart' as windows_webview;

import 'map_config.dart';
import 'tencent_js_map_html_loader.dart';

class TencentJsMapController {
  _TencentJsMapWidgetState? _state;

  void _attach(_TencentJsMapWidgetState state) {
    _state = state;
  }

  void _detach(_TencentJsMapWidgetState state) {
    if (identical(_state, state)) _state = null;
  }

  void syncCamera({required LatLng center, required double zoom}) {
    _state?._syncCamera(center: center, zoom: zoom);
  }
}

class TencentJsMapWidget extends StatefulWidget {
  const TencentJsMapWidget({
    super.key,
    required this.controller,
    required this.initialCenter,
    required this.initialZoom,
  });

  final TencentJsMapController controller;
  final LatLng initialCenter;
  final double initialZoom;

  @override
  State<TencentJsMapWidget> createState() => _TencentJsMapWidgetState();
}

class _TencentJsMapWidgetState extends State<TencentJsMapWidget> {
  mobile_webview.WebViewController? _mobileController;
  windows_webview.WebviewController? _windowsController;
  final List<StreamSubscription> _windowsSubscriptions = [];
  String? _loadError;
  bool _loaded = false;
  bool _disposed = false;
  DateTime? _lastSyncAt;
  String? _lastSyncSignature;
  int _syncLogCount = 0;
  LatLng? _pendingCenter;
  double? _pendingZoom;
  Timer? _syncTimer;
  bool _syncInFlight = false;

  bool get _useWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  bool get _useMobileWebView =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void initState() {
    super.initState();
    widget.controller._attach(this);
    _initialize();
  }

  @override
  void didUpdateWidget(TencentJsMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller._detach(this);
      widget.controller._attach(this);
    }
    if (oldWidget.initialCenter != widget.initialCenter ||
        oldWidget.initialZoom != widget.initialZoom) {
      _syncCamera(center: widget.initialCenter, zoom: widget.initialZoom);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    widget.controller._detach(this);
    for (final subscription in _windowsSubscriptions) {
      subscription.cancel();
    }
    _syncTimer?.cancel();
    _windowsController?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    if (!MapConfig.hasTencentWmtsApiKey) {
      _setLoadError('Tencent JS APIKEY is empty.');
      return;
    }
    if (_useWindows) {
      await _initializeWindows();
      return;
    }
    if (_useMobileWebView) {
      await _initializeMobile();
      return;
    }
    _setLoadError('Tencent JS map is not supported on this platform yet.');
  }

  Future<void> _initializeMobile() async {
    try {
      final controller = mobile_webview.WebViewController()
        ..setJavaScriptMode(mobile_webview.JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF152238))
        ..addJavaScriptChannel(
          'TencentMapBridge',
          onMessageReceived: (message) => _handleBridgeMessage(message.message),
        )
        ..setNavigationDelegate(
          mobile_webview.NavigationDelegate(
            onPageFinished: (_) =>
                debugPrint('[TencentJSMap] web page finished'),
            onWebResourceError: (error) {
              debugPrint(
                '[TencentJSMap] web resource error: '
                '${error.errorCode} ${error.description}',
              );
            },
          ),
        );
      _mobileController = controller;
      await controller.loadHtmlString(_html(), baseUrl: 'https://map.qq.com/');
      if (!_disposed && mounted) setState(() {});
    } catch (error, stackTrace) {
      debugPrint('[TencentJSMap] mobile init failed: $error');
      debugPrint('[TencentJSMap] mobile init stack: $stackTrace');
      _setLoadError('$error');
    }
  }

  Future<void> _initializeWindows() async {
    try {
      final version =
          await windows_webview.WebviewController.getWebViewVersion();
      if (version == null || version.isEmpty) {
        _setLoadError('WebView2 Runtime is not installed.');
        return;
      }
      debugPrint('[TencentJSMap] WebView2 version: $version');
      final controller = windows_webview.WebviewController();
      await controller.initialize();
      await controller.setBackgroundColor(const Color(0xFF152238));
      await controller.setPopupWindowPolicy(
        windows_webview.WebviewPopupWindowPolicy.deny,
      );
      _windowsSubscriptions.add(
        controller.loadingState.listen((state) {
          if (state == windows_webview.LoadingState.navigationCompleted) {
            debugPrint('[TencentJSMap] Windows page finished');
          }
        }),
      );
      _windowsSubscriptions.add(
        controller.onLoadError.listen((error) {
          debugPrint('[TencentJSMap] Windows load error: $error');
        }),
      );
      _windowsSubscriptions.add(
        controller.webMessage.listen((message) {
          _handleBridgeMessage(
            message is String ? message : jsonEncode(message),
          );
        }),
      );
      _windowsController = controller;
      final htmlUri = await writeTencentJsMapHtml(_html());
      debugPrint('[TencentJSMap] Windows load html: $htmlUri');
      await controller.loadUrl(htmlUri.toString());
      if (!_disposed && mounted) setState(() {});
    } on MissingPluginException catch (error, stackTrace) {
      debugPrint('[TencentJSMap] Windows plugin missing: $error');
      debugPrint('[TencentJSMap] Windows plugin missing stack: $stackTrace');
      _setLoadError('Windows WebView 插件未注册，请重新编译并重启应用。');
    } on PlatformException catch (error, stackTrace) {
      debugPrint('[TencentJSMap] Windows platform error: $error');
      debugPrint('[TencentJSMap] Windows platform stack: $stackTrace');
      _setLoadError(error.message ?? error.code);
    } catch (error, stackTrace) {
      debugPrint('[TencentJSMap] Windows init failed: $error');
      debugPrint('[TencentJSMap] Windows init stack: $stackTrace');
      _setLoadError('$error');
    }
  }

  void _markLoaded() {
    if (_loaded || _disposed) return;
    _loaded = true;
    debugPrint('[TencentJSMap] map ready');
    _syncCamera(
      center: _pendingCenter ?? widget.initialCenter,
      zoom: _pendingZoom ?? widget.initialZoom,
      force: true,
    );
  }

  void _handleBridgeMessage(String rawMessage) {
    try {
      final decoded = jsonDecode(rawMessage);
      if (decoded is Map) {
        final type = decoded['type']?.toString() ?? 'log';
        final message = decoded['message']?.toString() ?? rawMessage;
        debugPrint('[TencentJSMap] $type: $message');
        if (type == 'ready') {
          _markLoaded();
        }
        return;
      }
    } catch (_) {
      // Fall through and log the original string.
    }
    debugPrint('[TencentJSMap] $rawMessage');
  }

  void _setLoadError(String message) {
    debugPrint('[TencentJSMap] $message');
    if (_disposed || !mounted) return;
    setState(() => _loadError = message);
  }

  void _syncCamera({
    required LatLng center,
    required double zoom,
    bool force = false,
  }) {
    _pendingCenter = center;
    _pendingZoom = zoom;
    if (!_loaded && !force) return;
    if (force) {
      _syncTimer?.cancel();
      _syncTimer = null;
      _flushCameraSync(force: true);
      return;
    }
    _scheduleCameraSync();
  }

  void _scheduleCameraSync() {
    if (_syncTimer != null || _syncInFlight || _disposed) return;
    final now = DateTime.now();
    final last = _lastSyncAt;
    final delay = last == null
        ? Duration.zero
        : const Duration(milliseconds: 33) - now.difference(last);
    _syncTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _syncTimer = null;
      _flushCameraSync();
    });
  }

  Future<void> _flushCameraSync({bool force = false}) async {
    if (_disposed) return;
    final center = _pendingCenter;
    final zoom = _pendingZoom;
    if (center == null || zoom == null) return;
    final normalizedZoom = zoom.clamp(3.0, 18.0).toDouble();
    final signature =
        '${center.latitude.toStringAsFixed(5)},'
        '${center.longitude.toStringAsFixed(5)},'
        '${normalizedZoom.toStringAsFixed(2)}';
    if (!force && signature == _lastSyncSignature) return;
    _lastSyncAt = DateTime.now();
    _lastSyncSignature = signature;
    if (_syncLogCount < 5) {
      _syncLogCount++;
      debugPrint('[TencentJSMap] sync camera: $signature');
    }
    final script = _syncScript(
      latitude: center.latitude,
      longitude: center.longitude,
      zoom: normalizedZoom,
    );
    _syncInFlight = true;
    try {
      if (_useWindows) {
        await _windowsController?.executeScript(script);
      } else {
        await _mobileController?.runJavaScript(script);
      }
    } catch (error) {
      debugPrint('[TencentJSMap] sync camera failed: $error');
    } finally {
      _syncInFlight = false;
      if (!_disposed) {
        final latestSignature =
            '${_pendingCenter?.latitude.toStringAsFixed(5)},'
            '${_pendingCenter?.longitude.toStringAsFixed(5)},'
            '${(_pendingZoom ?? normalizedZoom).clamp(3.0, 18.0).toStringAsFixed(2)}';
        if (latestSignature != _lastSyncSignature) {
          _scheduleCameraSync();
        }
      }
    }
  }

  String _html() {
    final key = Uri.encodeComponent(MapConfig.tencentWmtsApiKey);
    final lat = widget.initialCenter.latitude.toStringAsFixed(8);
    final lng = widget.initialCenter.longitude.toStringAsFixed(8);
    final zoom = widget.initialZoom.clamp(3.0, 18.0).toStringAsFixed(2);
    return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
  <style>
    html, body, #map {
      width: 100%;
      height: 100%;
      margin: 0;
      padding: 0;
      overflow: hidden;
      background: #152238;
    }
    #map {
      filter: invert(1) hue-rotate(180deg) brightness(0.72) contrast(0.95) saturate(0.78);
    }
    .tmap-zoom-control, .tmap-scale-control, .tmap-control {
      display: none !important;
    }
  </style>
  <script charset="utf-8" src="https://map.qq.com/api/gljs?v=1.exp&key=$key"></script>
</head>
<body>
  <div id="map"></div>
  <script>
    (function() {
      var map = null;
      var pending = {lat: $lat, lng: $lng, zoom: $zoom};

      function post(type, message) {
        var payload = JSON.stringify({type: type, message: String(message)});
        try {
          if (window.TencentMapBridge && TencentMapBridge.postMessage) {
            TencentMapBridge.postMessage(payload);
            return;
          }
          if (window.chrome && window.chrome.webview) {
            window.chrome.webview.postMessage(payload);
          }
        } catch (e) {}
      }

      window.onerror = function(message, source, lineno, colno, error) {
        post('error', message + ' @' + lineno + ':' + colno);
      };

      window.__syncTencentMap = function(lat, lng, zoom) {
        pending = {lat: lat, lng: lng, zoom: zoom};
        if (!map || !window.TMap) return;
        try {
          map.setCenter(new TMap.LatLng(lat, lng));
          map.setZoom(Number(zoom));
        } catch (e) {
          post('sync-error', e && e.message ? e.message : e);
        }
      };

      function init() {
        if (!window.TMap) {
          post('error', 'TMap SDK not available');
          return;
        }
        try {
          map = new TMap.Map(document.getElementById('map'), {
            center: new TMap.LatLng(pending.lat, pending.lng),
            zoom: Number(pending.zoom),
            pitch: 0,
            rotation: 0,
            viewMode: '2D',
            showControl: false,
            mapStyleId: 'style1'
          });
          post('ready', 'Tencent JS map ready');
        } catch (e) {
          post('init-error', e && e.message ? e.message : e);
        }
      }

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
      } else {
        init();
      }
    })();
  </script>
</body>
</html>
''';
  }

  static String _syncScript({
    required double latitude,
    required double longitude,
    required double zoom,
  }) {
    return 'window.__syncTencentMap && '
        'window.__syncTencentMap($latitude, $longitude, $zoom);';
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return ColoredBox(
        color: const Color(0xFF152238),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Tencent map unavailable: $_loadError',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 11,
              ),
            ),
          ),
        ),
      );
    }
    if (_useWindows) {
      final controller = _windowsController;
      if (controller == null || !controller.value.isInitialized) {
        return const ColoredBox(color: Color(0xFF152238));
      }
      return IgnorePointer(child: windows_webview.Webview(controller));
    }
    final controller = _mobileController;
    if (controller == null) {
      return const ColoredBox(color: Color(0xFF152238));
    }
    return IgnorePointer(
      child: mobile_webview.WebViewWidget(controller: controller),
    );
  }
}
