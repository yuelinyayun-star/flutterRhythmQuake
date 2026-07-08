# JMA Reference Capture Review Packet

- Status: `pass`
- Manifest: `docs/data/jma_reference_event_candidates.json`
- Association report: `.dart_tool/jma_reference_capture_association/report.json`
- Packets: `2`
- Manual-review required: `2`
- Automatic clearances: `0`
- Manifest mutations: `0`
- Final catalog truth labels: `0`

## Validation

- Errors: none
- Warnings: none

## Packets

### `20260625_iwate_offshore_m46_jma_eqsc9`

- Status: `pending_capture_association`
- Origin JST: `2026-06-26T01:11:51+09:00`
- Region: `Iwate offshore`
- Latitude/longitude: `40.3, 142.2`
- Depth/M: `50.0 km / M4.6`
- Max shindo: `3`
- Existing local captures: ``
- Existing local fixtures: ``
- Review target: `docs/data/jma_reference_event_candidates.json`
- Validation command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_jma_reference_capture_association.ps1
```

- Import dry-run command:

```powershell
dart run tools\import_jma_reference_capture_package.dart --input <reviewed-capture-association.json> --dry-run
```

- Decision: associate only a real local replay/capture package. Keep this event reference-only until final-catalog linking clears.

### `20260626_yamanashi_central_west_m26_jma_equake5`

- Status: `pending_capture_association`
- Origin JST: `2026-06-26T15:41:13+09:00`
- Region: `Yamanashi central-west`
- Latitude/longitude: `35.8, 138.3`
- Depth/M: `10.0 km / M2.6`
- Max shindo: `1`
- Existing local captures: ``
- Existing local fixtures: ``
- Review target: `docs/data/jma_reference_event_candidates.json`
- Validation command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_jma_reference_capture_association.ps1
```

- Import dry-run command:

```powershell
dart run tools\import_jma_reference_capture_package.dart --input <reviewed-capture-association.json> --dry-run
```

- Decision: associate only a real local replay/capture package. Keep this event reference-only until final-catalog linking clears.

