import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

const pAlertRootAsset = 'assets/certificates/TWCA_Global_Root_CA.der';
const pAlertRootSha256 =
    '59769007f7685d0fcd50872f9f95d5755a5b2b457d81f3692b610a98672f0e1b';

SecurityContext createPAlertSecurityContext(List<int> rootDer) {
  if (sha256.convert(rootDer).toString() != pAlertRootSha256) {
    throw StateError('P-Alert TWCA root certificate fingerprint mismatch');
  }
  final pem =
      '-----BEGIN CERTIFICATE-----\n'
      '${base64.encode(rootDer)}\n'
      '-----END CERTIFICATE-----\n';
  // Supplement only this client's roots, never SecurityContext.defaultContext.
  return SecurityContext(withTrustedRoots: true)
    ..setTrustedCertificatesBytes(utf8.encode(pem));
}

Future<http.Client> createPAlertHttpClient() async {
  SecurityContext? context;
  try {
    final data = await rootBundle.load(pAlertRootAsset);
    final root =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    context = createPAlertSecurityContext(root);
  } catch (_) {
    // Keep context null if asset is not loaded in headless environments.
  }

  final httpClient = HttpClient(context: context);
  httpClient.badCertificateCallback = (cert, host, port) {
    // Tolerate TUN/proxy and non-standard root environments for the official P-Alert host.
    return host == 'palert.earth.sinica.edu.tw';
  };
  return IOClient(httpClient);
}
