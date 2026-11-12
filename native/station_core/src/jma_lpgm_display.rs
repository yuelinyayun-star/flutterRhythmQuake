use crate::unified_event_policy::{b, i, jma_lpgm_same_event, s, SECOND};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};

const PREVIEW_US: i64 = 15 * SECOND;

struct Preview {
    signature: String,
    has_regions: bool,
    until: i64,
    finished: bool,
    identity: Value,
}

/// Display projection only. Admission, source records and expiry stay owned by
/// the unified engine; a hidden companion can reappear when its main expires.
#[derive(Default)]
pub struct LpgmDisplay {
    previews: HashMap<String, Preview>,
    pub speech_busy: bool,
    clock: i64,
}

impl LpgmDisplay {
    pub fn next_deadline(&self) -> Option<i64> {
        self.previews
            .values()
            .filter(|v| v.has_regions && v.until > self.clock)
            .map(|v| v.until)
            .min()
    }

    pub fn project(&mut self, active: &[Value], clock: i64) -> Value {
        self.clock = clock;
        let mut retained = HashSet::new();
        let mut hidden = HashSet::new();
        let mut links = vec![];
        for event in active
            .iter()
            .filter(|e| b(e, "isJmaLpgm") && !b(e, "isEew"))
        {
            let bulletin = &event["jmaLpgmBulletin"];
            let id = format!(
                "{}|{}",
                s(event, "$replaySessionId"),
                s(bulletin, "eventId")
            );
            retained.insert(id.clone());
            let signature = s(bulletin, "signature");
            let has_regions = b(bulletin, "hasRegions");
            let preview = self.previews.entry(id).or_insert_with(|| Preview {
                signature: signature.into(),
                has_regions,
                until: clock + PREVIEW_US,
                finished: false,
                identity: bulletin.clone(),
            });
            // A class-only relay must not replace the complete XML's preview,
            // nor extend it each time another transport repeats the same data.
            if has_regions && (!preview.has_regions || preview.signature != signature) {
                preview.signature = signature.into();
                preview.has_regions = true;
                preview.until = clock + PREVIEW_US;
                preview.finished = false;
                preview.identity = bulletin.clone();
            } else if !preview.has_regions {
                preview.identity = bulletin.clone();
            }
            if clock >= preview.until && !self.speech_busy {
                preview.finished = true;
            }
            let matching = active
                .iter()
                .filter(|info| {
                    !b(info, "isJmaLpgm")
                        && s(info, "$replaySessionId") == s(event, "$replaySessionId")
                        && jma_lpgm_same_event(info, &preview.identity)
                })
                .map(|info| i(info, "$token"))
                .collect::<Vec<_>>();
            if matching.is_empty() {
                continue;
            }
            hidden.insert(i(event, "$token"));
            links.push(json!({
                "companion": i(event, "$token"),
                "information": matching,
                "showRegions": preview.has_regions
                    && !preview.finished
                    && (clock < preview.until || self.speech_busy),
            }));
        }
        self.previews.retain(|id, _| retained.contains(id));
        json!({
            "active": active.iter().map(|e| i(e, "$token"))
                .filter(|token| !hidden.contains(token)).collect::<Vec<_>>(),
            "links": links,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn info(source: &str, id: &str, token: i64) -> Value {
        json!({"$token":token,"source":source,"eventId":id,"isEew":false})
    }
    fn companion() -> Value {
        json!({"$token":2,"source":"jmaLpgm","isJmaLpgm":true,
            "jmaLpgmBulletin":{"eventId":"20261108010441","signature":"original",
                "hasRegions":true}})
    }

    #[test]
    fn combined_restores_after_fifteen_seconds_and_speech() {
        let mut state = LpgmDisplay::default();
        let active = vec![info("jmaEqlist", "20261108010441", 1), companion()];
        let first = state.project(&active, 0);
        assert_eq!(first["active"], json!([1]));
        assert_eq!(first["links"][0]["showRegions"], true);
        assert_eq!(state.next_deadline(), Some(PREVIEW_US));
        state.speech_busy = true;
        assert_eq!(
            state.project(&active, PREVIEW_US)["links"][0]["showRegions"],
            true
        );
        assert_eq!(state.next_deadline(), None);
        state.speech_busy = false;
        assert_eq!(
            state.project(&active, PREVIEW_US)["links"][0]["showRegions"],
            false
        );
        state.speech_busy = true;
        assert_eq!(
            state.project(&active, PREVIEW_US + SECOND)["links"][0]["showRegions"],
            false
        );
        // Expiry of the ordinary report reveals the retained standalone event.
        let standalone = state.project(&[companion()], PREVIEW_US + SECOND);
        assert_eq!(standalone["active"], json!([2]));
        assert_eq!(standalone["links"], json!([]));
    }

    #[test]
    fn p2p_is_supported_but_other_information_and_eew_are_untouched() {
        let mut state = LpgmDisplay::default();
        for source in ["jmaEqlist", "p2pJmaEqlist"] {
            let result = state.project(&[info(source, "20261108010441", 1), companion()], 0);
            assert_eq!(result["active"], json!([1]));
        }
        for source in ["cwaEqlist", "cencEqlist", "usgsEqlist", "jmaEew"] {
            let mut ordinary = info(source, "20261108010441", 1);
            ordinary["isEew"] = json!(source == "jmaEew");
            let result = state.project(&[ordinary, companion()], 0);
            assert_eq!(result["active"], json!([1, 2]));
            assert_eq!(result["links"], json!([]));
        }
        let mut replay = companion();
        replay["$replaySessionId"] = json!("replay");
        assert_eq!(
            state.project(&[info("jmaEqlist", "20261108010441", 1), replay], 0,)["links"],
            json!([])
        );
    }

    #[test]
    fn duplicates_do_not_restart_preview_and_new_full_revision_does() {
        let mut state = LpgmDisplay::default();
        let mut active = vec![info("jmaEqlist", "20261108010441", 1), companion()];
        state.project(&active, 0);
        assert_eq!(
            state.project(&active, PREVIEW_US)["links"][0]["showRegions"],
            false
        );
        active[1]["jmaLpgmBulletin"]["signature"] = json!("class-only-relay");
        active[1]["jmaLpgmBulletin"]["hasRegions"] = json!(false);
        assert_eq!(
            state.project(&active, PREVIEW_US)["links"][0]["showRegions"],
            false
        );
        active[1]["jmaLpgmBulletin"]["signature"] = json!("new-full-revision");
        active[1]["jmaLpgmBulletin"]["hasRegions"] = json!(true);
        assert_eq!(
            state.project(&active, PREVIEW_US)["links"][0]["showRegions"],
            true
        );
        assert_eq!(state.next_deadline(), Some(2 * PREVIEW_US));
        state.project(&[], 2 * PREVIEW_US);
        assert_eq!(state.next_deadline(), None);
        assert!(state.previews.is_empty());
    }

    #[test]
    fn class_only_repeat_preserves_the_complete_p2p_identity() {
        let mut state = LpgmDisplay::default();
        let ordinary = json!({"$token":1,"source":"p2pJmaEqlist",
            "eventId":"2026-11-08 01:04:00","timeZone":9,
            "originTime":"2026-11-08T01:04:00",
            "lat":34.9,"lng":137.7,"magnitude":5.7,"depth":40});
        let mut complete = companion();
        complete["jmaLpgmBulletin"]["originEpochUs"] =
            json!(crate::unified_event_policy::instant(&ordinary, "originTime").unwrap());
        for key in ["lat", "lng", "magnitude", "depth"] {
            complete["jmaLpgmBulletin"][key] = ordinary[key].clone();
        }
        assert_eq!(
            state.project(&[ordinary.clone(), complete], 0)["active"],
            json!([1])
        );
        let mut summary = companion();
        summary["jmaLpgmBulletin"]["hasRegions"] = json!(false);
        summary["jmaLpgmBulletin"]["signature"] = json!("class-only");
        let update = state.project(&[ordinary, summary], PREVIEW_US);
        assert_eq!(update["active"], json!([1]));
        assert_eq!(update["links"][0]["showRegions"], false);
    }
}
