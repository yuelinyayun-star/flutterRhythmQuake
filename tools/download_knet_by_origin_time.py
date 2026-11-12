#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""按「发震时刻(分钟)」自动解析 NIED K-NET 目录 ID 并下载事件波形。

问题
----
NIED 下载 URL 形如：
  https://www.kyoshin.bosai.go.jp/kyoshin/download/<collection>/zip/YYYY/MM/<dirId>/<dirId>_<fmt>.zip
其中 <dirId> = 发震时刻精确到秒 = YYYYMMDDHHMMSS。
但公开信息（NIED 导出的 CSV、zip 头 "Origin Time"）**只给到分钟** → 末两位"秒"未知。
未登录访问任何 URL 一律 401；**登录后**：dirId 错 → 404，dirId 对 → 200。
=> 本工具在登录态下对"秒位 00..59"（可选分钟 ±N）做扫描，首个 200 即真实 dirId 并落盘。

用法
----
    # 凭据走环境变量（不落盘）
    set NIED_USERNAME=你的账号
    set NIED_PASSWORD=你的密码

    python tools/download_knet_by_origin_time.py \
        --events tmp/knet_probe/nied_catalog_20260910_20261010.json \
        --output tmp/knet_downloads_same_station

    # 只解析不下载（仍会 GET，但 200 时丢弃内容，只记 URL）
    python tools/download_knet_by_origin_time.py --events <json> --resolve-only

    # 扩大分钟窗口（应对极少数"目录分钟比清单早/晚 1 分钟"的事件）
    python tools/download_knet_by_origin_time.py --events <json> --minute-window 1

产物
----
  <output>/<eventId>/<dirId>_<fmt>.zip         下载的波形包
  <output>/nied_dirid_resolution.json          解析报告（含每个事件锁定的 dirId + URL）
  <output>/nied_resolved_manifest.json         可直接喂 tools/download_knet_waveforms.ps1 的清单

只做只读采集：不改生产算法/fixture/扫描表；密码不写入任何文件。
"""
import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta

BASE = "https://www.kyoshin.bosai.go.jp"
UA = "Mozilla/5.0 (compatible; FlutterRhythmQuake-research/1.0)"


def build_url(collection: str, fmt: str, dirid: str) -> str:
    yyyy, mm = dirid[0:4], dirid[4:6]
    return (f"{BASE}/kyoshin/download/{collection}/zip/{yyyy}/{mm}/"
            f"{dirid}/{dirid}_{fmt}.zip")


def probe(url: str, auth_header: str, timeout: int = 60):
    """返回 (status, bytes|None)。status: 200/401/404/... ；网络异常返回 (None, None)。"""
    req = urllib.request.Request(url, headers={
        "Authorization": auth_header,
        "User-Agent": UA,
    })
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, None
    except Exception as e:  # noqa: BLE001
        return None, str(e)


def resolve_one(minute: str, auth_header: str, collection: str, fmt: str,
                minute_window: int, delay: float, resolve_only: bool,
                log):
    """扫描候选 dirId，返回 (dirid, url, data) 或 (None, None, None)。"""
    base_dt = datetime.strptime(minute, "%Y%m%d%H%M")
    offs = [0]
    for k in range(1, minute_window + 1):
        offs += [-k, k]
    # 秒位顺序：00 优先（最常见），再 01..59
    sec_order = [0] + [s for s in range(1, 60)]
    for dm in offs:
        dt = base_dt + timedelta(minutes=dm)
        base12 = dt.strftime("%Y%m%d%H%M")
        for ss in sec_order:
            dirid = f"{base12}{ss:02d}"
            url = build_url(collection, fmt, dirid)
            status, payload = probe(url, auth_header)
            if status == 200:
                log(f"    HIT  dirId={dirid}  (dm={dm:+d}, ss={ss:02d})")
                data = None if resolve_only else payload
                return dirid, url, (payload if resolve_only else data)
            if status is None:
                log(f"    net-error {url} -> {payload}")
            time.sleep(delay)
    return None, None, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--events", required=True, help="nied_event_catalog_v1 JSON，或 {minute:YYYYMMDDHHMM,...} 列表")
    ap.add_argument("--output", default=r"tmp/knet_downloads_same_station")
    ap.add_argument("--collection", default="knet", choices=["knet", "kik", "all"])
    ap.add_argument("--format", default="ascii", choices=["ascii", "csv"])
    ap.add_argument("--minute-window", type=int, default=0, help="分钟容差 ±N（默认 0）")
    ap.add_argument("--delay", type=float, default=0.15, help="每次请求间隔秒")
    ap.add_argument("--resolve-only", action="store_true", help="只解析 URL，不落盘")
    ap.add_argument("--username", default=os.environ.get("NIED_USERNAME", ""))
    ap.add_argument("--password", default=os.environ.get("NIED_PASSWORD", ""))
    args = ap.parse_args()

    if not args.username or not args.password:
        print("ERROR: 需要 NIED 凭据。设环境变量 NIED_USERNAME / NIED_PASSWORD，或用 --username/--password。",
              file=sys.stderr)
        return 3
    auth = "Basic " + base64.b64encode(f"{args.username}:{args.password}".encode()).decode()

    doc = json.load(open(args.events, encoding="utf-8"))
    if isinstance(doc, dict) and "events" in doc:
        events = doc["events"]
    else:
        events = doc

    out_root = os.path.abspath(args.output)
    os.makedirs(out_root, exist_ok=True)

    lines = []
    def log(s):
        lines.append(str(s))
        print(s)

    resolved, failed = [], []
    manifest_events, manifest_targets = [], {}

    for ev in events:
        eid = ev.get("eventId") or ev.get("originTimeJstMinute")
        minute = ev.get("originTimeJstMinute") or ev.get("minute")
        region = ev.get("region", "")
        log(f"[{eid}] {ev.get('originTimeJst', minute)} {region} M{ev.get('magnitude','?')}")
        if not minute or len(str(minute)) != 12:
            log("    skip: 缺少 12 位发震分钟")
            failed.append({"eventId": eid, "reason": "no_minute"})
            continue

        dirid, url, payload = resolve_one(minute, auth, args.collection, args.format,
                                          args.minute_window, args.delay, args.resolve_only, log)
        if not dirid:
            log("    NOT FOUND（该分钟 ±窗口内无 200）")
            failed.append({"eventId": eid, "minute": minute, "reason": "not_found"})
            continue

        rec = {"eventId": eid, "minute": minute, "dirId": dirid, "url": url,
               "region": region, "magnitude": ev.get("magnitude")}
        resolved.append(rec)

        if not args.resolve_only and payload:
            ev_dir = os.path.join(out_root, eid)
            os.makedirs(ev_dir, exist_ok=True)
            fname = f"{dirid}_{args.format}.zip"
            fpath = os.path.join(ev_dir, fname)
            sig_ok = payload[:4] == b"PK\x03\x04"
            if sig_ok:
                with open(fpath, "wb") as f:
                    f.write(payload)
                rec["savedPath"] = fpath
                rec["bytes"] = len(payload)
                log(f"    saved {fpath} ({len(payload)} B)")
            else:
                rec["warning"] = "not_a_zip"
                log("    WARNING: 200 但内容非 zip（可能被登录页拦截）")

        manifest_events.append({"eventId": eid, "originTimeJst": ev.get("originTimeJst"),
                                "region": region, "magnitude": ev.get("magnitude"),
                                "dirId": dirid})
        manifest_targets[eid] = [{"collection": args.collection, "format": args.format,
                                  "url": url, "requiresRegistration": True,
                                  "qualityFlags": ["dirid_resolved_by_probe"]}]

    report = {"schema": "nied_dirid_resolution_v1",
              "generatedAt": datetime.now().isoformat(timespec="seconds"),
              "sourceEvents": args.events, "collection": args.collection, "format": args.format,
              "minuteWindow": args.minute_window,
              "resolvedCount": len(resolved), "failedCount": len(failed),
              "resolved": resolved, "failed": failed, "log": lines}
    rp = os.path.join(out_root, "nied_dirid_resolution.json")
    json.dump(report, open(rp, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    if manifest_targets:
        mp = os.path.join(out_root, "nied_resolved_manifest.json")
        json.dump({"schemaVersion": "knet_waveform_download_manifest_v1",
                   "generatedAt": report["generatedAt"],
                   "events": manifest_events, "targetsByEventId": manifest_targets},
                  open(mp, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        log(f"manifest -> {mp}")

    log(f"resolved {len(resolved)} / failed {len(failed)}  report -> {rp}")
    return 0 if not failed else 2


if __name__ == "__main__":
    sys.exit(main())
