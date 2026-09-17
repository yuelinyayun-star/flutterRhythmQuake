import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/shake_alert_gate.dart';

void main() {
  test('basic detection does not repeat while the same level is held', () {
    final gate = ShakeAlertGate();
    expect([-1, 0, 0, 0, 0].map(gate.accept), [
      false,
      true,
      false,
      false,
      false,
    ]);
  });

  test('falls are silent and subsequent rises alert as in KA', () {
    final gate = ShakeAlertGate();
    expect([2, 2, 1, 2, 0, 2].map(gate.accept), [
      true,
      false,
      false,
      true,
      false,
      true,
    ]);
  });

  test('returning to basic detection is silent without ending detection', () {
    final gate = ShakeAlertGate();
    expect([0, 1, 0, 0, 2, 0, 1].where(gate.accept), [0, 1, 2, 1]);
  });

  test('new peaks still alert immediately including strong shaking', () {
    final gate = ShakeAlertGate();
    expect([0, 1, 2, 1, 3, 4, 3, 5].where(gate.accept), [0, 1, 2, 3, 4, 5]);
  });

  test('idle or explicit reset starts a new detection', () {
    final gate = ShakeAlertGate();
    expect([2, -1, -1, 2].map(gate.accept), [true, false, false, true]);
    gate.reset();
    expect(gate.accept(1), isTrue);
  });

  test('basic detection rearms only after idle or an explicit reset', () {
    final gate = ShakeAlertGate();
    expect([0, 0, -1, -1, 0, 0].where(gate.accept), [0, 0]);
    gate.reset();
    expect(gate.accept(0), isTrue);
    expect(gate.accept(0), isFalse);
  });

  test('networks have independent previous detection levels', () {
    final nied = ShakeAlertGate();
    final kma = ShakeAlertGate();
    expect(nied.accept(4), isTrue);
    expect(kma.accept(1), isTrue);
    expect(nied.accept(3), isFalse);
  });
}
