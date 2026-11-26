//! Experimental P-Alert publication gate. No effect on the detector or NIED.
use serde_json::{Value,json};
use std::collections::{BTreeMap,BTreeSet};

#[derive(Default)]
struct Episode {
    peaks: BTreeMap<usize,f64>,
    seen: BTreeSet<usize>,
    reported: BTreeSet<usize>,
    last_support: Option<i64>,
    last_accept: Option<f64>,
    frozen: bool,
    report: u32,
    published: Option<Value>,
}

pub(crate) struct HypGate {
    points: Vec<(f64,f64)>,
    slots: BTreeMap<(u64,u64),Episode>,
    last: Option<i64>,
}
impl HypGate {
    pub fn new(points: Vec<(f64,f64)>)->Self {
        Self{points,slots:BTreeMap::new(),last:None}
    }
    pub fn reset(&mut self) { self.slots.clear();self.last=None; }
    pub fn update(&mut self,stamp:i64,rows:&Value,confirmed:&[usize],samples:&[Option<(f64,i64)>])->Vec<Value>{
        if samples.len()!=self.points.len() || self.last.is_some_and(|t|stamp<=t){return vec![]}
        if self.last.is_some_and(|t|stamp-t>120_000){self.reset()}
        self.last=Some(stamp);
        let confirmed:BTreeSet<_>=confirmed.iter().copied().collect();
        let mut active=BTreeSet::new();
        let mut commits=vec![];
        for row in rows.as_array().into_iter().flatten(){
            let (Some(id),Some(start))=(row["id"].as_u64(),row["start"].as_f64())else{continue};
            if !start.is_finite(){continue}
            let key=(id,start.to_bits());
            active.insert(key);
            let state=self.slots.entry(key).or_default();
            if state.last_support.is_some_and(|t|stamp-t>10_000){state.frozen=true;}
            if row["hyp_state"]=="finished"{state.frozen=true;}
            if state.frozen{
                if let Some(p)=state.published.as_mut(){p["state"]=json!("finished");}
                continue
            }
            // Match the offline candidate: accumulate only same-slot confirmed
            // members after a valid geometric proposal exists.
            let e=&row["estimate"];
            if !e.is_object(){continue}
            let (Some(lat),Some(lon),Some(dep),Some(origin))=(e["lat"].as_f64(),e["lon"].as_f64(),e["depth"].as_f64(),e["origin"].as_f64())else{continue};
            if ![lat,lon,dep,origin].iter().all(|x|x.is_finite())||lat.abs()>90.||lon.abs()>180.||dep<0.{continue}
            let fresh:BTreeSet<_>=row["members"].as_array().into_iter().flatten().filter_map(|v|v.as_u64().map(|i|i as usize))
                .filter(|i|*i<samples.len()&&confirmed.contains(i)&&samples[*i].is_some_and(|(p,k)|p.is_finite()&&p>=0.&& (0..=20).contains(&k))).collect();
            if fresh.len()>=5{state.last_support=Some(stamp);}
            for &i in &fresh{
                if let Some((p,_))=samples[i]{
                    if p>0.{state.peaks.entry(i).and_modify(|v|*v=v.max(p)).or_insert(p);}
                }
            }
            state.seen.extend(fresh.iter().copied());
            let Some(accepted)=row["hyp_accepted_at"].as_f64()else{continue};
            if row["hyp_state"]!="updating"||fresh.len()<5||!accepted.is_finite()||
                state.last_accept.is_some_and(|a|accepted<=a)||
                (state.report>0&&state.seen.difference(&state.reported).count()<3){continue}
            // No new solve, only the existing PGA attenuation inverse evaluated
            // with the accepted geometry and the event's measured PGA peaks.
            let mut ms=vec![];
            for (&i,&pga) in &state.peaks{
                let (y,x)=self.points[i];let mean=(lat+y)/2.;
                let ys=((-0.000003885162*mean+0.0005279958)*mean-0.004162794)*mean+110.60424;
                let xs=((0.0000614022*mean-0.0204)*mean+0.091614)*mean+110.44248;
                let d=(((lat-y)*ys).powi(2)+((lon-x)*xs).powi(2)+dep*dep).sqrt();
                if d>0.&&d.is_finite(){let m=(libm::log(pga/1.657)+1.607*libm::log(d))/1.533;if m.is_finite(){ms.push(m);}}
            }
            ms.sort_by(f64::total_cmp);
            let magnitude=if ms.len()<5{None}else{let n=ms.len();Some(if n%2==0{(ms[n/2-1]+ms[n/2])/2.}else{ms[n/2]})};
            state.report+=1;state.last_accept=Some(accepted);state.reported=state.seen.clone();
            let published=json!({"id":id,"start":start,"time":stamp,"report":state.report,"state":"updating",
                "lat":lat,"lon":lon,"dep":dep,"origin":origin,"accept":accepted,"fresh":fresh.len(),
                "peak_count":state.peaks.len(),"pga_m":magnitude,"raw_m":e["magnitude"],"error":e["error"]});
            state.published=Some(published.clone());commits.push(published);
        }
        // Keep the slot's tombstone until the input stream resets so a slot
        // with the same identity cannot re-open after losing support.
        for (key,state) in &mut self.slots{
            if !active.contains(key){state.frozen=true;state.published=None;}
        }
        commits
    }
    pub fn snapshot(&self)->Value{json!(self.slots.values().filter_map(|s|s.published.as_ref()).collect::<Vec<_>>())}
}

#[cfg(test)]
mod tests{
    use super::*;
    fn row(start:f64,accepted:f64,members:Vec<usize>)->Value{
        json!([{"id":1,"start":start,"hyp_state":"updating","hyp_accepted_at":accepted,
          "members":members,"estimate":{"lat":24.,"lon":121.,"depth":10.,"origin":start-2.,"magnitude":3.,"error":10.}}])
    }
    #[test]
    fn lifecycle_and_peaks(){
        let mut g=HypGate::new(vec![(24.1,121.1);8]);
        let samples=vec![Some((2.,9));8];
        let a=(0..5).collect::<Vec<_>>();let b=(0..8).collect::<Vec<_>>();
        assert!(g.update(1000,&row(1.,1.,a.clone()),&a[..4],&samples).is_empty());
        let first=g.update(2000,&row(1.,2.,a.clone()),&a,&samples);
        assert_eq!(first[0]["report"],1);assert_eq!(first[0]["peak_count"],5);
        assert!(g.update(2000,&row(1.,3.,b.clone()),&b,&samples).is_empty());
        assert!(g.update(3000,&row(1.,3.,a.clone()),&a,&samples).is_empty());
        let second=g.update(4000,&row(1.,4.,b.clone()),&b,&samples);
        assert_eq!(second[0]["report"],2);assert_eq!(second[0]["peak_count"],8);
        assert_eq!(first[0]["pga_m"],second[0]["pga_m"]);
        assert!(g.update(15000,&row(1.,5.,b.clone()),&b,&samples).is_empty());
        assert_eq!(g.snapshot()[0]["state"],"finished");
        assert_eq!(g.snapshot()[0]["report"],2);
        assert!(g.update(16000,&json!([]),&[],&samples).is_empty());
        assert_eq!(g.snapshot(),json!([]));
        assert!(g.update(17000,&row(1.,6.,b.clone()),&b,&samples).is_empty());
        assert_eq!(g.update(18000,&row(2.,7.,a.clone()),&a,&samples)[0]["report"],1);
        g.reset();assert_eq!(g.snapshot(),json!([]));
    }
    #[test]
    fn saved_six_event_gate_matches_reference(){
        let Ok(root)=std::env::var("RQ_PALERT_GATE_DIR")else{return};
        let read=|name:&str|->Value{serde_json::from_str(&std::fs::read_to_string(std::path::Path::new(&root).join(name)).unwrap()).unwrap()};
        let raw=read("palert_hyp_six_event_input.json");
        let audit=read("palert_hyp_six_event_audit.json");
        let expected=read("palert_hyp_fast_gate_audit.json");
        let mut report=vec![];let mut total=0;
        for c in audit.as_array().unwrap(){
            let name=c["case"].as_str().unwrap();
            let input=raw.as_array().unwrap().iter().find(|v|v["source"]==name).unwrap();
            let reference=expected.as_array().unwrap().iter().find(|v|v["event"]==name.split('-').next().unwrap()&&v["policy"]=="fresh5_new3_gap10").unwrap();
            let points=input["stations"].as_array().unwrap().iter().map(|s|(s["lat"].as_f64().unwrap(),s["lon"].as_f64().unwrap())).collect();
            let mut gate=HypGate::new(points);let mut got=vec![];let mut micros=vec![];
            let first=c["frames"][0]["time"].as_i64().unwrap();
            for (f,s) in c["frames"].as_array().unwrap().iter().zip(input["frames"].as_array().unwrap()){
                let t=f["time"].as_i64().unwrap();assert_eq!(f["time"],s["time"]);
                let samples=s["pga"].as_array().unwrap().iter().zip(s["levels"].as_array().unwrap()).map(|(p,k)|Some((p.as_f64()?,k.as_i64()?))).collect::<Vec<_>>();
                let ids=f["confirmed"].as_array().unwrap().iter().map(|i|i.as_u64().unwrap() as usize).collect::<Vec<_>>();
                let now=std::time::Instant::now();
                got.extend(gate.update(t,&f["srev"],&ids,&samples));micros.push(now.elapsed().as_micros());
                total+=1;
            }
            let want=reference["rows"].as_array().unwrap();
            assert_eq!(got.len(),want.len(),"{} commits",name);
            for (g,w) in got.iter().zip(want){
                assert_eq!((g["time"].as_i64().unwrap()-first) as f64/1000.,w["t"].as_f64().unwrap());
                for k in ["lat","lon","dep","origin","accept","pga_m"]{
                    if g[k].is_null(){assert!(w[k].is_null());continue}
                    assert!((g[k].as_f64().unwrap()-w[k].as_f64().unwrap()).abs()<1e-8,"{} {}",name,k);
                }
                assert_eq!(g["fresh"],w["fresh"]);assert_eq!(g["peak_count"],w["peak_count"]);
            }
            micros.sort_unstable();
            println!("{}: {} commits, gate p95={} us",name,got.len(),micros[micros.len()*95/100]);
            report.push(json!({"case":name,"commits":got,"gate_p95_us":micros[micros.len()*95/100]}));
        }
        assert_eq!(total,1226);assert_eq!(report.iter().map(|c|c["commits"].as_array().unwrap().len()).sum::<usize>(),90);
        std::fs::write(std::path::Path::new(&root).join("palert_hyp_gate_rust_parity.json"),serde_json::to_string_pretty(&report).unwrap()).unwrap();
    }
}
