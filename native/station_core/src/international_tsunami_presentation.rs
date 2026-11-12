//! Source-aware list/sidebar projection. Original reports and readings stay intact.
use super::{absolute, s, text, wave_data};
use serde_json::{json, Value};

fn rows(v: &Value) -> impl Iterator<Item = &Value> {
    v.as_array().into_iter().flatten().filter(|v| v.is_object())
}
fn level_zh(value:&str)->String {
    match value.to_ascii_lowercase().as_str(){
        "warning"=>"海啸警报", "advisory"=>"海啸警戒", "watch"=>"海啸监视",
        "information"=>"海啸信息", "cancellation"=>"海啸解除", "alert"=>"海啸警戒", "threat"=>"海啸威胁",
        _=>value,
    }.to_owned()
}
fn no_threat(m:&Value)->String {
    let body=report_text(m);
    let lower=body.split_whitespace().collect::<Vec<_>>().join(" ").to_lowercase();
    match s(m,"source").as_str(){
        "incois" if lower.contains("no threat to india")||lower.contains("threat does not exist for india")||s(m,"title").contains("NO TSUNAMI THREAT FOR INDIAN COAST")=>"印度沿岸无海啸威胁".into(),
        "nmefc" if body.contains("不会对我国沿岸造成影响")=>"我国沿岸无海啸影响".into(),
        "nmefc" if body.contains("不会对我国沿岸造成灾害性影响")||body.contains("不会对我国沿岸造成重要影响")=>"我国沿岸无灾害性海啸影响".into(),
        "cwa" if body.contains("解除太平洋地區的海嘯威脅")||body.contains("解除太平洋地区的海啸威胁")=>"太平洋地区海啸威胁解除".into(),
        "cat" if lower.contains("no se espera la generacion de un tsunami para las costas nacionales")=>"墨西哥沿岸无海啸威胁".into(),
        "cat" if lower.contains("no se espera la generacion de un tsunami;")=>"预计不会产生海啸，海平面无显著变化".into(),
        "ntwc" if lower.contains("there is no tsunami danger for the u.s. west coast, british columbia, or alaska")=>"美国西海岸、不列颠哥伦比亚及阿拉斯加无海啸危险".into(),
        "ptwc" if lower.contains("no tsunami threat to guam/cnmi")=>"关岛及北马里亚纳群岛无海啸威胁".into(),
        "ptwc"|"ntwc" if lower.contains("there is no tsunami danger from this earthquake")=>"本次地震无海啸危险".into(),
        _=>String::new(),
    }
}
fn report_text(m:&Value)->String {
    let official=s(&m["officialDetail"],"bulletinText");
    if !official.is_empty(){return official;}
    let body=s(m,"titleText");
    let instruction=s(&m["sourcePayload"],"instruction");
    if instruction.is_empty()||instruction=="N/A"||body==instruction {body}
    else {format!("{body}\n\n{instruction}")}
}
fn information_text(m:&Value)->String {
    let body=report_text(m);
    if s(m,"source")=="nmefc" && body.contains("震源周围引发局地海啸") && body.contains("不会对我国沿岸造成影响") {
        return "震源周围可能引发局地海啸；我国沿岸无海啸影响".into();
    }
    let explicit=no_threat(m);
    if !explicit.is_empty(){return explicit;}
    if s(m,"source")=="cwa" && body.contains("可能在太平洋地區引發海嘯威脅") && body.contains("嚴密監視") {
        return "太平洋地区可能有海啸威胁，持续监视后续影响".into();
    }
    body
}
fn event_text(m:&Value)->String {
    let mut parts=vec![s(m,"epicenterName")];
    if m["magnitude"].is_number(){parts.push(format!("M{}",text(&m["magnitude"])));}
    if m["depth"].is_number(){parts.push(format!("深度{}km",text(&m["depth"])));}
    parts.retain(|v|!v.is_empty());parts.join(" · ")
}
fn short_name(value:&str)->String{
    let mut name=value.trim().to_owned();
    if name.starts_with(|c:char|c.is_ascii_digit()) && (name.contains(" km ")||name.contains(" miles ")){
        for separator in [" of "," OF "," DE "]{
            if let Some((_,place))=name.rsplit_once(separator){name=place.to_owned();break;}
        }
    }
    for (from,to) in [("The ",""),("California","CA"),("Alaska","AK"),("Oregon","OR"),
        ("British Columbia","BC"),(" Islands"," Is."),(" Island"," I."),(" - "," — ")]{name=name.replace(from,to);}
    name
}
fn visible(m: &Value, now: i64) -> bool {
    let zone=m["timeZone"].as_i64().unwrap_or(8)*60;
    let issued=absolute(&s(m,"reportTime"),zone).map(|t|t/1000);
    let deadline=absolute(&s(m,"expires"),zone).map(|t|t/1000).filter(|expiry|issued.is_none_or(|t|*expiry>t))
        .or_else(||if s(m,"bulletinLevel").eq_ignore_ascii_case("information"){issued.map(|t|t+3*60*60*1000)}else{None});
    !s(m, "bulletinLevel").eq_ignore_ascii_case("cancellation")
        && deadline
            .is_none_or(|t| now <= 0 || t > now)
        && (s(m,"grade") != "none" || s(m,"bulletinLevel").eq_ignore_ascii_case("information"))
}
fn colour(m: &Value, a: &Value) -> String {
    if s(m,"source")=="cwa" {
        let region=rows(&m["sourcePayload"]["warningAreas"]).find(|v|v["areaName"]==a["name"]);
        let raw=region.map(|v|s(v,"areaColor")).filter(|v|!v.is_empty()).unwrap_or_else(||s(&m["sourcePayload"],"reportColor"));
        let c=match raw.as_str(){"紅色"|"红色"=>"red","橙色"=>"orange","黃色"|"黄色"=>"yellow","綠色"|"绿色"=>"green",_=>""};
        if !c.is_empty(){return c.into();}
    }
    let c = s(a,"className");
    if !c.is_empty() { return c; }
    if let Some(original)=rows(&m["areas"]).find(|v|v["name"]==a["name"]) {
        let c=s(original,"className");
        if !c.is_empty(){return c;}
    }
    match s(a,"grade").as_str() {
        "majorWarning" => "purple".into(), "warning" => "red".into(),
        "watch" => "yellow".into(), _ => s(m,"className")
    }
}
fn label(m: &Value, a: &Value) -> String {
    if s(m,"source") == "nmefc" {
        return match colour(m,a).as_str() {
            "red"=>"红色警报", "orange"=>"橙色警报", "yellow"=>"黄色警报", "blue"=>"蓝色警报", _=>"海啸信息"
        }.into();
    }
    if matches!(s(m,"source").as_str(),"ptwc"|"ntwc") {
        let name=s(a,"name");
        if let Some(original)=rows(&m["areas"]).find(|v|v["name"]==a["name"]){
            if !s(original,"condition").is_empty(){return level_zh(&s(original,"condition"));}
        }
        for segment in rows(&m["officialDetail"]["segments"]) {
            let start=s(segment,"bkp_start_location"); let end=s(segment,"bkp_end_location");
            let coast=if start.is_empty(){end}else if end.is_empty()||end==start{start}else{format!("{start} - {end}")};
            if !name.is_empty() && name==coast && !s(segment,"category").is_empty(){return level_zh(&s(segment,"category"));}
        }
    }
    if s(m,"source") == "cwa" && !s(&m["sourcePayload"],"reportType").is_empty() {
        return s(&m["sourcePayload"],"reportType");
    }
    let raw = s(m,"bulletinLevel");
    if !raw.is_empty() { level_zh(&raw) } else { s(m,"title") }
}
fn height(reading: &Value) -> String {
    if let Some(n)=reading["metres"].as_f64().filter(|n|n.is_finite()) {
        let value=format!("{n:.3}");
        return format!("{}m",value.trim_end_matches('0').trim_end_matches('.'));
    }
    let raw = text(&reading["value"]);
    let unit = s(reading,"unit");
    if raw.is_empty() { return String::new(); }
    if !unit.is_empty() && raw.chars().all(|c|c.is_ascii_digit()||". -–—~～至<>≤≥".contains(c)) {format!("{raw}{unit}")} else {raw}
}
fn caption(m: &Value) -> String {
    let agency=s(m,"source").to_uppercase();
    let threat=no_threat(m);
    if !threat.is_empty(){return format!("{agency} {threat}");}
    let raw=s(&m["sourcePayload"],"headline");
    let raw=if raw.is_empty(){s(&m["sourcePayload"]["warningInfo"],"title")}else{raw};
    let raw=if raw.is_empty(){s(m,"title")}else{raw};
    let mut title=if raw.starts_with(&agency){raw}else{format!("{agency} {raw}")};
    for word in ["Warning","Advisory","Watch","Information","Cancellation"]{
        for variant in [word.to_owned(),word.to_uppercase(),word.to_lowercase()]{
            title=title.replace(&variant,&level_zh(word));
        }
    }
    title
}
fn bulletin(m: &Value) -> Value {
    json!({"label":"公报","reportTime":m["reportTime"],"reportNumber":m["reportNumber"],
        "headline":report_text(m),
        "rawText":serde_json::to_string_pretty(&json!({"sourcePayload":m["sourcePayload"],"officialDetail":m["officialDetail"]})).unwrap_or_default()})
}
fn time_row(name: &str, height: String, reading: &Value) -> Value {
    let time = s(reading,"time");
    let unparsed = !time.is_empty() && !reading["timeUtcMs"].is_number();
    let ist = reading["timeZone"].as_f64() == Some(5.5);
    json!({"name":short_name(name),"height":height,"arrivalTime":if unparsed||ist{""}else{&time},
        "arrivalLabel":if time.is_empty(){String::new()}else if ist{format!("{time} IST")}else if unparsed{time}else{String::new()},
        "heightTime":"","condition":s(reading,"condition"),"secondary":[],
        "details":if short_name(name)!=name{vec![json!({"label":"原始地名","text":name})]}else{vec![]}})
}
fn forecast_row(m: &Value, area: &Value) -> Value {
    let mut h = height(&area["forecast"]);
    // NOAA area descriptions explain a warning; they are not wave predictions.
    if matches!(s(m,"source").as_str(),"ptwc"|"ntwc") && !area["forecast"]["metres"].is_number() {h.clear();}
    time_row(&s(area,"name"),h,&area["forecast"])
}
pub fn project(m: &Value, now: i64) -> Value {
    if !visible(m,now) {return json!({"groups":[]});}
    let data = wave_data::project(m,now);
    let source=s(m,"source"); let agency=source.to_uppercase();
    let mut groups=Vec::<Value>::new();
    for area in rows(&data["areaForecasts"]) {
        let c=colour(m,area); let g=s(area,"grade");
        let index=groups.iter().position(|v|v["grade"]==g&&v["className"]==c).unwrap_or_else(||{
            let l=label(m,area);
            groups.push(json!({"key":format!("{source}:{}:{g}:{c}",s(m,"eventId")),"source":source,
                "timeZone":m["timeZone"],"grade":g,"className":c,"label":l,"caption":format!("{agency} {l}"),
                "reportTime":m["reportTime"],"reportNumber":m["reportNumber"],"headline":m["titleText"],
                "regionCount":0,"nameLabel":"地区","timeLabel":"到达","heightLabel":"预计","rows":[]}));
            groups.len()-1
        });
        groups[index]["rows"].as_array_mut().unwrap().push(forecast_row(m,area));
        groups[index]["regionCount"]=json!(groups[index]["rows"].as_array().unwrap().len());
    }
    if groups.is_empty() {
        let l=label(m,m); let name=s(m,"epicenterName");
        groups.push(json!({"key":format!("{source}:{}:bulletin",s(m,"eventId")),"source":source,"timeZone":m["timeZone"],
            "grade":m["grade"],"className":m["className"],"label":l,"caption":format!("{agency} {l}"),
            "reportTime":m["reportTime"],"reportNumber":m["reportNumber"],"headline":m["titleText"],
            "regionCount":1,"nameLabel":"地点","timeLabel":"","heightLabel":"","countLabel":"条",
            "rows":[time_row(&name,String::new(),&Value::Null)]}));
    }
    groups.sort_by_key(|g|std::cmp::Reverse(match s(g,"grade").as_str(){"majorWarning"=>4,"warning"=>3,"watch"=>2,_=>0}));
    let information=s(m,"grade")=="none" && s(m,"bulletinLevel").eq_ignore_ascii_case("information");
    for g in &mut groups{
        g["pinned"]=json!(!information);
        g["informationText"]=json!(information_text(m));
        g["eventText"]=json!(event_text(m));
        g["headline"]=json!(report_text(m));
    }
    json!({"groups":groups})
}
pub fn sidebar(m: &Value, now: i64) -> Value {
    let source=s(m,"source"); let data=wave_data::project(m,now);
    let areas=rows(&data["areaForecasts"]).collect::<Vec<_>>();
    let stations=rows(&data["stations"]).collect::<Vec<_>>();
    let mut cells=vec![]; let mut used=std::collections::HashSet::new();
    let station_cell=|i:usize,station:&Value,area:Option<&&Value>|{
        let region=s(station,"regionName"); let name=s(station,"stationName");
        let observed=&station["observed"]; let forecast=&station["forecast"];
        let observed_label=if !observed["metres"].is_number() && !text(&observed["value"]).is_empty() {"报告波幅（原文单位）"} else {match s(observed,"kind").as_str(){"maximumPositiveAmplitude"=>"最大正波幅","reportedWaveHeight"=>"报告波高",_=>"报告波幅"}};
        let mut observation=if observed.is_object(){Some(time_row(&name,height(observed),observed))}else{None};
        if let Some(row)=observation.as_mut(){
            let mut details=vec![json!({"label":"原始站名","text":name})];
            if !region.is_empty(){details.push(json!({"label":"预报区/岸段","text":region}));}
            details.push(json!({"label":"原始观测值","text":format!("{} {}",text(&observed["value"]),s(observed,"unit"))}));
            if !s(station,"firstArrivalTime").is_empty(){details.push(json!({"label":"到达（原文时间）","text":station["firstArrivalTime"]}));}
            if !s(station,"country").is_empty(){details.push(json!({"label":"国家/地区","text":station["country"]}));}
            row["details"]=json!(details);
        }
        json!({"key":format!("{source}:station:{i}"),"region":short_name(if name.is_empty(){&region}else{&name}),
            "grade":station["grade"].as_str().unwrap_or("none"),"gradeLabel":label(m,m),"className":area.map(|a|colour(m,a)).unwrap_or_else(||s(m,"className")),
            "stationName":name,"regionForecast":area.map(|a|forecast_row(m,a)),
            "forecast":if forecast.is_object(){Some(time_row(&name,height(forecast),forecast))}else{None},
            "observation":observation,
            "observedLabel":observed_label,"forecastLabel":"站点预计"})
    };
    for area in &areas {
        let name=s(area,"name"); let mut found=false;
        for (i,station) in stations.iter().enumerate().filter(|(_,v)|!name.is_empty()&&s(v,"regionName")==name) {
            used.insert(i); found=true; cells.push(station_cell(i,station,Some(area)));
        }
        if !found {cells.push(json!({"key":format!("{source}:area:{}",cells.len()),"region":short_name(&name),
            "grade":area["grade"],"gradeLabel":label(m,area),"className":colour(m,area),
            "stationName":"","regionForecast":forecast_row(m,area),"forecast":null,"observation":null}));}
    }
    for (i,station) in stations.iter().enumerate().filter(|(i,_)|!used.contains(i)) {cells.push(station_cell(i,station,None));}
    if cells.is_empty(){cells.push(json!({"key":format!("{source}:bulletin"),"region":short_name(&s(m,"epicenterName")),"grade":m["grade"],
        "gradeLabel":label(m,m),"className":m["className"],"stationName":"","regionForecast":null,"forecast":null,"observation":null}));}
    json!({"caption":caption(m),"regionCount":areas.len(),"stationCount":stations.len(),
        "columnHeadings":["地区/位置","观测","预计"],"cells":cells,
        "bulletins":[bulletin(m)]})
}
pub fn list_order(c:&Value)->Value{
    let mut pinned=vec![];let mut ordinary=vec![];let mut information=vec![];
    for (i,g) in rows(&c["groups"]).enumerate(){
        let item=json!({"group":i,"event":null,"receiptOrder":g["receiptOrder"].as_i64().unwrap_or(0),"time":absolute(&s(g,"reportTime"),g["timeZone"].as_i64().unwrap_or(8)*60).unwrap_or(0)});
        if g["pinned"]==false{information.push(item);}else{pinned.push(item);}
    }
    for (i,event) in rows(&c["events"]).enumerate(){
        let raw=s(event,"time");
        ordinary.push(json!({"group":null,"event":i,"receiptOrder":event["receiptOrder"].as_i64().unwrap_or(0),"time":absolute(raw.trim_end_matches('Z'),event["timeZone"].as_i64().unwrap_or(8)*60).unwrap_or(0)}));
    }
    information.sort_by_key(|v|std::cmp::Reverse((v["receiptOrder"].as_i64().unwrap_or(0),v["time"].as_i64().unwrap_or(0))));
    for info in information.into_iter().rev(){
        let by_time=ordinary.iter().position(|v|v["time"].as_i64().unwrap_or(0)<=info["time"].as_i64().unwrap_or(0)).unwrap_or(ordinary.len());
        // A newly received earthquake report can concern an older origin.
        // Keep earthquake relative order, but never leave information above
        // those newer receipts merely because its source clock is later.
        let after_newer=ordinary.iter().rposition(|v|v["receiptOrder"].as_i64().unwrap_or(0)>info["receiptOrder"].as_i64().unwrap_or(0)).map_or(0,|i|i+1);
        let index=by_time.max(after_newer);
        ordinary.insert(index,info);
    }
    pinned.extend(ordinary);json!({"rows":pinned})
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn protocol_information_is_unpinned_but_a_generic_definition_is_not_no_threat() {
        let mut m=json!({"source":"ntwc","grade":"none","bulletinLevel":"Information","areas":[],"titleText":"An information statement indicates no threat, or a warning for another section of the ocean.","sourcePayload":{}});
        assert_eq!(project(&m,0)["groups"][0]["pinned"],false);
        assert_eq!(no_threat(&m),"");
        assert_eq!(project(&m,0)["groups"][0]["informationText"],m["titleText"]);
        m["sourcePayload"]["instruction"]=json!("There is NO tsunami danger from this earthquake.");
        assert_eq!(project(&m,0)["groups"][0]["informationText"],"本次地震无海啸危险");
        m["grade"]=json!("warning");m["bulletinLevel"]=json!("Warning");
        assert_eq!(project(&m,0)["groups"][0]["pinned"],true);
    }
    #[test]
    fn protocol_timeline_compares_absolute_times_and_preserves_quake_relative_order() {
        let c=json!({"groups":[
          {"pinned":false,"reportTime":"2026-10-23T11:00:00+08:00"},
          {"pinned":true,"reportTime":"2026-10-23T09:00:00+08:00"}],
          "events":[{"time":"2026-10-23T12:30:00Z","timeZone":9},{"time":"2026-10-23T10:30:00","timeZone":8}]});
        let result=list_order(&c);
        assert_eq!(result["rows"][0]["group"],1);
        assert_eq!(result["rows"][1]["event"],0);
        assert_eq!(result["rows"][2]["group"],0);
        assert_eq!(result["rows"][3]["event"],1);
    }
    #[test]
    fn newly_received_report_pushes_information_down_even_for_an_older_earthquake() {
        let c=json!({"groups":[{"pinned":false,"reportTime":"2026-10-24T11:10:46+08:00","receiptOrder":4},
            {"pinned":true,"reportTime":"2026-10-24T10:00:00+08:00","receiptOrder":1}],
            "events":[{"time":"2026-10-24T10:50:00","timeZone":8,"receiptOrder":2},
                {"time":"2026-10-24T10:31:00","timeZone":8,"receiptOrder":5}]});
        let v=list_order(&c);
        assert_eq!(v["rows"][0]["group"],1);
        assert_eq!(v["rows"][1]["event"],0);
        assert_eq!(v["rows"][2]["event"],1);
        assert_eq!(v["rows"][3]["group"],0);
    }
    #[test]
    fn english_display_abbreviations_keep_original_place_in_details() {
        let name="125 km E of The Kodiak Island, Alaska";
        let row=time_row(name,String::new(),&Value::Null);
        assert_eq!(row["name"],"Kodiak I., AK");
        assert_eq!(row["details"][0]["text"],name);
        assert_eq!(level_zh("Advisory"),"海啸警戒");
        assert_eq!(level_zh("津波注意報"),"津波注意報");
        assert_eq!(level_zh("ALERTA"),"ALERTA");
    }
    #[test]
    fn original_noaa_all_stations_and_observations_reach_sidebar() {
        let detail:Value=serde_json::from_str(include_str!("../../../test/fixtures/tsunami_regions/ntwc_kamchatka_20250730_B12.original.json")).unwrap();
        let parsed=wave_data::noaa_detail(&json!({"json":detail.to_string()})).unwrap();
        let m=json!({"source":"ntwc","grade":"warning","className":"red","bulletinLevel":"Warning","timeZone":8,
            "reportTime":detail["bulletinIssueTime"],"officialDetail":parsed["detail"],"areas":parsed["areas"]});
        let before=m.to_string(); let view=sidebar(&m,0);
        assert_eq!(view["stationCount"],298);
        assert_eq!(rows(&view["cells"]).filter(|v|v["observation"].is_object()).count(),30);
        assert_eq!(m.to_string(),before);
        assert!(rows(&project(&m,0)["groups"]).all(|v|s(v,"caption").starts_with("NTWC ")));
    }
    #[test]
    fn cancellation_and_expiry_remove_left_groups() {
        let m=json!({"source":"cat","grade":"none","bulletinLevel":"Information","reportTime":"2026-01-01T00:00:00Z","expires":"2026-01-01T01:00:00Z","timeZone":8});
        assert_eq!(project(&m,0)["groups"].as_array().unwrap().len(),1);
        assert!(project(&m,i64::MAX)["groups"].as_array().unwrap().is_empty());
        let mut c=m; c["bulletinLevel"]=json!("Cancellation");
        assert!(project(&c,0)["groups"].as_array().unwrap().is_empty());
    }
}
