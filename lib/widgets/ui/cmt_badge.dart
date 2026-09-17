import 'package:flutter/material.dart';

import '../../models/unified_quake_data.dart';
import '../map/fssn_cmt_layer.dart';

class CmtBadge extends StatelessWidget {
  const CmtBadge({
    super.key,
    required this.event,
    required this.size,
    required this.color,
  });

  final UnifiedQuakeData event;
  final double size;
  final Color color;

  static bool supports(UnifiedQuakeData event) => const {
    'fssnCmt',
    'cencCmt',
    'usgsCmt',
    'jmaCmt',
    'fnetCmt',
    'hinetAquaCmt',
  }.contains(event.source);

  @override
  Widget build(BuildContext context) {
    final renderable = CmtBeachball.hasRenderableMechanism(
      momentTensor: event.momentTensor,
      nodalPlane: event.nodalPlane1,
      nodalPlane2: event.nodalPlane2,
    );
    return Semantics(
      label: renderable ? 'CMT 震源机制球' : 'CMT 缺少有效机制参数',
      image: renderable,
      child: Tooltip(
        message: renderable ? 'CMT 震源机制解' : '缺少有效机制参数',
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(size / 9),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (renderable)
                CmtBeachball(
                  diameter: size * 0.7,
                  momentTensor: event.momentTensor,
                  nodalPlane: event.nodalPlane1,
                  nodalPlane2: event.nodalPlane2,
                )
              else
                SizedBox.square(
                  dimension: size * 0.7,
                  child: Center(
                    child: Text(
                      '--',
                      style: TextStyle(color: color, fontSize: size * 0.3),
                    ),
                  ),
                ),
              SizedBox(height: size * 0.03),
              Text(
                'CMT',
                style: TextStyle(
                  fontSize: size * 0.14,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
