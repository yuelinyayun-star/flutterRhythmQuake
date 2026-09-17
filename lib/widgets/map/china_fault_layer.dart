import 'package:flutter/material.dart';

import '../../services/china_fault_service.dart';
import 'cached_fault_layer.dart';

Color chinaFaultColor(String age) => switch (age) {
  'Qh' => const Color(0x80FF0000),
  'Qp3' => const Color(0x80FFA500),
  _ => const Color(0x80008000),
};

class ChinaFaultLayer extends StatefulWidget {
  const ChinaFaultLayer({super.key, this.service});
  final ChinaFaultService? service;

  @override
  State<ChinaFaultLayer> createState() => _ChinaFaultLayerState();
}

class _ChinaFaultLayerState extends State<ChinaFaultLayer> {
  Widget _drawing = const SizedBox.shrink();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final lines = await (widget.service ?? ChinaFaultService.instance).load();
      if (!mounted) return;
      setState(() {
        _drawing = CachedFaultLayer(
          lines: List.unmodifiable(
            lines.map(
              (line) => FaultStroke(
                points: line.points,
                color: chinaFaultColor(line.age),
              ),
            ),
          ),
        );
      });
    } catch (error) {
      debugPrint('China fault layer load failed: ${error.runtimeType}');
    }
  }

  @override
  Widget build(BuildContext context) => _drawing;
}
