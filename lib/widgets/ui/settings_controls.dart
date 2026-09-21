import 'package:flutter/material.dart';

abstract final class SettingsControlStyle {
  static const accent = Color(0xFF82B1FF);
  static const panel = Color.fromRGBO(48, 48, 52, 0.28);
  static const field = Color.fromRGBO(255, 255, 255, 0.09);
  static const border = Color.fromRGBO(255, 255, 255, 0.16);
  static const divider = Color.fromRGBO(255, 255, 255, 0.10);
  static const muted = Color.fromRGBO(255, 255, 255, 0.58);
  static const blurSigma = 14.0;
  static BoxDecoration selectableDecoration({required bool selected}) {
    return BoxDecoration(
      gradient: selected
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.16),
                accent.withValues(alpha: 0.34),
              ],
            )
          : null,
      color: selected ? null : Colors.white.withValues(alpha: 0.11),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: selected
            ? accent.withValues(alpha: 0.78)
            : Colors.white.withValues(alpha: 0.22),
      ),
      boxShadow: selected
          ? [
              BoxShadow(
                color: accent.withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 3),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ]
          : null,
    );
  }
}

class SettingsControlRow extends StatelessWidget {
  const SettingsControlRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.leading,
    required this.control,
  });
  final String title;
  final String? subtitle;
  final IconData leading;
  final Widget control;
  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final titleBlock = Row(
          crossAxisAlignment: subtitle == null
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: SettingsControlStyle.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: SettingsControlStyle.accent.withValues(alpha: 0.28),
                ),
              ),
              child: Icon(
                leading,
                size: 18,
                color: SettingsControlStyle.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: SettingsControlStyle.muted,
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [titleBlock, const SizedBox(height: 12), control],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 220, maxWidth: 330),
              child: control,
            ),
          ],
        );
      },
    );
  }
}

class SettingsGlassAction extends StatelessWidget {
  const SettingsGlassAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.emphasized = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool emphasized;
  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration:
              SettingsControlStyle.selectableDecoration(
                selected: emphasized,
              ).copyWith(
                color: emphasized
                    ? null
                    : Colors.white.withValues(alpha: enabled ? 0.11 : 0.06),
                border: Border.all(
                  color: emphasized
                      ? SettingsControlStyle.accent.withValues(
                          alpha: enabled ? 0.78 : 0.35,
                        )
                      : Colors.white.withValues(alpha: enabled ? 0.22 : 0.12),
                ),
              ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                const SizedBox.square(
                  dimension: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: Colors.white70,
                  ),
                )
              else if (icon != null)
                Icon(
                  icon,
                  size: 16,
                  color: enabled ? Colors.white : Colors.white54,
                ),
              if (busy || icon != null) const SizedBox(width: 6),
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  color: enabled ? Colors.white : Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
