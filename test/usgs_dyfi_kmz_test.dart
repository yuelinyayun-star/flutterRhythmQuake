import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutterrhythmquake/models/usgs_dyfi.dart';
import 'package:flutterrhythmquake/services/native_dyfi_grid.dart';
import 'package:flutterrhythmquake/services/sources/usgs_dyfi_service.dart';
import 'usgs_dyfi_test.dart' show dyfiEvent;

const kenaiFixture = 'test/fixtures/usgs_dyfi/aka2026vqjriv';
Future<UsgsDyfiFrame> loadOriginalKenai() async {
  final detail = File(
    '$kenaiFixture/detail.original.geojson',
  ).readAsBytesSync();
  final kmz = File('$kenaiFixture/dyfi_geo.original.kmz').readAsBytesSync();
  final original = jsonDecode(utf8.decode(detail)) as Map<String, dynamic>;
  final product = UsgsDyfiProduct.fromDetail(original)!;
  final event = dyfiEvent(original);
  final service = UsgsDyfiService(
    client: MockClient((request) async {
      if (request.url == product.gridUrl) {
        return http.Response.bytes(kmz, 200);
      }
      return http.Response.bytes(detail, 200);
    }),
  );
  try {
    await service.select(event);
    final frame = service.manualFrame;
    expect(service.status, isNull);
    expect(frame, isNotNull);
    return frame!;
  } finally {
    service.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'original Kenai product loads actual KMZ through production service and Rust',
    () async {
      expect(NativeDyfiGrid.supported, isTrue);
      final detailFile = File('$kenaiFixture/detail.original.geojson');
      final gridFile = File('$kenaiFixture/dyfi_geo.original.kmz');
      final before = [
        sha256.convert(detailFile.readAsBytesSync()),
        sha256.convert(gridFile.readAsBytesSync()),
      ];
      final frame = await loadOriginalKenai();
      expect(frame.product.gridFormat, 'kmz');
      expect(frame.product.gridKm, 1);
      expect(frame.product.responses, 90);
      expect(frame.product.maxCdi, 3.9);
      expect(frame.cells, hasLength(71));
      expect(frame.cells!.fold<int>(0, (n, c) => n + c.responses), 87);
      expect(frame.cells!.first.cdi, 3.9);
      expect(frame.cells!.first.rings.first.first.latitude, 60.5140);
      expect(frame.cells!.first.rings.first.first.longitude, -150.6321);
      expect(frame.event.latitude, 60.198);
      expect(frame.event.longitude, -150.932);
      expect([
        sha256.convert(detailFile.readAsBytesSync()),
        sha256.convert(gridFile.readAsBytesSync()),
      ], before);
      expect(NativeDyfiGrid.outputs, 0);
    },
  );
  test(
    'corrupt KMZ is rejected rather than creating substitute observations',
    () async {
      await expectLater(
        NativeDyfiGrid.decodeKmz(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
      expect(NativeDyfiGrid.outputs, 0);
    },
  );
}
