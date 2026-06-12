import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../services/sources/kmoni_webview_bridge.dart';

class KmoniWebViewWidget extends StatefulWidget {
  const KmoniWebViewWidget({super.key});

  @override
  State<KmoniWebViewWidget> createState() => _KmoniWebViewWidgetState();
}

class _KmoniWebViewWidgetState extends State<KmoniWebViewWidget> {
  final KmoniWebViewBridge _bridge = KmoniWebViewBridge();

  @override
  void initState() {
    super.initState();
    _bridge.initialize();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _bridge.controller;
    if (controller == null) return const SizedBox.shrink();
    return SizedBox(
      width: 1,
      height: 1,
      child: WebViewWidget(controller: controller),
    );
  }
}
