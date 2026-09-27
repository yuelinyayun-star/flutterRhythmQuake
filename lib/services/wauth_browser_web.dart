import 'dart:html' as html;

/// Reserve a tab during the button click, before the session request awaits.
/// Browsers otherwise block a new tab opened after that network request.
class WAuthBrowserWindow {
  WAuthBrowserWindow._(this._window);

  final html.WindowBase _window;

  static WAuthBrowserWindow? openPending() {
    try {
      final window = html.window.open('about:blank', '_blank');
      return WAuthBrowserWindow._(window);
    } catch (_) {
      return null;
    }
  }

  void navigate(Uri uri) {
    _window.location.href = uri.toString();
  }

  void close() {
    if (_window.closed != true) _window.close();
  }
}
