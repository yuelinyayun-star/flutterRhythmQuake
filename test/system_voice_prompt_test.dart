import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/system_voice_availability.dart';
import 'package:flutterrhythmquake/widgets/ui/system_voice_prompt.dart';

Widget harness({
  required Future<SystemVoiceAvailability> Function() check,
  required void Function(bool) save,
  bool enabled = false,
  bool requiresSystemVoice = true,
  Future<bool> Function()? openSettings,
  ValueChanged<bool>? onBusyChanged,
}) => MaterialApp(
  theme: ThemeData.dark(),
  home: StatefulBuilder(
    builder: (context, setState) => Scaffold(
      body: Center(
        child: SystemVoiceEnableSwitch(
          value: enabled,
          requiresSystemVoice: requiresSystemVoice,
          check: check,
          onBusyChanged: onBusyChanged,
          openSettings: openSettings ?? () async => true,
          onChanged: (value) async {
            setState(() => enabled = value);
            save(value);
          },
        ),
      ),
    ),
  ),
);

const missing = SystemVoiceAvailability(SystemVoiceState.unavailable);
const available = SystemVoiceAvailability(SystemVoiceState.available);
Finder get toggle => find.byKey(const ValueKey('tts-enabled-switch'));

void main() {
  testWidgets('missing voices never enable or save the switch', (tester) async {
    final saved = <bool>[];
    await tester.pumpWidget(
      harness(check: () async => missing, save: saved.add),
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('未检测到可用系统语音'), findsOneWidget);
    expect(find.text('前往安装'), findsOneWidget);
    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(saved, isEmpty);
    await tester.tap(find.text('暂不开启'));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).onChanged, isNotNull);
  });
  testWidgets('available voices enable once', (tester) async {
    final saved = <bool>[];
    await tester.pumpWidget(
      harness(check: () async => available, save: saved.add),
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(saved, [true]);
    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(find.byType(SystemVoicePrompt), findsNothing);
  });
  testWidgets('detection failure does not claim the speech pack is missing', (
    tester,
  ) async {
    final saved = <bool>[];
    await tester.pumpWidget(
      harness(
        check: () async => throw StateError('native lookup failed'),
        save: saved.add,
      ),
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('暂时无法检测系统语音'), findsOneWidget);
    expect(find.text('前往安装'), findsNothing);
    expect(saved, isEmpty);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
  });
  testWidgets('GPT backend and turning speech off do not query system voices', (
    tester,
  ) async {
    var calls = 0;
    final saved = <bool>[];
    Future<SystemVoiceAvailability> probe() async {
      calls++;
      return missing;
    }

    await tester.pumpWidget(
      harness(check: probe, save: saved.add, requiresSystemVoice: false),
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(saved, [true]);
    expect(calls, 0);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(saved, [true, false]);
    expect(calls, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      harness(check: probe, save: saved.add, enabled: true),
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(saved.last, isFalse);
    expect(calls, 0);
  });
  testWidgets('repeated taps cannot start multiple probes', (tester) async {
    final pending = Completer<SystemVoiceAvailability>();
    var calls = 0;
    await tester.pumpWidget(
      harness(
        check: () {
          calls++;
          return pending.future;
        },
        save: (_) {},
      ),
    );
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.widget<Switch>(toggle).onChanged, isNull);
    await tester.tap(toggle);
    await tester.pump();
    expect(calls, 1);
    pending.complete(available);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isTrue);
  });
  testWidgets(
    'closing settings during detection neither saves nor shows a dialog',
    (tester) async {
      final pending = Completer<SystemVoiceAvailability>();
      final saved = <bool>[];
      final busy = <bool>[];
      await tester.pumpWidget(
        harness(
          check: () => pending.future,
          save: saved.add,
          onBusyChanged: busy.add,
        ),
      );
      await tester.tap(toggle);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      pending.complete(missing);
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(busy, [true, false]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('opening installation settings does not silently enable speech', (
    tester,
  ) async {
    var opened = 0;
    final saved = <bool>[];
    await tester.pumpWidget(
      harness(
        check: () async => missing,
        save: saved.add,
        openSettings: () async {
          opened++;
          return true;
        },
      ),
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.text('前往安装'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(saved, isEmpty);
    expect(find.byType(SystemVoicePrompt), findsNothing);
  });
  testWidgets(
    'failed settings launch retains a usable manual installation path',
    (tester) async {
      await tester.pumpWidget(
        harness(
          check: () async => missing,
          save: (_) {},
          openSettings: () async => false,
        ),
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.text('前往安装'));
      await tester.pumpAndSettle();
      expect(find.text('未能打开系统设置，请按上方路径手动进入。'), findsOneWidget);
    },
  );
  testWidgets('a later enable attempt checks again after installing voices', (
    tester,
  ) async {
    var result = missing;
    var calls = 0;
    final saved = <bool>[];
    await tester.pumpWidget(
      harness(
        check: () async {
          calls++;
          return result;
        },
        save: saved.add,
      ),
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.text('暂不开启'));
    await tester.pumpAndSettle();
    result = available;
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(saved, [true]);
  });
  for (final width in [320.0, 900.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('dialog fits width $width text scale $scale', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: Center(
                  child: SystemVoicePrompt(
                    detectionFailed: false,
                    openSettings: () async => true,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('render the actual dialog for visual inspection', (tester) async {
    var realFont = false;
    await tester.runAsync(() async {
      final file = File('C:/Windows/Fonts/msyh.ttc');
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        await (FontLoader(
          'SystemVoiceVisual',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        realFont = true;
      }
      final icons = File(
        'D:/flutter_windows_3.41.1-stable/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (await icons.exists()) {
        final bytes = await icons.readAsBytes();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
    });
    tester.view.physicalSize = const Size(720, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          textTheme: realFont
              ? ThemeData.dark().textTheme.apply(
                  fontFamily: 'SystemVoiceVisual',
                )
              : null,
        ),
        home: RepaintBoundary(
          key: boundaryKey,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xff25364c), Color(0xff202023)],
              ),
            ),
            child: Center(
              child: SystemVoicePrompt(
                detectionFailed: false,
                openSettings: () async => true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final image =
          await (boundaryKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'tmp/cloud_vgpub_20261101/system-voice-dialog.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
  });
}
