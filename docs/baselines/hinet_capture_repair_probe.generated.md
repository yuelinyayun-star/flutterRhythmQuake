# Hi-net Capture Repair Probe

- Status: `pass`
- Review report: `.dart_tool/hinet_capture_provenance_review/report.json`
- Scan roots: `test/fixtures/source_estimation`, `tmp/captures`, `tmp/quarantine`
- Repair input template directory: `.dart_tool/hinet_capture_repair_probe/files`
- Cases: `0`
- Affected files: `0`
- Repair input templates: `0`
- Manual-review required: `0`
- Automatic clearances: `0`
- Local candidates: `0`
- Valid GIF candidates: `0`
- Remote retrieval hints: `0`
- Repair-candidate ready cases: `0`
- Unresolved repair cases: `0`

## Validation

- Errors: none
- Warnings: none

## Cases

| Case | Decision | Affected file | Candidates | Valid GIFs | Remote hints | Ready |
| --- | --- | --- | ---: | ---: | ---: | --- |

## Remote Retrieval Hints

| Affected file | Source | URL | Notes |
| --- | --- | --- | --- |

## Repair Import Templates

| Case | Affected file | Template | Candidate status | Dry-run |
| --- | --- | --- | --- | --- |

## Decision

- This probe does not copy files into a capture package and does not approve exclusions.
- A found GIF is only a repair candidate. A reviewer still needs to inspect provenance before clearing the capture blocker.
- Filling a repair import template and running the importer only repairs the capture package after explicit review; it does not change source truth, split assignment or production behavior.
