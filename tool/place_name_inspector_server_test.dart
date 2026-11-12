import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/epicenter_region_service.dart';
import 'package:flutterrhythmquake/services/native_east_asia_regions.dart';
import 'package:flutterrhythmquake/utils/fe_regions.dart';

/// A read-only developer inspector. It runs the actual Flutter display entry
/// with the actual compiled native library; it does not replicate lookup in JS.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'serve the real application place-name entry for manual inspection',
    () async {
      if (!NativeEastAsiaRegions.supported) {
        throw StateError('The actual station-core library is required');
      }
      await EpicenterRegionService.instance.load();
      if (!EpicenterRegionService.instance.isLoaded) {
        throw StateError('Application region assets did not load');
      }
      final port = int.parse(
        Platform.environment['RQ_PLACE_INSPECTOR_PORT'] ?? '8769',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      final done = Completer<void>();
      final datasetHash = sha256
          .convert(File('assets/regions/east_asia_names.bin').readAsBytesSync())
          .toString();
      if (NativeEastAsiaRegions.datasetSha256 != datasetHash) {
        throw StateError(
          'Loaded native library does not contain the inspected dataset',
        );
      }
      final entryHash = sha256
          .convert(File('lib/utils/fe_regions.dart').readAsBytesSync())
          .toString();
      final library = Platform.environment['RQ_STATION_CORE_LIBRARY'];
      final libraryHash = library == null
          ? null
          : sha256.convert(File(library).readAsBytesSync()).toString();
      final staticFiles = <String, (String, ContentType)>{
        '/': ('tool/place_name_inspector/index.html', ContentType.html),
        '/d3.js': (
          'tool/place_name_inspector/vendor/d3.min.js',
          ContentType('text', 'javascript', charset: 'utf-8'),
        ),
        '/regions.json': (
          '.dart_tool/place_name_inspector/regions.json',
          ContentType.json,
        ),
      };
      Future<void> json(HttpRequest request, int status, Object body) async {
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType.json;
        request.response.headers.set(
          HttpHeaders.cacheControlHeader,
          'no-store',
        );
        request.response.write(jsonEncode(body));
        await request.response.close();
      }

      server.listen((request) async {
        try {
          if (!{
            '127.0.0.1',
            'localhost',
            '::1',
          }.contains(request.requestedUri.host)) {
            await json(request, 403, {'error': '仅接受本机查询'});
            return;
          }
          final path = request.uri.path;
          if (request.method == 'GET' && path == '/api/health') {
            await json(request, 200, {
              'ok': true,
              'entry': 'getFEName',
              'datasetSha256': datasetHash,
              'entrySha256': entryHash,
              'nativeLibrarySha256': libraryHash,
            });
          } else if (request.method == 'GET' && path == '/api/place') {
            final lat = double.tryParse(
              request.uri.queryParameters['lat'] ?? '',
            );
            final lon = double.tryParse(
              request.uri.queryParameters['lon'] ?? '',
            );
            if (lat == null ||
                lon == null ||
                !lat.isFinite ||
                !lon.isFinite ||
                lat < -90 ||
                lat > 90 ||
                lon < -180 ||
                lon > 180) {
              await json(request, 400, {'error': '请输入有效经纬度'});
              return;
            }
            // Exactly the function used by source-estimation/catalog display.
            // Preserve the supplied doubles; do not round or move the point.
            final name = getFEName(lat, lon);
            await json(request, 200, {
              'ok': true,
              'lat': lat,
              'lon': lon,
              'displayName': name,
              'detailedName': EpicenterRegionService.instance.lookup(lat, lon),
              'entry': 'getFEName',
              'datasetSha256': datasetHash,
            });
          } else if (request.method == 'GET' && staticFiles.containsKey(path)) {
            final file = staticFiles[path]!;
            request.response.headers.contentType = file.$2;
            request.response.headers.set(
              HttpHeaders.cacheControlHeader,
              'no-store',
            );
            request.response.add(await File(file.$1).readAsBytes());
            await request.response.close();
          } else {
            await json(request, 404, {'error': 'Not found'});
          }
        } catch (error) {
          await json(request, 500, {'error': error.toString()});
        }
      });
      stdout.writeln(
        'APP_PLACE_INSPECTOR_READY http://127.0.0.1:$port/ dataset=$datasetHash',
      );
      addTearDown(() => server.close(force: true));
      await done.future;
    },
    timeout: const Timeout(Duration(days: 1)),
    skip: Platform.environment['RQ_PLACE_INSPECTOR'] != '1',
  );
}
