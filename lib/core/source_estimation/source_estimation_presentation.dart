import '../../utils/fe_regions.dart';

/// Both station networks use the same user-facing inference title.
const sourceEstimationTitle = '震源本地推算';

/// The shared place resolver queries the Rust region owner for native builds.
String sourceEstimationLocation(double latitude, double longitude) =>
    getFEName(latitude, longitude);
