"""Capture one unmodified live official sample, explicitly NOT a fake anomaly."""
import argparse
import asyncio
from dataclasses import asdict
from datetime import UTC, datetime, timedelta
import json
from pathlib import Path
import zipfile

from kma_pews_relay import Config, KmaRelay, decode_header


async def validate(directory):
    relay = KmaRelay(Config(anomaly_directory=str(directory / "outbox")))
    await relay.http.start()
    relay.anomalies.start()
    try:
        await relay.http.synchronize_clock()
        target = datetime.fromtimestamp(int(relay.clock.now_epoch()) - relay.config.target_lag_seconds, UTC)
        for lag in range(relay.config.lag_retry_seconds + 1):
            stamp = target - timedelta(seconds=lag)
            response = await relay.http.fetch(f"data/{stamp.strftime('%Y%m%d%H%M%S')}.b")
            if response.status == 404:
                continue
            if response.status != 200:
                raise ValueError(f"Live official HTTP status {response.status}")
            await relay._accept_frame(stamp, response.body, response)
            # The actual decode outputs come from the same production parser.
            decoded = {"header": asdict(decode_header(response.body)),
                       "rawMmi": relay.state.latest_raw_mmi, "Data": relay.state.latest_data,
                       "validationOnly": True,
                       "clientWouldReject": -3 in relay.state.latest_data["mmi"]}
            relay._record_anomaly(stamp, response.body, response, decoded,
                                  ["manual_live_validation"], "complete")
            await relay.anomalies.queue.join()
            if relay.anomalies.failed:
                raise ValueError("Validation archive failed")
            for path in sorted((directory / "outbox").glob("*.zip")):
                with zipfile.ZipFile(path) as archive:
                    report = json.loads(archive.read("report.json"))
                    assert archive.read("raw/frame.b") == response.body
                    assert archive.read("raw/stations.s") == relay._station_input[1].body
                    assert report["decoded"]["rawMmi"] == relay.state.latest_raw_mmi
                    assert report["decoded"]["Data"] == relay.state.latest_data
                print(json.dumps({"archive": str(path), "frameUtc": stamp.isoformat(),
                                  "frameBytes": len(response.body),
                                  "stationBytes": len(relay._station_input[1].body),
                                  "stationCount": len(relay.state.stations),
                                  "clientWouldReject": -3 in relay.state.latest_data["mmi"],
                                  "reason": report["reasons"]}, ensure_ascii=False), flush=True)
            return
        raise ValueError("No available official live frame")
    finally:
        await relay.http.close()
        await relay.anomalies.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", type=Path, required=True)
    args = parser.parse_args()
    asyncio.run(validate(args.directory))
