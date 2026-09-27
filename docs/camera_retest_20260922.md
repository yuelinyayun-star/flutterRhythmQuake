# Camera Retest Inputs

## Original Hyuganada Bulletin

The unchanged original response is saved in
`test/fixtures/jma_voice/p2p_history_20260921.json`.
Select the entry with `issue.type = DetailScale` and
`earthquake.time = 2026/09/21 22:38:00`.
Its ID is `6ab13449e88ee598246bf33b`; it contains 191 observation points.

The offline regression is `test/jma_info_camera_fit_test.dart`. It passes
the original bulletin through the adapter without changing its timestamps,
coordinates, intensity observations, or region names. It does not inject
anything into the running application.

## Synthetic Nearby Pair

The saved JSON template is `tools/fixtures/nearby_camera_simulation.json`.
Its timestamps are intentionally the preparation-time snapshot, not current
earthquake observations. A was prepared for the cancelled test; B is its
saved companion template. Neither has been successfully injected.

`tools/prepare_nearby_camera_simulation.ps1 -Event A` prepares the first
local-only simulated bulletin; `-Event B` prepares the second. Each command
generates a fresh event ID and timestamp and puts the JSON in the clipboard.
Both use the CENC information schema and explicitly say
`SIMULATION ... - NOT A REAL EARTHQUAKE`.

- A: latitude 30.6, longitude 103.9, M5.0, depth 10 km.
- B: latitude 30.85, longitude 104.15, M5.2, depth 10 km.

Paste A into the app's simulation panel, observe its settled view, then
paste B. Do not submit these to any external alert service. The stopped
2026-09-22 test did not successfully inject either bulletin.

## Connectivity

On inspection, local sshd was stopped and port 8765 belonged to AgentDock,
not LocalInjectServer. Do not send injection requests to that port unless
the service identity has first been checked. These are inspection-time
observations, not assumptions about later runs.
