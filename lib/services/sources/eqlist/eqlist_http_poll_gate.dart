/// Shared gate so HTTP eqlist polls can yield to fresher push updates.
class EqlistHttpPollGate {
  EqlistHttpPollGate({
    this.freshWindow = const Duration(minutes: 2),
  });

  /// Skip HTTP while an external push updated the same list within this window.
  final Duration freshWindow;

  DateTime? _lastExternalUpdate;

  void noteExternalUpdate([DateTime? at]) {
    _lastExternalUpdate = at ?? DateTime.now();
  }

  bool get shouldSkipHttp {
    final updatedAt = _lastExternalUpdate;
    if (updatedAt == null) return false;
    return DateTime.now().difference(updatedAt) < freshWindow;
  }

  void reset() {
    _lastExternalUpdate = null;
  }
}
