const REGIONS: u32 = 0b111;
const RETRYING: u32 = 1 << 3;
const UNKNOWN_READY_MS: u32 = 15_001;

#[derive(Clone, Copy)]
struct Candidate {
    regions: u32,
    feeds: u32,
    ready_ms: u32,
}

impl Candidate {
    fn usable_regions(self) -> u32 {
        if self.regions & RETRYING == 0 {
            self.regions & REGIONS
        } else {
            0
        }
    }
}

fn select(rows: &[Candidate]) -> u32 {
    if !rows.iter().any(|row| row.regions & REGIONS != 0) {
        // A single supplementary EEW API is useful when no configured API
        // covers the priority regions. Catalog-only sources have no feeds.
        return rows
            .iter()
            .enumerate()
            .filter(|(_, row)| row.feeds != 0)
            .max_by_key(|(index, row)| {
                (
                    row.regions & RETRYING == 0,
                    row.feeds.count_ones(),
                    std::cmp::Reverse(row.ready_ms.min(UNKNOWN_READY_MS)),
                    std::cmp::Reverse(*index),
                )
            })
            .map_or(0, |(index, _)| 1 << index);
    }
    let mut best_score = None;
    let mut best_mask = 0;
    for (i, &first) in rows.iter().enumerate() {
        let first_regions = first.regions & REGIONS;
        if first_regions == 0 {
            continue;
        }
        for j in i..rows.len() {
            let second = (i != j).then(|| rows[j]);
            if second.is_some_and(|row| row.regions & REGIONS == 0) {
                continue;
            }
            let first_usable = first.usable_regions();
            let second_usable = second.map_or(0, Candidate::usable_regions);
            let coverage = first_usable | second_usable;
            let usable_feeds = if first_usable == 0 { 0 } else { first.feeds }
                | second
                    .filter(|_| second_usable != 0)
                    .map_or(0, |row| row.feeds);
            let ready_ms = first.ready_ms.min(UNKNOWN_READY_MS)
                + second.map_or(0, |row| row.ready_ms.min(UNKNOWN_READY_MS));
            let score = (
                (first_usable | second_usable).count_ones(),
                coverage.count_ones(),
                (first_usable & second_usable).count_ones(),
                usable_feeds.count_ones(),
                second.is_none(),
                std::cmp::Reverse(ready_ms),
            );
            if best_score.is_none_or(|best| score > best) {
                best_score = Some(score);
                best_mask = (1 << i) | (1 << j);
            }
        }
    }
    best_mask
}

/// `rows` is `count * 3` aligned words: region/retry mask, feed mask, readiness
/// in milliseconds (u32::MAX when unavailable). No pointer is retained.
#[no_mangle]
pub unsafe extern "C" fn rq_background_api_select(rows: *const u32, count: usize) -> u32 {
    if rows.is_null() || count == 0 || count > u32::BITS as usize {
        return 0;
    }
    let rows = unsafe { std::slice::from_raw_parts(rows, count * 3) };
    let candidates: Vec<_> = rows
        .chunks_exact(3)
        .map(|row| Candidate {
            regions: row[0],
            feeds: row[1],
            ready_ms: row[2],
        })
        .collect();
    select(&candidates)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn api(regions: u32, feeds: u32, ready_ms: u32) -> Candidate {
        Candidate {
            regions,
            feeds,
            ready_ms,
        }
    }

    #[test]
    fn chooses_joint_priority_coverage_before_speed_and_supplementary_feeds() {
        assert_eq!(
            select(&[api(1, 1, 10), api(6, 6, 900), api(0, 8, 1)]),
            0b011
        );
        assert_eq!(select(&[api(7, 7, 10), api(0, 8, 1)]), 0b001);
        assert_eq!(select(&[api(0, 0, 1)]), 0);
        assert_eq!(select(&[api(0, 8, 1), api(0, 24, 3), api(0, 0, 1)]), 0b010);
    }

    #[test]
    fn prefers_feed_breadth_then_observed_latency_at_equal_coverage() {
        assert_eq!(
            select(&[api(7, 15, 500), api(7, 7, u32::MAX), api(7, 7, 20)]),
            0b101
        );
        assert_eq!(
            select(&[api(7, 7, 5), api(7, 7, 10), api(7, 15, 500)]),
            0b101
        );
    }

    #[test]
    fn replaces_an_unusable_api_but_keeps_retrying_unique_coverage() {
        let failed_full = api(7 | RETRYING, 7, 5);
        let healthy_full = api(7, 7, 500);
        let healthy_partial = api(1, 1, 50);
        assert_eq!(select(&[failed_full, healthy_full]), 0b10);
        assert_eq!(select(&[failed_full, healthy_partial]), 0b10);
        assert_eq!(select(&[failed_full]), 0b1);
    }
}
