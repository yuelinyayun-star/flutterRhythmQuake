import 'package:flutter/material.dart';

enum JmaMegaquakeFamily { nankai, hokkaidoSanriku }

enum JmaMegaquakeKeyword {
  investigating,
  megaquakeWarning,
  megaquakeAdvisory,
  investigationEnded,
  extraCommentary,
  routineCommentary,
  subsequentQuakeWatch,
  unknown,
}

@immutable
class JmaMegaquakeAdvisory {
  const JmaMegaquakeAdvisory({
    required this.id,
    required this.eventId,
    required this.family,
    required this.telegramCode,
    required this.keyword,
    required this.title,
    this.headTitle = '',
    this.infoType = '',
    this.serial = '',
    this.serialName = '',
    this.serialCode = '',
    this.headline = '',
    this.bodyText = '',
    this.nextAdvisory = '',
    this.reportTime,
    this.expiresAt,
    this.detailUrl = '',
  });

  final String id;
  final String eventId;
  final JmaMegaquakeFamily family;
  final String telegramCode;
  final JmaMegaquakeKeyword keyword;
  final String title;
  final String headTitle;
  final String infoType;
  final String serial;
  final String serialName;
  final String serialCode;
  final String headline;
  final String bodyText;
  final String nextAdvisory;
  final DateTime? reportTime;
  final DateTime? expiresAt;
  final String detailUrl;

  bool get isCanceled => infoType.contains('取消');

  bool get isRoutineCommentary =>
      telegramCode == 'VYSE52' || serialCode == '200';

  String get displayTitle {
    if (headTitle.isNotEmpty) return headTitle;
    return title;
  }

  String get keywordLabel {
    if (serialName.isNotEmpty) return serialName;
    return jmaMegaquakeKeywordLabel(keyword);
  }

  String get sourceLabel {
    final parts = <String>['JMA', telegramCode];
    if (infoType.isNotEmpty) parts.add(infoType);
    return parts.join(' · ');
  }

  String get signature =>
      '$id|$eventId|$telegramCode|$serialCode|$keyword|$infoType|'
      '${reportTime?.toUtc().toIso8601String() ?? ''}';

  Map<String, dynamic> toMap() => {
    'id': id,
    'eventId': eventId,
    'family': family.name,
    'telegramCode': telegramCode,
    'keyword': keyword.name,
    'title': title,
    'headTitle': headTitle,
    'infoType': infoType,
    'serial': serial,
    'serialName': serialName,
    'serialCode': serialCode,
    'headline': headline,
    'bodyText': bodyText,
    'nextAdvisory': nextAdvisory,
    'reportTime': reportTime?.toIso8601String(),
    'expiresAt': expiresAt?.toIso8601String(),
    'detailUrl': detailUrl,
  };

  factory JmaMegaquakeAdvisory.fromMap(Map<dynamic, dynamic> map) =>
      JmaMegaquakeAdvisory(
        id: map['id']?.toString() ?? '',
        eventId: map['eventId']?.toString() ?? '',
        family: JmaMegaquakeFamily.values.firstWhere(
          (item) => item.name == map['family']?.toString(),
          orElse: () => JmaMegaquakeFamily.nankai,
        ),
        telegramCode: map['telegramCode']?.toString() ?? '',
        keyword: JmaMegaquakeKeyword.values.firstWhere(
          (item) => item.name == map['keyword']?.toString(),
          orElse: () => JmaMegaquakeKeyword.unknown,
        ),
        title: map['title']?.toString() ?? '',
        headTitle: map['headTitle']?.toString() ?? '',
        infoType: map['infoType']?.toString() ?? '',
        serial: map['serial']?.toString() ?? '',
        serialName: map['serialName']?.toString() ?? '',
        serialCode: map['serialCode']?.toString() ?? '',
        headline: map['headline']?.toString() ?? '',
        bodyText: map['bodyText']?.toString() ?? '',
        nextAdvisory: map['nextAdvisory']?.toString() ?? '',
        reportTime: DateTime.tryParse(map['reportTime']?.toString() ?? ''),
        expiresAt: DateTime.tryParse(map['expiresAt']?.toString() ?? ''),
        detailUrl: map['detailUrl']?.toString() ?? '',
      );

  bool isActive({DateTime? now}) {
    if (isCanceled) return false;
    if (expiresAt == null) return true;
    return expiresAt!.toUtc().isAfter((now ?? DateTime.now()).toUtc());
  }

  JmaMegaquakeAdvisory copyWith({
    String? id,
    String? eventId,
    JmaMegaquakeFamily? family,
    String? telegramCode,
    JmaMegaquakeKeyword? keyword,
    String? title,
    String? headTitle,
    String? infoType,
    String? serial,
    String? serialName,
    String? serialCode,
    String? headline,
    String? bodyText,
    String? nextAdvisory,
    DateTime? reportTime,
    DateTime? expiresAt,
    String? detailUrl,
  }) {
    return JmaMegaquakeAdvisory(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      family: family ?? this.family,
      telegramCode: telegramCode ?? this.telegramCode,
      keyword: keyword ?? this.keyword,
      title: title ?? this.title,
      headTitle: headTitle ?? this.headTitle,
      infoType: infoType ?? this.infoType,
      serial: serial ?? this.serial,
      serialName: serialName ?? this.serialName,
      serialCode: serialCode ?? this.serialCode,
      headline: headline ?? this.headline,
      bodyText: bodyText ?? this.bodyText,
      nextAdvisory: nextAdvisory ?? this.nextAdvisory,
      reportTime: reportTime ?? this.reportTime,
      expiresAt: expiresAt ?? this.expiresAt,
      detailUrl: detailUrl ?? this.detailUrl,
    );
  }
}

String jmaMegaquakeKeywordLabel(JmaMegaquakeKeyword keyword) {
  return switch (keyword) {
    JmaMegaquakeKeyword.investigating => '調査中',
    JmaMegaquakeKeyword.megaquakeWarning => '巨大地震警戒',
    JmaMegaquakeKeyword.megaquakeAdvisory => '巨大地震注意',
    JmaMegaquakeKeyword.investigationEnded => '調査終了',
    JmaMegaquakeKeyword.extraCommentary => '臨時解説',
    JmaMegaquakeKeyword.routineCommentary => '定例解説',
    JmaMegaquakeKeyword.subsequentQuakeWatch => '',
    JmaMegaquakeKeyword.unknown => '',
  };
}

Color jmaMegaquakeKeywordColor(JmaMegaquakeKeyword keyword) {
  return switch (keyword) {
    JmaMegaquakeKeyword.megaquakeWarning => const Color(0xFFE53935),
    JmaMegaquakeKeyword.megaquakeAdvisory => const Color(0xFFFB8C00),
    JmaMegaquakeKeyword.subsequentQuakeWatch => const Color(0xFFFB8C00),
    JmaMegaquakeKeyword.investigating => const Color(0xFFF2C94C),
    JmaMegaquakeKeyword.extraCommentary => const Color(0xFF5B9BD5),
    JmaMegaquakeKeyword.routineCommentary => const Color(0xFF5B9BD5),
    JmaMegaquakeKeyword.investigationEnded => const Color(0xFF9EA9B7),
    JmaMegaquakeKeyword.unknown => const Color(0xFF9EA9B7),
  };
}

JmaMegaquakeKeyword jmaMegaquakeKeywordFrom({
  required String serialCode,
  required String serialName,
  required String headTitle,
  required String telegramCode,
}) {
  final code = serialCode.trim();
  if (code == '120') return JmaMegaquakeKeyword.megaquakeWarning;
  if (code == '130') return JmaMegaquakeKeyword.megaquakeAdvisory;
  if (code == '190') return JmaMegaquakeKeyword.investigationEnded;
  if (code == '111' || code == '112' || code == '113') {
    return JmaMegaquakeKeyword.investigating;
  }
  if (code == '210' || code == '219') {
    return JmaMegaquakeKeyword.extraCommentary;
  }
  if (code == '200' || telegramCode == 'VYSE52') {
    return JmaMegaquakeKeyword.routineCommentary;
  }
  if (telegramCode == 'VYSE60') {
    return JmaMegaquakeKeyword.subsequentQuakeWatch;
  }

  final text = '$serialName $headTitle';
  if (text.contains('巨大地震警戒')) return JmaMegaquakeKeyword.megaquakeWarning;
  if (text.contains('巨大地震注意')) return JmaMegaquakeKeyword.megaquakeAdvisory;
  if (text.contains('調査終了') || text.contains('调查结束')) {
    return JmaMegaquakeKeyword.investigationEnded;
  }
  if (text.contains('調査中') || text.contains('调查中')) {
    return JmaMegaquakeKeyword.investigating;
  }
  if (text.contains('後発') || text.contains('后续')) {
    return JmaMegaquakeKeyword.subsequentQuakeWatch;
  }
  if (text.contains('定例')) return JmaMegaquakeKeyword.routineCommentary;
  if (telegramCode == 'VYSE51') return JmaMegaquakeKeyword.extraCommentary;
  return JmaMegaquakeKeyword.unknown;
}

Duration jmaMegaquakeTtl(JmaMegaquakeKeyword keyword) {
  return switch (keyword) {
    JmaMegaquakeKeyword.megaquakeWarning ||
    JmaMegaquakeKeyword.megaquakeAdvisory ||
    JmaMegaquakeKeyword.subsequentQuakeWatch ||
    JmaMegaquakeKeyword.investigating ||
    JmaMegaquakeKeyword.extraCommentary ||
    JmaMegaquakeKeyword.routineCommentary ||
    JmaMegaquakeKeyword.unknown => const Duration(minutes: 5),
    JmaMegaquakeKeyword.investigationEnded => const Duration(minutes: 3),
  };
}

int jmaMegaquakePriority(JmaMegaquakeKeyword keyword) {
  return switch (keyword) {
    JmaMegaquakeKeyword.megaquakeWarning => 50,
    JmaMegaquakeKeyword.megaquakeAdvisory => 40,
    JmaMegaquakeKeyword.subsequentQuakeWatch => 40,
    JmaMegaquakeKeyword.investigating => 30,
    JmaMegaquakeKeyword.extraCommentary => 20,
    JmaMegaquakeKeyword.routineCommentary => 12,
    JmaMegaquakeKeyword.investigationEnded => 10,
    JmaMegaquakeKeyword.unknown => 0,
  };
}
