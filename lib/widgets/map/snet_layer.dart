import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../models/snet_station.dart';
import '../../services/sources/jp_shindo_scale.dart';
import 'station_dot_painter_layer.dart';

class SnetLayer extends StatelessWidget {
  final List<SnetStation>? stations;

  const SnetLayer({super.key, this.stations});

  static const Color _idleColor = Color(0x4D0003CF);

  static const List<Color> _shindoColors = [
    Color(0xFF888888),
    Color(0xFF8282FF),
    Color(0xFF46B4FF),
    Color(0xFF00DC8C),
    Color(0xFFFFFF00),
    Color(0xFFFFB400),
    Color(0xFFFF6400),
    Color(0xFFFF0000),
    Color(0xFFB40000),
    Color(0xFF640096),
  ];

  static const List<Color> _snDotColors = [
    Color(0x4D0003CF),
    Color(0x4D0014DA),
    Color(0x4D0037F0),
    Color(0x4D006CDC),
    Color(0x4D00B3A2),
    Color(0x4D12DC72),
  ];

  static const List<String> _shindoLabels = [
    '0',
    '1',
    '2',
    '3',
    '4',
    '5-',
    '5+',
    '6-',
    '6+',
    '7',
  ];

  @override
  Widget build(BuildContext context) {
    final data = stations;
    if (data == null || data.isEmpty) return const SizedBox.shrink();

    double zoom = 4.0;
    final camera = MapCamera.maybeOf(context);
    if (camera != null) zoom = camera.zoom;

    final overview = _overviewFactor(zoom);
    final dotSize = (0.9 + (zoom - 3) * 0.95).clamp(0.9, 7.5);
    final dotOpacity = (0.08 + overview * 0.62).clamp(0.08, 0.78);
    final dotBorderWidth = (0.35 + overview * 0.55).clamp(0.35, 0.9);

    final dots = <StationDot>[];
    final iconMarkers = <Marker>[];

    final sorted = List<SnetStation>.from(data)
      ..sort((a, b) {
        final rankCompare = _drawRank(a).compareTo(_drawRank(b));
        if (rankCompare != 0) return rankCompare;
        return a.code.compareTo(b.code);
      });

    for (var station in sorted) {
      final level = station.level;

      if (!station.isActive || level < 0) {
        dots.add(
          StationDot(
            coordinate: station.coordinate,
            color: _idleColor,
            radius: dotSize / 2,
            fillOpacity: dotOpacity * 0.12,
            borderOpacity: dotOpacity * 0.32,
            borderWidth: dotBorderWidth,
          ),
        );
      } else if (level <= 5) {
        final dotColor =
            _snDotColors[level.clamp(0, _snDotColors.length - 1).toInt()];
        dots.add(
          StationDot(
            coordinate: station.coordinate,
            color: dotColor,
            radius: dotSize / 2,
            fillOpacity: dotOpacity * 0.22,
            borderOpacity: dotOpacity * 0.68,
            borderWidth: dotBorderWidth,
          ),
        );
      } else {
        final jmaIndex = JpShindoScale.jmaIndexFromLevel(level);
        final color =
            _shindoColors[jmaIndex.clamp(0, _shindoColors.length - 1)];
        final label =
            _shindoLabels[jmaIndex.clamp(0, _shindoLabels.length - 1)];
        iconMarkers.add(
          Marker(
            width: 14.0,
            height: 14.0,
            point: station.coordinate,
            child: _SnetShindoMarker(
              color: color,
              label: label,
              shindo: station.shindo,
              jmaIndex: jmaIndex,
            ),
          ),
        );
      }
    }

    return Stack(
      children: [
        StationDotPainterLayer(dots: dots),
        if (iconMarkers.isNotEmpty) MarkerLayer(markers: iconMarkers),
      ],
    );
  }

  static double _overviewFactor(double zoom) {
    return ((zoom - 3.2) / 3.8).clamp(0.0, 1.0).toDouble();
  }

  static double _drawRank(SnetStation station) {
    if (!station.isActive || station.level < 0) return -1;
    return station.shindo;
  }
}

class _SnetShindoMarker extends StatelessWidget {
  final Color color;
  final String label;
  final double shindo;
  final int jmaIndex;

  const _SnetShindoMarker({
    required this.color,
    required this.label,
    required this.shindo,
    required this.jmaIndex,
  });

  @override
  Widget build(BuildContext context) {
    final isStrong = jmaIndex >= 7;
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: isStrong ? 1.5 : 1.0),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: jmaIndex >= 4 ? Colors.black : Colors.white,
            fontSize: isStrong ? 8.0 : 7.0,
            fontWeight: FontWeight.bold,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

class SnetControlPanel extends StatelessWidget {
  final List<SnetStation>? stations;
  final VoidCallback onRefresh;
  final VoidCallback onToggleMonitoring;
  final bool isMonitoring;

  const SnetControlPanel({
    super.key,
    this.stations,
    required this.onRefresh,
    required this.onToggleMonitoring,
    required this.isMonitoring,
  });

  @override
  Widget build(BuildContext context) {
    final data = stations ?? [];
    final activeStations = data
        .where((s) => s.isActive && s.shindo > 0)
        .toList();
    final maxShindo = activeStations.isEmpty
        ? 0.0
        : activeStations.map((e) => e.shindo).reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.sensors,
                color: isMonitoring ? Colors.cyanAccent : Colors.white60,
                size: 16,
              ),
              const SizedBox(width: 6),
              const Text(
                'S-net 海底观测网',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '总测站: ${data.length} 个',
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          Text(
            '活跃测站: ${activeStations.length} 个',
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          if (activeStations.isNotEmpty) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '最大震度: ',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                _buildIntensityBadge(maxShindo),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildButton(
                icon: isMonitoring ? Icons.pause : Icons.play_arrow,
                onPressed: onToggleMonitoring,
                tooltip: isMonitoring ? '停止监测' : '开始监测',
                isActive: isMonitoring,
              ),
              const SizedBox(width: 6),
              _buildButton(
                icon: Icons.refresh,
                onPressed: onRefresh,
                tooltip: '更新数据',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIntensityBadge(double shindo) {
    final colors = [
      Colors.grey,
      Colors.blue,
      Colors.cyan,
      Colors.green,
      Colors.yellow,
      Colors.orange,
      Colors.red,
      Colors.purple,
      Colors.deepPurple,
    ];
    final idx = shindo.round().clamp(0, colors.length - 1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: colors[idx].withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        shindo.toStringAsFixed(2),
        style: TextStyle(
          color: shindo >= 3.0 ? Colors.black : Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    bool isActive = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isActive
            ? Colors.cyanAccent.withValues(alpha: 0.2)
            : Colors.white10,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              icon,
              size: 16,
              color: isActive ? Colors.cyanAccent : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}
