import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/cmt_fault_type.dart';

void main() {
  group('CMT fault type classification', () {
    test('classifies reverse, thrust and normal rakes', () {
      expect(
        CmtFaultTypeClassifier.fromNodalPlane('358/45/85'),
        CmtFaultType.thrust,
      );
      expect(
        CmtFaultTypeClassifier.fromNodalPlane('10/60/90'),
        CmtFaultType.reverse,
      );
      expect(
        CmtFaultTypeClassifier.fromNodalPlane('10/45/-90'),
        CmtFaultType.normal,
      );
    });

    test('uses 22.5-degree boundaries for strike-slip and oblique types', () {
      expect(
        CmtFaultTypeClassifier.fromNodalPlane('0/90/22.5'),
        CmtFaultType.strikeSlip,
      );
      expect(
        CmtFaultTypeClassifier.fromNodalPlane('0/90/45'),
        CmtFaultType.obliqueReverse,
      );
      expect(
        CmtFaultTypeClassifier.fromNodalPlane('0/90/-45'),
        CmtFaultType.obliqueNormal,
      );
    });

    test('does not classify an absent or malformed nodal plane', () {
      expect(
        CmtFaultTypeClassifier.fromNodalPlane(null),
        CmtFaultType.unavailable,
      );
      expect(
        CmtFaultTypeClassifier.fromNodalPlane('1/2'),
        CmtFaultType.unavailable,
      );
    });
  });
}
