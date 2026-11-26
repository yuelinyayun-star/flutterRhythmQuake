//! SREV modified edition HYP entrypoints. The generated search is the original
//! coordinate descent, using its own JMA2001 coefficients and event state.
//! A synchronous solve owns the detector state for its duration.
use super::*;
#[derive(Debug,Clone,PartialEq)]
pub struct HypEstimate {
 pub event_id:usize,pub longitude:f64,pub latitude:f64,pub depth_km:f64,
 pub origin_seconds_2000:f64,pub error:f64,pub p_radius_km:Option<f64>,pub s_radius_km:Option<f64>,
}
impl Detector {
 /// Reproducible random stream; distribution matches Scratch integer random.
 /// Set a different seed for production if desired.
 pub fn seed_hyp(&self,seed:u32){self.hyp_rng.set(seed);self.hyp_draws.set(0);}
 pub fn hyp_random_draws(&self)->u64{self.hyp_draws.get()}
 #[inline] pub(crate) fn random_int(&self,a:f64,b:f64)->f64 {
  let (lo,hi)=if a>b{(b,a)}else{(a,b)};
  // TurboWarp generic random returns equal bounds without consuming RNG.
  if lo==hi{return lo}
  let x=self.hyp_rng.get().wrapping_mul(1664525).wrapping_add(1013904223);
  self.hyp_rng.set(x);self.hyp_draws.set(self.hyp_draws.get()+1);
  lo+((x as f64/4294967296.)*((hi+1.)-lo)).floor()
 }
 /// Original JMA2001 polynomial (P/S, elapsed->distance or distance->travel time).
 /// Returns (distance or travel seconds, epicentral radius).
 pub fn hyp_travel(&mut self,value:f64,depth:f64,p:bool,inverse:bool)->(f64,f64){
  self.hyp_travel_raw(V::N(value),V::N(depth),V::B(p),V::B(inverse));
  (self.variable("tjma:波震源距離or波走時").unwrap().num(),self.variable("tjma3:波震央距離").unwrap().num())
 }
 fn valid_event(&self,id:usize)->bool{
  let l=self.list("4-3 検出id別情報").unwrap();
  id>0&&id<=l.len()/20&&self.list("4-4 検出id震源要素").unwrap().len()/10>=id
 }
 pub fn hyp_estimate(&self,id:usize)->Option<HypEstimate>{
  if !self.valid_event(id){return None}
  let row=&self.list("4-4 検出id震源要素")?[(id-1)*10..id*10];
  let info=&self.list("4-3 検出id別情報")?[(id-1)*20..id*20];
  let n=|v:&V|{let n=v.compare_num();if n.is_finite(){Some(n)}else{None}};
  Some(HypEstimate{event_id:id,longitude:n(&row[1])?,latitude:n(&row[2])?,depth_km:n(&row[3])?,origin_seconds_2000:n(&row[4])?,error:info[10].raw_num(),p_radius_km:n(&row[5]),s_radius_km:n(&row[6])})
 }
 /// Solve a specific one-based event, using the original source limits and phases.
 /// Returns existing estimate unchanged when original age/quality gates reject an update.
 pub fn solve_hyp(&mut self,id:usize)->Result<Option<HypEstimate>, &'static str>{
  if !self.valid_event(id){return Err("invalid HYP event id")}
  self.hyp_solve_raw(V::N(id as f64),V::N(((id-1)*20) as f64));
  self.update_magnitudes();
  Ok(self.hyp_estimate(id))
 }
 /// Advance original round-robin event selection, then solve its selected event.
 /// Does not emulate overlapping Scratch render/update threads.
 pub fn solve_next_hyp(&mut self)->Result<Option<HypEstimate>, &'static str>{
  if self.list("4-3 検出id別情報").unwrap().is_empty(){return Ok(None)}
  self.hyp_next_raw();
  let id=self.variable("@hyp計算中").unwrap().num() as usize;
  self.solve_hyp(id)
 }
 pub fn update_hyp_circles(&mut self,observations_updated:bool){self.hyp_circles_raw(V::B(observations_updated))}
 pub fn recalculate_hyp_arrivals(&mut self,id:usize)->Result<(), &'static str>{
  if !self.valid_event(id){return Err("invalid HYP event id")}
  self.hyp_recalculate_raw(V::N(id as f64));Ok(())
 }
}
#[cfg(test)]
mod tests{
 use super::*;
 #[test] fn empty_event(){let mut d=Detector::new();assert!(d.solve_hyp(0).is_err());assert!(d.solve_next_hyp().unwrap().is_none());}
 #[test] fn travel_table(){let mut d=Detector::new();for dep in [10.,50.,100.,300.,700.] {for p in [true,false]{let (t,_)=d.hyp_travel(100.,dep,p,true);assert!(t.is_finite());}}}
 #[test] fn random_reproducible(){let d=Detector::new();d.seed_hyp(123);let a=d.random_int(1.,10.);d.seed_hyp(123);assert_eq!(a,d.random_int(1.,10.));assert_eq!(d.hyp_random_draws(),1);assert_eq!(d.random_int(1.,1.),1.);assert_eq!(d.hyp_random_draws(),1);}
}
