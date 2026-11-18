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

  /// Panel backdrop quality, applied both at rest and during camera motion.
  ///
  /// 0 = full glass (bake at native resolution every changed frame);
  /// 2 = lightweight frosted tint (ordinary painting, at rest and in motion).
  static const int mapDragGlassFull = 0;
  // Keep value 2 so existing lightweight-frosted preferences remain valid.
  static const int mapDragGlassOff = 2;
  static const mapDragGlassModeKey = 'map_drag_glass_mode';

  /// 默认使用轻量磨砂。
  static final mapDragGlassModeNotifier = ValueNotifier<int>(
    mapDragGlassOff,
  );

  static void restoreMapDragGlassMode(SharedPreferences prefs) {
    final saved = prefs.getInt(mapDragGlassModeKey);
    // Value 1 was the removed half-resolution mode. Migrate it to the
    // lightweight mode instead of restoring a mode that no longer exists.
    mapDragGlassModeNotifier.value =
        saved == mapDragGlassFull || saved == mapDragGlassOff
        ? saved!
        : mapDragGlassOff;
  }

  static Future<void> setMapDragGlassMode(int value) async {
    if (value != mapDragGlassFull && value != mapDragGlassOff) {
      throw RangeError('Unsupported map glass mode: $value');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(mapDragGlassModeKey, value);
    mapDragGlassModeNotifier.value = value;
  }
}
