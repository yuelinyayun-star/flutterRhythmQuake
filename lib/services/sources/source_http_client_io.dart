import 'dart:io';

import '../debug/network_diagnostic.dart';
import 'package:http/http.dart' as http;
import 'native_http_client.dart';
import 'native_station_core_library_io.dart';

http.Client createSourceHttpClient() =>
    // Windows retains the reviewed opt-in because WinHTTP used more CPU/RSS
    // on ordinary API loads. Android ships and uses the Rust transport.
    (Platform.isAndroid || const bool.fromEnvironment('RQ_NATIVE_HTTP')) &&
        StationCoreLibrary.supported &&
        !NetworkDiagnostic.hasTransportOverrides
    ? NativeHttpClient()
    : http.Client();
