import 'package:http/http.dart' as http;

Future<http.Client> createPAlertHttpClient() async => http.Client();

Future<http.Client> createPAlertHttpClientWithRoot(
  List<int>? root, {
  Future<String> Function(Uri)? resolveProxy,
}) async => http.Client();
