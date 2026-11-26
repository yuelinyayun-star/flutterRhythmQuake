//! Native port of the modified SREV sprite 独自震度計算.
//! Uses nearest catalog station (not nearest triggered station), epicentral
//! distance, and the original maximum-intensity rule. Depth is not used.
use super::*;
#[derive(Debug,Clone,Copy,PartialEq)]
pub struct MagnitudeEstimate{
 pub event_id:usize,pub magnitude:f64,pub longitude:f64,pub latitude:f64,
 pub nearest_station_km:f64,pub intensity:f64,
}
const OUTPUT:&str="4-6 推定まぐ";
const EVENTS:&str="4-4 検出id震源要素";
const INFO:&str="4-3 検出id別情報";
const GLOBAL:&str="4リアルタイム状況(最大震度など)";
#[inline] fn source_distance(lon:f64,lat:f64,x:f64,y:f64)->f64{
 let dy=(lat-y)*111.2;
 let dx=(6371.*((lon-x)*(3.1416/180.)))*math("cos",(lat+y)/2.);
 nz(dy*dy+dx*dx).sqrt().max(20.)
}
#[inline] fn formula(intensity:f64,distance:f64)->f64{
 let amp=10_f64.powf((intensity-0.94)/2.);
 let m=nz((amp*amp).ln()/std::f64::consts::LN_10)+nz(1.73*nz(distance.ln()/std::f64::consts::LN_10));
 if m<0.{0.}else{m}
}
impl Detector {
 /// Original algorithm: one event uses global max intensity; multiple event
 /// slots use each slot's max, with its original >4 conversion. The catalog
 /// includes every station regardless of availability/trigger status.
 pub fn magnitude_estimate(&self,id:usize)->Option<MagnitudeEstimate>{
  let events=self.list(EVENTS)?;
  let count=events.len()/10;
  if id==0||id>count||id>self.list(OUTPUT)?.len(){return None}
  let row=&events[(id-1)*10..id*10];
  // Original outer if skips blank longitude, preserving old output list item.
  if eq(&row[1],&EMPTY){return None}
  let lon=round(row[1].num()*10.)/10.;
  let lat=round(row[2].num()*10.)/10.;
  let intensity=if count==1{self.list(GLOBAL)?.first()?.num()}else{
   let i=self.list(INFO)?.get((id-1)*20+5).unwrap_or(&EMPTY).num();
   if i>4.{(i-4.)/2.+5.}else{i}
  };
  let mut dist=99999999999999.;
  for (x,y) in self.list("d ten:x")?.iter().zip(self.list("d ten:y")?){
   let d=source_distance(lon,lat,x.num(),y.num());
   if d<dist{dist=d}
   if dist==20.{break} // minimum attainable distance; remaining points cannot change output
  }
  Some(MagnitudeEstimate{event_id:id,magnitude:formula(intensity,dist),longitude:lon,latitude:lat,nearest_station_km:dist,intensity})
 }
 /// Run a single pass of the original forever-loop's calculation.
 /// Blank event slots preserve their previous 4-6 item, as in SREV.
 pub fn update_magnitudes(&mut self){
  let n=(self.list(EVENTS).unwrap().len()/10).min(self.list(OUTPUT).unwrap().len());
  for id in 1..=n{
   if let Some(m)=self.magnitude_estimate(id){self.list_mut(OUTPUT).unwrap()[id-1]=V::N(m.magnitude);}
  }
 }
}
#[cfg(test)]
mod tests{
 use super::*;
 fn event(d:&mut Detector,lon:f64,lat:f64){
  let mut row=vec![EMPTY;10];row[1]=V::N(lon);row[2]=V::N(lat);row[3]=V::N(10.);
  d.list_mut(EVENTS).unwrap().extend(row);
  d.list_mut(INFO).unwrap().extend(vec![EMPTY;20]);
 }
 #[test]fn source_floor_and_clamp(){assert_eq!(source_distance(135.,35.,135.,35.),20.);assert_eq!(formula(-10.,20.),0.);}
 #[test]fn single_and_multiple(){let mut d=Detector::new();event(&mut d,135.,35.);d.list_mut(GLOBAL).unwrap()[0]=V::N(3.4);assert_eq!(d.magnitude_estimate(1).unwrap().intensity,3.4);event(&mut d,140.,35.);d.list_mut(INFO).unwrap()[5]=V::N(6.);assert_eq!(d.magnitude_estimate(1).unwrap().intensity,6.);d.update_magnitudes();assert!(d.list(OUTPUT).unwrap()[0].num()>0.);}
 #[test]fn blank_slot_preserves_output(){let mut d=Detector::new();let prior=d.list(OUTPUT).unwrap()[0].clone();d.list_mut(EVENTS).unwrap().extend(vec![EMPTY;10]);d.update_magnitudes();assert_eq!(d.list(OUTPUT).unwrap()[0],prior);assert!(d.magnitude_estimate(1).is_none());}
}
