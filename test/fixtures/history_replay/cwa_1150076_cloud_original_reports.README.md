# CWA 1150076 cloud replay reports

`cwa_1150076_cloud_original_reports.json` contains the four complete, unchanged
`reports` objects and their UTC arrival metadata extracted from two user-provided
cloud-computer replay files. No source ID, timestamp, location, intensity or
payload value was rewritten. The large station archives are excluded from this
report-processing regression fixture.

Original file SHA-256:

- `RhythmQuake_1791883824520.rqreplay`:
  `701e6bdb168a2d2d92608f628b8282e19d44dfe69a0e3ebe6c99dc8da7081440`
- `RhythmQuake_1791883838999.rqreplay`:
  `5012f4827673df7c65d5a3311a9be76f8f410b96dc3dabe3330bf79073449ac4`

The first archive has Wolfx report 1 and Jian reports 2/3, with agency ID
`1150076`. The second has FAN report 1, with upstream ID
`cwa.gov.tw_earthquakeEW_1150076`; it arrived after Jian report 3. The first-report
epicenter differs from the revised epicenter enough to exceed the existing
coordinate fallback. Identity comparison must recognize the captured namespace
without changing either stored ID, and the late report must not replace report 3.

`cwa_cloud_replay_test.dart` can optionally verify both complete original files
with `--dart-define=CLOUD_REPLAY_DIRECTORY=<directory>` before exercising their
unchanged reports.
