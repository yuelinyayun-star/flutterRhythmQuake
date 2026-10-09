# SASMEX protocol unit fixture

`sasmex_protocol_unit.json` reuses the existing `data` literal in
`server/kma_pews_relay/test_sidesis_realtime.py` →
`test_maps_info_severity_and_keeps_real_fields` without altering any values.
`relayEvent` is the output of the production `parse_sidesis_message` parser.

This is an existing protocol unit example, **not a captured upstream alert**.
UI tests render it directly without admitting it into the active EEW lifecycle,
changing its timestamp, connecting to public sources, or injecting the live app.
