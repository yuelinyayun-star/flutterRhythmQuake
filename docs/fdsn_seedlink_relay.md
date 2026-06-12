# FDSN SeedLink Relay

This relay connects to a small set of EarthScope and GEOFON SeedLink streams,
converts miniSEED traces into simplified motion samples, and serves them to the
Flutter app over WebSocket.

## Run

```powershell
.\tools\run_fdsn_seedlink_relay.ps1
```

Default WebSocket endpoint:

```text
ws://127.0.0.1:8791/fdsn-motion
```

The Flutter app connects to this endpoint automatically.

## Dependencies

```powershell
pip install obspy websockets numpy
```

If you want to run the Python script directly:

```powershell
python tools/fdsn_seedlink_relay.py
```

## Default Streams

The relay intentionally subscribes to only a few streams by default:

- EarthScope: `IU.ANMO.BH?`, `IU.COLA.BH?`, `II.PFO.BH?`
- GEOFON: `GE.ACRG.BH?`, `GE.MORC.BH?`, `GE.WLF.BH?`

Do not subscribe to full global networks from a desktop app. Add stations in
`STREAMS` only after checking bandwidth and server policy.

## Output

Each WebSocket frame is JSON:

```json
{
  "type": "motion",
  "source": "GEOFON",
  "network": "GE",
  "station": "ACRG",
  "channel": "BHZ",
  "pga": 1.23,
  "pgv": 0.04,
  "intensity": 1.7,
  "active": true,
  "timestamp": "2026-06-11T12:00:00Z"
}
```

`pga` is gal, `pgv` is cm/s, and `intensity` is a simplified display value
derived from PGA. If StationXML response cannot be fetched or response removal
fails, those physical values are `null` rather than fabricated.

## Accuracy Notes

This is a live-data MVP:

- It fetches StationXML response through FDSN and removes instrument response
  with ObsPy.
- Velocity channels are converted to velocity, then differentiated for PGA.
- Proper JMA instrumental intensity requires the official filtering/windowing
  algorithm and should replace the simplified PGA formula later.
