import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class UiScale {
  const UiScale._();

  static const double mainRefWidth = 1700.0;
  static const double compactRefWidth = 1280.0;
  static const double phoneBreakpoint = 600.0;

  static bool isPhone(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return shouldUsePhoneLayout(
      size,
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    );
  }

  static bool shouldUsePhoneLayout(
    Size size, {
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    // A short desktop browser window should not switch the whole app to phone UI.
    // Keep the shortest-side rule for phones, including landscape orientation.
    if (isWeb && size.width >= phoneBreakpoint) {
      switch (platform) {
        case TargetPlatform.windows:
        case TargetPlatform.macOS:
        case TargetPlatform.linux:
          return false;
        case TargetPlatform.android:
        case TargetPlatform.iOS:
        case TargetPlatform.fuchsia:
          break;
      }
    }
    return size.shortestSide < phoneBreakpoint;
  }

  static double factor(
    BuildContext context, {
    double refWidth = mainRefWidth,
    double min = 0.55,
    double max = 1.0,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    return (width / refWidth).clamp(min, max).toDouble();
  }

  static double main(BuildContext context) => factor(context);

  static double topChrome(BuildContext context) => factor(context, min: 0.92);

  static double topBarHeight(BuildContext context) => 50.0 * topChrome(context);

  static double belowTopBar(
    BuildContext context,
    double gap, {
    double refWidth = mainRefWidth,
    double min = 0.55,
  }) {
    return topBarHeight(context) +
        gap * factor(context, refWidth: refWidth, min: min);
  }

  static double compact(BuildContext context) =>
      factor(context, refWidth: compactRefWidth, min: 0.7);

  /// Width-only scale for right-side panels: keep the original compact
  /// baseline at 1280px, never shrink below 1.0, grow on wider windows.
  static double sidePanelWidthScale(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return (width / compactRefWidth).clamp(1.0, 2.0).toDouble();
  }

  static double sidePanelWidth(BuildContext context, double value) {
    return value * sidePanelWidthScale(context);
  }

  static double phone(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return (width / 430.0).clamp(0.88, 1.0).toDouble();
  }

  static double s(
    BuildContext context,
    double value, {
    double refWidth = mainRefWidth,
    double min = 0.55,
    double max = 1.0,
  }) {
    return value * factor(context, refWidth: refWidth, min: min, max: max);
  }

  static double sc(BuildContext context, double value) {
    return value * compact(context);
  }
}
