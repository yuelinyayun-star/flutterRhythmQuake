# P-Alert TLS Trust Anchor

`TWCA_Global_Root_CA.der` is the unmodified public TWCA Global Root CA
certificate, not a server certificate or private key. It supplements the
default trusted roots of the Windows P-Alert HTTP client only. It is not
installed into the system or added to Dart's global default context.

- Official repository: https://www.twca.com.tw/repository?lang=en
- Download: https://www.twca.com.tw/upload/saveArea/filePage/20210309/0dcf70c4d84245a5874abf36da01ba16/0dcf70c4d84245a5874abf36da01ba16.zip
- Original archive entry: `TWCA Global Root CA_4096.crt`
- Official certificate information: https://download.twca.com.tw/upload/saveArea/filePage/20230630/b4c6aa6586bb43088350ef493df9a85c/b4c6aa6586bb43088350ef493df9a85c.pdf
- Subject and issuer: `C=TW, O=TAIWAN-CA, OU=Root CA, CN=TWCA Global Root CA`
- Serial: `0CBE`
- Valid until: `2030-12-31T15:59:59Z`
- SHA-1: `9cbb4853f6a4f6d352a4e83252556013f5adaf65`
- SHA-256 (DER): `59769007f7685d0fcd50872f9f95d5755a5b2b457d81f3692b610a98672f0e1b`
- Verified: `2026-10-02`

The client verifies the bundled certificate's SHA-256 before loading it.
Normal certificate chain, hostname and validity checks remain enabled.
When updating this asset, verify the replacement against official CA
information and update the fingerprint and tests together.
