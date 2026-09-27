import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/widgets/map/tile_error_retry_controller.dart';

void main() {
  testWidgets('coalesces failures and backs off repeated tile resets', (
    tester,
  ) async {
    final controller = TileErrorRetryController(
      retryDelays: const [
        Duration(milliseconds: 10),
        Duration(milliseconds: 20),
      ],
    );
    addTearDown(controller.dispose);
    var resets = 0;
    controller.reset.listen((_) => resets++);

    controller.reportFailure('petalDark', (_) => true);
    controller.reportFailure('petalDark', (_) => true);
    await tester.pump(const Duration(milliseconds: 11));
    expect(resets, 1);

    controller.reportFailure('petalDark', (_) => true);
    await tester.pump(const Duration(milliseconds: 11));
    expect(resets, 1);
    await tester.pump(const Duration(milliseconds: 10));
    expect(resets, 2);

    controller.reportFailure('petalDark', (_) => true);
    await tester.pump(const Duration(milliseconds: 21));
    expect(resets, 3, reason: 'Further failures still get retried');
  });

  testWidgets('does not reset a basemap that is no longer selected', (
    tester,
  ) async {
    final controller = TileErrorRetryController(
      retryDelays: const [Duration(milliseconds: 10)],
    );
    addTearDown(controller.dispose);
    var selected = 'petalDark';
    var resets = 0;
    controller.reset.listen((_) => resets++);

    controller.reportFailure('petalDark', (key) => selected == key);
    selected = 'jianSatellite';
    await tester.pump(const Duration(milliseconds: 11));
    expect(resets, 0);

    controller.reportFailure('petalDark', (key) => selected == key);
    await tester.pump(const Duration(milliseconds: 11));
    expect(resets, 0);
  });
}
