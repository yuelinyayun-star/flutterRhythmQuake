import 'package:flutter/material.dart';

/// Shared UI runtime flags between settings and main screen.
class UiRuntimeFlags {
  UiRuntimeFlags._();

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
}
