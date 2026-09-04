import 'dart:convert';

class ObsAutomationValueNode {
  const ObsAutomationValueNode({
    required this.kind,
    required this.value,
    this.family,
    this.options = const {},
    this.arguments = const [],
  });

  const ObsAutomationValueNode.literal(String value)
    : this(kind: 'literal', value: value);

  const ObsAutomationValueNode.inputField(String value, {String? family})
    : this(kind: 'inputField', value: value, family: family);

  const ObsAutomationValueNode.variable(String value)
    : this(kind: 'variable', value: value);

  const ObsAutomationValueNode.operation(
    String value, {
    Map<String, String> options = const {},
    List<ObsAutomationValueNode> arguments = const [],
  }) : this(
         kind: 'operation',
         value: value,
         options: options,
         arguments: arguments,
       );

  final String kind;
  final String value;
  final String? family;
  final Map<String, String> options;
  final List<ObsAutomationValueNode> arguments;

  bool get isOperation => kind == 'operation';

  ObsAutomationValueNode copyWith({
    String? kind,
    String? value,
    String? family,
    Map<String, String>? options,
    List<ObsAutomationValueNode>? arguments,
  }) {
    return ObsAutomationValueNode(
      kind: kind ?? this.kind,
      value: value ?? this.value,
      family: family ?? this.family,
      options: options ?? this.options,
      arguments: arguments ?? this.arguments,
    );
  }

  ObsAutomationValueNode replaceAt(
    List<int> path,
    ObsAutomationValueNode replacement,
  ) {
    if (path.isEmpty) return replacement;
    final index = path.first;
    if (index < 0 || index >= arguments.length) return this;
    final nextArguments = List<ObsAutomationValueNode>.from(arguments);
    nextArguments[index] = nextArguments[index].replaceAt(
      path.sublist(1),
      replacement,
    );
    return copyWith(arguments: nextArguments);
  }

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'value': value,
    if (family != null) 'family': family,
    if (options.isNotEmpty) 'options': options,
    if (arguments.isNotEmpty)
      'arguments': arguments.map((argument) => argument.toJson()).toList(),
  };

  String encode() => jsonEncode(toJson());

  factory ObsAutomationValueNode.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    final options = <String, String>{};
    if (rawOptions is Map) {
      for (final entry in rawOptions.entries) {
        options[entry.key.toString()] = entry.value?.toString() ?? '';
      }
    }
    final arguments = <ObsAutomationValueNode>[];
    final rawArguments = json['arguments'];
    if (rawArguments is List) {
      for (final raw in rawArguments) {
        if (raw is Map<String, dynamic>) {
          arguments.add(ObsAutomationValueNode.fromJson(raw));
        } else if (raw is Map) {
          arguments.add(
            ObsAutomationValueNode.fromJson(Map<String, dynamic>.from(raw)),
          );
        }
      }
    }
    return ObsAutomationValueNode(
      kind: json['kind']?.toString() ?? 'literal',
      value: json['value']?.toString() ?? '',
      family: json['family']?.toString(),
      options: options,
      arguments: arguments,
    );
  }

  static ObsAutomationValueNode? tryDecode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return ObsAutomationValueNode.fromJson(decoded);
      }
      if (decoded is Map) {
        return ObsAutomationValueNode.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}
