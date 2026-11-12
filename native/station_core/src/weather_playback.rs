//! Separate, bounded display catalog. Never replaces live source snapshots.
use serde_json::{json, Value};
use std::collections::BTreeMap;

fn epoch(s: &str, offset_hours: i64) -> Option<i64> {
    if s.len() != 14 || !s.bytes().all(|b| b.is_ascii_digit()) { return None; }
    let n = |a,b| s[a..b].parse::<i64>().ok();
    let (mut y,m,d,h,mi,se) = (n(0,4)?,n(4,6)?,n(6,8)?,n(8,10)?,n(10,12)?,n(12,14)?);
    let leap = y%4==0 && (y%100!=0 || y%400==0);
    let len = match m {1|3|5|7|8|10|12=>31,4|6|9|11=>30,2=>if leap {29}else{28},_=>return None};
    if d<1 || d>len || h>23 || mi>59 || se>59 {return None;}
    y -= i64::from(m<=2);
    let era=y.div_euclid(400); let yo=y-era*400;
    let mp=m+if m>2 {-3}else{9};
    let days=era*146097+yo*365+yo/4-yo/100+(153*mp+2)/5+d-1-719468;
    Some((days*86400+h*3600+mi*60+se-offset_hours*3600)*1000)
}

pub(crate) fn catalog(kind: u32, bytes: &[u8]) -> Result<Value,String> {
    let text=std::str::from_utf8(bytes).map_err(|e|e.to_string())?.trim_start_matches('\u{feff}').trim();
    let body=if kind<2 {
        let callback=if kind==0 {"readRadarList"}else{"getPreObs1h"};
        text.strip_prefix(callback).and_then(|v|v.trim_start().strip_prefix('('))
            .and_then(|v|v.trim_end_matches(';').trim_end().strip_suffix(')')).ok_or("Invalid weather JSONP")?
    } else {text};
    let raw:Value=serde_json::from_str(body).map_err(|e|e.to_string())?;
    let rows=match kind {0|1=>raw["datas"].as_array(),2|3=>raw.as_array(),4 if raw["returnCode"]==0=>raw["ds"].as_array(),_=>None}.ok_or("Missing weather frame catalog")?;
    let mut frames=BTreeMap::new();
    for row in rows {
        let value = match kind {
            0|1=> {
                let Some(dt)=row["dt"].as_str() else {continue};
                if dt.len()!=if kind==0 {14}else{10} || !dt.bytes().all(|b|b.is_ascii_digit()) {continue;}
                let stamp=if kind==1 {format!("{dt}0000")}else{dt.to_owned()};
                let Some(time)=epoch(&stamp,8) else {continue};
                let filename=if kind==0 {format!("ACHN_QREF_{}_{}.png",&dt[..8],&dt[8..])}else{format!("prec_{dt}.png")};
                if row[if kind==0 {"fn"}else{"picPath"}].as_str()!=Some(&filename) {continue;}
                let directory=if kind==0 {"radar/pic"}else{"prec1h"};
                json!({"epochMs":time,"url":format!("https://d1.weather.com.cn/radar_channel/{directory}/{filename}")})
            },
            2|3=>{
                let (Some(base),Some(valid))=(row["basetime"].as_str(),row["validtime"].as_str()) else {continue};
                if epoch(base,0).is_none() {continue;}
                let Some(time)=epoch(valid,0) else {continue};
                // Playback is observed history, never forecast rainfall.
                if valid>base {continue;}
                if kind==2 && row["elements"].as_array().is_some_and(|v| !v.iter().any(|e|e=="hrpns")) {continue;}
                json!({"epochMs":time,"basetime":base,"validtime":valid})
            },
            4=>{
                let (Some(date),Some(clock))=(row["dataDate"].as_str(),row["dataTime"].as_str()) else {continue};
                let Some(time)=epoch(&format!("{date}{clock}"),0) else {continue};
                json!({"epochMs":time})
            },
            _=>continue,
        };
        let time=value["epochMs"].as_i64().unwrap();
        frames.insert(time,value);
        // Metadata only: bounded even for unexpectedly long upstream lists.
        if frames.len()>24 {frames.pop_first();}
    }
    Ok(json!(frames.into_values().collect::<Vec<_>>()))
}

#[no_mangle]
pub unsafe extern "C" fn rq_weather_playback_catalog(kind:u32,input:*const u8,len:usize,size:*mut usize)->*mut u8 {
    if size.is_null() {return std::ptr::null_mut();}
    unsafe { *size=0; }
    if input.is_null() || len>4*1024*1024 {return std::ptr::null_mut();}
    std::panic::catch_unwind(||{
        let result=catalog(kind,unsafe {std::slice::from_raw_parts(input,len)}).unwrap_or_else(|e|json!({"error":e}));
        let bytes=serde_json::to_vec(&result).unwrap().into_boxed_slice();
        unsafe { *size=bytes.len(); } Box::into_raw(bytes).cast()
    }).unwrap_or(std::ptr::null_mut())
}
#[no_mangle]
pub unsafe extern "C" fn rq_weather_playback_free(input:*mut u8,len:usize) {
    if !input.is_null() {drop(unsafe {Box::from_raw(std::ptr::slice_from_raw_parts_mut(input,len))});}
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn original_upstream_catalogs_are_ordered_bounded_and_not_mutated() {
        let root=std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../test/fixtures/weather_playback_20261105");
        for (kind,file) in ["radar","precipitation","jma_radar","jma_cloud","nsmc"].iter().enumerate() {
            let bytes=std::fs::read(root.join(format!("{file}.json"))).unwrap(); let before=bytes.clone();
            let output=catalog(kind as u32,&bytes).unwrap(); let frames=output.as_array().unwrap();
            assert!(frames.len()>1 && frames.len()<=24,"{file}");
            assert!(frames.windows(2).all(|v|v[0]["epochMs"].as_i64()<v[1]["epochMs"].as_i64()));
            assert_eq!(bytes,before);
            for _ in 0..20 {let mut len=0;unsafe{let p=rq_weather_playback_catalog(kind as u32,bytes.as_ptr(),bytes.len(),&mut len); assert!(!p.is_null());rq_weather_playback_free(p,len);}}
        }
    }
    #[test]
    fn zones_invalid_dates_and_forecasts() {
        assert_eq!(epoch("19700101080000",8),Some(0));
        assert_eq!(epoch("19700101000000",0),Some(0));
        assert_eq!(epoch("20260230000000",0),None);
        let raw=br#"[{"basetime":"20261105083000","validtime":"20261105083500"}]"#;
        assert_eq!(catalog(2,raw).unwrap(),json!([]));
        assert!(catalog(0,b"wrong({})").is_err());
    }
}
