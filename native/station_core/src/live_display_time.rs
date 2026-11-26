use crate::unified_event_runtime::WorkerClock;
use std::sync::OnceLock;

#[no_mangle]
pub extern "C" fn rq_live_display_elapsed_us() -> i64 {
    static CLOCK: OnceLock<WorkerClock> = OnceLock::new();
    CLOCK.get_or_init(WorkerClock::new).elapsed_us()
}

#[no_mangle]
pub extern "C" fn rq_live_display_lifetime_us(kind: u8) -> i64 {
    let minutes = match kind {
        0 => 2,    // Automatic USGS products
        1 => 1440, // Weather alarms without a source expiry
        2 => 5,    // JMA advisory
        3 => 3,    // JMA investigation ended
        4 => return crate::station_runtime::SEISJS_STATION_MAX_AGE_MS * 1_000,
        _ => return 0,
    };
    minutes * 60 * 1_000_000
}
