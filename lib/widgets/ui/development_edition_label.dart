import 'package:flutter/material.dart';

import '../../core/app_edition.dart';

class DevelopmentEditionLabel extends StatelessWidget {
  const DevelopmentEditionLabel({super.key});

  @override
  Widget build(BuildContext context) {
    if (AppEdition.isPublic) return const SizedBox.shrink();
    return const IgnorePointer(
      child: Text(
        '开发版',
        maxLines: 1,
        style: TextStyle(
          color: Colors.white54,
          fontSize: 11,
          height: 1,
          shadows: [Shadow(color: Colors.black87, blurRadius: 2)],
        ),
      ),
    );
  }
}
