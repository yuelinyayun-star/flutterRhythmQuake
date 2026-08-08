import 'fan_socket_connection.dart';

bool get fanBrowserSocketSupported => false;

Future<bool> shouldUseFanBrowserSocket(Uri uri) async => false;

FanSocketConnection createFanBrowserSocket(Uri uri) {
  throw const FanBrowserSocketUnavailableException(
    'Browser WebSocket is not supported on this platform',
  );
}
