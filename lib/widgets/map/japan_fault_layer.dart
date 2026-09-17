import 'package:flutter/material.dart';

import '../../services/japan_fault_service.dart';
import 'cached_fault_layer.dart';

class JapanFaultLayer extends StatefulWidget {
  const JapanFaultLayer({super.key, this.service});
  final JapanFaultService? service;

  @override
  State<JapanFaultLayer> createState() => _JapanFaultLayerState();
}

class _JapanFaultLayerState extends State<JapanFaultLayer> {
  Widget _drawing = const SizedBox.shrink();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final lines = await (widget.service ?? JapanFaultService.instance).load();
      if (!mounted) return;
      setState(() {
        _drawing = CachedFaultLayer(
          lines: List.unmodifiable(
            lines.map(
              (line) => FaultStroke(
                points: line.points,
                color: Color(line.colorArgb),
              ),
            ),
          ),
        );
      });
    } catch (error) {
      debugPrint('Japan fault layer load failed: ${error.runtimeType}');
    }
  }

  @override
  Widget build(BuildContext context) => _drawing;
}
