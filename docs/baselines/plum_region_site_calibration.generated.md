# PLUM Region/Site Calibration Diagnostic

- Status: `pass`
- Split: `validation`
- Frozen test evaluated: `false`
- Production ready: `false`
- Raw predicted intensity mutated: `false`
- Station forecasts: `185694`

## Method

- This report does not suppress, cap, replace, or hide predicted intensity.
- It builds a calibration table over `region` (estimated-source latitude band) x `site` (station latitude band) for high-threshold predictions, and maps each non-empty joint bucket to an empirical confidence band.
- region uses the **estimated** source latitude (production-available), not the truth latitude; site uses station latitude as a coarse site-amplification proxy.
- Confidence bands are diagnostic labels only; they do not change the raw predicted intensity field and must not feed notifications or UI wording until explicit wording-only acceptance criteria exist.

## Bucket Definitions

- region bands: `[hokkaido, tohoku, kanto_chubu, west_south]`
- site bands: `[hokkaido, tohoku, kanto_chubu, west_south]`
- region source: `estimated_source_latitude`
- site source: `station_latitude`

## Band Definitions

| Band | Min empirical precision |
| --- | ---: |
| `high` | `75.0%` |
| `medium` | `55.0%` |
| `low` | `0.0%` |
- Min sample for band assignment: `20`

## `shindo4`

- Baseline P/R/F1: `55.9% / 72.5% / 63.1%`

### Marginal Region Precision

| Region | Pred+ | TP | FP | Precision |
| --- | ---: | ---: | ---: | ---: |
| `kanto_chubu` | 1677 | 897 | 780 | 53.5% |
| `tohoku` | 4921 | 2884 | 2037 | 58.6% |
| `west_south` | 193 | 42 | 151 | 21.8% |
| `hokkaido` | 48 | 1 | 47 | 2.1% |

### Marginal Site Precision

| Site | Pred+ | TP | FP | Precision |
| --- | ---: | ---: | ---: | ---: |
| `kanto_chubu` | 3374 | 2011 | 1363 | 59.6% |
| `tohoku` | 3224 | 1770 | 1454 | 54.9% |
| `west_south` | 193 | 42 | 151 | 21.8% |
| `hokkaido` | 48 | 1 | 47 | 2.1% |

### Joint Calibration Table

| Region | Site | Pred+ | TP | FP | Precision | Band |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `hokkaido` | `hokkaido` | 48 | 1 | 47 | 2.1% | `low` |
| `kanto_chubu` | `kanto_chubu` | 1676 | 896 | 780 | 53.5% | `low` |
| `kanto_chubu` | `tohoku` | 1 | 1 | 0 | 100.0% | `insufficient` |
| `tohoku` | `kanto_chubu` | 1698 | 1115 | 583 | 65.7% | `medium` |
| `tohoku` | `tohoku` | 3223 | 1769 | 1454 | 54.9% | `low` |
| `west_south` | `west_south` | 193 | 42 | 151 | 21.8% | `low` |

### Band Summary

| Band | Buckets | Pred+ | TP | FP | Precision |
| --- | ---: | ---: | ---: | ---: | ---: |
| `high` | 0 | 0 | 0 | 0 | 0.0% |
| `medium` | 1 | 1698 | 1115 | 583 | 65.7% |
| `low` | 4 | 5140 | 2708 | 2432 | 52.7% |
| `insufficient` | 1 | 1 | 1 | 0 | 100.0% |

## `shindo5-`

- Baseline P/R/F1: `58.8% / 46.9% / 52.2%`

### Marginal Region Precision

| Region | Pred+ | TP | FP | Precision |
| --- | ---: | ---: | ---: | ---: |
| `tohoku` | 573 | 422 | 151 | 73.6% |
| `west_south` | 3 | 0 | 3 | 0.0% |
| `kanto_chubu` | 205 | 37 | 168 | 18.0% |

### Marginal Site Precision

| Site | Pred+ | TP | FP | Precision |
| --- | ---: | ---: | ---: | ---: |
| `tohoku` | 447 | 322 | 125 | 72.0% |
| `kanto_chubu` | 331 | 137 | 194 | 41.4% |
| `west_south` | 3 | 0 | 3 | 0.0% |

### Joint Calibration Table

| Region | Site | Pred+ | TP | FP | Precision | Band |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `kanto_chubu` | `kanto_chubu` | 205 | 37 | 168 | 18.0% | `low` |
| `tohoku` | `kanto_chubu` | 126 | 100 | 26 | 79.4% | `high` |
| `tohoku` | `tohoku` | 447 | 322 | 125 | 72.0% | `medium` |
| `west_south` | `west_south` | 3 | 0 | 3 | 0.0% | `insufficient` |

### Band Summary

| Band | Buckets | Pred+ | TP | FP | Precision |
| --- | ---: | ---: | ---: | ---: | ---: |
| `high` | 1 | 126 | 100 | 26 | 79.4% |
| `medium` | 1 | 447 | 322 | 125 | 72.0% |
| `low` | 1 | 205 | 37 | 168 | 18.0% |
| `insufficient` | 1 | 3 | 0 | 3 | 0.0% |

## Decision

- Production remains blocked.
- Frozen test remains closed.
- Use the region/site calibration table to design a future wording-only confidence layer; do not replace, cap, or hide predicted intensity.

