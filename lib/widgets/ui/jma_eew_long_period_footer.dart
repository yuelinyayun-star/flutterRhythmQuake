import 'package:flutter/material.dart';
import '../../models/jma_lpgm_bulletin.dart';

/// Paint only the existing badge's bottom label area. The parent owns the
/// unchanged intensity number, outline, dimensions and ordinary background.
class JmaEewLongPeriodFooter extends StatelessWidget {
  const JmaEewLongPeriodFooter({
    super.key,
    required this.level,
    required this.height,
    required this.radius,
    required this.fontSize,
  });
  final int level;
  final double height, radius, fontSize;
  @override
  Widget build(BuildContext context) {
    final color = jmaLpgmClassColor(level);
    return Container(
      key: const ValueKey('jma-eew-long-period-footer'),
      height: height,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.28),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '长周期 $level',
          style: TextStyle(
            fontSize: fontSize,
            height: 1,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
