import 'dart:async';

import 'package:flutter/material.dart';

import 'settings_controls.dart';
import 'ui_runtime_flags.dart';
import 'ui_scale.dart';

/// Layout-specific setting: also available on tablets using the desktop UI.
class UnifiedCarouselSettings extends StatelessWidget {
  const UnifiedCarouselSettings({super.key});

  @override
  Widget build(BuildContext context) {
    if (UiScale.isPhone(context)) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: UiRuntimeFlags.desktopUnifiedPageSizeNotifier,
      builder: (context, value, _) => SettingsControlRow(
        title: '统一 UI 每页卡片数',
        subtitle: '超过所选条数时分页轮播，切换仍跟随地图视角',
        leading: Icons.view_carousel_outlined,
        control: DropdownButtonFormField<int>(
          key: ValueKey('unified-carousel-page-size-$value'),
          initialValue: value,
          isExpanded: true,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (var size = 1; size <= 4; size++)
              DropdownMenuItem(
                value: size,
                child: Text('$size 条${size == 4 ? '（默认）' : ''}'),
              ),
          ],
          onChanged: (selected) {
            if (selected != null) {
              unawaited(UiRuntimeFlags.setDesktopUnifiedPageSize(selected));
            }
          },
        ),
      ),
    );
  }
}
