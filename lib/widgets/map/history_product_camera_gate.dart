/// Keeps a list selection visible, but releases its camera when information
/// advances. Returning to an earlier carousel item does not relock the map.
class HistoryProductCameraGate {
  String? _ownerAtSelection;
  bool _released = false;

  void select(String? informationOwner) {
    _ownerAtSelection = informationOwner;
    _released = false;
  }

  bool canFollow(String? informationOwner) {
    if (informationOwner != _ownerAtSelection) _released = true;
    return !_released;
  }
}
