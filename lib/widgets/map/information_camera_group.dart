import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';
import '../../core/calculator.dart';
import '../../models/usgs_dyfi.dart';
import '../../providers/map_state_provider.dart';
import '../../services/native_camera_focus.dart';
import 'cenc_ir_focus.dart';
import 'desktop_event_camera_focus.dart';
import 'usgs_dyfi_focus.dart';
import 'usgs_shakemap_focus.dart';

// Keep the existing distance at which information views split.
const informationCameraSplitDistanceKm = 2500.0;

class InformationCameraGroup {
  InformationCameraGroup(List<DesktopCameraCandidate> events)
    : members = List.unmodifiable(events),
      key = (events.map((e) => e.key).toList()..sort()).join('|');
  final List<DesktopCameraCandidate> members;
  final String key;
  late final DesktopCameraCandidate owner =
      (List.of(members)..sort((a, b) {
            int priority(DesktopCameraCandidate e) => e.isMapProduct
                ? 0
                : e.stationPoints.length > 1
                ? 1
                : 2;
            final order = priority(a).compareTo(priority(b));
            return order == 0 ? a.key.compareTo(b.key) : order;
          }))
          .first;
  late final List<LatLng> points = List.unmodifiable([
    for (final event in members) ...[event.location, ...event.fitPoints],
  ]);
  late final int geometryKey = Object.hash(
    key,
    owner.key,
    Object.hashAll(points.map((p) => (p.latitude, p.longitude))),
  );
}

/// Camera geometry only. Membership and extent are independent of carousel
/// index, so a card turn inside a group does not refit or move the map.
class InformationCameraGroups {
  Object? _dataset;
  final _groups = <String, InformationCameraGroup>{};
  Object? _lastFit;
  Object? _fittedViewport;
  Set<String> _retainedMembers = const {};
  void leave() {
    _lastFit = null;
    _fittedViewport = null;
    _retainedMembers = const {};
  }

  void clear() {
    _dataset = null;
    _groups.clear();
    leave();
  }

  void update(
    Object dataset,
    List<DesktopCameraCandidate> Function() candidates,
  ) {
    if (_dataset == dataset) return;
    _dataset = dataset;
    _groups.clear();
    final pending = candidates().where((e) => !e.isVolcano).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    while (pending.isNotEmpty) {
      final group = <DesktopCameraCandidate>[pending.removeAt(0)];
      for (var i = 0; i < pending.length;) {
        final next = pending[i];
        if (group.every(
          (e) =>
              QuakeCalculator.haversineDistance(
                e.location.latitude,
                e.location.longitude,
                next.location.latitude,
                next.location.longitude,
              ) <=
              informationCameraSplitDistanceKm,
        )) {
          group.add(pending.removeAt(i));
        } else {
          i++;
        }
      }
      final view = InformationCameraGroup(group);
      for (final event in group) {
        _groups[event.key] = view;
      }
    }
  }

  InformationCameraGroup? sharedGroup(String key) {
    final group = _groups[key];
    return group != null && group.members.length > 1 ? group : null;
  }

  bool needsFit(
    InformationCameraGroup group,
    Object viewport, {
    bool force = false,
  }) {
    final signature = (group.geometryKey, viewport);
    if (!force && _lastFit == signature) return false;
    _lastFit = signature;
    return true;
  }

  bool focus({
    required BuildContext context,
    required MapStateProvider mapState,
    required InformationCameraGroup group,
    UsgsDyfiFrame? dyfi,
    bool force = false,
  }) {
    final camera = mapState.mapController?.camera;
    if (camera == null) return false;
    final hasProduct = group.members.any((event) => event.isMapProduct);
    final padding = hasProduct
        ? usgsProductViewportPadding(context)
        : cencIrViewportPadding(context) ?? const EdgeInsets.all(50);
    final viewport = (camera.nonRotatedSize, camera.rotation, padding);
    if (!needsFit(group, viewport, force: force)) return true;
    final retainsOwner = group.members.any(
      (e) => _retainedMembers.contains(e.key),
    );
    if (_fittedViewport == viewport &&
        retainsOwner &&
        NativeCameraFocus.prepare({
              'op': 'retainInformationGroup',
              'sameViewport': true,
              'hasPreviousMember': true,
              'allVisible': mapState.areGeometryPointsInEventViewport(
                group.points,
                // Fitted corners can differ from the exact panel edge by a
                // floating-point fraction of a pixel after Mercator projection.
                padding: padding - const EdgeInsets.all(1),
              ),
            }) ==
            true) {
      _retainedMembers = group.members.map((e) => e.key).toSet();
      return true;
    }
    _fittedViewport = viewport;
    _retainedMembers = group.members.map((e) => e.key).toSet();
    final hasDyfi =
        dyfi != null &&
        group.members.any(
          (event) => event.key == 'usgsDyfi:${dyfi.event.eventId}',
        );
    final stationFit = group.members.any((e) => e.stationPoints.length > 1);
    mapState.smartMoveToPoints(
      group.points,
      padding: 1,
      minZoom: hasDyfi
          ? dyfiMinimumZoom(camera, dyfi)
          : hasProduct
          ? 2
          : 3,
      maxZoom: hasDyfi || stationFit
          ? 12
          : hasProduct
          ? 10
          : 7,
      viewportPadding: padding,
      focusAnchor:
          NativeCameraFocus.prepare({
                'op': 'groupAnchor',
                'hasProduct': hasProduct,
                'stationFit': stationFit,
              })
              as bool
          ? group.owner.location
          : null,
      sourceTag: 'policy-info-group-${group.key}',
      force: force,
      minInterval: Duration.zero,
    );
    return true;
  }
}
