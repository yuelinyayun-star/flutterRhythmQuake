import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/utils/world_wrap.dart';
import '../../services/location_service.dart';

class UserLocationLayer extends StatelessWidget {
  const UserLocationLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: LocationService().positionListenable,
      builder: (context, pos, _) {
        if (pos == null) return const SizedBox.shrink();

        return Builder(
          builder: (innerContext) {
            final camera = MapCamera.of(innerContext);
            final latLng = WorldWrap.latLngClosestToCamera(
              LatLng(pos.latitude, pos.longitude),
              camera,
            );
            final centerPos = camera.getOffsetFromOrigin(latLng);

            final size = MediaQuery.of(innerContext).size;
            if (centerPos.dx < -50 ||
                centerPos.dx > size.width + 50 ||
                centerPos.dy < -50 ||
                centerPos.dy > size.height + 50) {
              return const SizedBox.shrink();
            }

            return CustomPaint(
              painter: UserLocationPainter(
                center: centerPos,
                zoom: camera.zoom,
              ),
              size: Size.infinite,
            );
          },
        );
      },
    );
  }
}

class UserLocationPainter extends CustomPainter {
  final Offset center;
  final double zoom;

  UserLocationPainter({required this.center, required this.zoom});

  @override
  void paint(Canvas canvas, Size size) {
    final outerGlow = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 16, outerGlow);

    final outerRing = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, 14, outerRing);

    final centerDot = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 3.5, centerDot);

    final centerBorder = Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, 3.5, centerBorder);
  }

  @override
  bool shouldRepaint(covariant UserLocationPainter oldDelegate) {
    return oldDelegate.center != center || oldDelegate.zoom != zoom;
  }
}
