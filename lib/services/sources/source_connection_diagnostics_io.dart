import 'dart:convert';
import 'dart:io';

/// Opt-in local diagnostics. Never include headers, query strings or credentials.
void recordSourceConnection(Map<String, Object?> event, {String secret = ''}) {
  final path = Platform.environment['RHYTHMQUAKE_WHEWS_LOG'];
  if (path == null || path.isEmpty) return;
  var line = jsonEncode({
    'time': DateTime.now().toUtc().toIso8601String(),
    ...event,
  });
  if (secret.isNotEmpty) {
    line = line
        .replaceAll(secret, '[REDACTED]')
        .replaceAll(Uri.encodeComponent(secret), '[REDACTED]');
  }
  line = line
      .replaceAll(RegExp(r'wat_[A-Za-z0-9_.~-]+'), '[REDACTED]')
      .replaceAll(RegExp(r'token=[^&\s"\\]+'), 'token=[REDACTED]');
  try {
    File(path).writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  } on FileSystemException catch (error) {
    stderr.writeln(
      'Connection diagnostics write failed: ${error.osError?.errorCode}',
    );
  }
}
