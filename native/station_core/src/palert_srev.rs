//! P-Alert detection only; PGA/PGV levels and display remain unchanged.
use crate::srev_nied::SrevNied;
use std::collections::VecDeque;
pub(crate) struct PAlertSrev {
    adapter: SrevNied,
    noise: Vec<VecDeque<(i64,f64)>>,
    neighbors: Vec<Vec<usize>>,
    previous_cluster: Vec<bool>,
    last: Option<i64>,
    hyp_gate: Option<crate::palert_hyp_gate::HypGate>,
}
impl PAlertSrev {
    pub fn new(points:&[(f64,f64)],names:&[String])->Option<Self>{
        let xy=points.iter().flat_map(|p|[p.0,p.1]).collect::<Vec<_>>();
        let adapter=SrevNied::new_taiwan(&xy,names)?;
        let neighbors=points.iter().map(|a|points.iter().enumerate().filter_map(|(j,b)|{
            let dy=(a.0-b.0)*111.2;
            let dx=(a.1-b.1)*111.2*((a.0+b.0)/2.).to_radians().cos();
            (dy.hypot(dx)<=30.).then_some(j)
        }).collect()).collect();
        Some(Self{adapter,noise:vec![VecDeque::new();points.len()],neighbors,previous_cluster:vec![false;points.len()],last:None,hyp_gate:None})
    }
    pub(crate) fn enable_hyp_candidate(&mut self,points:Vec<(f64,f64)>){
        self.adapter.solve_enabled=true;
        self.hyp_gate=Some(crate::palert_hyp_gate::HypGate::new(points));
    }
    pub(crate) fn candidate_snapshot(&self)->Option<serde_json::Value>{self.hyp_gate.as_ref().map(|g|g.snapshot())}
    #[cfg(test)]
    pub(crate) fn enable_hyp_for_audit(&mut self){ self.adapter.solve_enabled=true; }
    #[cfg(test)]
    pub(crate) fn audit_source_rows(&self)->serde_json::Value{ self.adapter.source_rows() }
    pub fn reset(&mut self){
        if let Some(g)=self.hyp_gate.as_mut(){g.reset();}
        self.adapter.reset();self.noise.iter_mut().for_each(|h|h.clear());
        self.previous_cluster.fill(false);self.last=None;
    }
    pub fn floor(history:&VecDeque<(i64,f64)>)->f64{
        if history.len()<10{return 0.59}
        let mut vals=history.iter().map(|x|x.1).collect::<Vec<_>>();
        let n=vals.len()/4;
        let (_,q,_)=vals.select_nth_unstable_by(n,|a,b|a.total_cmp(b));
        (*q*3.).clamp(0.25,1.4)
    }
    // Only current observations. Below-floor valid PGA is quiet, not missing.
    pub fn process(&mut self,stamp:i64,samples:&[Option<(f64,i64)>],sensitivity:i32)->Option<Vec<usize>>{
        if samples.len()!=self.noise.len(){return None}
        if self.last.is_some_and(|old|stamp<=old){return None}
        if self.last.is_some_and(|old|stamp-old>120_000){self.reset()}
        let minimum=if sensitivity==1{4}else{3};
        let n=samples.len();
        let mut rows=vec![0i64;n*8];let mut above=vec![false;n];
        let us=stamp.checked_mul(1000)?;
        for (i,sample) in samples.iter().enumerate(){
            let h=&mut self.noise[i];
            while h.front().is_some_and(|x|x.0<stamp-90_000){h.pop_front();}
            let floor=if sensitivity==3{(Self::floor(h)*0.85).max(0.25)}else{Self::floor(h)};
            let k=match sample{
                Some((p,k)) if p.is_finite() && *p>=0. && (0..=20).contains(k)=>{
                    let pass=*p>=floor;above[i]=pass;
                    h.push_back((stamp,*p));
                    if pass{*k}else{0}
                },
                _=>-1
            };
            rows[i*8+2]=k;rows[i*8+3]=f64::NAN.to_bits() as i64;
            rows[i*8+5]=us;rows[i*8+7]=if k<0{2}else{0};
        }
        let picks=self.adapter.process(&rows,us).ok()?;
        let active=picks.iter().enumerate().map(|(i,p)|p.active&&above[i]).collect::<Vec<_>>();
        let mut cluster=vec![false;n];
        for (i,near) in self.neighbors.iter().enumerate(){
            if active[i] && near.iter().filter(|&&j|active[j]).count()>=minimum{
                for &j in near{if active[j]{cluster[j]=true;}}
            }
        }
        // Local continuity; disjoint clusters cannot share a global event latch.
        let adjacent=self.last.is_some_and(|old|stamp-old<=6000);
        let mut confirmed=vec![false;n];
        if adjacent{
            for (i,near) in self.neighbors.iter().enumerate(){
                if active[i] && near.iter().filter(|&&j|active[j]).count()>=minimum
                    && near.iter().any(|&j|active[j]&&self.previous_cluster[j]){
                    for &j in near{if active[j]{confirmed[j]=true;}}
                }
            }
        }
        self.last=Some(stamp);self.previous_cluster=cluster;
        let confirmed=confirmed.iter().enumerate().filter_map(|(i,v)|v.then_some(i)).collect::<Vec<_>>();
        if let Some(g)=self.hyp_gate.as_mut(){g.update(stamp,&self.adapter.source_rows(),&confirmed,samples);}
        Some(confirmed)
    }
}
#[cfg(test)]
mod tests{
    use super::*;
    #[test] fn archived_five_events_and_quiet_tails(){
        let Ok(path)=std::env::var("RQ_PALERT_REPLAY_INPUT")else{return};
        let input:serde_json::Value=serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
        let mut report=vec![];
        for c in input.as_array().unwrap(){
            let name=c["source"].as_str().unwrap();
            if !name.ends_with("-palert-fixed0.0"){continue}
            let cat=c["stations"].as_array().unwrap();
            let names=cat.iter().map(|s|s["id"].as_str().unwrap().to_owned()).collect::<Vec<_>>();
            let points=cat.iter().map(|s|(s["lat"].as_f64().unwrap(),s["lon"].as_f64().unwrap())).collect::<Vec<_>>();
            let fs=c["frames"].as_array().unwrap();
            for sensitivity in [1,2,3]{
            let mut d=PAlertSrev::new(&points,&names).unwrap();
            let tail=fs.last().unwrap()["time"].as_i64().unwrap()-60_000;
            let mut out=vec![];
            for f in fs{
                let stamp=f["time"].as_i64().unwrap();
                let samples=f["pga"].as_array().unwrap().iter().zip(f["levels"].as_array().unwrap()).map(|(p,k)|Some((p.as_f64()?,k.as_i64()?))).collect::<Vec<_>>();
                let now=std::time::Instant::now();
                let got=d.process(stamp,&samples,sensitivity).unwrap();
                let elapsed_us=now.elapsed().as_micros();
                assert!(d.process(stamp,&samples,sensitivity).is_none(),"duplicate must not advance history");
                if stamp>=tail{assert!(got.is_empty(),"{} late confirmed cluster",name);}
                out.push(serde_json::json!({"time":stamp,"confirmed":got.iter().map(|&i|&names[i]).collect::<Vec<_>>(),"old":f["baseline"],"elapsed_us":elapsed_us}));
            }
            assert!(out.iter().any(|r|!r["confirmed"].as_array().unwrap().is_empty()),"{} missed",name);
            d.reset();
            for f in fs.iter().filter(|f|f["time"].as_i64().unwrap()>=tail){
                let samples=f["pga"].as_array().unwrap().iter().zip(f["levels"].as_array().unwrap()).map(|(p,k)|Some((p.as_f64()?,k.as_i64()?))).collect::<Vec<_>>();
                assert!(d.process(f["time"].as_i64().unwrap(),&samples,sensitivity).unwrap().is_empty(),"{} cold tail",name);
            }
            report.push(serde_json::json!({"case":name,"sensitivity":sensitivity,"frames":out}));
            }
        }
        assert_eq!(report.len(),15);
        std::fs::write(std::env::var("RQ_PALERT_REPLAY_OUTPUT").unwrap(),serde_json::to_string_pretty(&report).unwrap()).unwrap();
    }
    #[test] fn floor_is_causal_and_bounded(){
        let mut h=VecDeque::new();assert_eq!(PAlertSrev::floor(&h),0.59);
        for i in 0..10{h.push_back((i,0.1));}
        assert!((PAlertSrev::floor(&h)-0.3).abs()<1e-10);
        h.iter_mut().for_each(|x|x.1=10.);assert_eq!(PAlertSrev::floor(&h),1.4);
    }
    #[test] fn rejects_outside_catalogue_and_small_catalogue(){
        assert!(PAlertSrev::new(&[(0.,0.);8],&vec!["x".into();8]).is_none());
        assert!(PAlertSrev::new(&[(23.,121.);2],&vec!["x".into();2]).is_none());
    }
}
