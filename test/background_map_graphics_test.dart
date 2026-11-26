import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/background_service.dart';
import 'package:flutterrhythmquake/widgets/map/background_map_graphics.dart';

void main() {
  testWidgets('an unfocused visible map keeps its graphics', (tester) async {
    final changes = <bool>[];
    final graphics = BackgroundMapGraphics(onRetentionChanged: changes.add);
    addTearDown(graphics.dispose);

    void send(AppLifecycleState state) {
      graphics.setWindowVisible(BackgroundService.isAndroidMapUiVisible(state));
    }

    send(AppLifecycleState.inactive);
    await tester.pump(BackgroundMapGraphics.releaseDelay);
    expect(graphics.retained, isTrue);

    send(AppLifecycleState.hidden);
    await tester.pump(const Duration(milliseconds: 100));
    send(AppLifecycleState.inactive);
    await tester.pump(BackgroundMapGraphics.releaseDelay);
    expect(changes, isEmpty);

    send(AppLifecycleState.hidden);
    send(AppLifecycleState.paused);
    await tester.pump(BackgroundMapGraphics.releaseDelay);
    expect(changes, [false]);
    expect(graphics.retained, isFalse);

    send(AppLifecycleState.inactive);
    expect(changes, [false, true]);
    expect(graphics.retained, isTrue);
  });
}
