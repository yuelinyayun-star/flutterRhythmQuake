"""Run the isolated native recording probe with production resource limits."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import time


def command(*args: str) -> str:
    return subprocess.check_output(args, text=True, encoding="utf-8").strip()


def properties(unit: str) -> dict[str, str]:
    return dict(line.split("=", 1) for line in command(
        "systemctl", "show", unit, "-p", "ActiveState", "-p", "Result",
        "-p", "ExecMainStatus", "-p", "MemoryPeak", "-p", "NRestarts",
    ).splitlines())


def read_stats(cgroup: Path) -> dict:
    cpu = dict(line.split() for line in (cgroup / "cpu.stat").read_text().splitlines())
    io = {"rbytes": 0, "wbytes": 0}
    for line in (cgroup / "io.stat").read_text().splitlines():
        for token in line.split()[1:]:
            name, value = token.split("=", 1)
            if name in io:
                io[name] += int(value)
    rss = 0
    hwm = 0
    for pid in (cgroup / "cgroup.procs").read_text().split():
        try:
            fields = dict(line.split(":", 1) for line in
                          Path(f"/proc/{pid}/status").read_text().splitlines() if ":" in line)
            if fields["Name"].strip().startswith("flutterrhythm"):
                rss += int(fields.get("VmRSS", "0 kB").split()[0]) * 1024
                hwm += int(fields.get("VmHWM", "0 kB").split()[0]) * 1024
        except FileNotFoundError:
            pass
    return {"cpuUsec": int(cpu["usage_usec"]),
            "groupMemory": int((cgroup / "memory.current").read_text()),
            "groupMemoryHighWater": int((cgroup / "memory.peak").read_text()),
            "rss": rss, "rssHighWater": hwm, **io}


def journal(unit: str) -> list[dict]:
    result = []
    for line in command("journalctl", "-u", unit, "--no-pager", "-o", "json").splitlines():
        entry = json.loads(line)
        try:
            message = json.loads(entry.get("MESSAGE", ""))
        except (json.JSONDecodeError, TypeError):
            continue
        if isinstance(message, dict) and "phase" in message:
            result.append({"epoch": int(entry["__REALTIME_TIMESTAMP"]) / 1_000_000,
                           **message})
    return result


def phase_at(epoch: float, messages: list[dict]) -> str:
    phase = "startup"
    transitions = {"start": "recording", "recorded": "prepare-audit",
                   "export": "export", "exported": "verify", "verified": "verify",
                   "settle": "settle", "done": "done"}
    for entry in messages:
        if entry["epoch"] > epoch:
            break
        label = entry["phase"]
        if label in transitions:
            phase = transitions[label]
    return phase


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--events", required=True)
    parser.add_argument("--unit", required=True)
    parser.add_argument("--seconds", type=int, default=300)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--export-input", type=Path)
    args = parser.parse_args()
    unit = args.unit + ".service"
    if args.root.exists() or args.report.exists():
        raise ValueError("Use new isolated paths; never overwrite a previous run")
    options = [f"--setenv=RQ_EXPORT_INPUT={args.export_input}"] if args.export_input else []
    subprocess.run([
        "systemd-run", "--unit", args.unit, "--property=User=filebrowser",
        "--property=Group=filebrowser", "--property=CPUAccounting=true",
        "--property=MemoryAccounting=true", "--property=CPUQuota=100%",
        "--property=MemoryHigh=640M", "--property=MemoryMax=896M",
        "--property=OOMPolicy=stop", "--property=TimeoutStopSec=30",
        "--property=NoNewPrivileges=true", "--property=PrivateTmp=true",
        f"--working-directory={args.bundle}", "--setenv=LIBGL_ALWAYS_SOFTWARE=1",
        "--setenv=NO_AT_BRIDGE=1", "--setenv=GSETTINGS_BACKEND=memory",
        f"--setenv=RQ_PROBE_ROOT={args.root}", f"--setenv=RQ_PROBE_EVENTS={args.events}",
        f"--setenv=RQ_PROBE_SECONDS={args.seconds}", *options, "/usr/bin/xvfb-run",
        "-a", "-s", "-screen 0 640x480x24", "./flutterrhythmquake",
    ], check=True)
    cgroup = Path("/sys/fs/cgroup/system.slice") / unit
    deadline = time.monotonic() + args.seconds + 600
    samples = []
    last_progress = 0.0
    status = {}
    while time.monotonic() < deadline:
        try:
            samples.append({"epoch": time.time(), **read_stats(cgroup)})
        except FileNotFoundError:
            status = properties(unit)
            if status.get("ActiveState") in {"inactive", "failed"}:
                break
        if time.monotonic() - last_progress >= 30:
            status = properties(unit)
            if samples:
                print(json.dumps({"progress": status, "latest": samples[-1]}), flush=True)
            if status.get("ActiveState") in {"inactive", "failed"}:
                break
            available = int(next(line.split()[1] for line in
                                 Path("/proc/meminfo").read_text().splitlines()
                                 if line.startswith("MemAvailable:")))
            if available < 700 * 1024:
                subprocess.run(["systemctl", "stop", unit], check=True)
                raise RuntimeError("Stopped only the test: host available memory below 700 MiB")
            last_progress = time.monotonic()
        time.sleep(0.1)
    else:
        subprocess.run(["systemctl", "stop", unit], check=True)
        status = properties(unit)
    status = properties(unit)
    messages = journal(unit)
    if (status.get("Result") == "success" and status.get("ExecMainStatus") == "0"
            and any(entry["phase"] == "done" for entry in messages)
            and not any(entry["phase"] == "verified" for entry in messages)):
        try:
            from verify_replay_exports import verify_directory
            verified = verify_directory(args.root)
            recorded = next((entry["frames"] for entry in messages if entry["phase"] == "recorded"), None)
            if recorded is not None and any(entry["frames"] != recorded for entry in verified):
                raise ValueError("Recorded frames missing")
            messages.extend(verified)
        except Exception as error:
            messages.append({"epoch": time.time(), "phase": "verification-failed", "error": str(error)})
    summary = {}
    previous = None
    for sample in samples:
        phase = phase_at(sample["epoch"], messages)
        value = summary.setdefault(phase, {"rssPeak": 0, "groupMemoryPeak": 0,
                                           "durationSeconds": 0.0, "cpuUsec": 0,
                                           "readBytes": 0, "writeBytes": 0})
        value["rssPeak"] = max(value["rssPeak"], sample["rss"])
        value["groupMemoryPeak"] = max(value["groupMemoryPeak"], sample["groupMemory"])
        if previous:
            value["durationSeconds"] += sample["epoch"] - previous["epoch"]
            value["cpuUsec"] += max(0, sample["cpuUsec"] - previous["cpuUsec"])
            value["readBytes"] += max(0, sample["rbytes"] - previous["rbytes"])
            value["writeBytes"] += max(0, sample["wbytes"] - previous["wbytes"])
        previous = sample
    for value in summary.values():
        elapsed = value["durationSeconds"]
        value["oneCoreCpuAveragePct"] = value["cpuUsec"] / elapsed / 10000 if elapsed else 0
        value["fourCoreHostCpuAveragePct"] = value["oneCoreCpuAveragePct"] / 4
    expected_events = (next(entry["eventCount"] for entry in messages if entry["phase"] == "start")
                       if args.export_input else len(args.events.split(",")))
    passed = (status.get("Result") == "success" and status.get("ExecMainStatus") == "0"
              and any(entry["phase"] == "done" for entry in messages)
              and sum(entry["phase"] == "verified" for entry in messages)
              == expected_events)
    report = {"unit": unit, "status": status, "passed": passed, "summary": summary,
              "messages": messages, "samples": samples,
              "note": "Original reports and station JSON unchanged. Test receipt clock only. No TG upload."}
    args.report.write_text(json.dumps(report, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({"status": status, "passed": passed, "summary": summary,
                      "messages": messages}, ensure_ascii=False), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
