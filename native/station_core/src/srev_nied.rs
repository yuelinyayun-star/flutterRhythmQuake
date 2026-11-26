//! SREV detector adapter; original core vendored under CC-BY-SA-2.0.
//! Presentation retains KA-compatible levels; they are not used as SREV indices.
use srev_detector::{Detector, V};
use serde_json::{Value,json};
use std::collections::{HashMap, HashSet};

const EPOCH_2000_MS: i64 = 946_684_800_000;
#[derive(Clone, Copy, Default, Debug, PartialEq, Eq)]
pub(crate) struct Pick {
    pub active: bool,
    pub trigger_ms: i64,
    pub permission: i64,
    pub event_id: i64,
}
fn key(lat:f64,lon:f64)->(i64,i64){((lat*100000.).round() as i64,(lon*100000.).round() as i64)}
pub(crate) fn observation(ka:i64, fine:f64)->(f64,V){
    if !(0..=20).contains(&ka){return (0.,V::from(""))}
    let q=if fine.is_finite(){
        ((fine*10.).round()+30.).clamp(0.,98.) as i64
    }else{
        match ka{0=>0,1=>3,20=>97,_=>ka*5-3}
    };
    let code=if q<15{1+q/5}else if q<75{4+(q-15)*3/10}else if q<95{22+(q-75)*4/10}else{30};
    (code as f64,V::N((q as f64-30.)/10.))
}
fn fresh()->Detector{
    let mut d=Detector::new();
    d.seed_hyp(12345); // deterministic stream matching the validated SREV replay
    d.list_mut("7システム設定").unwrap()[50]=V::B(true);
    d
}
// Original SREV spherical distance, rounded to 0.01 km with 0.1 km
// minimum for co-located independent stations.
fn distance(a:(f64,f64),b:(f64,f64))->f64 {
    let round10=|x:f64|(x*1e10).round()/1e10;
    let (a1,b1)=(a.0.to_radians(),b.0.to_radians());
    let c=round10(a1.sin())*round10(b1.sin())+
        round10(a1.cos())*round10(b1.cos())*round10((a.1-b.1).to_radians().cos());
    ((111.31949*c.clamp(-1.,1.).acos().to_degrees()*100.).round()/100.).max(0.1)
}
fn grid(lat:f64,lon:f64)->usize {
    let x=(lon.floor() as i64-123).clamp(0,22);
    let y=(lat.floor() as i64-23).clamp(0,22);
    (y*23+x+1) as usize
}
fn layout(xy:&[f64],names:&[String])->(Detector,Vec<Option<usize>>) {
    let mut d=fresh();
    let mut coords:Vec<_>=d.list("d ten:y").unwrap().iter().zip(d.list("d ten:x").unwrap()).map(|(y,x)|(y.num(),x.num())).collect();
    let original=coords.len();
    let original_names:Vec<_>=d.list("d ten:名前").unwrap().iter().map(V::string).collect();
    let thresholds=d.list("d ten:しきい").unwrap().to_vec();
    let mut catalog:HashMap<_,Vec<usize>>=HashMap::new();
    let mut incoming:HashMap<_,Vec<usize>>=HashMap::new();
    for i in 0..original {catalog.entry((key(coords[i].0,coords[i].1),original_names[i].clone())).or_default().push(i);}
    for (i,n) in names.iter().enumerate(){incoming.entry((key(xy[2*i],xy[2*i+1]),n.clone())).or_default().push(i);}
    let mut mapping=vec![None;names.len()];
    let mut used=HashSet::new();
    for (k,indices) in incoming {
        if let Some(slots)=catalog.get(&k) {
            if indices.len()==slots.len() && slots.iter().all(|&j|thresholds[j]==thresholds[slots[0]]) {
                for (&i,&j) in indices.iter().zip(slots){mapping[i]=Some(j);used.insert(j);}
            }
        }
    }
    let mut changed=HashSet::new();
    for (i,n) in names.iter().enumerate(){
        if mapping[i].is_some(){continue}
        let pos=(xy[i*2],xy[i*2+1]);
        // A unique unused same-name site within 15 km may be a relocated
        // station. Use current coordinates, not the old coordinates.
        let candidates:Vec<_>=(0..original).filter(|&j|!used.contains(&j)&&original_names[j]==*n&&distance(pos,coords[j])<=15.).collect();
        let slot=if candidates.len()==1 {
            let j=candidates[0];coords[j]=pos;
            d.list_mut("d ten:x").unwrap()[j]=V::N(pos.1);
            d.list_mut("d ten:y").unwrap()[j]=V::N(pos.0);
            j
        } else {
            let j=coords.len();
            let nearest=(0..original).min_by(|&a,&b|distance(pos,coords[a]).total_cmp(&distance(pos,coords[b]))).unwrap();
            let area=d.list("d ten:観測点所属区域").unwrap()[nearest].clone();
            coords.push(pos);
            for (name,v) in [("d ten:x",V::N(pos.1)),("d ten:y",V::N(pos.0)),("d ten:名前",V::from(n.as_str())),("d ten:しきい",V::from("320")),("d ten:観測点所属区域",area),("dtc:Xpix",V::N((pos.1-136.)*10.)),("dtc:Ypix",V::N(0.))] {
                d.list_mut(name).unwrap().push(v);
            }
            j
        };
        mapping[i]=Some(slot);used.insert(slot);changed.insert(slot);
    }
    if changed.is_empty(){return (d,mapping)}
    let count=coords.len();
    for name in ["ten:最終更新","@1 ten:最高震度更新時刻","ten:震度変化速度","ten:震度","ten c:揺れ検出トリガー時間","ten c:検出許可済み震度","ten:点用カメラ範囲"] {
        d.list_mut(name).unwrap().resize(count+2,V::from(""));
    }
    d.list_mut("ten:震度100").unwrap().resize(count+2,V::N(-3.));
    d.list_mut("ten c:揺れ検出許可").unwrap().resize(count+2,V::from("1"));
    d.list_mut("ten:震度履歴").unwrap().resize((count+2)*10,V::from(""));
    d.list_mut("ten c:震源距離").unwrap().resize((count+2)*10,V::from(""));
    d.list_mut("ten:推定用").unwrap().resize((count+1)*10,V::from(""));
    let mut grid_ids=vec![V::N(-651.);count+2];
    let mut buckets=std::collections::BTreeMap::<usize,Vec<usize>>::new();
    for (i,&(lat,lon)) in coords.iter().enumerate(){
        let id=grid(lat,lon);grid_ids[i]=V::N(id as f64);
        buckets.entry(id).or_default().push(i+1);
    }
    *d.list_mut("dc ten:点からグリッド番号").unwrap()=grid_ids;
    d.grid_stride=70.max(buckets.values().map(|v|v.len()+1).max().unwrap_or(1));
    let mut entries=vec![V::from("");buckets.len()*d.grid_stride];
    for (i,values) in buckets.values().enumerate(){
        for (j,&v) in values.iter().enumerate(){entries[i*d.grid_stride+j]=V::N(v as f64);}
    }
    *d.list_mut("dc grid連番:点がある番号").unwrap()=buckets.keys().map(|&i|V::N(i as f64)).collect();
    *d.list_mut("dc grid:グリッドに含まれる点番号").unwrap()=entries;
    let old=d.list("dc ten:最短7点").unwrap().to_vec();
    let mut near=old.clone();near.resize(count*14,V::from(""));
    for i in 0..count {
        let needs=changed.contains(&i)||i>=original||
            (0..7).any(|k|changed.contains(&(old[i*14+k*2+1].num() as usize-1)))||
            changed.iter().any(|&j|i!=j&&distance(coords[i],coords[j])<=old[i*14+12].num());
        if !needs{continue}
        let mut ns:Vec<_>=(0..count).filter(|&j|j!=i).map(|j|(distance(coords[i],coords[j]),j)).collect();
        ns.sort_by(|a,b|a.0.total_cmp(&b.0).then(a.1.cmp(&b.1)));
        for (k,(dist,j)) in ns.into_iter().take(7).enumerate(){
            near[i*14+2*k]=V::N(dist);near[i*14+2*k+1]=V::N((j+1) as f64);
        }
    }
    *d.list_mut("dc ten:最短7点").unwrap()=near;
    (d,mapping)
}
// Isolated Taiwan detection catalogue. Do not append to Japan's stations or
// inherit Japanese coastal extrapolation or station-specific thresholds.
// Independent Taiwan station topology (HYP is disabled).
fn taiwan_layout(xy:&[f64],names:&[String])->(Detector,Vec<Option<usize>>){
    assert_eq!(xy.len(),names.len()*2);
    assert!(names.len()>=8);
    let coords:Vec<_>=xy.chunks_exact(2).map(|p|(p[0],p[1])).collect();
    let mut d=fresh();
    let n=coords.len();
    for (name,values) in [
        ("d ten:x",coords.iter().map(|p|V::N(p.1)).collect()),
        ("d ten:y",coords.iter().map(|p|V::N(p.0)).collect()),
        ("d ten:名前",names.iter().map(|v|V::from(v.as_str())).collect()),
        ("d ten:しきい",vec![V::from("320");n]),
        ("d ten:観測点所属区域",vec![V::N(1.);n]),
        ("dtc:Xpix",vec![V::N(0.);n]),
        ("dtc:Ypix",vec![V::N(0.);n]),
    ]{*d.list_mut(name).unwrap()=values;}
    for name in ["ten:最終更新","@1 ten:最高震度更新時刻","ten:震度変化速度","ten:震度","ten c:揺れ検出トリガー時間","ten c:検出許可済み震度","ten:点用カメラ範囲"] {
        *d.list_mut(name).unwrap()=vec![V::from("");n+2];
    }
    *d.list_mut("ten:震度100").unwrap()=vec![V::N(-3.);n+2];
    *d.list_mut("ten c:揺れ検出許可").unwrap()=vec![V::from("1");n+2];
    *d.list_mut("ten:震度履歴").unwrap()=vec![V::from("");(n+2)*10];
    *d.list_mut("ten c:震源距離").unwrap()=vec![V::from("");(n+2)*10];
    *d.list_mut("ten:推定用").unwrap()=vec![V::from("");(n+1)*10];
    d.list_mut("dc grid:沿岸").unwrap().clear();
    let mut grid_ids=vec![V::N(-651.);n+2];
    let mut buckets=std::collections::BTreeMap::<usize,Vec<usize>>::new();
    for (i,&(lat,lon)) in coords.iter().enumerate(){
        let x=lon.floor() as i64-112; let y=lat.floor() as i64-16;
        // Fail rather than clamp or merge geographically different cells.
        assert!((1..22).contains(&x)&&(1..22).contains(&y),"Taiwan candidate outside padded grid");
        let id=(y*23+x+1) as usize;
        grid_ids[i]=V::N(id as f64);buckets.entry(id).or_default().push(i+1);
    }
    *d.list_mut("dc ten:点からグリッド番号").unwrap()=grid_ids;
    d.grid_stride=70.max(buckets.values().map(|v|v.len()+1).max().unwrap());
    let mut entries=vec![V::from("");buckets.len()*d.grid_stride];
    for (i,values) in buckets.values().enumerate(){
        for (j,&v) in values.iter().enumerate(){entries[i*d.grid_stride+j]=V::N(v as f64);}
    }
    *d.list_mut("dc grid連番:点がある番号").unwrap()=buckets.keys().map(|&v|V::N(v as f64)).collect();
    *d.list_mut("dc grid:グリッドに含まれる点番号").unwrap()=entries;
    let mut near=vec![V::from("");n*14];
    for i in 0..n {
        let mut ns:Vec<_>=(0..n).filter(|&j|j!=i).map(|j|(distance(coords[i],coords[j]),j)).collect();
        ns.sort_by(|a,b|a.0.total_cmp(&b.0).then(a.1.cmp(&b.1)));
        for (k,(dist,j)) in ns.into_iter().take(7).enumerate(){
            near[i*14+2*k]=V::N(dist);near[i*14+2*k+1]=V::N((j+1) as f64);
        }
    }
    *d.list_mut("dc ten:最短7点").unwrap()=near;
    (d,(0..n).map(Some).collect())
}

pub(crate) struct SrevNied {
    detector:Detector,
    mapping:Vec<Option<usize>>,
    xy:Vec<f64>,
    names:Vec<String>,
    observations:Vec<(f64,V)>,
    last:Option<i64>,
    first:Option<i64>,
    picks:Vec<Pick>,
    pub solve_enabled:bool,
    taiwan:bool,
}
impl SrevNied{
    pub fn new(xy:&[f64],names:&[String])->Self{
        let (d,mapping)=layout(xy,names);
        let count=d.list("d ten:x").unwrap().len();
        Self{detector:d,mapping,xy:xy.to_vec(),names:names.to_vec(),observations:vec![(0.,V::from(""));count],last:None,first:None,picks:vec![Pick::default();names.len()],solve_enabled:false,taiwan:false}
    }
    pub(crate) fn new_taiwan(xy:&[f64],names:&[String])->Option<Self>{
        if names.len()<8 || xy.len()!=names.len()*2 || xy.chunks_exact(2).any(|p|
            !p[0].is_finite() || !p[1].is_finite() || !(17.0..38.0).contains(&p[0]) || !(113.0..134.0).contains(&p[1])){return None}
        let (detector,mapping)=taiwan_layout(xy,names);
        let count=names.len();
        Some(Self{detector,mapping,xy:xy.to_vec(),names:names.to_vec(),observations:vec![(0.,V::from(""));count],last:None,first:None,picks:vec![Pick::default();count],solve_enabled:false,taiwan:true})
    }
    pub fn reset(&mut self){
        let (d,mapping)=if self.taiwan{taiwan_layout(&self.xy,&self.names)}else{layout(&self.xy,&self.names)};
        self.detector=d;self.mapping=mapping;self.last=None;self.first=None;self.picks.fill(Pick::default());
    }
    pub fn process(&mut self,rows:&[i64],stamp_us:i64)->Result<&[Pick],()>{
        if rows.len()!=self.mapping.len()*8{return Err(())}
        if self.last==Some(stamp_us){return Ok(&self.picks)}
        if self.last.is_some_and(|t|stamp_us<t || stamp_us.saturating_sub(t)>120_000_000){self.reset()}
        let first=*self.first.get_or_insert(stamp_us);
        let seconds=(stamp_us as f64/1000.-EPOCH_2000_MS as f64)/1000.;
        self.detector.timer=60.+(stamp_us-first) as f64/1e6;
        self.observations.fill((0.,V::from("")));
        for (i,slot) in self.mapping.iter().enumerate(){
            let r=&rows[i*8..i*8+8];
            if let Some(j)=slot{
                if r[5]==stamp_us && r[7]&2==0{self.observations[*j]=observation(r[2],f64::from_bits(r[3] as u64));}
            }
        }
        // Use the original SREV event state; never run a second detector for HYP.
        for i in [52,57]{self.detector.list_mut("7システム設定").unwrap()[i-1]=V::B(self.solve_enabled);}
        self.detector.list_mut("7システム設定").unwrap()[61]=V::B(true);
        self.detector.process_frame(seconds,&self.observations).map_err(|_|())?;
        if self.solve_enabled {
            self.detector.keys.insert("3".into());
            self.detector.update_hyp_circles(true);
            let n=self.detector.list("4-3 検出id別情報").unwrap().len()/20;
            if n>0 {
                let _=self.detector.solve_next_hyp().map_err(|_|())?;
                let id=self.detector.variable("@hyp計算中").unwrap().num() as usize;
                if id>0 && id<=n && self.detector.hyp_estimate(id).is_some() {
                    self.detector.recalculate_hyp_arrivals(id).map_err(|_|())?;
                }
            }
        }
        let permission=self.detector.list("ten c:揺れ検出許可").unwrap();
        let trigger=self.detector.list("ten c:揺れ検出トリガー時間").unwrap();
        let intensity=self.detector.list("ten:震度").unwrap();
        let assoc=self.detector.list("ten:推定用").unwrap();
        for (i,slot) in self.mapping.iter().enumerate(){
            self.picks[i]=slot.map_or(Pick::default(),|j|{
                let p=permission[j].num() as i64;
                let active=p>=4 && intensity[j].num()>0. && self.observations[j].0>0.;
                let event_id=assoc[j*10+2].num() as i64;
                let t=if event_id>0 && assoc[j*10].num()>0.{assoc[j*10].num()}else{trigger[j].num()};
                Pick{active,permission:p,event_id,trigger_ms:if active && t>0. && t.is_finite(){(t*1000.).round() as i64+EPOCH_2000_MS}else{0}}
            });
        }
        self.last=Some(stamp_us);
        Ok(&self.picks)
    }
    // Export the active original event slots, including association membership.
    // Null estimate means the original solver has not produced one yet.
    pub fn source_rows(&self)->Value {
        let d=&self.detector;
        let info=d.list("4-3 検出id別情報").unwrap();
        let mut rows=Vec::new();
        for (i,e) in info.chunks_exact(20).enumerate(){
            if !e[1].truth(){continue}
            let id=i+1;
            let a=d.hyp_estimate(id).filter(|a|a.latitude.is_finite()&&a.longitude.is_finite()&&a.latitude.abs()<=90.&&a.longitude.abs()<=180.&&a.depth_km.is_finite()&&a.depth_km>=0.&&a.origin_seconds_2000.is_finite()&&a.origin_seconds_2000>0.);
            let m=d.magnitude_estimate(id).map(|m|m.magnitude).filter(|m|m.is_finite());
            let members:Vec<_>=self.picks.iter().enumerate().filter(|(_,p)|p.active&&p.event_id==id as i64).map(|(j,_)|j).collect();
            // Original p39 writes field 18 only on accepted HYP results.
            let now=d.list("#r:最新クラウド変数").unwrap()[0].num();
            let accepted=e[17].num();
            let last_accept=if a.is_some() && accepted.is_finite() && accepted>0. && accepted<=now {Some(accepted)}else{None};
            let hyp_state=if now-e[2].num()>=120. {"finished"}else if a.is_some(){"updating"}else{"pending"};
            rows.push(json!({"id":id,"start":e[2].num(),"count":e[3].num(),"members":members,
                "hyp_state":hyp_state,"hyp_accepted_at":last_accept,"observed_at":now,
                "estimate":a.map(|x|json!({"lat":x.latitude,"lon":x.longitude,"depth":x.depth_km,"origin":x.origin_seconds_2000,"error":if x.error.is_finite(){Some(x.error)}else{None},"magnitude":m,"p_radius":x.p_radius_km,"s_radius":x.s_radius_km}))}));
        }
        json!(rows)
    }
    #[cfg(test)]
    fn matched(&self)->usize{self.mapping.iter().flatten().count()}
}
#[cfg(test)]
mod tests{
    use super::*;
    #[test]
    fn taiwan_candidate_replay(){
        let Ok(path)=std::env::var("RQ_TAIWAN_CANDIDATE_INPUT")else{return};
        let j:Value=serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
        let mut reports=vec![];
        for case in j.as_array().unwrap(){
            let names:Vec<_>=case["stations"].as_array().unwrap().iter().map(|s|s["id"].as_str().unwrap().to_string()).collect();
            let xy:Vec<_>=case["stations"].as_array().unwrap().iter().flat_map(|s|[s["lat"].as_f64().unwrap(),s["lon"].as_f64().unwrap()]).collect();
            let (d,mapping)=taiwan_layout(&xy,&names);
            let count=names.len();
            let cells=d.list("dc grid連番:点がある番号").unwrap().len();
            let mut adapter=SrevNied{detector:d,mapping,xy:xy.clone(),names:names.clone(),observations:vec![(0.,V::from(""));count],last:None,first:None,picks:vec![Pick::default();count],solve_enabled:false,taiwan:true};
            let mut frames=vec![];
            for f in case["frames"].as_array().unwrap(){
                let t=f["time"].as_i64().unwrap()*1000;
                let mut rows=vec![0i64;count*8];
                for (i,v) in f["levels"].as_array().unwrap().iter().enumerate(){
                    let k=v.as_i64().unwrap();
                    rows[i*8+2]=k;rows[i*8+3]=f["fine"][i].as_f64().unwrap_or(f64::NAN).to_bits() as i64;
                    rows[i*8+5]=t;rows[i*8+7]=if k<0{2}else{0};
                }
                let active=adapter.process(&rows,t).unwrap().iter().enumerate().filter(|(_,p)|p.active).map(|(i,_)|names[i].clone()).collect::<Vec<_>>();
                let slots=adapter.source_rows();
                frames.push(json!({"time":f["time"],"active":active,"slots":slots.as_array().unwrap().len(),"baseline":f["baseline"]}));
            }
            reports.push(json!({"source":case["source"],"stations":count,"cells":cells,"frames":frames}));
        }
        let path=std::env::var("RQ_TAIWAN_CANDIDATE_OUTPUT").unwrap();
        std::fs::write(path,serde_json::to_string_pretty(&reports).unwrap()).unwrap();
    }
    #[test]
    fn ka_midpoint_bins(){
        let expected=[1,1,2,3,4,6,7,9,10,12,13,15,16,18,19,21,22,24,26,28,30];
        assert_eq!(observation(-1,f64::NAN).0,0.);
        for (i,&v) in expected.iter().enumerate(){assert_eq!(observation(i as i64,f64::NAN).0,v as f64,"KA {i}");}
        assert_eq!(observation(7,0.1).0,8.);
        assert_eq!(observation(7,0.2).0,9.);
    }
    #[test]
    fn exact_catalog_replay_parity(){
        let mut reference=fresh();
        let xs=reference.list("d ten:x").unwrap();
        let ys=reference.list("d ten:y").unwrap();
        let ns=reference.list("d ten:名前").unwrap();
        let xy:Vec<_>=ys.iter().zip(xs).flat_map(|(y,x)|[y.num(),x.num()]).collect();
        let names:Vec<_>=ns.iter().map(V::string).collect();
        let count=names.len();
        let mut adapter=SrevNied::new(&xy,&names);
        // Equal-sized co-located groups with equal thresholds retain distinct slots.
        assert_eq!(adapter.matched(),count);
        let mapping=adapter.mapping.clone();
        let mut rows=vec![0i64;count*8];
        for f in 0..24{
            let ts=846_209_400_000_000+i64::from(f)*1_000_000+EPOCH_2000_MS*1000;
            let mut input=vec![];
            for i in 0..count{
                let k=if f<10{-1}else if i%11==0{(f-9).min(20) as i64}else{2};
                let r=&mut rows[i*8..i*8+8];
                r[2]=k;r[3]=f64::NAN.to_bits() as i64;r[5]=ts;
                input.push(if mapping[i].is_some(){observation(k,f64::NAN)}else{(0.,V::from(""))});
            }
            reference.timer=60.+f as f64;
            reference.process_frame((ts as f64/1000.-EPOCH_2000_MS as f64)/1000.,&input).unwrap();
            let got=adapter.process(&rows,ts).unwrap();
            let p=reference.list("ten c:揺れ検出許可").unwrap();
            let v=reference.list("ten:震度").unwrap();
            let a=reference.list("ten:推定用").unwrap();
            for i in 0..count{
                if mapping[i].is_none(){assert_eq!(got[i],Pick::default());continue}
                assert_eq!(got[i].permission,p[i].num() as i64,"frame {f} station {i}");
                assert_eq!(got[i].active,p[i].num()>=4.&&v[i].num()>0.&&input[i].0>0.);
                assert_eq!(got[i].event_id,a[i*10+2].num() as i64);
            }
        }
    }
}

