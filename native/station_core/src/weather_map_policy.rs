/// Data acquisition serves both display profiles; neither profile can shut off
/// a weather source still requested by the other. No input data is retained.
#[no_mangle]
pub extern "C" fn rq_weather_map_required_sources(general: u32, mobile: u32) -> u32 {
    (general | mobile) & 0x7f
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn profiles_are_independent_and_unknown_bits_cannot_enable_sources() {
        for general in 0..128 {
            for mobile in 0..128 {
                let expected = (0..7).fold(0, |mask, index| {
                    if general & (1 << index) != 0 || mobile & (1 << index) != 0 {
                        mask | (1 << index)
                    } else { mask }
                });
                assert_eq!(rq_weather_map_required_sources(general, mobile), expected);
            }
        }
        assert_eq!(rq_weather_map_required_sources(0x80000000, 0x100), 0);
    }
}
