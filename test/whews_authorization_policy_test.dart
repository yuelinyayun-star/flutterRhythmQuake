// Controlled close frames and storage; never sends credentials to an upstream.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/whews_authorization_policy.dart';
import 'package:flutterrhythmquake/services/connection_retry_store_io.dart';
import 'package:flutterrhythmquake/services/sources/whews_socket_client.dart';
import 'package:flutterrhythmquake/services/sources/whews_service.dart';
import 'jian_auth_retry_policy_test.dart' show Peer;

class WhewsPeer extends Peer {
  @override
  int? closeCode;
  @override
  String? closeReason;
}

void main() {
  setUp(
    () => WhewsAuthorizationPolicy.storeOverride = MemoryConnectionRetryStore(),
  );
  for (final code in [4401, 4403, 4008]) {
    testWidgets(
      '$code stays stopped across owners; another endpoint and token still work',
      (tester) async {
        final url = 'ws://example.invalid/controlled_$code';
        var opens = 0;
        final peer = WhewsPeer();
        WhewsSocketClient create({
          String? endpoint,
          String token = 'wat_controlled',
        }) => WhewsSocketClient(
          url: endpoint ?? url,
          apiToken: token,
          onMessage: (_) {},
          socketFactory: (_) {
            opens++;
            return WhewsPeer();
          },
        );
        final first = WhewsSocketClient(
          url: url,
          apiToken: 'wat_controlled',
          onMessage: (_) {},
          socketFactory: (_) {
            opens++;
            return peer;
          },
        );
        first.start();
        await tester.pump();
        peer.closeCode = code;
        peer.closeReason = 'controlled rejection';
        await peer.frames.close();
        await tester.pump();
        await first.closed;
        expect(first.authorizationRejected, isTrue);
        first.dispose();
        final restarted = create();
        restarted.start();
        await tester.pump();
        expect(restarted.authorizationRejected, isTrue);
        expect(opens, 1);
        final otherPath = create(endpoint: '$url/another');
        otherPath.start();
        await tester.pump();
        expect(opens, 2);
        final replacement = create(token: 'wat_replacement');
        replacement.start();
        await tester.pump();
        expect(opens, 3);
        restarted.dispose();
        otherPath.dispose();
        replacement.dispose();
        await tester.pump();
      },
    );
  }
  testWidgets('explicit same-token save restores aggregate clients once', (
    tester,
  ) async {
    final policy = WhewsAuthorizationPolicy();
    await policy.block(WhewsService.aggregateUrl, 'wat_controlled', 4401);
    await policy.block(WhewsService.ceaAggregateUrl, 'wat_controlled', 4401);
    final peers = <WhewsPeer>[];
    final service = WhewsService(
      apiToken: 'wat_controlled',
      socketFactory: (_) {
        final peer = WhewsPeer();
        peers.add(peer);
        return peer;
      },
    );
    service.connect();
    await tester.pump();
    expect(peers, isEmpty);
    service.setApiToken('wat_controlled');
    await tester.pump();
    expect(peers, isEmpty);
    await policy.resumeToken('wat_controlled');
    service.setApiToken('wat_controlled', retryRejected: true);
    await tester.pump();
    expect(peers, hasLength(2));
    for (final peer in peers) {
      peer.closeCode = 4401;
      await peer.frames.close();
    }
    await tester.pump();
    await tester.pump(const Duration(hours: 1));
    expect(peers, hasLength(2));
    expect(
      await policy.blockedCode(WhewsService.aggregateUrl, 'wat_controlled'),
      4401,
    );
    service.dispose();
    await tester.pump();
  });
  testWidgets(
    '4503 remains temporary with increasing backoff and no persisted rejection',
    (tester) async {
      var opens = 0;
      final peers = <WhewsPeer>[];
      final client = WhewsSocketClient(
        url: 'ws://example.invalid/temporary',
        apiToken: 'wat_controlled',
        onMessage: (_) {},
        socketFactory: (_) {
          opens++;
          final peer = WhewsPeer();
          peers.add(peer);
          return peer;
        },
      );
      client.start();
      await tester.pump();
      peers.last.closeCode = 4503;
      await peers.last.frames.close();
      await tester.pump();
      await tester.pump(const Duration(seconds: 14));
      expect(opens, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(opens, 2);
      peers.last.closeCode = 4503;
      await peers.last.frames.close();
      await tester.pump();
      await tester.pump(const Duration(seconds: 29));
      expect(opens, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(opens, 3);
      expect(
        await WhewsAuthorizationPolicy().blockedCode(
          'ws://example.invalid/temporary',
          'wat_controlled',
        ),
        isNull,
      );
      client.dispose();
      await tester.pump();
    },
  );
  test(
    'endpoint rejection survives file recreation and stores no token',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'whews_retry_test_',
      );
      try {
        final path = '${directory.path}/state.json';
        final first = WhewsAuthorizationPolicy(
          store: FileConnectionRetryStore(path: path),
        );
        const url = 'wss://api.beecld.com/ws/kma_station';
        await first.block(url, 'wat_private_controlled', 4401);
        final reloaded = WhewsAuthorizationPolicy(
          store: FileConnectionRetryStore(path: path),
        );
        expect(await reloaded.blockedCode(url, 'wat_private_controlled'), 4401);
        expect(
          await reloaded.blockedCode(
            'wss://api.beecld.com/ws/all',
            'wat_private_controlled',
          ),
          isNull,
        );
        expect(
          await File(path).readAsString(),
          isNot(contains('wat_private_controlled')),
        );
        await reloaded.resumeToken('wat_private_controlled');
        expect(
          await reloaded.blockedCode(url, 'wat_private_controlled'),
          isNull,
        );
        // A missing previously committed file is not silently treated as fresh state.
        await File(path).delete();
        await expectLater(
          reloaded.blockedCode(url, 'wat_private_controlled'),
          throwsStateError,
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
