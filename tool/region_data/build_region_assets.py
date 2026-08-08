#!/usr/bin/env python3
"""Build compact runtime assets for offline epicenter place-name lookup."""

from __future__ import annotations

import argparse
import collections
import json
import math
import re
import struct
from pathlib import Path
from typing import Any, Callable, Iterable


MAGIC_CHINA = b"CPR1"
MAGIC_BBOX = b"BBR1"
MAGIC_CWA = b"CWR1"
VERSION = 1
MISSING_REGION = 0xFFFF


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _align(data: bytearray, alignment: int = 4) -> None:
    padding = (-len(data)) % alignment
    if padding:
        data.extend(b"\0" * padding)


def _encode_strings(values: Iterable[str]) -> tuple[bytes, list[int]]:
    encoded = bytearray()
    offsets = [0]
    for value in values:
        encoded.extend(value.encode("utf-8"))
        offsets.append(len(encoded))
    return bytes(encoded), offsets


def _write_string_section(data: bytearray, strings: list[str]) -> int:
    offset = len(data)
    encoded, offsets = _encode_strings(strings)
    for item in offsets:
        data.extend(struct.pack("<I", item))
    data.extend(encoded)
    _align(data)
    return offset


def build_china(source: Path, destination: Path) -> None:
    raw = _load_json(source)
    if raw.get("lookup_mode") != "grid":
        raise ValueError("china_place_index must use grid lookup")
    grid = raw["grid"]
    rows = int(grid["rows"])
    cols = int(grid["cols"])
    table = grid["table"]
    regions = raw["regions"]
    if len(table) != rows * cols:
        raise ValueError("china grid dimensions do not match table length")
    if len(regions) >= MISSING_REGION:
        raise ValueError("china region table does not fit uint16")

    names = [str(region["place_name"]).strip() for region in regions]
    if any(not name for name in names):
        raise ValueError("china place_name must not be empty")

    data = bytearray(72)
    string_offset = _write_string_section(data, names)
    grid_offset = len(data)
    for value in table:
        region_id = MISSING_REGION if value is None or int(value) < 0 else int(value)
        if region_id != MISSING_REGION and region_id >= len(names):
            raise ValueError(f"china grid region index out of range: {region_id}")
        data.extend(struct.pack("<H", region_id))

    struct.pack_into(
        "<4sI4d7I",
        data,
        0,
        MAGIC_CHINA,
        VERSION,
        float(grid["lat_min"]),
        float(grid["lon_min"]),
        float(grid["lat_step"]),
        float(grid["lon_step"]),
        rows,
        cols,
        len(names),
        string_offset,
        grid_offset,
        len(table),
        MISSING_REGION,
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)


def _bbox_regions(raw: Any) -> list[dict[str, Any]]:
    if isinstance(raw, list):
        return raw
    if isinstance(raw, dict) and isinstance(raw.get("regions"), list):
        return raw["regions"]
    raise ValueError("bbox source must be a list or contain a regions list")


def build_bbox(source: Path, destination: Path) -> None:
    regions = _bbox_regions(_load_json(source))
    normalized: list[tuple[str, float, float, float, float, int]] = []
    for order, region in enumerate(regions):
        name = str(region["name"]).strip()
        lat_min = float(region["lat_min"])
        lat_max = float(region["lat_max"])
        lon_min = float(region["lon_min"])
        lon_max = float(region["lon_max"])
        values = (lat_min, lat_max, lon_min, lon_max)
        if not name or not all(math.isfinite(value) for value in values):
            raise ValueError(f"invalid bbox region at index {order}")
        if lat_min > lat_max or lon_min > lon_max:
            raise ValueError(f"reversed bbox at index {order}")
        normalized.append((name, lat_min, lat_max, lon_min, lon_max, order))

    names = list(dict.fromkeys(item[0] for item in normalized))
    name_indices = {name: index for index, name in enumerate(names)}
    data = bytearray(32)
    string_offset = _write_string_section(data, names)
    record_offset = len(data)
    for name, lat_min, lat_max, lon_min, lon_max, order in normalized:
        data.extend(
            struct.pack(
                "<4f2I",
                lat_min,
                lat_max,
                lon_min,
                lon_max,
                name_indices[name],
                order,
            )
        )

    struct.pack_into(
        "<4s6I",
        data,
        0,
        MAGIC_BBOX,
        VERSION,
        len(normalized),
        len(names),
        string_offset,
        record_offset,
        24,
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)


def _cwa_display_name(properties: dict[str, Any]) -> str:
    category = str(properties.get("類型", "")).strip()
    county = str(properties.get("COUNTYNAME", "")).strip()
    town = str(properties.get("TOWNNAME", "")).strip()
    if category == "陆地":
        return f"{county}{town}"
    if category == "近岸海域":
        return f"{county}近岸海域"
    if category == "海域":
        return county
    raise ValueError(f"unsupported CWA region type: {category!r}")


def _iter_polygons(geometry: dict[str, Any]) -> list[list[list[list[float]]]]:
    geometry_type = geometry.get("type")
    coordinates = geometry.get("coordinates")
    if geometry_type == "Polygon":
        return [coordinates]
    if geometry_type == "MultiPolygon":
        return coordinates
    raise ValueError(f"unsupported CWA geometry type: {geometry_type!r}")


def _build_polygon_features(
    features_source: list[dict[str, Any]],
    destination: Path,
    display_name: Callable[[dict[str, Any]], str],
) -> None:
    features: list[dict[str, Any]] = []
    polygons: list[tuple[int, int]] = []
    rings: list[tuple[int, int]] = []
    points: list[tuple[float, float]] = []
    display_names: list[str] = []

    for order, feature in enumerate(features_source):
        name = display_name(feature)
        if not name:
            raise ValueError(f"polygon feature has an empty name: {order}")
        display_names.append(name)
        feature_polygon_start = len(polygons)
        min_lon = min_lat = math.inf
        max_lon = max_lat = -math.inf
        for polygon in _iter_polygons(feature["geometry"]):
            polygon_ring_start = len(rings)
            for ring in polygon:
                if len(ring) < 4:
                    raise ValueError(f"polygon ring has fewer than four points: {order}")
                ring_point_start = len(points)
                for coordinate in ring:
                    lon = float(coordinate[0])
                    lat = float(coordinate[1])
                    if not math.isfinite(lon) or not math.isfinite(lat):
                        raise ValueError(f"invalid polygon coordinate: {order}")
                    points.append((lon, lat))
                    min_lon = min(min_lon, lon)
                    max_lon = max(max_lon, lon)
                    min_lat = min(min_lat, lat)
                    max_lat = max(max_lat, lat)
                rings.append((ring_point_start, len(ring)))
            polygons.append((polygon_ring_start, len(polygon)))
        features.append(
            {
                "bbox": (min_lat, max_lat, min_lon, max_lon),
                "name": name,
                "polygon_start": feature_polygon_start,
                "polygon_count": len(polygons) - feature_polygon_start,
                "order": order,
            }
        )

    names = list(dict.fromkeys(display_names))
    name_indices = {name: index for index, name in enumerate(names)}
    data = bytearray(64)
    string_offset = _write_string_section(data, names)
    feature_offset = len(data)
    for feature in features:
        data.extend(
            struct.pack(
                "<4f4I",
                *feature["bbox"],
                name_indices[feature["name"]],
                feature["polygon_start"],
                feature["polygon_count"],
                feature["order"],
            )
        )
    polygon_offset = len(data)
    for ring_start, ring_count in polygons:
        data.extend(struct.pack("<2I", ring_start, ring_count))
    ring_offset = len(data)
    for point_start, point_count in rings:
        data.extend(struct.pack("<2I", point_start, point_count))
    point_offset = len(data)
    for lon, lat in points:
        data.extend(struct.pack("<2f", lon, lat))

    struct.pack_into(
        "<4s14I",
        data,
        0,
        MAGIC_CWA,
        VERSION,
        len(features),
        len(polygons),
        len(rings),
        len(points),
        len(names),
        string_offset,
        feature_offset,
        polygon_offset,
        ring_offset,
        point_offset,
        32,
        8,
        8,
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)


def build_cwa(source: Path, destination: Path) -> None:
    raw = _load_json(source)
    if raw.get("type") != "FeatureCollection":
        raise ValueError("CWA source must be a GeoJSON FeatureCollection")
    _build_polygon_features(
        raw["features"],
        destination,
        lambda feature: _cwa_display_name(feature.get("properties", {})),
    )


def _province_names(china_index: Path) -> dict[int, str]:
    raw = _load_json(china_index)
    candidates: dict[int, collections.Counter[str]] = collections.defaultdict(
        collections.Counter
    )
    for region in raw["regions"]:
        adcode = int(region["adcode"])
        province = str(region.get("province", "")).strip()
        if province:
            candidates[adcode // 10000][province] += 1
    return {
        prefix: counts.most_common(1)[0][0] for prefix, counts in candidates.items()
    }


def build_china_admin(
    source: Path,
    china_index: Path,
    destination: Path,
) -> None:
    raw = _load_json(source)
    if raw.get("type") != "FeatureCollection":
        raise ValueError("China admin source must be a GeoJSON FeatureCollection")
    provinces = _province_names(china_index)
    features: list[dict[str, Any]] = []
    names: dict[int, str] = {}
    for feature in raw["features"]:
        properties = feature.get("properties", {})
        adcode_text = str(properties.get("adcode", ""))
        if not adcode_text.isdigit():
            continue
        adcode = int(adcode_text)
        if adcode // 10000 == 71:
            # Taiwan uses the more detailed CWA town and sea polygons.
            continue
        name = str(properties.get("name", "")).strip()
        province = provinces.get(adcode // 10000, "")
        if not name or not province:
            raise ValueError(f"missing China admin name for adcode {adcode}")
        names[id(feature)] = name if name.startswith(province) else f"{province}{name}"
        features.append(feature)
    _build_polygon_features(
        features,
        destination,
        lambda feature: names[id(feature)],
    )


def build_japan_land(source: Path, destination: Path) -> None:
    raw = _load_json(source)
    if raw.get("type") != "FeatureCollection":
        raise ValueError("Japan source must be a GeoJSON FeatureCollection")
    _build_polygon_features(
        raw["features"],
        destination,
        lambda feature: str(
            feature.get("properties", {}).get("N03_001", "日本")
        ).strip(),
    )


def update_embedded_fe(source: Path, dart_file: Path) -> None:
    raw = _load_json(source)
    expected = [value for row in raw["grid"]["table"] for value in row]
    names = [str(value) for value in raw["grid"]["names"]]
    if len(expected) != 180 * 360 or len(names) != 758:
        raise ValueError("unexpected FE grid or name count")

    text = dart_file.read_bytes().decode("utf-8")
    grid_match = re.search(
        r"Uint16List\.fromList\(\[(.*?)\]\);",
        text,
        flags=re.DOTALL,
    )
    if grid_match is None:
        raise ValueError("could not locate embedded FE grid")
    grid_text = grid_match.group(1)
    number_matches = list(re.finditer(r"\d+", grid_text))
    if len(number_matches) != len(expected):
        raise ValueError("embedded FE grid length does not match source")

    replacements: list[tuple[int, int, str]] = []
    for index, match in enumerate(number_matches):
        if int(match.group()) != expected[index]:
            replacements.append((match.start(), match.end(), str(expected[index])))
    for start, end, value in reversed(replacements):
        grid_text = grid_text[:start] + value + grid_text[end:]
    text = text[: grid_match.start(1)] + grid_text + text[grid_match.end(1) :]

    text = text.replace("'\u200c加拿大育空地区南部'", "'加拿大育空地区南部'")
    dart_file.write_bytes(text.encode("utf-8"))
    print(
        f"{dart_file}: corrected {len(replacements)} FE grid cells and UTF-8 names"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=Path("references/region_data"),
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("assets/regions"),
    )
    parser.add_argument(
        "--map-dir",
        type=Path,
        default=Path("assets/maps"),
    )
    parser.add_argument(
        "--fe-dart",
        type=Path,
        default=Path("lib/utils/fe_regions.dart"),
    )
    args = parser.parse_args()

    build_china(
        args.source_dir / "china_place_index.json",
        args.output_dir / "china_place_index.bin",
    )
    build_china_admin(
        args.map_dir / "中华人民共和国.geojson",
        args.source_dir / "china_place_index.json",
        args.output_dir / "china_admin_regions.bin",
    )
    build_japan_land(
        args.map_dir / "japan_prefectures.geojson",
        args.output_dir / "japan_land_regions.bin",
    )
    build_bbox(
        args.source_dir / "korea_region_data.json",
        args.output_dir / "korea_regions.bin",
    )
    build_bbox(
        args.source_dir / "us_mexico_region_data.json",
        args.output_dir / "us_mexico_regions.bin",
    )
    build_cwa(
        args.source_dir / "CWA震央名.geojson",
        args.output_dir / "cwa_epicenter_regions.bin",
    )
    update_embedded_fe(
        args.source_dir / "fe_fix_region_data.json",
        args.fe_dart,
    )

    for path in sorted(args.output_dir.glob("*.bin")):
        print(f"{path}: {path.stat().st_size} bytes")


if __name__ == "__main__":
    main()
