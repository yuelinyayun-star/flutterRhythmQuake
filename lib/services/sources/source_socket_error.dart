import 'package:web_socket_channel/web_socket_channel.dart';

class SourceSocketException extends WebSocketChannelException {
  SourceSocketException(super.message, {this.statusCode});
  final int? statusCode;
}

int? sourceSocketStatusCode(Object error) {
  if (error is SourceSocketException) return error.statusCode;
  if (error is WebSocketChannelException &&
      error.inner != null &&
      !identical(error.inner, error)) {
    return sourceSocketStatusCode(error.inner!);
  }
  return null;
}
