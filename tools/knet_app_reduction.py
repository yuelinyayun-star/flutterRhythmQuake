"""
K-NET / KiK-net ASCII -> 「App 视角」归约器 + 生产震级链路离线复现
================================================================================
目的
  K-NET ASCII 是**最终波形 = 保真度上限**。本工具把它归约到**本 App 真正能看到
  的输入形态**（kmoni 1634 个扫描点），再喂进生产的 srev-kaizou 震级公式，从而
  **不依赖实时事件**就能逐事件复现「若输入够好，生产会给出多少 M」，并与 JMA 目录
  震级 / App 实际回放值对照，定位误差归属。

链路（每步严格复刻生产语义，均有 Dart 出处）
  1) 解析 ASCII 三分量（地表：knet=NS/EW/UD，kik=NS2/EW2/UD2）
  2) 官方 JMA 计测震度 I = 2*log10(a_0.3s) + 0.94        （频域滤波，NHK/気象庁规格）
  3) 量化  level = levelFromShindo(I)  →  I_q = scratchValues[level]   （向下取整）
        出处 lib/services/sources/jp_shindo_scale.dart:37-67
  4) 「App 视角」归约：只有**在 nied_scan_positions 里有扫描点**的站，App 才读得到
        出处 lib/core/intensity_reconstruction/ka_capture_input_extractor.dart:105-138
        （App 读的是该站扫描点像素的颜色 → 站值；无扫描点的站在图上不可观测）
  5) inputIntensity = max(I_q over 可见站)                （复刻生产：全网活动站最大）
        出处 lib/core/source_estimation/source_estimator.dart:1518-1531
  6) 最近站距 D = max(dist(取整震央 -> scratch 站点表 1748 点最近点), 20km)
        出处 lib/core/source_estimation/srev_kaizou_magnitude.dart:245-264
  7) M = 0.7016*I_proc + 0.0903 + 1.73*log10(D), floor 0   （同一公式，两处）
        出处 srev_kaizou_magnitude.dart:215-237（2026-10-14 斜率修正）
        旧式 M = (I_prev - 0.94) + 1.73*log10(D) 的展开对 I 斜率为 1.0

对照口径
  M_appView : 只用 App 可见站（= 生产**本应**看到的输入）
  M_fullNet : 用全部 K-NET 站（= App 若点名到所有站的上限）
  M_coherent: 用「产生 max I 的可见站自身」的震央距（配对修复候选）
  JMA M     : ASCII 头的 Mag.（JMA 目录震级，另一套尺度，仅供参照）

约束：只读，不改生产代码；不写回仓库数据；结果仅作离线实验证据。
用法
  python tools/knet_app_reduction.py                # 扫描默认目录
  python tools/knet_app_reduction.py --zip <a.zip> [--zip ...]
  python tools/knet_app_reduction.py --manifest tmp/knet_app_reduction/events_manifest.json
"""
from __future__ import annotations

import argparse
import glob
import json
import math
import os
import re
import sys
import zipfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
DEFAULT_OUTDIR = os.path.join(PROJECT, "tmp", "knet_app_reduction")

SCRATCH_DART = os.path.join(
    PROJECT, "lib", "core", "source_estimation", "srev_kaizou_scratch_station_table.dart"
)
SCAN_DART = os.path.join(PROJECT, "lib", "models", "nied_scan_positions.dart")
STATION_DB_DART = os.path.join(PROJECT, "lib", "models", "nied_station_db.dart")

DEFAULT_ZIP_ROOTS = [
    r"D:\Users\Rhythm\Downloads",
    os.path.join(os.path.expanduser("~"), "Downloads"),
    os.path.join(PROJECT, "tmp", "knet_downloads_same_station"),
]

# JpShindoScale.scratchValues（与生产逐字一致）
SCRATCH_VALUES = [-3.0, -2.5, -2.0, -1.5, -1.17, -0.84, -0.5, -0.17, 0.16, 0.5,
                  0.83, 1.16, 1.5, 1.83, 2.16, 2.5, 2.83, 3.16, 3.5, 3.83, 4.16,
                  4.5, 4.75, 5.0, 5.25, 5.5, 5.75, 6.0, 6.25, 6.5]
MIN_DIST_KM = 20.0          # srevKaizouMinimumStationDistanceKm
MULTIPLE_SOURCES = False    # 单源
FS_HZ = 100.0               # K-NET/KiK-net 标准采样率

HEADER_KEYS = ["Station Height(m)", "Sampling Freq(Hz)", "Duration Time(s)",
    "Max. Acc. (gal)", "Max Acc. (gal)", "Last Correction", "Station Code",
    "Station Long.", "Station Lon.", "Station Lat.", "Depth. (km)", "Scale Factor",
    "Origin Time", "Record Time", "Long.", "Lon.", "Lat.", "Mag.", "Dir.", "Memo."]


# ================================ 生产语义复刻 ================================
def level_from_shindo(s: float) -> int:
    if not math.isfinite(s) or s < SCRATCH_VALUES[0]:
        return -1
    if s >= SCRATCH_VALUES[-1]:
        return len(SCRATCH_VALUES) - 1
    for i in range(len(SCRATCH_VALUES) - 1, -1, -1):
        if s >= SCRATCH_VALUES[i]:
            return i
    return -1


def round_coord(v: float) -> float:
    return math.floor(v * 10 + 0.5) / 10.0     # Dart (v*10).round()/10（正值区）


def station_distance_km(src_lat, src_lon, st_lat, st_lon) -> float:
    lat_part = (src_lat - st_lat) * 111.2
    lon_part = 6371.0 * (src_lon - st_lon) * (3.1416 / 180.0) * math.cos(
        ((src_lat + st_lat) / 2.0) * math.pi / 180.0)
    return math.sqrt(lat_part * lat_part + lon_part * lon_part)


def magnitude_from(I_proc, D):
    if D is None or D <= 0 or not math.isfinite(I_proc) or not math.isfinite(D):
        return None
    # 与生产 srev_kaizou_magnitude.dart 同步（2026-10-14 斜率修正）：
    # 旧式 (I_proc - 0.94) + 1.73*log10(D) 对 I 的斜率恒为 1.0，现改为 LOO 重拟合系数。
    m = 0.7016 * I_proc + 0.0903 + 1.73 * math.log10(D)
    return 0.0 if m < 0.0 else m


# ================================ ASCII / 计测震度 ============================
def split_header(line: str):
    for k in HEADER_KEYS:
        if line.startswith(k):
            return k, line[len(k):].strip()
    parts = re.split(r"\s{2,}", line.strip(), maxsplit=1)
    return (parts[0].strip(), parts[1].strip()) if len(parts) == 2 else (line.strip(), "")


def parse_ascii(text: str):
    lines = text.splitlines()
    header = {split_header(lines[i])[0]: split_header(lines[i])[1]
              for i in range(min(17, len(lines)))}
    samples = []
    for line in lines[17:]:
        for m in re.finditer(r"[+-]?\d+", line):
            samples.append(int(m.group(0)))
    sf = None
    m = re.match(r"(-?\d+(?:\.\d+)?)\s*\(gal\)\s*/\s*(-?\d+(?:\.\d+)?)",
                 header.get("Scale Factor", ""), re.I)
    if m:
        sf = float(m.group(1)) / float(m.group(2))
    return header, samples, sf


_JMA_H_CACHE: dict = {}


def jma_h(fs: float, n: int):
    key = (fs, n)
    if key in _JMA_H_CACHE:
        return _JMA_H_CACHE[key]
    F = np.fft.rfftfreq(n, d=1.0 / fs)
    X = F / 10.0
    h1 = np.zeros_like(F)
    nz = F > 0
    h1[nz] = np.sqrt(1.0 / F[nz])
    denom = (1 + 0.694 * X**2 + 0.241 * X**4 + 0.0557 * X**6 + 0.009664 * X**8
             + 0.00134 * X**10 + 0.000155 * X**12)
    h2 = 1.0 / np.sqrt(denom)
    h3 = np.sqrt(np.clip(1.0 - np.exp(-(F / 0.5) ** 3), 0.0, None))
    h = h1 * h2 * h3
    _JMA_H_CACHE[key] = h
    return h


def _filtered_vector(ns, ew, ud, fs):
    n = len(ns)
    outs = []
    for x in (ns, ew, ud):
        x = np.asarray(x, dtype=float)
        x = x - x.mean()
        outs.append(np.fft.irfft(np.fft.rfft(x) * jma_h(fs, n), n=n))
    return np.sqrt(outs[0]**2 + outs[1]**2 + outs[2]**2)


def intensity_of(ns, ew, ud, fs=FS_HZ):
    v = _filtered_vector(ns, ew, ud, fs)
    k = max(1, int(round(0.3 * fs)))
    a = np.sort(v)[::-1][k - 1] if len(v) >= k else None
    return (2 * math.log10(a) + 0.94) if (a and a > 0) else None


def shindo_class(I):
    if I is None:
        return "-"
    for hi, nm in [(0.5, "0"), (1.5, "1"), (2.5, "2"), (3.5, "3"), (4.5, "4"),
                   (5.0, "5弱"), (5.5, "5強"), (6.0, "6弱"), (6.5, "6強")]:
        if I < hi:
            return nm
    return "7"


def surface_ext(net: str, ext: str) -> bool:
    # KiK-net 地表 = 扩展名以 2 结尾（Dir 4/5/6）；K-NET 地表 = NS/EW/UD
    if net == "kik":
        return ext in ("NS2", "EW2", "UD2")
    return ext in ("NS", "EW", "UD")


# ================================ 静态表加载 ==================================
def load_scratch():
    t = open(SCRATCH_DART, encoding="utf-8").read()
    rows = re.findall(
        r'\(longitude:\s*(-?\d+\.?\d*),\s*latitude:\s*(-?\d+\.?\d*),\s*name:\s*"([^"]*)"\)', t)
    return [(float(lon), float(lat), nm) for lon, lat, nm in rows]


def load_scan_positions():
    """站码 -> (sampleX, sampleY)。正则抓 NiedScanPoint(...) 参数体，兼容多行/尾逗号。"""
    t = open(SCAN_DART, encoding="utf-8").read()
    out = {}
    for m in re.finditer(r'"([A-Z][A-Z0-9]{3,})"\s*:\s*NiedScanPoint\(([^)]*)\)', t, re.S):
        code, body = m.group(1), m.group(2)
        cx = re.search(r"centerX:\s*(-?\d+)", body)
        cy = re.search(r"centerY:\s*(-?\d+)", body)
        if not cx or not cy:
            continue
        ox = re.search(r"offsetX:\s*(-?\d+)", body)
        oy = re.search(r"offsetY:\s*(-?\d+)", body)
        x = int(cx.group(1)) + (int(ox.group(1)) if ox else 0)
        y = int(cy.group(1)) + (int(oy.group(1)) if oy else 0)
        out[code] = (x, y)
    return out


# ================================ 单事件归约 ==================================
def analyze_event(scratch, scan_positions, zip_path):
    z = zipfile.ZipFile(zip_path)
    groups = {}
    event = {}
    for name in z.namelist():
        base = name.split("/")[-1]
        if "." not in base:
            continue
        stem, ext = base.rsplit(".", 1)
        net = "kik" if "/kik/" in name else ("knet" if "/knet/" in name else "?")
        if not surface_ext(net, ext):
            continue
        m = re.match(r"^(.*?)(\d{10})$", stem)
        if not m:
            continue
        code = m.group(1)
        hdr, smp, sf = parse_ascii(z.read(name).decode("utf-8", "replace"))
        groups.setdefault((net, code), {})[ext[:2]] = (hdr, smp, sf)
        if not event and hdr.get("Lat.") and hdr.get("Long."):
            event = {
                "lat": float(hdr["Lat."]), "lon": float(hdr["Long."]),
                "depth_km": float(hdr["Depth. (km)"]) if hdr.get("Depth. (km)") else None,
                "jma_mag": float(hdr["Mag."]) if hdr.get("Mag.") else None,
                "origin_time": hdr.get("Origin Time"),
            }

    rows = []
    for (net, code), comps in groups.items():
        if not {"NS", "EW", "UD"}.issubset(comps):
            continue
        h = comps["NS"][0]
        if comps["NS"][2] is None:
            continue
        ns = [v * comps["NS"][2] for v in comps["NS"][1]]
        ew = [v * comps["EW"][2] for v in comps["EW"][1]]
        ud = [v * comps["UD"][2] for v in comps["UD"][1]]
        I = intensity_of(ns, ew, ud)
        if I is None:
            continue
        lvl = level_from_shindo(I)
        rows.append({
            "station": code, "network": net,
            "lat": float(h.get("Station Lat.", "nan")),
            "lon": float(h.get("Station Long.", "nan")),
            "I_raw": round(I, 3), "level": lvl,
            "I_q": SCRATCH_VALUES[lvl] if lvl >= 0 else None,
            "shindo": shindo_class(I),
            "appVisible": code in scan_positions,
            "scanPixel": scan_positions.get(code),
        })
    if not rows or not event:
        return None

    rows.sort(key=lambda r: -(r["I_raw"] if r["I_raw"] is not None else -99))
    visible = [r for r in rows if r["appVisible"]]
    invisible = [r for r in rows if not r["appVisible"]]

    def max_q(rs):
        q = [r["I_q"] for r in rs if r["I_q"] is not None]
        return max(q) if q else None

    I_full = max_q(rows)
    I_app = max_q(visible)
    strongest = rows[0]
    strongest_visible = visible[0] if visible else None

    rlat, rlon = round_coord(event["lat"]), round_coord(event["lon"])
    near = min(((station_distance_km(rlat, rlon, s[1], s[0]), s[2]) for s in scratch),
               key=lambda x: x[0])
    D_prod = max(near[0], MIN_DIST_KM)

    M_full = magnitude_from(I_full, D_prod) if I_full is not None else None
    M_app = magnitude_from(I_app, D_prod) if I_app is not None else None
    M_coh = None
    if strongest_visible is not None and I_app is not None:
        d = station_distance_km(rlat, rlon, strongest_visible["lat"], strongest_visible["lon"])
        M_coh = magnitude_from(I_app, max(d, MIN_DIST_KM))

    # 盲区：全网站里强度超过「可见最大」的不可见站（App 根本读不到的真峰）
    blind = [r for r in invisible
             if (I_app is None) or (r["I_q"] is not None and r["I_q"] > I_app)]
    # 像素碰撞：可见站共享同一像素
    pix = {}
    for r in visible:
        pix.setdefault(tuple(r["scanPixel"]), []).append(r["station"])
    collisions = {f"{k[0]},{k[1]}": v for k, v in pix.items() if len(v) > 1}

    return {
        "zip": os.path.basename(zip_path),
        "event": event,
        "stationCount": len(rows),
        "appVisibleCount": len(visible),
        "appInvisibleCount": len(invisible),
        "knet": sum(1 for r in rows if r["network"] == "knet"),
        "kik": sum(1 for r in rows if r["network"] == "kik"),
        "strongestStation": strongest["station"],
        "strongestVisibleStation": strongest_visible["station"] if strongest_visible else None,
        "topStations": rows[:8],
        "inputIntensity_fullNet": I_full,
        "inputIntensity_appView": I_app,
        "blindPeakStations": [{"station": r["station"], "I_raw": r["I_raw"],
                               "I_q": r["I_q"], "shindo": r["shindo"]} for r in blind[:5]],
        "pixelCollisions": collisions,
        "nearestScratchStation": {"name": near[1], "distanceKm": round(near[0], 3)},
        "D_production_km": round(D_prod, 3),
        "M_fullNet": None if M_full is None else round(M_full, 3),
        "M_appView": None if M_app is None else round(M_app, 3),
        "M_coherent": None if M_coh is None else round(M_coh, 3),
        "jma_mag": event["jma_mag"],
        "resid_fullNet": None if (M_full is None or event["jma_mag"] is None)
                         else round(M_full - event["jma_mag"], 3),
        "resid_appView": None if (M_app is None or event["jma_mag"] is None)
                         else round(M_app - event["jma_mag"], 3),
        "blindCost": None if (M_full is None or M_app is None) else round(M_full - M_app, 3),
    }


# ================================ 入口 ========================================
def _collect_zips(args):
    zips = []
    if args.zip:
        for z in args.zip:
            if os.path.isfile(z) and z.endswith(".zip"):
                zips.append(z)
    if args.zip_dir:
        for d in args.zip_dir:
            zips += glob.glob(os.path.join(d, "**", "*_ascii.zip"), recursive=True)
    if not zips:
        for root in DEFAULT_ZIP_ROOTS:
            if os.path.isdir(root):
                zips += glob.glob(os.path.join(root, "**", "*_ascii.zip"), recursive=True)
    # 按内容 sha256 去重（同包可能同时存在于 Downloads 与投递目录）
    import hashlib
    seen, uniq = set(), []
    for z in zips:
        try:
            h = hashlib.sha256(open(z, "rb").read()).hexdigest()
        except OSError:
            continue
        if h in seen:
            continue
        seen.add(h)
        uniq.append(z)
    return sorted(uniq)


def _load_manifest(path):
    """事件清单 -> {14位目录ID: {eventId, jmaMagnitude, appActualMagnitude, ...}}"""
    if not path:
        return {}
    with open(path, encoding="utf-8") as f:
        doc = json.load(f)
    idx = {}
    for e in doc.get("events", []):
        did = str(e.get("niedDirectoryId") or "").strip()
        if did:
            idx[did[:14]] = e
    return idx


def main():
    ap = argparse.ArgumentParser(description="K-NET ASCII -> App 视角归约 + 生产震级复现")
    ap.add_argument("--zip", action="append", help="单个 *_ascii.zip（可多次）")
    ap.add_argument("--zip-dir", action="append", help="递归扫描目录（可多次）")
    ap.add_argument("--manifest", help="事件清单 json（可选，用于附加 JMA/App 元数据）")
    ap.add_argument("--outdir", default=DEFAULT_OUTDIR)
    args = ap.parse_args()

    scratch = load_scratch()
    scan = load_scan_positions()
    print(f"[load] scratch stations = {len(scratch)}   scan points = {len(scan)}")

    manifest = _load_manifest(args.manifest)
    zips = _collect_zips(args)
    print(f"[load] ascii zips = {len(zips)}   manifest entries = {len(manifest)}")
    if not zips:
        print("!! 没找到 *_ascii.zip。用 --zip 或 --zip-dir 指定。")
        return 2

    out = {
        "schema": "knet_app_reduction_v1",
        "scratchStations": len(scratch),
        "scanPoints": len(scan),
        "minDistKm": MIN_DIST_KM,
        "multipleSources": MULTIPLE_SOURCES,
        "note": ("M_appView 只用 App 可见扫描点（忠实渲染假设）；M_fullNet 用全部 K-NET 站；"
                 "blindCost = M_fullNet - M_appView（空间覆盖损失）；"
                 "renderLoss = M_appView - appActualMagnitude（GIF 渲染/解码损失，需清单提供）"),
        "events": [],
    }
    hdr = (f"{'zip':<24}{'nSta':>5}{'vis':>5}{'maxI':>7}{'震度':>4} | "
           f"{'D':>6}{'M_app':>7}{'M_full':>7}{'blind':>6} | {'JMA':>6}"
           f"{'residFull':>10}{'M_act':>7}{'render':>7}")
    print("\n" + hdr)
    print("-" * len(hdr))
    for zp in zips:
        try:
            r = analyze_event(scratch, scan, zp)
        except Exception as e:  # noqa: BLE001
            print(f"{os.path.basename(zp):<24}  ERR {type(e).__name__}: {e}")
            continue
        if not r:
            print(f"{os.path.basename(zp):<24}  (no data)")
            continue

        did = os.path.basename(zp)[:14]
        r["jmaMagnitudeAsciiHeader"] = r["jma_mag"]     # 保留 ASCII 头里的 NIED 值
        meta = manifest.get(did, {})
        if meta:
            r["eventId"] = meta.get("eventId")
            if meta.get("jmaMagnitude") is not None:
                r["jma_mag"] = meta["jmaMagnitude"]
            r["appActualMagnitude"] = meta.get("appActualMagnitude")
        act = r.get("appActualMagnitude")
        r["renderLoss"] = (None if (act is None or r["M_appView"] is None)
                           else round(r["M_appView"] - act, 3))
        out["events"].append(r)

        top = r["topStations"][0] if r["topStations"] else {"I_raw": 0.0, "shindo": "-"}

        def f(v, w=7):
            return f"{('nan' if v is None else format(v, '.2f')):>{w}}"

        print(f"{r['zip']:<24}{r['stationCount']:>5}{r['appVisibleCount']:>5}"
              f"{top['I_raw']:>7.2f}{top['shindo']:>4} | "
              f"{r['D_production_km']:>6.1f}{f(r['M_appView'])}{f(r['M_fullNet'])}"
              f"{f(r['blindCost'], 6)} | {f(r['jma_mag'], 6)}"
              f"{f(r['resid_fullNet'], 10)}{f(act)}{f(r['renderLoss'])}")

    os.makedirs(args.outdir, exist_ok=True)
    op = os.path.join(args.outdir, "report.json")
    with open(op, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"\nwrote {op}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
