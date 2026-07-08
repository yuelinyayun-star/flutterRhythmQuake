import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/replay/jma_intensity_archive.dart';

void main() {
  test('parses station coordinates and activity dates from EUC-JP table', () {
    final nameBytes = Uint8List.fromList([0xc0, 0xd0, 0xbc, 0xed]);
    final bytes = BytesBuilder()
      ..add(ascii.encode('1000000\t'))
      ..add(nameBytes)
      ..add(ascii.encode('\t4310\t14119\t199604011200\t202012311230\n'));

    final stations = const JmaIntensityStationTableParser().parse(
      bytes.takeBytes(),
    );
    final station = stations['1000000'];

    expect(station, isNotNull);
    expect(station!.latitude, closeTo(43.1666667, 0.000001));
    expect(station.longitude, closeTo(141.3166667, 0.000001));
    expect(station.activeFrom, DateTime.utc(1996, 4, 1, 3));
    expect(station.activeUntil, DateTime.utc(2020, 12, 31, 3, 30));
    expect(station.rawNameHex, 'c0d0bced');
  });

  test('parses 96-byte hypocenter and station intensity records', () {
    final header = List<String>.filled(96, ' ');
    void put(List<String> target, int start, String value) {
      for (var index = 0; index < value.length; index++) {
        target[start - 1 + index] = value[index];
      }
    }

    put(header, 1, 'A');
    put(header, 2, '2020');
    put(header, 6, '01');
    put(header, 8, '01');
    put(header, 10, '03');
    put(header, 12, '56');
    put(header, 14, '1943');
    put(header, 22, '036');
    put(header, 25, '4827');
    put(header, 33, '0140');
    put(header, 37, '3248');
    put(header, 45, '021  ');
    put(header, 53, '32');
    put(header, 55, 'V');
    put(header, 62, '3');
    put(header, 91, '00001');
    put(header, 96, 'K');

    final observation = List<String>.filled(96, ' ');
    put(observation, 1, '3000120');
    put(observation, 9, '01');
    put(observation, 11, '03');
    put(observation, 13, '56');
    put(observation, 15, '275');
    put(observation, 19, '1');
    put(observation, 21, '09');
    put(observation, 24, '56');
    put(observation, 26, '276');
    put(observation, 30, '00094');
    put(observation, 36, 'N');
    put(observation, 37, '00074');
    put(observation, 43, 'E');
    put(observation, 44, '00086');
    put(observation, 50, 'Z');
    put(observation, 51, '00045');

    final bytes = Uint8List.fromList(
      ascii.encode('${header.join()}\r\n${observation.join()}\r\n'),
    );
    final events = const JmaIntensityArchiveParser().parse(bytes);

    expect(events, hasLength(1));
    final event = events.single;
    expect(
      event.preferredHypocenter.originTime,
      DateTime.utc(2019, 12, 31, 18, 56, 19, 430),
    );
    expect(event.preferredHypocenter.latitude, closeTo(36.8045, 0.00001));
    expect(event.preferredHypocenter.longitude, closeTo(140.541333, 0.00001));
    expect(event.preferredHypocenter.depthKm, 21);
    expect(event.preferredHypocenter.magnitude, 3.2);
    expect(event.observations, hasLength(1));
    expect(event.observations.single.instrumentalIntensity, 0.9);
    expect(event.observations.single.peakAccelerationGal, 9.4);
    expect(event.observations.single.northSouthAccelerationGal, 7.4);
    expect(event.observations.single.eastWestAccelerationGal, 8.6);
    expect(event.observations.single.verticalAccelerationGal, 4.5);
  });
}
