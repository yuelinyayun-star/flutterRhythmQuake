import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../services/sources/seisjs_service.dart';

class SeisJsLayer extends StatelessWidget {
  final List<SeisJsStation>? stations;

  const SeisJsLayer({super.key, this.stations});

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

  static const List<String> _shindoLabels = [
    '0', '1', '2', '3', '4', '5弱', '5強', '6弱', '6強', '7',
  ];

  static const Color _idleColor = Color(0x804466AA);

  @override
  Widget build(BuildContext context) {
    final data = stations;
    if (data == null || data.isEmpty) return const SizedBox.shrink();

    final dotMarkers = <Marker>[];
    final iconMarkers = <Marker>[];

    for (var station in data) {
      final shindo = station.shindo;
      final active = shindo >= 0;

      if (active) {
        iconMarkers.add(Marker(
          width: _getSize(shindo) * 0.75,
          height: _getSize(shindo) * 0.75,
          point: station.coordinate,
          child: _ShindoMarker(
            color: _getColor(shindo),
            label: _getLabel(shindo),
            intensity: shindo,
            isSeisJs: true,
          ),
        ));
      } else {
        dotMarkers.add(Marker(
          width: 2.5,
          height: 2.5,
          point: station.coordinate,
          child: Container(
            decoration: BoxDecoration(
              color: _idleColor,
              shape: BoxShape.circle,
            ),
          ),
        ));
      }
    }

    return MarkerLayer(markers: [...dotMarkers, ...iconMarkers]);
  }

  Color _getColor(int shindo) {
    final idx = shindo.clamp(0, _shindoColors.length - 1);
    return _shindoColors[idx];
  }

  String _getLabel(int shindo) {
    final idx = shindo.clamp(0, _shindoLabels.length - 1);
    return _shindoLabels[idx];
  }

  double _getSize(int shindo) {
    return 14.0;
  }
}

class _ShindoMarker extends StatelessWidget {
  final Color color;
  final String label;
  final int intensity;
  final bool isSeisJs;

  const _ShindoMarker({
    required this.color,
    required this.label,
    required this.intensity,
    this.isSeisJs = false,
  });

  @override
  Widget build(BuildContext context) {
    final isHigh = intensity >= 5;

    return Container(
      decoration: BoxDecoration(
        color: isSeisJs ? color.withValues(alpha: 0.75) : color,
        shape: isSeisJs ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: isSeisJs ? BorderRadius.circular(3) : null,
        border: Border.all(
          color: isHigh ? Colors.white : Colors.white.withValues(alpha: 0.4),
          width: isHigh ? 1.5 : 0.8,
        ),
        boxShadow: isHigh
            ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 1)]
            : [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 2)],
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: intensity >= 4 && !isSeisJs ? Colors.black : Colors.white,
            fontSize: intensity >= 5 ? 8 : 6.5,
            fontWeight: FontWeight.bold,
            height: 1.0,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
