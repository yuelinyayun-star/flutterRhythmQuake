# History Report Payloads

Each report retained in `unified_eew_history` includes `sourcePayload` beside
its normalized display fields. The existing latest-15-event-group retention and
report acceptance/deduplication rules are unchanged. This is not an archive of
every received socket frame or of all earthquake-list entries.

For Wolfx, FAN, WHEWS, Jian and P2P, the payload is the original decoded JSON
event body. Nested values and provider-specific fields are retained without
renaming or normalization. FAN captures the input before field reconstruction;
WHEWS captures before alias expansion; P2P captures before merging previous
reports. Transport envelopes, JSON whitespace and authentication messages are
not archived. This is the API-delivered body, not an upstream JMA XML telegram
unless that telegram was itself included in the body.

For GlobalQuake, `sourcePayload.format` is `java-object-stream-decoded-v1`.
`packet` contains the decoded Java class and fields, tagged object references,
custom serialization blocks (base64) and tagged non-finite numbers. It is not a
byte-identical copy of the TCP stream. The existing `rawEvent` field is a derived
application model and must not be described as the original protocol message.

Payload snapshots are deep, immutable copies. They survive `copyWith`, Android
foreground-service handoff and history JSON save/restore. History saved before
this change without a payload continues to load, but no original is fabricated
from its display fields. No new history viewer/export UI is added here.
