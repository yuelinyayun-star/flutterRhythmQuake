import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/hinet_aqua_cmt_service.dart';

void main() {
  test('AQUA angle cleanup preserves numeric values', () {
    final service = HinetAquaCmtService();

    expect(service.splitAngleForTest('298.7˚/195.5˚'), ['298.7', '195.5']);
    expect(service.splitAngleForTest('77.9˚/43.2˚'), ['77.9', '43.2']);
    expect(service.splitAngleForTest('48.2&#730;/162.2&#730;'), [
      '48.2',
      '162.2',
    ]);
  });
}
