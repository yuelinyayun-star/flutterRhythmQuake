#!/usr/bin/env python3
"""Compile unchanged official land geometry with separate domestic display names.

Build-only dependencies: pyshp==2.3.1, opencc-python-reimplemented==0.1.7.
No shapefile parser or Chinese conversion library is shipped in the app.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import zipfile
from pathlib import Path

import shapefile
from opencc import OpenCC

from build_region_assets import _build_polygon_features, _province_names

SOURCE_SHA256 = "e028e5a750eee48cf7913330655e5e5c5bb1f176868fbd0afdfc661fca60557c"
SOURCE_URL = "https://maps.nlsc.gov.tw/download/鄉鎮市區界線(TWD97經緯度).zip"
MAIN_LAYER = "TOWN_MOI_1120317"
SUPPLEMENT = "Town_Majia_Sanhe"


def domestic_display_name(properties: dict[str, str], converter: OpenCC) -> str:
    county, town = properties["COUNTYNAME"], properties.get("TOWNNAME", "")
    # Source jurisdiction fields are retained verbatim. These strings are
    # presentation aliases, never written back to the source DBF/geometry.
    if county == "金門縣":
        if town == "烏坵鄉":
            return "福建省莆田市秀屿区乌丘屿"
        return "福建省泉州市金门县" + converter.convert(town)
    if county == "連江縣":
        return "福建省福州市连江县马祖列岛" + converter.convert(town).removesuffix("乡")
    taiwan_counties = {
        "臺北市", "新北市", "桃園市", "臺中市", "臺南市", "高雄市", "基隆市",
        "新竹市", "嘉義市", "新竹縣", "苗栗縣", "彰化縣", "南投縣", "雲林縣",
        "嘉義縣", "屏東縣", "宜蘭縣", "花蓮縣", "臺東縣", "澎湖縣",
    }
    if county not in taiwan_counties:
        raise ValueError(f"Unreviewed source jurisdiction: {county!r}")
    return "台湾省" + converter.convert(county + town)


def read_land(source: Path) -> list[dict]:
    if hashlib.sha256(source.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise ValueError("Official package hash changed; review the new version first")
    result = []
    converter = OpenCC("t2s")
    with zipfile.ZipFile(source) as archive:
        if archive.testzip() is not None:
            raise ValueError("Damaged official ZIP")
        for layer in (MAIN_LAYER, SUPPLEMENT):
            crs = archive.read(layer + ".prj").decode("utf-8")
            if 'GEOGCS["GCS_TWD97[2020]"' not in crs or 'UNIT["Degree"' not in crs:
                raise ValueError("Unexpected coordinate system; do not reinterpret coordinates")
            reader = shapefile.Reader(
                shp=io.BytesIO(archive.read(layer + ".shp")),
                shx=io.BytesIO(archive.read(layer + ".shx")),
                dbf=io.BytesIO(archive.read(layer + ".dbf")),
                encoding="utf-8",
            )
            for record in reader.iterShapeRecords():
                properties = record.record.as_dict()
                geometry = record.shape.__geo_interface__
                excluded_parts = 0
                if properties["COUNTYNAME"] == "高雄市" and properties["TOWNNAME"] == "旗津區":
                    # This source groups Dongsha/Nansha islands under Qijin.
                    # Do not import that assignment into domestic display names.
                    # Retain the complete mainland Qijin polygon only; never
                    # clip/redraw source rings or alter the original ZIP.
                    parts = [geometry["coordinates"]] if geometry["type"] == "Polygon" else geometry["coordinates"]
                    kept = [p for p in parts if all(lon >= 118 and lat >= 21 for ring in p for lon, lat in ring)]
                    excluded_parts = len(parts) - len(kept)
                    if len(kept) != 1 or excluded_parts != 16:
                        raise ValueError("Qijin source grouping changed; review offshore assignments")
                    geometry = {"type": "Polygon", "coordinates": kept[0]}
                result.append({
                    "type": "Feature",
                    "properties": properties,
                    "geometry": geometry,
                    "displayName": domestic_display_name(properties, converter),
                    "sourceLayer": layer,
                    "excludedOffshoreParts": excluded_parts,
                })
    names = {f["properties"]["TOWNCODE"] for f in result}
    if len(names) != 368 or len(result) != 369:
        raise ValueError(f"Unexpected source coverage: {len(names)} townships / {len(result)} features")
    return result


def build(source: Path, source_dir: Path, map_dir: Path, output_dir: Path) -> dict:
    land = read_land(source)
    provinces = _province_names(source_dir / "china_place_index.json")
    china = json.loads((map_dir / "中华人民共和国.geojson").read_text(encoding="utf-8"))
    features = []
    for feature in china["features"]:
        props = feature.get("properties", {})
        code = str(props.get("adcode", ""))
        if not code.isdigit() or int(code) // 10000 == 71:
            continue
        name, province = props.get("name", ""), provinces.get(int(code) // 10000, "")
        if not name or not province:
            raise ValueError(f"Missing existing administrative name: {code}")
        features.append({**feature, "displayName": name if name.startswith(province) else province + name})
    # The existing minimum-containing-area lookup now sees precise island land
    # polygons before ever falling through to the old coastal/sea layer.
    features.extend(land)
    _build_polygon_features(features, output_dir / "china_admin_regions.bin", lambda f: f["displayName"])

    raw_cwa = json.loads((source_dir / "CWA震央名.geojson").read_text(encoding="utf-8"))
    converter = OpenCC("t2s")
    marine = []
    for feature in raw_cwa["features"]:
        props = feature["properties"]
        if props["類型"] == "陆地":
            continue
        if props["類型"] == "近岸海域":
            name = domestic_display_name(props, converter) + "近岸海域"
        elif props["類型"] == "海域":
            name = converter.convert(props["COUNTYNAME"])
        else:
            raise ValueError(f"Unsupported marine source category: {props['類型']!r}")
        marine.append({**feature, "displayName": name})
    if len(marine) != 23:
        raise ValueError("Unexpected existing marine coverage")
    _build_polygon_features(marine, output_dir / "cwa_epicenter_regions.bin", lambda f: f["displayName"])

    return {
        "sourceUrl": SOURCE_URL,
        "sourceSha256": SOURCE_SHA256,
        "sourceLayers": [MAIN_LAYER, SUPPLEMENT],
        "sourceCrs": "TWD97[2020] geographic degrees; original coordinates retained",
        "landFeatures": len(land), "townshipCount": 368, "marineFeatures": len(marine),
        "names": [{"sourceLayer": f["sourceLayer"], **f["properties"], "displayName": f["displayName"],
                   "excludedOffshoreParts": f["excludedOffshoreParts"]} for f in land],
        "outputs": {p.name: {"bytes": p.stat().st_size, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
                    for p in (output_dir / "china_admin_regions.bin", output_dir / "cwa_epicenter_regions.bin")},
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-zip", type=Path, required=True)
    parser.add_argument("--source-dir", type=Path, default=Path("references/region_data"))
    parser.add_argument("--map-dir", type=Path, default=Path("assets/maps"))
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    manifest = build(args.source_zip, args.source_dir, args.map_dir, args.output_dir)
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in manifest.items() if k != "names"}, ensure_ascii=False, indent=2))
