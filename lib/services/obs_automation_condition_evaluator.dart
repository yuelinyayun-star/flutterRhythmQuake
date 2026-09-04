import 'dart:math' as math;

import '../models/obs_automation_preset.dart';
import '../models/obs_automation_value_expression.dart';
import '../models/quake_message.dart';
import '../models/unified_event_presentation.dart';
import 'obs_automation_input_service.dart';

class ObsAutomationEvaluationContext {
  const ObsAutomationEvaluationContext({
    this.eventVariables = const {},
    this.valueVariables = const {},
  });

  final Map<String, ObsAutomationInputEvent> eventVariables;
  final Map<String, Object?> valueVariables;
}

class ObsAutomationConditionEvaluator {
  const ObsAutomationConditionEvaluator();

  static final math.Random _random = math.Random();

  bool matchesStack(ObsAutomationStack stack, ObsAutomationInputEvent event) {
    return matchesBlocks(stack.blocks, event);
  }

  bool matchesBlocks(
    List<ObsAutomationBlock> blocks,
    ObsAutomationInputEvent event, {
    ObsAutomationEvaluationContext context =
        const ObsAutomationEvaluationContext(),
  }) {
    var index = 0;
    var hasBranch = false;
    var anyBranchMatched = false;

    while (index < blocks.length) {
      final input = blocks[index];
      if (!_isInput(input.type)) return false;
      hasBranch = true;
      var branchMatched = _matchesInput(input, event);
      index++;

      var sawCondition = false;
      var expectsConditionAfterAnd = false;
      while (index < blocks.length) {
        final type = blocks[index].type;
        if (_isCondition(type)) {
          sawCondition = true;
          expectsConditionAfterAnd = false;
          if (branchMatched) {
            branchMatched = _matchesCondition(blocks[index], event, context);
          }
          index++;
          continue;
        }
        if (type == ObsAutomationBlockType.andBranch) {
          if (!sawCondition || expectsConditionAfterAnd) return false;
          expectsConditionAfterAnd = true;
          index++;
          continue;
        }
        break;
      }
      if (expectsConditionAfterAnd) return false;
      anyBranchMatched = anyBranchMatched || branchMatched;

      if (index >= blocks.length) break;
      if (_isAction(blocks[index].type)) {
        for (
          var actionIndex = index;
          actionIndex < blocks.length;
          actionIndex++
        ) {
          if (!_isAction(blocks[actionIndex].type)) return false;
        }
        break;
      }
      if (blocks[index].type != ObsAutomationBlockType.orBranch) return false;
      index++;
      if (index >= blocks.length) return false;
    }

    return hasBranch && anyBranchMatched;
  }

  bool matchesConditions(
    Iterable<ObsAutomationBlock> blocks,
    ObsAutomationInputEvent event, {
    ObsAutomationEvaluationContext context =
        const ObsAutomationEvaluationContext(),
  }) {
    var sawCondition = false;
    var expectsConditionAfterAnd = false;
    for (final block in blocks) {
      if (block.type == ObsAutomationBlockType.andBranch) {
        if (!sawCondition || expectsConditionAfterAnd) return false;
        expectsConditionAfterAnd = true;
        continue;
      }
      if (!_isCondition(block.type)) {
        return false;
      }
      sawCondition = true;
      expectsConditionAfterAnd = false;
      if (!_matchesCondition(block, event, context)) return false;
    }
    return !expectsConditionAfterAnd;
  }

  bool matchesInputKind(String? kind, ObsAutomationInputEvent event) {
    return switch (kind) {
      'networkDetection' =>
        event.kind == ObsAutomationInputKind.networkDetection,
      'stationChange' => event.kind == ObsAutomationInputKind.stationChange,
      _ => event.kind == ObsAutomationInputKind.unifiedEvent,
    };
  }

  Object? readInputField(ObsAutomationInputEvent event, String? field) {
    final unified = event.unifiedEvent;
    final presentation = unified == null
        ? null
        : UnifiedEventPresentation.fromEvent(unified);
    return switch (field) {
      'inputKind' => event.kind.name,
      'occurredAt' => event.occurredAt.toIso8601String(),
      'phase' => switch (event.kind) {
        ObsAutomationInputKind.unifiedEvent => event.unifiedPhase?.name,
        ObsAutomationInputKind.networkDetection => event.networkPhase?.name,
        ObsAutomationInputKind.stationChange => event.stationPhase?.name,
      },
      'network' => event.network,
      'eventId' => event.eventId,
      'source' => unified?.source,
      'agency' =>
        unified?.isEew == true ? _eewAgency(event) : _informationAgency(event),
      'reviewType' => _informationReviewType(event),
      'eventType' => _eventType(event),
      'isEew' => unified?.isEew,
      'magnitude' =>
        unified != null && unified.magnitude >= 0 ? unified.magnitude : null,
      'estimatedIntensity' => _unifiedIntensity(event),
      'reportNumber' => _reportNumber(event),
      'reportText' => unified?.reportNumText,
      'title' => unified?.titleText,
      'uiTitle' => presentation?.title,
      'uiPrimaryText' => presentation?.primaryText,
      'uiSecondaryText' => presentation?.secondaryText,
      'uiCompactSecondaryText' => presentation?.compactSecondaryText,
      'uiTimeText' => presentation?.timeText,
      'uiBadgeLabel' => presentation?.intensityLabel,
      'uiBadgeValue' => presentation?.intensityValue,
      'uiApiTypeLabel' => presentation?.apiTypeLabel,
      'uiNotificationBody' => presentation?.notificationBody,
      'hypocenter' => unified?.hypocenter,
      'depth' => unified != null && unified.depth >= 0 ? unified.depth : null,
      'latitude' => unified?.lat ?? event.latitude,
      'longitude' => unified?.lng ?? event.longitude,
      'isFinal' => unified?.isFinal,
      'isCanceled' => unified?.isCanceled,
      'isWarn' => unified?.isWarn,
      'apiType' => unified?.apiTypeLabel,
      'originTime' => unified?.originTime?.toIso8601String(),
      'reportTime' => unified?.reportTime?.toIso8601String(),
      'stationId' => event.stationId,
      'stationName' => event.stationName,
      'currentStationIntensity' => _stationShindoIndex(
        event.network,
        event.intensityLevel,
      ),
      'currentStationRawIntensity' => event.intensity,
      'previousStationIntensity' => _stationShindoIndex(
        event.network,
        event.previousIntensityLevel,
      ),
      'previousStationRawIntensity' => event.previousIntensity,
      'detectedStationCount' => event.detectedStationCount,
      'networkMaxIntensity' => _broadShindoIndex(event.maxIntensity),
      'networkMaxRawIntensity' => event.maxIntensity,
      _ => null,
    };
  }

  Object? resolveValueReference(
    ObsAutomationInputEvent event, {
    required String kind,
    required String value,
    ObsAutomationEvaluationContext context =
        const ObsAutomationEvaluationContext(),
  }) {
    return switch (kind) {
      'empty' => null,
      'inputField' => readInputField(event, value),
      'variable' => context.valueVariables[value.trim()],
      'expression' => _evaluateValueNode(
        ObsAutomationValueNode.tryDecode(value),
        event,
        context,
      ),
      _ => _resolveVariableReferences(value, context),
    };
  }

  Object? _evaluateValueNode(
    ObsAutomationValueNode? node,
    ObsAutomationInputEvent event,
    ObsAutomationEvaluationContext context, {
    int depth = 0,
  }) {
    if (node == null || depth > 16) return null;
    if (!node.isOperation) {
      return resolveValueReference(
        event,
        kind: node.kind,
        value: node.value,
        context: context,
      );
    }
    final arguments = node.arguments
        .map(
          (argument) =>
              _evaluateValueNode(argument, event, context, depth: depth + 1),
        )
        .toList(growable: false);
    Object? argument(int index) =>
        index < arguments.length ? arguments[index] : null;
    final leftNumber = _dynamicNumber(argument(0));
    final rightNumber = _dynamicNumber(argument(1));

    return switch (node.value) {
      'arithmetic' => _evaluateArithmetic(
        node.options['operator'] ?? 'add',
        leftNumber,
        rightNumber,
      ),
      'random' => _randomBetween(leftNumber, rightNumber),
      'modulo' =>
        leftNumber == null || rightNumber == null || rightNumber == 0
            ? null
            : leftNumber % rightNumber,
      'round' => leftNumber?.round(),
      'math' => _evaluateMath(node.options['operator'] ?? 'abs', leftNumber),
      'join' => '${argument(0) ?? ''}${argument(1) ?? ''}',
      'length' => (argument(0)?.toString() ?? '').runes.length,
      'contains' =>
        argument(0) == null || argument(1) == null
            ? null
            : argument(0).toString().contains(argument(1).toString()),
      'comparison' => _compareDynamic(
        argument(0),
        argument(1),
        node.options['operator'] ?? 'equals',
      ),
      'boolean' => _evaluateBoolean(
        node.options['operator'] ?? 'and',
        _dynamicBool(argument(0)),
        _dynamicBool(argument(1)),
      ),
      'not' => _negate(_dynamicBool(argument(0))),
      _ => null,
    };
  }

  Object? _evaluateArithmetic(String operator, double? left, double? right) {
    if (left == null || right == null) return null;
    return switch (operator) {
      'add' => left + right,
      'subtract' => left - right,
      'multiply' => left * right,
      'divide' => right == 0 ? null : left / right,
      _ => null,
    };
  }

  Object? _randomBetween(double? first, double? second) {
    if (first == null || second == null) return null;
    final lower = math.min(first, second);
    final upper = math.max(first, second);
    if (lower == upper) return lower;
    if (lower == lower.roundToDouble() && upper == upper.roundToDouble()) {
      return lower.toInt() + _random.nextInt(upper.toInt() - lower.toInt() + 1);
    }
    return lower + _random.nextDouble() * (upper - lower);
  }

  Object? _evaluateMath(String operator, double? value) {
    if (value == null) return null;
    return switch (operator) {
      'abs' => value.abs(),
      'floor' => value.floor(),
      'ceil' => value.ceil(),
      'sqrt' => value < 0 ? null : math.sqrt(value),
      'sin' => math.sin(value * math.pi / 180),
      'cos' => math.cos(value * math.pi / 180),
      'tan' => math.tan(value * math.pi / 180),
      'ln' => value <= 0 ? null : math.log(value),
      'log10' => value <= 0 ? null : math.log(value) / math.ln10,
      'pow10' => math.pow(10, value),
      _ => null,
    };
  }

  Object? _evaluateBoolean(String operator, bool? left, bool? right) {
    if (left == null || right == null) return null;
    return switch (operator) {
      'and' => left && right,
      'or' => left || right,
      _ => null,
    };
  }

  bool? _negate(bool? value) => value == null ? null : !value;

  double? _dynamicNumber(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '');
  }

  bool? _dynamicBool(Object? value) {
    if (value is bool) return value;
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
    return null;
  }

  bool _matchesInput(ObsAutomationBlock block, ObsAutomationInputEvent event) {
    switch (block.type) {
      case ObsAutomationBlockType.unifiedEvent:
        return event.kind == ObsAutomationInputKind.unifiedEvent;
      case ObsAutomationBlockType.networkDetection:
        return event.kind == ObsAutomationInputKind.networkDetection &&
            _matchesNetwork(block.parameters['network'], event.network);
      case ObsAutomationBlockType.stationChange:
        return event.kind == ObsAutomationInputKind.stationChange &&
            _matchesNetwork(block.parameters['network'], event.network);
      default:
        return false;
    }
  }

  bool _matchesCondition(
    ObsAutomationBlock block,
    ObsAutomationInputEvent event,
    ObsAutomationEvaluationContext context,
  ) {
    final operator = block.parameters['operator'] ?? 'equals';
    final expected = block.parameters['value'] ?? '';
    switch (block.type) {
      case ObsAutomationBlockType.unifiedPhase:
        return _compareText(event.unifiedPhase?.name, expected, operator);
      case ObsAutomationBlockType.networkPhase:
        return _compareText(event.networkPhase?.name, expected, operator);
      case ObsAutomationBlockType.stationPhase:
        return _compareText(event.stationPhase?.name, expected, operator);
      case ObsAutomationBlockType.isEew:
        return event.unifiedEvent?.isEew == true;
      case ObsAutomationBlockType.isInformation:
        final unifiedEvent = event.unifiedEvent;
        return unifiedEvent != null && !unifiedEvent.isEew;
      case ObsAutomationBlockType.eewAgency:
        return _compareText(_eewAgency(event), expected, operator);
      case ObsAutomationBlockType.informationAgency:
        return _compareText(_informationAgency(event), expected, operator);
      case ObsAutomationBlockType.informationReviewType:
        return _compareText(_informationReviewType(event), expected, operator);
      case ObsAutomationBlockType.sameEarthquakeAsVariable:
        final variableName = block.parameters['variable']?.trim() ?? '触发事件';
        return _sameEarthquake(
          event,
          context.eventVariables[variableName],
          maxSeconds: _positiveDouble(
            block.parameters['maxSeconds'],
            fallback: 300,
          ),
          maxDistanceKm: _positiveDouble(
            block.parameters['maxDistanceKm'],
            fallback: 300,
          ),
        );
      case ObsAutomationBlockType.inputFieldMatchesVariable:
        final variableName = block.parameters['variable']?.trim() ?? '';
        if (variableName.isEmpty ||
            !context.valueVariables.containsKey(variableName)) {
          return false;
        }
        return _compareDynamic(
          readInputField(event, block.parameters['field']),
          context.valueVariables[variableName],
          operator,
        );
      case ObsAutomationBlockType.inputFieldCondition:
        return _compareDynamic(
          readInputField(event, block.parameters['field']),
          _resolveVariableReferences(expected, context),
          operator,
        );
      case ObsAutomationBlockType.compareValues:
        return _compareDynamic(
          resolveValueReference(
            event,
            kind: block.parameters['leftKind'] ?? 'inputField',
            value: block.parameters['leftValue'] ?? 'eventType',
            context: context,
          ),
          resolveValueReference(
            event,
            kind: block.parameters['rightKind'] ?? 'literal',
            value: block.parameters['rightValue'] ?? '',
            context: context,
          ),
          operator,
        );
      case ObsAutomationBlockType.valueVariableCondition:
        final variableName = block.parameters['variable']?.trim() ?? '';
        if (variableName.isEmpty ||
            !context.valueVariables.containsKey(variableName)) {
          return false;
        }
        return _compareDynamic(
          context.valueVariables[variableName],
          _resolveVariableReferences(expected, context),
          operator,
        );
      case ObsAutomationBlockType.eventType:
        return _compareText(_eventType(event), expected, operator);
      case ObsAutomationBlockType.source:
        return _compareText(event.unifiedEvent?.source, expected, operator);
      case ObsAutomationBlockType.magnitude:
        final magnitude = event.unifiedEvent?.magnitude;
        return _compareNumber(
          magnitude != null && magnitude >= 0 ? magnitude : null,
          expected,
          operator,
        );
      case ObsAutomationBlockType.estimatedIntensity:
        return _compareNumber(_unifiedIntensity(event), expected, operator);
      case ObsAutomationBlockType.reportNumber:
        return _compareNumber(_reportNumber(event), expected, operator);
      case ObsAutomationBlockType.isFinal:
        final value = event.unifiedEvent?.isFinal;
        if (value == null) return false;
        return value == (expected == 'true');
      case ObsAutomationBlockType.networkMaxIntensity:
        return _compareNumber(
          _broadShindoIndex(event.maxIntensity),
          expected,
          operator,
        );
      case ObsAutomationBlockType.detectedStationCount:
        return _compareNumber(
          event.detectedStationCount?.toDouble(),
          expected,
          operator,
        );
      case ObsAutomationBlockType.stationId:
        return _compareText(event.stationId, expected, operator);
      case ObsAutomationBlockType.stationName:
        return _compareText(event.stationName, expected, operator);
      case ObsAutomationBlockType.currentStationIntensity:
        return _compareNumber(
          _stationShindoIndex(event.network, event.intensityLevel),
          expected,
          operator,
        );
      case ObsAutomationBlockType.previousStationIntensity:
        return _compareNumber(
          _stationShindoIndex(event.network, event.previousIntensityLevel),
          expected,
          operator,
        );
      default:
        return false;
    }
  }

  bool _matchesNetwork(String? expected, String? actual) {
    if (actual == null) return false;
    final normalized = expected?.trim().toLowerCase() ?? 'any';
    return normalized == 'any' || normalized == actual.trim().toLowerCase();
  }

  String? _eventType(ObsAutomationInputEvent input) {
    final event = input.unifiedEvent;
    if (event == null) return null;
    if (event.isEew) return 'eew';
    final volcano = event.volcanoEvent;
    if (volcano != null) {
      return volcano.hasAshfallForecast ? 'ashfall' : 'volcano';
    }
    final raw = event.rawEvent;
    if (raw?.isTsunamiWarning == true) return 'tsunami';
    if (raw != null && _cmtSources.contains(raw.source)) return 'cmt';
    return 'earthquake';
  }

  String? _eewAgency(ObsAutomationInputEvent input) {
    final event = input.unifiedEvent;
    if (event == null || !event.isEew) return null;
    return switch (event.source.trim()) {
      'jmaEew' => 'jma',
      'cwaEew' => 'cwa',
      'ceaEew' => 'cea',
      'scEew' => 'sichuan',
      'fjEew' => 'fujian',
      'cqEew' => 'chongqing',
      'kmaEew' => 'kma',
      'sa' => 'shakeAlert',
      'globalQuakeEew' || 'gqEew' => 'globalQuake',
      _ => null,
    };
  }

  String? _informationAgency(ObsAutomationInputEvent input) {
    final event = input.unifiedEvent;
    if (event == null || event.isEew) return null;
    return switch (event.source.trim()) {
      'jmaEqlist' || 'p2pJmaEqlist' => 'jma',
      'cwaEqlist' => 'cwa',
      'cencEqlist' => 'cenc',
      'kmaEqlist' => 'kma',
      'usgsEqlist' => 'usgs',
      'fssnEqlist' => 'fssn',
      'hko' => 'hko',
      'emsc' => 'emsc',
      'bcsf' => 'bcsf',
      'gfz' => 'gfz',
      'usp' => 'usp',
      'geonet' || 'whews_geonet' => 'geonet',
      'whews_bmkg' => 'bmkg',
      'whews_tmd' => 'tmd',
      'whews_ingv' => 'ingv',
      'whews_nrcan' => 'nrcan',
      'whews_mmd' => 'mmd',
      'whews_phivolcs' => 'phivolcs',
      'whews_sgc' => 'sgc',
      'whews_ga' => 'ga',
      'whews_cenais' => 'cenais',
      'ningxia' => 'ningxia',
      'guangxi' => 'guangxi',
      'shanxi' => 'shanxi',
      'beijing' => 'beijing',
      'yunnan' => 'yunnan',
      _ => null,
    };
  }

  String? _informationReviewType(ObsAutomationInputEvent input) {
    final event = input.unifiedEvent;
    if (event == null || event.isEew) return null;
    final raw = [
      event.rawEvent?.reviewType,
      event.rawEvent?.infoTypeName,
      event.reportNumText,
      event.titleText,
    ].whereType<String>().join(' ').toLowerCase();
    if (raw.contains('reviewed') || raw.contains('正式')) return 'reviewed';
    if (raw.contains('automatic') || raw.contains('自动')) return 'automatic';
    return null;
  }

  bool _sameEarthquake(
    ObsAutomationInputEvent current,
    ObsAutomationInputEvent? saved, {
    required double maxSeconds,
    required double maxDistanceKm,
  }) {
    final left = current.unifiedEvent;
    final right = saved?.unifiedEvent;
    if (left == null || right == null) return false;
    final leftTime = left.originTime;
    final rightTime = right.originTime;
    final leftLat = left.lat;
    final leftLng = left.lng;
    final rightLat = right.lat;
    final rightLng = right.lng;
    if (leftTime == null ||
        rightTime == null ||
        !_validCoordinate(leftLat, leftLng) ||
        !_validCoordinate(rightLat, rightLng)) {
      return false;
    }
    final seconds = leftTime.difference(rightTime).inMilliseconds.abs() / 1000;
    if (seconds > maxSeconds) return false;
    return _haversineKm(leftLat!, leftLng!, rightLat!, rightLng!) <=
        maxDistanceKm;
  }

  bool _validCoordinate(double? lat, double? lng) {
    if (lat == null || lng == null || !lat.isFinite || !lng.isFinite) {
      return false;
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;
    return lat != 0 || lng != 0;
  }

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0088;
    final latDelta = _radians(lat2 - lat1);
    final lngDelta = _radians(lng2 - lng1);
    final a =
        math.sin(latDelta / 2) * math.sin(latDelta / 2) +
        math.cos(_radians(lat1)) *
            math.cos(_radians(lat2)) *
            math.sin(lngDelta / 2) *
            math.sin(lngDelta / 2);
    return 2 * earthRadiusKm * math.asin(math.sqrt(a.clamp(0, 1)));
  }

  double _radians(double degrees) => degrees * math.pi / 180;

  double _positiveDouble(String? raw, {required double fallback}) {
    final value = double.tryParse(raw ?? '');
    return value != null && value.isFinite && value > 0 ? value : fallback;
  }

  double? _unifiedIntensity(ObsAutomationInputEvent input) {
    final event = input.unifiedEvent;
    if (event == null) return null;
    final raw = event.maxIntensity.trim();
    if (raw.isEmpty || raw == '-' || raw == '--') return null;
    if (!event.useShindo) return double.tryParse(raw);
    return _shindoLabelIndex(raw)?.toDouble();
  }

  double? _reportNumber(ObsAutomationInputEvent input) {
    final event = input.unifiedEvent;
    if (event == null) return null;
    final rawNumber = event.rawEvent?.reportNumber;
    if (rawNumber != null) return rawNumber.toDouble();
    final match = RegExp(r'\d+').firstMatch(event.reportNumText);
    return double.tryParse(match?.group(0) ?? '');
  }

  double? _broadShindoIndex(int? value) {
    if (value == null || value < 0) return null;
    return switch (value) {
      <= 4 => value.toDouble(),
      5 => 5,
      6 => 7,
      _ => 9,
    };
  }

  double? _stationShindoIndex(String? network, int? value) {
    if (value == null || value < 0) return null;
    final normalizedNetwork = network?.trim().toLowerCase();
    if (normalizedNetwork == 'kma' ||
        normalizedNetwork == 'fdsn' ||
        normalizedNetwork == 'seisjs') {
      return _broadShindoIndex(value);
    }
    return value.clamp(0, 9).toDouble();
  }

  int? _shindoLabelIndex(String value) {
    final normalized = value
        .trim()
        .replaceAll('强', '強')
        .replaceAll('強', '+')
        .replaceAll('弱', '-')
        .replaceAll('−', '-')
        .replaceAll('＋', '+')
        .replaceAll('震度', '')
        .replaceAll('級', '');
    return switch (normalized) {
      '0' => 0,
      '1' => 1,
      '2' => 2,
      '3' => 3,
      '4' => 4,
      '5' || '5-' => 5,
      '5+' => 6,
      '6' || '6-' => 7,
      '6+' => 8,
      '7' => 9,
      _ => null,
    };
  }

  bool _compareText(String? actual, String expected, String operator) {
    if (actual == null) return false;
    final left = actual.trim().toLowerCase();
    final right = expected.trim().toLowerCase();
    return switch (operator) {
      'equals' => left == right,
      'notEquals' => left != right,
      'contains' => left.contains(right),
      'notContains' => !left.contains(right),
      _ => false,
    };
  }

  bool _compareNumber(double? actual, String expected, String operator) {
    final right = double.tryParse(expected);
    if (actual == null || right == null || !actual.isFinite) return false;
    return switch (operator) {
      'equals' => actual == right,
      'notEquals' => actual != right,
      'greaterThan' => actual > right,
      'greaterThanOrEqual' => actual >= right,
      'lessThan' => actual < right,
      'lessThanOrEqual' => actual <= right,
      _ => false,
    };
  }

  bool _compareDynamic(Object? actual, Object? expected, String operator) {
    if (actual == null || expected == null) return false;
    final leftNumber = actual is num
        ? actual.toDouble()
        : double.tryParse(actual.toString());
    final rightNumber = expected is num
        ? expected.toDouble()
        : double.tryParse(expected.toString());
    if (leftNumber != null && rightNumber != null) {
      return switch (operator) {
        'equals' => leftNumber == rightNumber,
        'notEquals' => leftNumber != rightNumber,
        'greaterThan' => leftNumber > rightNumber,
        'greaterThanOrEqual' => leftNumber >= rightNumber,
        'lessThan' => leftNumber < rightNumber,
        'lessThanOrEqual' => leftNumber <= rightNumber,
        _ => false,
      };
    }
    if (actual is bool && expected is bool) {
      return switch (operator) {
        'equals' => actual == expected,
        'notEquals' => actual != expected,
        _ => false,
      };
    }
    return _compareText(actual.toString(), expected.toString(), operator);
  }

  Object? _resolveVariableReferences(
    String raw,
    ObsAutomationEvaluationContext context,
  ) {
    final exact = RegExp(r'^\{\{([^{}]+)\}\}$').firstMatch(raw.trim());
    if (exact != null) {
      return context.valueVariables[exact.group(1)?.trim() ?? ''];
    }
    return raw.replaceAllMapped(RegExp(r'\{\{([^{}]+)\}\}'), (match) {
      final name = match.group(1)?.trim() ?? '';
      return context.valueVariables[name]?.toString() ?? match.group(0)!;
    });
  }

  bool _isInput(ObsAutomationBlockType type) => const {
    ObsAutomationBlockType.unifiedEvent,
    ObsAutomationBlockType.networkDetection,
    ObsAutomationBlockType.stationChange,
  }.contains(type);

  bool _isCondition(ObsAutomationBlockType type) => const {
    ObsAutomationBlockType.unifiedPhase,
    ObsAutomationBlockType.networkPhase,
    ObsAutomationBlockType.stationPhase,
    ObsAutomationBlockType.isEew,
    ObsAutomationBlockType.isInformation,
    ObsAutomationBlockType.eewAgency,
    ObsAutomationBlockType.informationAgency,
    ObsAutomationBlockType.informationReviewType,
    ObsAutomationBlockType.sameEarthquakeAsVariable,
    ObsAutomationBlockType.valueVariableCondition,
    ObsAutomationBlockType.inputFieldMatchesVariable,
    ObsAutomationBlockType.inputFieldCondition,
    ObsAutomationBlockType.compareValues,
    ObsAutomationBlockType.eventType,
    ObsAutomationBlockType.source,
    ObsAutomationBlockType.magnitude,
    ObsAutomationBlockType.estimatedIntensity,
    ObsAutomationBlockType.reportNumber,
    ObsAutomationBlockType.isFinal,
    ObsAutomationBlockType.networkMaxIntensity,
    ObsAutomationBlockType.detectedStationCount,
    ObsAutomationBlockType.stationId,
    ObsAutomationBlockType.stationName,
    ObsAutomationBlockType.currentStationIntensity,
    ObsAutomationBlockType.previousStationIntensity,
  }.contains(type);

  bool _isAction(ObsAutomationBlockType type) => const {
    ObsAutomationBlockType.wait,
    ObsAutomationBlockType.waitForUnifiedEvent,
    ObsAutomationBlockType.waitForInput,
    ObsAutomationBlockType.setEventVariable,
    ObsAutomationBlockType.setValueVariable,
    ObsAutomationBlockType.setVariable,
    ObsAutomationBlockType.changeVariable,
    ObsAutomationBlockType.stopScript,
    ObsAutomationBlockType.startRecord,
    ObsAutomationBlockType.stopRecord,
    ObsAutomationBlockType.pauseRecord,
    ObsAutomationBlockType.resumeRecord,
    ObsAutomationBlockType.splitRecordFile,
    ObsAutomationBlockType.createRecordChapter,
    ObsAutomationBlockType.startReplayBuffer,
    ObsAutomationBlockType.stopReplayBuffer,
    ObsAutomationBlockType.saveReplayBuffer,
  }.contains(type);

  static const _cmtSources = <QuakeSourceType>{
    QuakeSourceType.fssnCmt,
    QuakeSourceType.cencCmt,
    QuakeSourceType.usgsCmt,
    QuakeSourceType.jmaCmt,
    QuakeSourceType.fnetCmt,
    QuakeSourceType.hinetAquaCmt,
  };
}
