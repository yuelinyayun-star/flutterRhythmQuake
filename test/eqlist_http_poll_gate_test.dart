import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/eqlist/eqlist_http_poll_gate.dart';

void main() {
  test('skips HTTP only while external push is fresh', () {
    final gate = EqlistHttpPollGate(
      freshWindow: const Duration(seconds: 30),
    );
    expect(gate.shouldSkipHttp, isFalse);

    gate.noteExternalUpdate(DateTime.now());
    expect(gate.shouldSkipHttp, isTrue);

    gate.noteExternalUpdate(
      DateTime.now().subtract(const Duration(seconds: 31)),
    );
    expect(gate.shouldSkipHttp, isFalse);
  });

  test('reset clears the gate', () {
    final gate = EqlistHttpPollGate();
    gate.noteExternalUpdate();
    expect(gate.shouldSkipHttp, isTrue);
    gate.reset();
    expect(gate.shouldSkipHttp, isFalse);
  });
}
