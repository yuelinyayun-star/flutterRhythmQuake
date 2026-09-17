import 'package:flutter/material.dart';

typedef ManualLocationCoordinates = ({double latitude, double longitude});

class ManualLocationDialog extends StatefulWidget {
  const ManualLocationDialog({super.key, this.latitude, this.longitude});
  final double? latitude;
  final double? longitude;

  @override
  State<ManualLocationDialog> createState() => _ManualLocationDialogState();
}

class _ManualLocationDialogState extends State<ManualLocationDialog> {
  late final latCtl = TextEditingController(
    text: widget.latitude?.toStringAsFixed(6) ?? '',
  );
  late final lngCtl = TextEditingController(
    text: widget.longitude?.toStringAsFixed(6) ?? '',
  );
  String? errorText;

  static const _accentColor = Color(0xFF82B1FF);
  static const _panelColor = Color.fromRGBO(48, 48, 52, 0.28);
  static const _fieldColor = Color.fromRGBO(255, 255, 255, 0.09);
  static const _borderColor = Color.fromRGBO(255, 255, 255, 0.16);
  static const _dividerColor = Color.fromRGBO(255, 255, 255, 0.10);
  static const _mutedTextColor = Color.fromRGBO(255, 255, 255, 0.58);

  @override
  void dispose() {
    // Keep controllers alive until the route and its exit animation unmount.
    latCtl.dispose();
    lngCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: _panelColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _borderColor),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(
                  Icons.edit_location_alt_outlined,
                  color: _accentColor,
                  size: 18,
                ),
                SizedBox(width: 8),
                Text(
                  '手动输入定位',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '请输入经纬度，保存后将作为所在地（本地预警与距离计算的参考点）。',
              style: TextStyle(color: _mutedTextColor, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: latCtl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: '纬度 (Latitude)',
                labelStyle: const TextStyle(color: _mutedTextColor),
                filled: true,
                fillColor: _fieldColor,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _dividerColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _accentColor),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: lngCtl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: '经度 (Longitude)',
                labelStyle: const TextStyle(color: _mutedTextColor),
                filled: true,
                fillColor: _fieldColor,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _dividerColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _accentColor),
                ),
              ),
            ),
            if (errorText != null) ...[
              const SizedBox(height: 10),
              Text(
                errorText!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _dividerColor),
                        foregroundColor: Colors.white70,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentColor.withValues(alpha: 0.22),
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: _accentColor),
                        elevation: 0,
                      ),
                      onPressed: () {
                        final lat = double.tryParse(latCtl.text.trim());
                        final lng = double.tryParse(lngCtl.text.trim());
                        if (lat == null ||
                            lng == null ||
                            !lat.isFinite ||
                            !lng.isFinite) {
                          setState(() => errorText = '请输入有效的数字坐标');
                          return;
                        }
                        if (lat < -90 || lat > 90) {
                          setState(() => errorText = '纬度范围必须在 -90 ~ 90');
                          return;
                        }
                        if (lng < -180 || lng > 180) {
                          setState(() => errorText = '经度范围必须在 -180 ~ 180');
                          return;
                        }
                        FocusScope.of(context).unfocus();
                        Navigator.of(
                          context,
                        ).pop((latitude: lat, longitude: lng));
                      },
                      child: const Text('保存'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
