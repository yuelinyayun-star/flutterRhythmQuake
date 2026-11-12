import 'dart:convert';
import 'dart:io';
import 'main.dart' as app;
import 'services/debug/network_diagnostic.dart';

Future<void> main(List<String> arguments) async {
  NetworkDiagnostic.start();
  if (arguments.contains('--network-diagnostic-self-test')) {
    // Exercise the compiled application and installed DLL without starting
    // SourceManager, credentials, or any external network connection.
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.write('compiled diagnostic loopback');
        await request.response.close();
      });
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/compiled-self-test'),
      );
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      client.close(force: true);
      await server.close(force: true);
      await Future<void>.delayed(const Duration(seconds: 1));
      final directory = NetworkDiagnostic.directory!;
      final rows = File(
        '${directory.path}/network_raw.jsonl',
      ).readAsLinesSync().map((s) => jsonDecode(s) as Map).toList();
      final stats =
          jsonDecode(
                File(
                  '${directory.path}/network_raw.jsonl.status.json',
                ).readAsStringSync(),
              )
              as Map;
      final passed =
          body == 'compiled diagnostic loopback' &&
          rows.any((v) => v['transport'] == 'native') &&
          rows.any((v) => v['event'] == 'response_body') &&
          stats['lost'] == 0 &&
          stats['writeErrors'] == 0;
      File('${directory.path}/compiled_self_test.json').writeAsStringSync(
        jsonEncode({
          'passed': passed,
          'externalApiRequests': 0,
          'rows': rows.length,
          'writer': stats,
        }),
      );
      exit(passed ? 0 : 1);
    } catch (error) {
      File(
        '${NetworkDiagnostic.directory!.path}/compiled_self_test.json',
      ).writeAsStringSync(
        jsonEncode({
          'passed': false,
          'errorType': error.runtimeType.toString(),
          'externalApiRequests': 0,
        }),
      );
      exit(1);
    }
  }
  app.main();
}
