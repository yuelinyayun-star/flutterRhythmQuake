# Hi-net Authenticated Export Row Templates

- Status: `pass`
- Request file: `docs/data/hinet_authenticated_export_request.json`
- Rows file: `docs/data/hinet_authenticated_export_rows.json`
- Template directory: `.dart_tool/hinet_authenticated_export_row_templates/files`
- Row templates: `0`
- Manual-review required: `0`
- Automatic clearances: `0`
- Credential fields: `0`

## Validation

- Errors: none
- Warnings: none

## Templates

| Case | File | Preferred source | Query window |
| --- | --- | --- | --- |

## Decision

- These files are scratch templates only. They are written under `.dart_tool` and do not edit `docs/data/hinet_authenticated_export_rows.json`.
- Fill a template from an authenticated event-level Hi-net/JMA row, then pass it to `tools/import_hinet_authenticated_export_row.dart`.
- Do not add credentials, cookies or session material to any template.
