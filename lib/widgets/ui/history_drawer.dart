import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'history_panel.dart';
import 'settings_controls.dart';

class HistoryDrawer extends StatelessWidget {
  const HistoryDrawer({super.key});

  @override
  Widget build(BuildContext context) => Drawer(
    width: math.min(350, MediaQuery.sizeOf(context).width - 16),
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.horizontal(right: Radius.circular(14)),
    ),
    child: ClipRRect(
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(14)),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: SettingsControlStyle.blurSigma,
          sigmaY: SettingsControlStyle.blurSigma,
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: SettingsControlStyle.panel,
            border: Border(
              right: BorderSide(color: SettingsControlStyle.border),
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.history,
                        color: SettingsControlStyle.accent,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          '历史记录',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭历史记录',
                        onPressed: () =>
                            Scaffold.maybeOf(context)?.closeDrawer(),
                        icon: const Icon(Icons.close, size: 20),
                        color: SettingsControlStyle.muted,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: SettingsControlStyle.divider),
                const Expanded(child: HistoryPanel()),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
