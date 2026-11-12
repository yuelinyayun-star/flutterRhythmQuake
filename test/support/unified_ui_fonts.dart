import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Match bundled app glyphs and Windows CJK fallback rather than test Ahem.
Future<void> loadUnifiedUiFonts() async {
  final fonts = FontLoader('MPLUSRounded1c');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    fonts.addFont(
      File(
        'assets/fonts/MPLUSRounded1c-$weight.ttf',
      ).readAsBytes().then(ByteData.sublistView),
    );
  }
  await fonts.load();
  final fallback = File('C:/Windows/Fonts/msyh.ttc');
  if (await fallback.exists()) {
    await (FontLoader(
      'WindowsCjkFallback',
    )..addFont(fallback.readAsBytes().then(ByteData.sublistView))).load();
  }
}

ThemeData unifiedUiTestTheme() =>
    ThemeData(brightness: Brightness.dark, useMaterial3: true).copyWith(
      textTheme: ThemeData.dark().textTheme.apply(
        fontFamily: 'MPLUSRounded1c',
        fontFamilyFallback: const ['WindowsCjkFallback'],
      ),
    );
