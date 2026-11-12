#!/usr/bin/env python3
"""Build place-name lookup polygons, never territorial or maritime boundaries."""
from __future__ import annotations

import argparse
import hashlib
from html import unescape
import json
from pathlib import Path
import re

from build_region_assets import _build_polygon_features

COMMIT = "a7ee5949d8df9879dd081eec21142a37622e9f3a"
GEOJSON_SHA256 = "8bd26502076d77b5d440a30df2c40356ecb5d5ad62309494ade4742246084a02"
BASELINE_SHA256 = "72f24d85b3c7f2bbad03e92f48acc91da86939ca6e26650905e52be8534f7663"
BASELINE_URL = "https://www.fmprc.gov.cn/web/wjb_673085/zzjg_673183/bjhysws_674671/bhsmgb/201209/t20120910_320427.shtml"
EXTRA_SEAS = {677, 785, 901, 902, 903, 904, 905, 906, 907, 908, 909, 911, 913, 914,
              915, 916, 917, 918, 919, 920, 921, 939}
ALIASES = {
    186: "国后岛周边海域", 187: "择捉岛周边海域",
    191: "十胜海域", 193: "苫小牧海域", 487: "远州滩",
    # These are only epicentral naming polygons. Their extent is not a claim
    # about jurisdiction. China/CWA names and the official baselines win first.
    858: "东海", 859: "东海", 860: "东海",
    906: "萨哈林岛（库页岛）西部海域",
    939: "萨哈林岛（库页岛）周边海域",
}


def checked(path: Path, expected: str) -> bytes:
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != expected:
        raise ValueError(f"Unreviewed source version: {path}")
    return data


def sea_name(properties: dict) -> str:
    code = properties["id"]
    if code in ALIASES:
        return ALIASES[code]
    name = properties["name_zh-cn"]
    for before, after in [("南西", "西南"), ("北西", "西北"),
                          ("南东", "东南"), ("北东", "东北"),
                          ("南東", "东南"), ("南方", "以南"),
                          ("北方", "以北"), ("东方", "以东"),
                          ("西方", "以西"), ("諸", "诸")]:
        name = name.replace(before, after)
    name = re.sub(r"附近$", "周边海域", name)
    return re.sub(r"[冲沖]$", "海域", name)


def baseline_features(baseline: Path) -> list[dict]:
    html = checked(baseline, BASELINE_SHA256).decode('utf-8')
    text = unescape(re.sub(r'<[^>]+>', ' ', html))
    pairs = re.findall(r'北纬\s*(\d+)°\s*([\d.]+)′\s*东经\s*(\d+)°\s*([\d.]+)′', text)
    if len(pairs) != 19:raise ValueError('Unexpected official baseline coordinate table')
    points = [[int(lon) + float(lonm)/60, int(lat) + float(latm)/60] for lat,latm,lon,lonm in pairs]
    result=[]
    for group,ring in [('diaoyu_huangwei',points[:13]),('chiwei',points[13:])]:
        if ring[0]!=ring[-1]:raise ValueError('Official baseline is not closed')
        result.append({'type':'Feature','properties':{'displayName':'钓鱼岛及其附属岛屿','group':group},'geometry':{'type':'Polygon','coordinates':[ring]}})
    return result

def build(source: Path, baseline: Path, output: Path) -> dict:
    raw = json.loads(checked(source, GEOJSON_SHA256))
    if raw["type"] != "FeatureCollection" or len(raw["features"]) != 332:
        raise ValueError("Unexpected JMA region source structure")
    selected = []
    for feature in raw["features"]:
        p = feature["properties"]
        code = p["id"]
        if (100 <= code < 900 and re.search(r"(?:沖|近海|湾|灘|水道|海峡|付近)$", p["name"])) or code in EXTRA_SEAS:
            selected.append(feature)
    codes = [f["properties"]["id"] for f in selected]
    if len(selected) != 120:
        raise ValueError("Unexpected reviewed sea-region count")
    if len(codes) != len(set(codes)):
        raise ValueError("Duplicate selected sea-region codes")
    # HTML is retained byte-for-byte. Parse the coordinates actually published
    # by China; do not invent island extents from points or draw buffers.
    baselines = baseline_features(baseline)
    output.mkdir(parents=True, exist_ok=True)
    _build_polygon_features(selected, output / "japan_sea_regions.bin",
                            lambda f: sea_name(f["properties"]))
    _build_polygon_features(baselines, output / "diaoyu_baseline_regions.bin",
                            lambda f: f["properties"]["displayName"],double_precision=True)
    manifest = {
        "purpose": "Offline epicentral place names only; not territorial/EEZ boundaries or map rendering",
        "source": "0Quake/JMA_Region: third-party tracing of JMA official epicenter maps, NOT official vector data",
        "commit": COMMIT, "sourceSha256": GEOJSON_SHA256,
        "sourceUrl": f"https://github.com/0Quake/JMA_Region/tree/{COMMIT}",
        "officialReference": "https://www.jma.go.jp/jma/press/0609/20b/20060920bessi3.pdf",
        "license": "CC0-1.0; JMA source attribution retained",
        "baselineUrl": BASELINE_URL, "baselineSha256": BASELINE_SHA256,
        "baselineMeaning": "Area enclosed by published baseline only, not the entire territorial sea or exact island shoreline",
        "baselineFormat":"CWR2 Float64; coordinates from official table, no Float32 rounding",
        "geometryProcessing": "Original selected polygons/rings; no simplification or buffers; existing CWR1 Float32 storage",
        "count": len(selected), "regions": [
            {"code": f["properties"]["id"], "sourceName": f["properties"]["name"],
             "sourceChineseName": f["properties"]["name_zh-cn"], "displayName": sea_name(f["properties"])}
            for f in sorted(selected, key=lambda f: f["properties"]["id"])],
        "outputs": {n: {"bytes": (output / n).stat().st_size,
                         "sha256": hashlib.sha256((output / n).read_bytes()).hexdigest()}
                    for n in ["japan_sea_regions.bin", "diaoyu_baseline_regions.bin"]},
    }
    (output / "japan_sea_regions.provenance.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=Path("references/region_data/jma/震央地名.geojson"))
    parser.add_argument("--baseline", type=Path, default=Path("references/region_data/official/diaoyu_baselines_20120910.original.html"))
    parser.add_argument("--output-dir", type=Path, default=Path("assets/regions"))
    args = parser.parse_args()
    result = build(args.source, args.baseline, args.output_dir)
    print(json.dumps({"regions": result["count"], "outputs": result["outputs"]}, ensure_ascii=False))
