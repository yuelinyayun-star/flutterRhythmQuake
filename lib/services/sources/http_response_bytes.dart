import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readHttpResponseBytes(
  HttpClientResponse response, {
  required Duration timeout,
  bool discard = false,
}) async {
  final result = Completer<Uint8List>();
  final bytes = BytesBuilder();
  late final StreamSubscription<List<int>> subscription;
  subscription = response.listen(
    (chunk) {
      if (!discard) bytes.add(chunk);
    },
    onError: (Object error, StackTrace stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    },
    onDone: () {
      if (!result.isCompleted) result.complete(bytes.takeBytes());
    },
    cancelOnError: true,
  );
  final timer = Timer(timeout, () {
    unawaited(subscription.cancel());
    if (!result.isCompleted) {
      result.completeError(TimeoutException('HTTP response body timed out'));
    }
  });
  try {
    return await result.future;
  } finally {
    timer.cancel();
  }
}
