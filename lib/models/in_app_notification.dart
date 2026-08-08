import 'package:flutter/material.dart';

/// 应用内轻通知数据模型
class InAppNotification {
  final String id;
  final String title;
  final String body;
  final IconData icon;
  final Color accentColor;
  final VoidCallback? onTap;

  InAppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.icon,
    required this.accentColor,
    this.onTap,
  });
}
