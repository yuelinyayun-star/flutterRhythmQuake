/// Non-secret credential metadata carried by the source-status channel.
class SourceCredentialInfo {
  const SourceCredentialInfo({
    this.configured = false,
    this.expiresAt,
    this.errorCode,
  });

  final bool configured;
  final DateTime? expiresAt;
  final String? errorCode;

  Map<String, dynamic> toMap() => {
    'configured': configured,
    'expiresAt': expiresAt?.toUtc().toIso8601String(),
    'errorCode': errorCode,
  };

  static SourceCredentialInfo? fromMap(dynamic value) {
    if (value is! Map) return null;
    final date = value['expiresAt'];
    return SourceCredentialInfo(
      configured: value['configured'] == true,
      expiresAt: date is String ? DateTime.tryParse(date)?.toUtc() : null,
      errorCode: value['errorCode'] is String
          ? value['errorCode'] as String
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SourceCredentialInfo &&
      configured == other.configured &&
      expiresAt == other.expiresAt &&
      errorCode == other.errorCode;

  @override
  int get hashCode => Object.hash(configured, expiresAt, errorCode);
}
