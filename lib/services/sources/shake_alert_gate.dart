/// KA alerts on a rise from the previous level, not only on new session peaks.
/// Keep this state across station payload replacements, until detection ends.
class ShakeAlertGate {
  int _previous = -1;

  bool accept(int current) {
    if (current < 0) {
      reset();
      return false;
    }
    final rising = current > _previous;
    _previous = current;
    return rising;
  }

  void reset() => _previous = -1;
}
