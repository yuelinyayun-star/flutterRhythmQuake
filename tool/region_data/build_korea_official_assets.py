#!/usr/bin/env python3
"""Compile the unchanged official SGIS 2025 land polygons to the existing CWR1 format."""
import argparse
import hashlib
import json
from pathlib import Path

from build_region_assets import _build_polygon_features, _iter_polygons

SOURCE_URL = "https://sgis.mods.go.kr/js/data/geo_sido_2025.js"
SOURCE_SHA256 = "ebf9456e7f6d53a14088b1bfe56fd1be4c5c1b8c15ac44f4b59b75e42e897b17"
NAMES = {
    "11": ("서울특별시", "首尔特别市"), "21": ("부산광역시", "釜山广域市"),
    "22": ("대구광역시", "大邱广域市"), "23": ("인천광역시", "仁川广域市"),
    "24": ("광주광역시", "光州广域市"), "25": ("대전광역시", "大田广域市"),
    "26": ("울산광역시", "蔚山广域市"), "29": ("세종특별자치시", "世宗特别自治市"),
    "31": ("경기도", "京畿道"), "32": ("강원특별자치도", "江原特别自治道"),
    "33": ("충청북도", "忠清北道"), "34": ("충청남도", "忠清南道"),
    "35": ("전북특별자치도", "全北特别自治道"), "36": ("전라남도", "全罗南道"),
    "37": ("경상북도", "庆尚北道"), "38": ("경상남도", "庆尚南道"),
    "39": ("제주특별자치도", "济州特别自治道"),
}


def build(source: Path, output: Path) -> dict:
    import pyproj
    from pyproj import Transformer
    pyproj.network.set_network_enabled(False)
    data = source.read_bytes()
    if hashlib.sha256(data).hexdigest() != SOURCE_SHA256:
        raise ValueError("Unreviewed official SGIS source version")
    raw = json.loads(data)
    if raw["type"] != "FeatureCollection" or raw["errCd"] != 0 or len(raw["features"]) != 17:
        raise ValueError("Unexpected official SGIS response")
    transform = Transformer.from_crs("EPSG:5179", "EPSG:4326", always_xy=True)
    features = []
    manifest = []
    neutral_polygons = []
    # Source geometry is geographic land data, not marine forecast/EEZ zones.
    for feature in raw["features"]:
        p = feature["properties"]
        code = p["adm_cd"]
        if p["adm_nm"] != NAMES[code][0]:
            raise ValueError(f"Unreviewed administrative name: {p}")
        polygons = []
        for part_index, polygon in enumerate(_iter_polygons(feature["geometry"])):
            rings = []
            for ring in polygon:
                if ring[0] != ring[-1]:
                    raise ValueError(f"Unclosed source polygon: {code}")
                converted = [list(transform.transform(*point)) for point in ring]
                if any(not (123 < lon < 133 and 32 < lat < 40) for lon, lat in converted):
                    raise ValueError(f"Unexpected projected extent: {code}")
                rings.append(converted)
            if code == "37" and part_index in (1, 2):
                # The pinned source attaches Dokdo/Takeshima to Gyeongbuk.
                # Keep both complete original island polygons but use only a
                # geographic display name, without assigning disputed ownership.
                if not all(131.85 < lon < 131.88 and 37.23 < lat < 37.26 for lon, lat in rings[0]):
                    raise ValueError("Unreviewed disputed island geometry")
                neutral_polygons.append(rings)
            else:
                polygons.append(rings)
        features.append({"type": "Feature", "properties": {"displayName": "韩国" + NAMES[code][1]},
                         "geometry": {"type": "MultiPolygon", "coordinates": polygons}})
        manifest.append({"code": code, "sourceName": p["adm_nm"], "displayName": "韩国" + NAMES[code][1]})
    if {p["code"] for p in manifest} != set(NAMES):
        raise ValueError("Incomplete or duplicate SGIS units")
    if len(neutral_polygons) != 2:
        raise ValueError("Unreviewed disputed island parts")
    features.append({"type": "Feature", "properties": {"displayName": "独岛（竹岛）"},
                     "geometry": {"type": "MultiPolygon", "coordinates": neutral_polygons}})
    output.mkdir(parents=True, exist_ok=True)
    destination = output / "korea_land_regions.bin"
    _build_polygon_features(features, destination, lambda f: f["properties"]["displayName"])
    result = {
        "source": "Official SGIS public website's 2025 provincial/municipal boundary data",
        "sourceUrl": SOURCE_URL, "sourceSha256": SOURCE_SHA256,
        "sourceCRS": "EPSG:5179 (UTM-K, KGD2002/GRS80)", "outputCRS": "EPSG:4326",
        "coordinateProcessing": "pyproj 3.7.2, always_xy, offline transform; no simplification, clipping or buffers; CWR1 Float32 storage",
        "officialDataIndex": "https://link.mods.go.kr/view/pss/openDataIntrcn",
        "year": 2025, "count": 17, "compiledFeatures": len(features), "regions": manifest,
        "neutralGeographicParts": {"sourceCode": "37", "sourcePolygonIndices": [1, 2],
                                   "displayName": "独岛（竹岛）", "pointsChanged": False,
                                   "reference": "https://www.mfa.gov.cn/fyrbt_673021/dhdw_673027/201208/t20120824_5432741.shtml"},
        "purpose": "Land place-name lookup only, not national borders, marine epicentral regions or EEZ claims",
        "marine": "Existing FE geographic regions retained; KMA reference-place/direction/distance text is not polygon data",
        "output": {"bytes": destination.stat().st_size, "sha256": hashlib.sha256(destination.read_bytes()).hexdigest()},
    }
    (output / "korea_land_regions.provenance.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=Path("references/region_data/kma/geo_sido_2025.original.js"))
    parser.add_argument("--output-dir", type=Path, default=Path("assets/regions"))
    args = parser.parse_args()
    result = build(args.source, args.output_dir)
    print(json.dumps({"count": result["count"], "output": result["output"]}, ensure_ascii=False))
