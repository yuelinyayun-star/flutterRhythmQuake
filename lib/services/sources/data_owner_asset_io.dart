import 'dart:convert';
import 'dart:io';

Future<String> readPackagedDataOwnerAsset(String key) => File(
  '${File(Platform.resolvedExecutable).parent.path}/data/flutter_assets/$key',
).readAsString(encoding: utf8);
