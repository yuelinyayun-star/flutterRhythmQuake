class EewWaveCameraFollowGate {
  static const Duration holdAtMinimumZoom = Duration(seconds: 10);

  String _eventSignature = '';
  DateTime? _minimumZoomReachedAt;
  bool _released = false;

  bool get released => _released;

  bool syncEvents(Iterable<String> eventKeys, DateTime now) {
    final keys = eventKeys.toSet().toList()..sort();
    final nextSignature = keys.join('|');
    if (nextSignature != _eventSignature) {
      _eventSignature = nextSignature;
      _minimumZoomReachedAt = null;
      _released = false;
    }

    if (_eventSignature.isEmpty) {
      _minimumZoomReachedAt = null;
      _released = false;
      return false;
    }

    if (!_released &&
        _minimumZoomReachedAt != null &&
        now.difference(_minimumZoomReachedAt!) >= holdAtMinimumZoom) {
      _released = true;
    }
    return _released;
  }

  void noteTargetZoom({
    required double targetZoom,
    required double minimumZoom,
    required DateTime now,
  }) {
    if (_eventSignature.isEmpty || _released) return;
    if (targetZoom <= minimumZoom + 0.0001) {
      _minimumZoomReachedAt ??= now;
    }
  }
}

List<T> eewCameraFocusEvents<T>({
  required List<T> events,
  required bool splitDistant,
  required T? currentEvent,
}) {
  // Keep distant EEWs on the carousel target even after wave follow releases.
  if (splitDistant && currentEvent != null) {
    return <T>[currentEvent];
  }
  return events;
}
