# Zhejiang Typhoon Capture

Captured on 2026-09-21 directly with Invoke-WebRequest -OutFile. The two JSON
files are unmodified HTTP response bodies, not generated weather observations.

- `zj_activity_20260921.json`: https://typhoon.slt.zj.gov.cn/Api/TyhoonActivity
- `zj_202625_20260921.json`: https://typhoon.slt.zj.gov.cn/Api/TyphoonInfo/202625

These are historical test captures, not a current live feed. Deliberately
constructed protocol failures and model boundary inputs are separately marked
in `test/typhoon_service_test.dart`; they do not overwrite these captures.
