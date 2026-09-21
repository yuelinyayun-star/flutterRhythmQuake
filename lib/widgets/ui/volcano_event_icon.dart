import 'package:flutter/material.dart';

import '../../core/utils/volcano_icon_assets.dart';
import '../../models/volcano_event_data.dart';
import '../../services/sources/jma_volcano_map_service.dart';

/// Updates even when the standing warning arrives after the event card.
class VolcanoEventIcon extends StatelessWidget {
  const VolcanoEventIcon({
    super.key,
    required this.volcano,
    this.imageKey,
    this.service,
  });

  final VolcanoEventData volcano;
  final Key? imageKey;
  final JmaVolcanoMapService? service;

  @override
  Widget build(BuildContext context) {
    final warnings = service ?? JmaVolcanoMapService();
    return ListenableBuilder(
      listenable: warnings,
      builder: (context, child) => Image.asset(
        VolcanoIconAssets.forVolcanoEvent(
          volcano,
          officialSite: warnings.siteForCode(volcano.volcanoCode),
        ),
        key: imageKey,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
