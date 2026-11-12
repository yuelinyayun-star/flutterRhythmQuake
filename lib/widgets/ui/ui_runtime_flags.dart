import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared UI runtime flags between settings and main screen.
class UiRuntimeFlags {
  UiRuntimeFlags._();

  static const tsunamiSidebarVisibleKey = 'tsunami_sidebar_visible';
  static final tsunamiSidebarVisibleNotifier = ValueNotifier<bool>(true);
  static void restoreTsunamiSidebarVisible(SharedPreferences prefs) {
    tsunamiSidebarVisibleNotifier.value =
        prefs.getBool(tsunamiSidebarVisibleKey) ?? true;
  }

  static Future<void> setTsunamiSidebarVisible(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(tsunamiSidebarVisibleKey, value);
    tsunamiSidebarVisibleNotifier.value = value;
  }

  static const desktopUnifiedPageSizeKey = 'desktop_unified_page_size';
  static final desktopUnifiedPageSizeNotifier = ValueNotifier<int>(4);

  static void restoreDesktopUnifiedPageSize(SharedPreferences prefs) {
    final saved = prefs.getInt(desktopUnifiedPageSizeKey);
    desktopUnifiedPageSizeNotifier.value =
        saved != null && saved >= 1 && saved <= 4 ? saved : 4;
  }

  static Future<void> setDesktopUnifiedPageSize(int value) async {
    RangeError.checkValueInInterval(value, 1, 4, 'value');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(desktopUnifiedPageSizeKey, value);
    desktopUnifiedPageSizeNotifier.value = value;
  }

  static final ValueNotifier<bool> hideGridOnEewNotifier = ValueNotifier<bool>(
    false,
  );

  static const String niedHypCurvePanelVisiblePreferenceKey =
      'debug_nied_hyp_curve_panel_visible';

  static final ValueNotifier<bool> sideInfoAutoShowBetaNotifier =
      ValueNotifier<bool>(false);

  static const String localEewDomesticKey = 'local_eew_sidebar_domestic';
  static const String localEewForeignKey = 'local_eew_sidebar_foreign';
  static final ValueNotifier<bool> localEewDomesticNotifier =
      ValueNotifier<bool>(true);
  static final ValueNotifier<bool> localEewForeignNotifier =
      ValueNotifier<bool>(false);

  static final ValueNotifier<bool> weatherMarqueeEnabledNotifier =
      ValueNotifier<bool>(false);

  static final ValueNotifier<bool> niedHypCurvePanelVisibleNotifier =
      ValueNotifier<bool>(false);

  /// Panel backdrop behavior while the map camera is moving.
  ///
  /// 0 = full glass (bake at native resolution every frame);
  /// 1 = low-res glass (bake at half resolution while moving, blur hides it);
  /// 2 = glass off (plain translucent panels while moving, cheapest).
  static const int mapDragGlassFull = 0;
  static const int mapDragGlassLowRes = 1;
  static const int mapDragGlassOff = 2;
  static const mapDragGlassModeKey = 'map_drag_glass_mode';
  /// 默认档位 = 低清毛玻璃（1.0.5.31 起改为 lowRes，实测拖拽 CPU 收益最大档）。
  static final mapDragGlassModeNotifier = ValueNotifier<int>(
    mapDragGlassLowRes,
  );

  static void restoreMapDragGlassMode(SharedPreferences prefs) {
    final saved = prefs.getInt(mapDragGlassModeKey);
    mapDragGlassModeNotifier.value =
        (saved == mapDragGlassFull ||
            saved == mapDragGlassLowRes ||
            saved == mapDragGlassOff)
        ? saved!
        : mapDragGlassLowRes;
  }

  static Future<void> setMapDragGlassMode(int value) async {
    RangeError.checkValueInInterval(value, 0, 2, 'value');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(mapDragGlassModeKey, value);
    mapDragGlassModeNotifier.value = value;
  }
}
