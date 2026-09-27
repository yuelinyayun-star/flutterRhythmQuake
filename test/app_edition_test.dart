import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/app_edition.dart';

void main() {
  test('edition gates match the build definition', () {
    final public =
        const String.fromEnvironment('RQ_EDITION', defaultValue: 'personal') ==
        'public';
    expect(AppEdition.isPublic, public);
    expect(AppEdition.hasPAlertStations, !public);
    expect(AppEdition.hasGlobalQuake, !public);
    expect(AppEdition.hasIcl, !public);
    expect(AppEdition.allowsUnifiedSource('globalQuakeEew'), !public);
    expect(AppEdition.allowsUnifiedSource('iclEew'), !public);
    expect(AppEdition.allowsUnifiedSource('jmaEew'), isTrue);
  });
}
