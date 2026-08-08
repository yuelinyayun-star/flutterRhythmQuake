import 'package:flutter_test/flutter_test.dart';

import 'package:flutterrhythmquake/core/source_estimation/jshis_surface_structure_api.dart';

void main() {
  test('builds the documented J-SHIS V4 WGS84 ARV request', () {
    const request = JshisSurfaceStructureRequest(
      latitude: 35.2974,
      longitude: 136.7505,
    );

    expect(request.uri.host, 'www.j-shis.bosai.go.jp');
    expect(request.uri.path, '/map/api/sstrct/V4/meshinfo.geojson');
    expect(request.uri.queryParameters, {
      'position': '136.7505,35.2974',
      'epsg': '4326',
      'attr': 'ARV',
      'lang': 'en',
    });
  });

  test(
    'parses the documented GeoJSON ARV response without changing its value',
    () {
      const rawResponse = '''
{
  "type": "FeatureCollection",
  "status": "Success",
  "features": [
    {
      "properties": {
        "ARV": "1.94",
        "meshcode": "5236765031"
      }
    }
  ],
  "metaData": {
    "version": "V4"
  }
}
''';

      final parsed = JshisSurfaceStructureArvResponse.tryParse(rawResponse);

      expect(parsed, isNotNull);
      expect(parsed!.version, 'V4');
      expect(parsed.meshCode, '5236765031');
      expect(parsed.arv, 1.94);
    },
  );

  test('rejects a response that is not exactly one successful ARV mesh', () {
    expect(
      JshisSurfaceStructureArvResponse.tryParse(
        '{"status":"Success","features":[],"metaData":{"version":"V4"}}',
      ),
      isNull,
    );
  });
}
