import 'package:flutter/foundation.dart';

import '../../core/source_estimation/source_estimation_models.dart';

/// Independent from NIED's event tracker, shared by map and unified cards.
class PAlertSourceState {
  PAlertSourceState._();

  static final events = ValueNotifier<List<SeismicActiveEvent>>(const []);
}
