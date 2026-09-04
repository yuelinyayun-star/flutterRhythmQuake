import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class KmoniWebViewBridge {
  static final KmoniWebViewBridge _instance = KmoniWebViewBridge._internal();
  factory KmoniWebViewBridge() => _instance;
  KmoniWebViewBridge._internal();

  static const String _kmoniUrl = 'http://www.kmoni.bosai.go.jp/';

  WebViewController? _controller;
  bool _pageLoaded = false;
  bool _isRunning = false;

  final _urlController = StreamController<String>.broadcast();
  final _statusController = StreamController<bool>.broadcast();

  Stream<String> get gifUrlStream => _urlController.stream;
  Stream<bool> get statusStream => _statusController.stream;

  bool get isRunning => _isRunning;

  Future<void> initialize() async {
    if (_controller != null) return;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..addJavaScriptChannel('KmoniBridge', onMessageReceived: _onMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _pageLoaded = true;
            _injectInterceptor();
          },
        ),
      )
      ..loadRequest(Uri.parse(_kmoniUrl));
    _isRunning = true;
  }

  WebViewController? get controller => _controller;

  void _injectInterceptor() {
    if (_controller == null || !_pageLoaded) return;
    _controller!.runJavaScript(_interceptorJs);
    debugPrint('KmoniWebView: JS 注入完成');
  }

  void _onMessage(JavaScriptMessage msg) {
    try {
      final decoded = msg.message;
      if (decoded.startsWith('http') || decoded.startsWith('/')) {
        final url = decoded.startsWith('/')
            ? 'http://www.kmoni.bosai.go.jp$decoded'
            : decoded;
        _urlController.add(url);
        _statusController.add(true);
      }
    } catch (e) {
      debugPrint('KmoniWebView parse error: $e');
    }
  }

  void dispose() {
    _isRunning = false;
    _urlController.close();
    _statusController.close();
    _controller = null;
    _pageLoaded = false;
  }

  static const String _interceptorJs = r'''
(function() {
  if (window.__kmoniIntercepted) return;
  window.__kmoniIntercepted = true;

  let scanTimer = null;
  let lastUrl = '';

  function checkUrl() {
    try {
      var img = document.getElementById('map-shihyo');
      if (!img || img.naturalWidth < 10) return;
      var url = img.src;
      if (url === lastUrl) return;
      lastUrl = url;
      KmoniBridge.postMessage(url);
    } catch(e) {}
  }

  function startScan() {
    if (scanTimer) return;
    checkUrl();
    scanTimer = setInterval(checkUrl, 1000);
  }

  if (document.readyState === 'complete') startScan();
  else window.addEventListener('load', startScan);
})();
''';
}
