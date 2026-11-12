import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutterrhythmquake/models/usgs_dyfi.dart';
import 'package:flutterrhythmquake/widgets/map/usgs_dyfi_layer.dart';
import 'support/dyfi_outline_reference.dart';
import 'usgs_dyfi_test.dart' show originalDetail, dyfiEvent, emptyDyfiDetail;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final original = File(
    'assets/maps/world_countries.geojson',
  ).readAsBytesSync();
  final json = jsonDecode(utf8.decode(original));
  final before = referenceCountries(json);
  final after = parseDyfiCountryPolygons(json);

  test('thumbnail keeps every original country coordinate and ring', () {
    final raw = [
      for (final f in json['features'])
        ...f['geometry']['type'] == 'Polygon'
            ? [f['geometry']['coordinates']]
            : f['geometry']['coordinates'],
    ];
    expect(after.length, raw.length);
    for (var i = 0; i < raw.length; i++) {
      expect(after[i].rings.length, raw[i].length);
      for (var j = 0; j < raw[i].length; j++) {
        final ring = after[i].rings[j];
        expect(ring.length, raw[i][j].length);
        for (var k = 0; k < ring.length; k++) {
          expect(ring[k].longitude, raw[i][j][k][0]);
          expect(ring[k].latitude, raw[i][j][k][1]);
        }
      }
    }
    expect(
      sha256.convert(
        File('assets/maps/world_countries.geojson').readAsBytesSync(),
      ),
      sha256.convert(original),
    );
  });

  testWidgets('original DYFI cells retain paths, hit targets and pixels', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final id in ['ci41345415', 'us6000u0xi', 'us6000u1em']) {
        final detail = id == 'us6000u1em'
            ? emptyDyfiDetail()
            : originalDetail(id);
        final frame = UsgsDyfiFrame(
          event: dyfiEvent(detail),
          product: UsgsDyfiProduct.fromDetail(detail)!,
          cells: UsgsDyfiCell.parse(
            jsonDecode(
              File(
                'test/fixtures/usgs_dyfi/$id.dyfi_geo_10km.original.geojson',
              ).readAsStringSync(),
            ),
          ),
        );
        for (final longitude in [
          frame.event.longitude,
          frame.event.longitude + 360,
        ]) {
          for (final rotation in [0.0, 57.0]) {
            const size = ui.Size(350, 450);
            final camera = MapCamera(
              crs: const Epsg3857(),
              center: LatLng(frame.event.latitude, longitude),
              zoom: 6,
              rotation: rotation,
              nonRotatedSize: size,
            );
            final painter = UsgsDyfiGridPainter(frame: frame, camera: camera);
            final paths = [
              for (final cell in frame.cells!)
                referenceDyfiPath(cell.rings, camera),
            ];
            for (var i = 0; i < paths.length; i++) {
              expect(painter.shapes[i].$2.getBounds(), paths[i].getBounds());
              final position = paths[i].getBounds().center;
              final expected = frame.cells!
                  .asMap()
                  .entries
                  .toList()
                  .reversed
                  .where((e) => paths[e.key].contains(position))
                  .firstOrNull
                  ?.value;
              expect(painter.cellAt(position), same(expected));
            }
            Future<List<int>> render(bool optimized) async {
              final recorder = ui.PictureRecorder();
              final canvas = ui.Canvas(recorder);
              if (optimized) {
                painter.paint(canvas, size);
              } else {
                final visible = ui.Offset.zero & size;
                canvas.save();
                canvas.clipRect(visible);
                for (var i = 0; i < paths.length; i++) {
                  final path = paths[i];
                  if (!path.getBounds().overlaps(visible)) continue;
                  canvas.drawPath(
                    path,
                    ui.Paint()
                      ..color = dyfiColor(
                        frame.cells![i].cdi,
                      ).withValues(alpha: .7),
                  );
                  canvas.drawPath(
                    path,
                    ui.Paint()
                      ..color = const ui.Color(0xBB172129)
                      ..style = ui.PaintingStyle.stroke
                      ..strokeWidth = .8,
                  );
                }
                canvas.restore();
              }
              final picture = recorder.endRecording();
              final image = await picture.toImage(350, 450);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              final result = bytes!.buffer.asUint8List().toList();
              image.dispose();
              picture.dispose();
              return result;
            }

            expect(
              await render(true),
              await render(false),
              reason: '$id $longitude $rotation',
            );
          }
        }
      }
    });
  });

  testWidgets(
    'original country rendering matches across world copies and rotations',
    (tester) async {
      await tester.runAsync(() async {
        final centers = [
          const LatLng(0, 0),
          const LatLng(34, -118),
          const LatLng(38, 140),
          const LatLng(50, 10),
          const LatLng(-17, 179.8),
          const LatLng(-17, -179.8),
          const LatLng(-17, 539.8),
          const LatLng(-17, -539.8),
          const LatLng(84, 30),
          const LatLng(-84, 30),
        ];
        for (final size in [const ui.Size(144, 116), const ui.Size(446, 160)]) {
          for (final center in centers) {
            for (final zoom in [0.0, 3.5, 10.0]) {
              for (final rotation in [0.0, 57.0]) {
                final camera = MapCamera(
                  crs: const Epsg3857(),
                  center: center,
                  zoom: zoom,
                  rotation: rotation,
                  nonRotatedSize: size,
                );
                Future<List<int>> render(bool optimized) async {
                  final recorder = ui.PictureRecorder();
                  final canvas = ui.Canvas(recorder);
                  if (optimized) {
                    DyfiCountriesPainter(after, camera).paint(canvas, size);
                  } else {
                    paintReferenceCountries(canvas, size, before, camera);
                  }
                  final picture = recorder.endRecording();
                  final image = await picture.toImage(
                    size.width.toInt(),
                    size.height.toInt(),
                  );
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.rawRgba,
                  );
                  final result = bytes!.buffer.asUint8List().toList();
                  image.dispose();
                  picture.dispose();
                  return result;
                }

                expect(
                  await render(true),
                  await render(false),
                  reason: '$center $zoom $rotation $size',
                );
              }
            }
          }
        }
      });
    },
  );
}
