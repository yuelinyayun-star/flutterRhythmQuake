import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/source_status.dart';
import 'package:flutterrhythmquake/services/sources/global_quake_service_io.dart';
import 'package:flutterrhythmquake/services/sources/native_station_core_library_io.dart';

import 'support/global_quake_decoder_before_20261015.dart';

List<Map<String, dynamic>> reference(Uint8List raw) => [
  for (final packet in FrozenGlobalQuakeDecoder().add(raw))
    {'format': 'java-object-stream-decoded-v1', 'packet': packet},
];

Iterable<Uint8List> chunks(Uint8List raw, int size) sync* {
  for (var i = 0; i < raw.length; i += size) {
    yield Uint8List.sublistView(raw, i, (i + size).clamp(0, raw.length));
  }
}

Future<void> until(bool Function() predicate) async {
  final timeout = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(timeout)) fail('Timed out');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Uint8List primitiveProtocolFixture() {
  // Controlled Java serialization types only; no earthquake or station data.
  List<int> utf(String text) {
    final bytes = utf8.encode(text);
    return [bytes.length >> 8, bytes.length & 255, ...bytes];
  }

  List<int> integer(int value, int length) {
    final data = ByteData(8)..setInt64(0, value, Endian.big);
    return data.buffer.asUint8List().sublist(8 - length);
  }

  List<int> doubleBytes(double value) =>
      (ByteData(8)..setFloat64(0, value, Endian.big)).buffer.asUint8List();
  final fields = <(String, String, List<int>)>[
    ('B', 'byte', [255]),
    ('C', 'char', [0xff, 0xff]),
    ('S', 'short', integer(-32768, 2)),
    ('I', 'int', integer(-2147483648, 4)),
    ('J', 'longMin', integer(-9223372036854775808, 8)),
    ('J', 'longMax', integer(9223372036854775807, 8)),
    ('D', 'negativeZero', doubleBytes(-0.0)),
    ('D', 'subnormal', doubleBytes(5e-324)),
    ('D', 'maxDouble', doubleBytes(1.7976931348623157e308)),
    ('D', 'nan', doubleBytes(double.nan)),
    ('D', 'positiveInfinity', doubleBytes(double.infinity)),
    ('D', 'negativeInfinity', doubleBytes(double.negativeInfinity)),
    (
      'F',
      'float',
      (ByteData(4)..setFloat32(0, -3.4028234663852886e38, Endian.big)).buffer
          .asUint8List(),
    ),
    ('Z', 'true', [1]),
    ('Z', 'false', [0]),
    ('L', 'self', [0x71, 0, 0x7e, 0, 2]),
  ];
  return Uint8List.fromList([
    0xac,
    0xed,
    0,
    5,
    0x73,
    0x72,
    ...utf('型確認Protocol'),
    ...List.filled(8, 0),
    2,
    0,
    fields.length,
    for (final (type, name, _) in fields) ...[
      type.codeUnitAt(0),
      ...utf(name),
      if (type == 'L') ...[0x74, ...utf('Ljava/lang/Object;')],
    ],
    0x78,
    0x70,
    for (final (_, _, bytes) in fields) ...bytes,
  ]);
}

void main() {
  final native = StationCoreLibrary.supported;
  final service = GlobalQuakeService();
  final raw = File(
    'test/fixtures/global_quake/stream_20260921.bin',
  ).readAsBytesSync();
  final expected = reference(raw);

  test('unchanged real TCP capture has identical ordered object snapshots', () {
    expect(
      sha256.convert(raw).toString(),
      'a0960645c07f48e1900950db22e91c461635cb0808b7308e12d5d52e5ea5370d',
    );
    expect(service.decodePayloadsForTesting(raw), expected);
    expect(
      jsonEncode(service.decodePayloadsForTesting(raw)),
      jsonEncode(expected),
    );
  });

  test('every TCP split boundary preserves packet order and graph fields', () {
    for (var split = 0; split <= raw.length; split++) {
      expect(
        service.decodeChunksForTesting([
          Uint8List.sublistView(raw, 0, split),
          Uint8List.sublistView(raw, split),
        ]),
        expected,
        reason: 'split $split',
      );
    }
    for (final size in [1, 2, 3, 4, 7, 31, 128, 512]) {
      expect(
        service.decodeChunksForTesting(chunks(raw, size)),
        expected,
        reason: 'chunk size $size',
      );
    }
  });

  test('protocol resets and references can span arbitrary TCP chunks', () {
    // Framing test: repeat the unchanged capture payload after Java TC_RESET.
    // This is not a new or simulated earthquake report.
    final frozen = FrozenGlobalQuakeDecoder()..add(raw);
    // The capture ends partway through its next object. A protocol reset is
    // legal only after the preceding complete object, not inside its bytes.
    final complete = Uint8List.sublistView(
      raw,
      0,
      raw.length - frozen.pendingBytes,
    );
    final wire = Uint8List.fromList([
      ...complete,
      0x79,
      ...complete.sublist(4),
      0x79,
      ...complete.sublist(4),
    ]);
    final all = reference(wire);
    expect(all.length, expected.length * 3);
    for (final size in [1, 7, 64, 512, wire.length]) {
      expect(service.decodeChunksForTesting(chunks(wire, size)), all);
    }
  });

  test(
    'protocol primitive boundaries and a self reference preserve exact values',
    () {
      final bytes = primitiveProtocolFixture();
      final expected = reference(bytes);
      for (final size in [1, 7, bytes.length]) {
        expect(
          jsonEncode(service.decodeChunksForTesting(chunks(bytes, size))),
          jsonEncode(expected),
        );
      }
      final packet =
          service.decodePayloadsForTesting(bytes).single['packet'] as Map;
      final fields = packet['fields'] as Map;
      expect(fields['longMin'], -9223372036854775808);
      expect(fields['longMax'], 9223372036854775807);
      expect((fields['negativeZero'] as double).isNegative, isTrue);
      expect(fields['self'], {'ref': 0});
    },
  );

  test(
    'explicit cleanup returns Rust allocations to the warmed baseline',
    () {
      final memory = StationCoreLibrary.library
          .lookupFunction<Uint64 Function(), int Function()>(
            'rq_station_memory_current',
          );
      service.decodePayloadsForTesting(raw);
      final baseline = memory();
      for (var i = 0; i < 100; i++) {
        service.decodePayloadsForTesting(raw);
        expect(service.nativeDecoderDiagnostics['sessions'], 0);
        expect(memory(), baseline);
      }
    },
    skip: !native,
  );

  test('truncated and malformed streams release their native owner', () {
    for (var length = 0; length < raw.length; length += 13) {
      service.decodePayloadsForTesting(Uint8List.sublistView(raw, 0, length));
      expect(service.nativeDecoderDiagnostics['sessions'], 0);
    }
    for (final wire in [
      [0, 0, 0, 5],
      [0xac, 0xed, 0, 5, 0x71, 0, 0x7e, 0, 99],
      [0xac, 0xed, 0, 5, 0xff],
    ]) {
      expect(
        () => service.decodePayloadsForTesting(Uint8List.fromList(wire)),
        throwsFormatException,
      );
      expect(service.nativeDecoderDiagnostics['sessions'], 0);
    }
  }, skip: !native);

  test(
    'disconnect frees connection state and reconnect decodes a fresh stream',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <Socket>[];
      var malformedResponse = false;
      final sub = server.listen((socket) {
        peers.add(socket);
        socket.listen((_) {});
        socket.add(malformedResponse ? [0, 0, 0, 5] : raw);
      });
      addTearDown(() async {
        service.disconnect();
        for (final peer in peers) {
          peer.destroy();
        }
        await sub.cancel();
        await server.close();
        service.configureServers(
          primaryHost: GlobalQuakeService.defaultPrimaryHost,
          primaryPort: GlobalQuakeService.defaultPort,
          secondaryHost: GlobalQuakeService.defaultSecondaryHost,
          secondaryPort: GlobalQuakeService.defaultPort,
        );
      });
      service.configureServers(
        primaryHost: '127.0.0.1',
        primaryPort: server.port,
        secondaryHost: '127.0.0.1',
        secondaryPort: server.port,
      );
      for (var round = 0; round < 3; round++) {
        service.connect();
        await until(() => service.nativeDecoderDiagnostics['sessions'] == 1);
        await until(
          () => service.lastLog?.startsWith('Handshake accepted') ?? false,
        );
        expect(service.status, SourceStatus.connected);
        service.disconnect();
        await until(() => service.nativeDecoderDiagnostics['sessions'] == 0);
        expect(service.status, SourceStatus.disconnected);
        expect(service.lastError, isNull);
      }
      service.connect();
      service.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(service.status, SourceStatus.disconnected);
      expect(service.nativeDecoderDiagnostics['sessions'], 0);
      expect(
        peers.length,
        3,
        reason: 'Cancelled connect must not create a socket',
      );

      service.connect();
      await until(() => service.nativeDecoderDiagnostics['sessions'] == 1);
      peers.last.destroy();
      await until(() => service.nativeDecoderDiagnostics['sessions'] == 0);
      expect(service.status, SourceStatus.disconnected);
      service.disconnect();

      malformedResponse = true;
      service.connect();
      await until(() => service.status == SourceStatus.error);
      expect(service.nativeDecoderDiagnostics['sessions'], 0);
      expect(service.status, SourceStatus.error);
      expect(service.lastError, startsWith('GlobalQuake parse error:'));
      service.disconnect();
    },
    skip: !native,
  );
}
