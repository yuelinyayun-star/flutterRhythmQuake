import 'package:flutter/material.dart';

/// Shared UI runtime flags between settings and main screen.
class UiRuntimeFlags {
  UiRuntimeFlags._();

  static final ValueNotifier<bool> sideInfoAutoShowBetaNotifier =
      ValueNotifier<bool>(false);

  static final ValueNotifier<bool> weatherMarqueeEnabledNotifier =
      ValueNotifier<bool>(false);
}
