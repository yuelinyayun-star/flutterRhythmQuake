//! Native SREV detector. Generated procedure bodies retain the original
//! Scratch source's ordering and one-based list addressing.
use std::{collections::HashSet, sync::Arc};

// Compact text handle: immutable numeric conversion and flags stored once per string.
#[derive(Debug)]
struct StaticText { text:&'static str, number:f64, cmp_number:f64, truth:bool }
#[derive(Debug)]
struct OwnedText { text:Box<str>, number:f64, cmp_number:f64, truth:bool }
#[derive(Clone,Debug)]
pub struct Text(TextStorage);
#[derive(Clone,Debug)]
enum TextStorage { Static(&'static StaticText), Owned(Arc<OwnedText>) }
impl AsRef<str> for Text { #[inline] fn as_ref(&self)->&str {match &self.0{TextStorage::Static(t)=>t.text,TextStorage::Owned(t)=>&t.text}} }
impl PartialEq for Text {fn eq(&self,other:&Self)->bool{self.as_ref()==other.as_ref()}}
impl Text {
 #[inline] fn number(&self)->f64 {match &self.0{TextStorage::Static(t)=>t.number,TextStorage::Owned(t)=>t.number}}
 #[inline] fn cmp_number(&self)->f64 {match &self.0{TextStorage::Static(t)=>t.cmp_number,TextStorage::Owned(t)=>t.cmp_number}}
 #[inline] fn truth(&self)->bool {match &self.0{TextStorage::Static(t)=>t.truth,TextStorage::Owned(t)=>t.truth}}
}
#[derive(Clone,Debug,PartialEq)]
pub enum V { N(f64), S(Text), B(bool) }
macro_rules! lit {($t:literal,$n:expr,$c:expr,$b:expr)=>{V::S(Text(TextStorage::Static(&StaticText{text:$t,number:$n,cmp_number:$c,truth:$b})))}}
const EMPTY:V=lit!("",0.,f64::NAN,false);
static EMPTY_REF:V=lit!("",0.,f64::NAN,false);
#[allow(dead_code)] const FALSE:V=V::B(false);
mod static_texts;
mod generated;
mod hyp;
mod magnitude;
pub use magnitude::MagnitudeEstimate;
pub use hyp::HypEstimate;
fn parse_number(x:&str)->f64{
 let x=x.trim();if x.is_empty(){0.}else if x=="Infinity"||x=="+Infinity"{f64::INFINITY}else if x=="-Infinity"{f64::NEG_INFINITY}else{x.parse().unwrap_or(f64::NAN)}
}
#[inline] fn s(x:&str)->V {
 if let Some(v)=static_texts::known(x){return v}
 let n=parse_number(x);let cmp_number=if x.trim().is_empty(){f64::NAN}else{n};
 let truth=!x.is_empty()&&x!="0"&&!x.eq_ignore_ascii_case("false");
 V::S(Text(TextStorage::Owned(Arc::new(OwnedText{text:x.into(),number:n,cmp_number,truth}))))
}
impl From<f64> for V { fn from(x:f64)->Self{Self::N(x)} }
impl From<&str> for V {fn from(x:&str)->Self{s(x)}}
#[inline] fn nz(n:f64)->f64{if n.is_nan(){0.0}else{n}}
#[inline] fn truth_num(n:f64)->bool{n!=0.0&&!n.is_nan()}
impl V {
    #[inline] fn raw_num(&self)->f64 {match self {V::N(x)=>*x,V::B(x)=>u8::from(*x) as f64,V::S(x)=>x.number()}}
    #[inline] pub fn num(&self)->f64{nz(self.raw_num())}
    pub fn string(&self)->String{match self{V::S(x)=>x.as_ref().to_owned(),V::B(x)=>x.to_string(),V::N(n)=>if n.is_nan(){"NaN".into()}else if *n==f64::INFINITY{"Infinity".into()}else if *n==f64::NEG_INFINITY{"-Infinity".into()}else if *n==0.0{"0".into()}else{n.to_string()}}}
    #[inline] pub fn truth(&self)->bool{match self{V::B(b)=>*b,V::N(n)=>truth_num(*n),V::S(t)=>t.truth()}}
    fn json(v:&serde_json::Value)->Self{match v{serde_json::Value::Number(n)=>V::N(n.as_f64().unwrap()),serde_json::Value::Bool(b)=>V::B(*b),serde_json::Value::String(t)=>s(t),_=>EMPTY}}
    #[inline] fn compare_num(&self)->f64 {match self {V::S(t)=>t.cmp_number(),_=>self.raw_num()}}
}
#[cold] fn lexical_cmp(a:&V,b:&V)->i8 {
    use std::borrow::Cow;
    fn text(v:&V)->Cow<'_,str>{match v {V::S(t)=>Cow::Borrowed(t.as_ref()),_=>Cow::Owned(v.string())}}
    let a=text(a);let b=text(b);
    if a.is_empty(){return if b.is_empty(){0}else{-1}}
    if b.is_empty(){return 1}
    let o=if a.is_ascii()&&b.is_ascii(){a.bytes().map(|x|x.to_ascii_lowercase()).cmp(b.bytes().map(|x|x.to_ascii_lowercase()))}else{a.to_lowercase().cmp(&b.to_lowercase())};
    match o{std::cmp::Ordering::Less=>-1,std::cmp::Ordering::Equal=>0,std::cmp::Ordering::Greater=>1}
}
#[inline] fn cmp(a:&V,b:&V)->i8 {
 let (x,y)=(a.compare_num(),b.compare_num());
 if x.is_nan()||y.is_nan(){
  if matches!(a,V::S(t) if t.as_ref().is_empty()){return if matches!(b,V::S(t) if t.as_ref().is_empty()){0}else{-1}}
  if matches!(b,V::S(t) if t.as_ref().is_empty()){return 1}
  lexical_cmp(a,b)
 }else if x<y{-1}else if x>y{1}else{0}
}
#[inline] fn eq(a:&V,b:&V)->bool{cmp(a,b)==0}
#[inline] fn round(n:f64)->f64{(n+0.5).floor()}
#[inline] fn repeat_count(n:f64)->usize{round(n).max(0.0) as usize}
#[inline] fn smod(a:f64,b:f64)->f64{let r=a%b;if r/b<0.0{r+b}else{r}}
fn join(a:V,b:V)->V{s(&(a.string()+&b.string()))}
#[inline] fn letter_ref(a:&V,b:f64)->V{
    let i=b.floor() as i64-1;if i<0{return EMPTY}
    fn character(t:&str,i:usize)->V{
        const DIGITS:[V;10]=[lit!("0",0.,0.,false),lit!("1",1.,1.,true),lit!("2",2.,2.,true),lit!("3",3.,3.,true),lit!("4",4.,4.,true),lit!("5",5.,5.,true),lit!("6",6.,6.,true),lit!("7",7.,7.,true),lit!("8",8.,8.,true),lit!("9",9.,9.,true)];
        if t.is_ascii(){if let Some(c)=t.as_bytes().get(i){if c.is_ascii_digit(){return DIGITS[(c-b'0') as usize].clone()}}else{return EMPTY}}
        t.chars().nth(i).map(|c|s(&c.to_string())).unwrap_or(EMPTY)
    }
    match a {V::S(t)=>character(t.as_ref(),i as usize),_=>character(&a.string(),i as usize)}
}
#[inline] fn math(op:&str,n:f64)->f64{match op{"abs"=>n.abs(),"floor"=>n.floor(),"sqrt"=>n.sqrt(),"ln"=>n.ln(),"log"=>n.log10(),"e ^"=>n.exp(),"10 ^"=>10f64.powf(n),"sin"=>round((std::f64::consts::PI*n/180.).sin()*1e10)/1e10,"cos"=>round((std::f64::consts::PI*n/180.).cos()*1e10)/1e10,"atan"=>180.*n.atan()/std::f64::consts::PI,"acos"=>180.*n.acos()/std::f64::consts::PI,_=>panic!("unsupported math: {op}")}}
#[inline] fn numeric_index(n:f64,len:usize)->Option<usize>{
 let n=n.floor();if n>=1.&&n<=len as f64{Some(n as usize-1)}else{None}
}
#[inline] fn index(i:&V,len:usize,insert:bool)->Option<usize>{
 let limit=len+usize::from(insert);let n=i.raw_num();
 if !n.is_nan(){return numeric_index(n,limit)}
 if let V::S(x)=i{let x=x.as_ref();if x=="last"{return limit.checked_sub(1)};if x=="random"||x=="any"{panic!("random list index not supported")}}
 None
}
pub struct Detector {
    pub grid_stride: usize,
    hyp_rng: std::cell::Cell<u32>,
    hyp_draws: std::cell::Cell<u64>,
    vars:Vec<V>, lists:Vec<Vec<V>>, var_names:Vec<String>,list_names:Vec<String>,
    pub timer:f64,pub days_since_2000:f64,pub keys:HashSet<String>,pub broadcasts:Vec<String>,
}
impl Default for Detector{fn default()->Self{Self::new()}}
impl Detector {
    /// Serialized Scratch project state, not yet the green-flag initialized live state.
    pub fn new()->Self{
        let j:serde_json::Value=serde_json::from_str(include_str!("state.json")).expect("generated state");
        let vs=j["variables"].as_array().unwrap();let ls=j["lists"].as_array().unwrap();
        Self{grid_stride:70,hyp_rng:std::cell::Cell::new(1),hyp_draws:std::cell::Cell::new(0),vars:vs.iter().map(|x|V::json(&x[1])).collect(),lists:ls.iter().map(|x|x[1].as_array().unwrap().iter().map(V::json).collect()).collect(),var_names:vs.iter().map(|x|x[0].as_str().unwrap().into()).collect(),list_names:ls.iter().map(|x|x[0].as_str().unwrap().into()).collect(),timer:0.,days_since_2000:0.,keys:HashSet::new(),broadcasts:vec![]}
    }
    #[inline] fn set_v(&mut self,i:usize,v:V){self.vars[i]=v;}
    #[inline] fn item_ref(&self,l:usize,i:&V)->&V{index(i,self.lists[l].len(),false).map(|i|&self.lists[l][i]).unwrap_or(&EMPTY_REF)}
    #[inline] fn item_scalar_ref(&self,l:usize,i:f64)->&V{numeric_index(i,self.lists[l].len()).map(|i|&self.lists[l][i]).unwrap_or(&EMPTY_REF)}
    #[inline] fn replace(&mut self,l:usize,i:V,v:V){if let Some(i)=index(&i,self.lists[l].len(),false){self.lists[l][i]=v;}}
    fn insert(&mut self,l:usize,i:V,v:V){if let Some(i)=index(&i,self.lists[l].len(),true){self.lists[l].insert(i,v);}}
    fn push(&mut self,l:usize,v:V){self.lists[l].push(v);}
    fn delete(&mut self,l:usize,i:V){if matches!(&i,V::S(x) if x.as_ref()=="all"){self.lists[l].clear()}else if let Some(i)=index(&i,self.lists[l].len(),false){self.lists[l].remove(i);}}
    fn item_num(&self,l:usize,v:V)->V{V::N(self.lists[l].iter().position(|x|eq(x,&v)).map_or(0,|x|x+1) as f64)}
    fn contains(&self,l:usize,v:V)->V{V::B(self.lists[l].iter().any(|x|eq(x,&v)))}
    pub fn list(&self,name:&str)->Option<&[V]>{self.list_names.iter().position(|x|x==name).map(|i|self.lists[i].as_slice())}
    pub fn list_mut(&mut self,name:&str)->Option<&mut Vec<V>>{let i=self.list_names.iter().position(|x|x==name)?;Some(&mut self.lists[i])}
    pub fn variable(&self,name:&str)->Option<&V>{self.var_names.iter().position(|x|x==name).map(|i|&self.vars[i])}
    pub fn set_variable(&mut self,name:&str,v:V)->bool{if let Some(i)=self.var_names.iter().position(|x|x==name){self.vars[i]=v;true}else{false}}
    pub fn set_time(&mut self,seconds_since_2000:f64){self.list_mut("#r:最新クラウド変数").unwrap()[0]=V::N(seconds_since_2000);self.days_since_2000=seconds_since_2000/86400.;}
    /// Original procedure, zero-based station number; input is SREV's 30-step intensity index.
    pub fn update_station(&mut self,station:usize,intensity_code:f64,intensity_100:V){self.p0(V::N(station as f64),V::N(intensity_code),intensity_100);}
    pub fn advance_history(&mut self){self.p38(s(""),s(""));}
    pub fn evaluate_permissions(&mut self){self.p6();}
    pub fn evaluate_allowed_intensity(&mut self){self.p12();}
    pub fn associate_events(&mut self){self.p17();}
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn scratch_casts(){assert!(eq(&s("01"),&V::N(1.)));assert!(!eq(&s(""),&V::N(0.)));assert!(!s("false").truth());assert!(s("0.0").truth());assert_eq!(smod(-1.,7.),6.);assert_eq!(round(-1.5),-1.);}
    #[test] fn real_station_data(){let d=Detector::new();assert_eq!(d.list("d ten:x").unwrap().len(),1748);assert_eq!(d.list("dc ten:最短7点").unwrap().len(),1748*14);assert_eq!(d.list("d #震度換算30段階").unwrap().len(),90);}
    #[test] fn timestamp_history(){let mut d=Detector::new();for i in 0..10{d.set_time(100.+i as f64);d.advance_history();}let h=d.list("ten:震度履歴時間2000s").unwrap();assert_eq!(h[0].num(),109.);assert_eq!(h[10].num(),5.);assert_eq!(h[11].num(),10.);}
    #[test] fn station_update_changes_intensity(){let mut d=Detector::new();d.set_time(1000.);d.advance_history();d.list_mut("7システム設定").unwrap()[61]=V::B(false);d.update_station(0,10.,V::N(1.25));assert_eq!(d.list("ten:震度").unwrap()[0].num(),10.);assert_eq!(d.list("ten:震度100").unwrap()[0].num(),1.25);}
}
impl Detector {
    /// Run one already-decoded station frame in original SREV station order.
    /// Callers must supply all stations; missing observations use code 0.
    /// This entrypoint does not decode cloud packets or initialize a new data source.
    pub fn process_frame(&mut self, seconds_since_2000: f64, observations: &[(f64, V)]) -> Result<(), &'static str> {
        if observations.len() != self.list("d ten:x").unwrap().len() { return Err("station count mismatch"); }
        if !seconds_since_2000.is_finite() || observations.iter().any(|(c,_)| !c.is_finite() || *c < 0. || *c > 30. || c.fract() != 0.) {return Err("invalid frame input");}
        self.set_time(seconds_since_2000);
        self.advance_history();
        self.set_variable("ca:震度変化合計", V::N(0.));
        self.list_mut("4リアルタイム状況(最大震度など)").unwrap()[3]=V::N(0.);
        self.list_mut("4-1震度n以上の点数").unwrap()[12]=V::N(0.);
        for (i,(code,intensity)) in observations.iter().enumerate(){self.update_station(i,*code,intensity.clone());}
        self.evaluate_permissions();
        self.evaluate_allowed_intensity();
        if self.list("7システム設定").unwrap()[50].truth(){self.associate_events();}
        self.update_magnitudes();
        Ok(())
    }
}
#[cfg(test)]
mod reference_tests {
    use super::*;
    #[test]
    fn compare_source_blocks_frame_by_frame() {
        let fixtures:serde_json::Value=serde_json::from_str(include_str!("reference_fixtures.json")).unwrap();
        let mut compared=0usize;
        for scenario in fixtures.as_array().unwrap() {
            let mut d=Detector::new();
            let association=scenario["association"].as_bool().unwrap();
            d.list_mut("7システム設定").unwrap()[50]=V::B(association);
            for (f,frame) in scenario["frames"].as_array().unwrap().iter().enumerate() {
                let observations:Vec<_>=frame["codes"].as_array().unwrap().iter().map(|x|(x.as_f64().unwrap(),s(""))).collect();
                d.process_frame(frame["time"].as_f64().unwrap(),&observations).unwrap();
                for (name, expected) in frame["snapshot"].as_object().unwrap() {
                    let actual=d.list(name).unwrap(); let expected=expected.as_array().unwrap();
                    assert_eq!(actual.len(),expected.len(),"association={association}, frame={f}, list={name}");
                    for (i,(a,b)) in actual.iter().zip(expected).enumerate() {
                        let equal=match (a,b) {
                            (V::N(n),serde_json::Value::Number(m))=>{let m=m.as_f64().unwrap(); (*n-m).abs()<=1e-9 * m.abs().max(1.)},
                            (V::N(n),serde_json::Value::Null)=>!n.is_finite(),
                            _=>*a==V::json(b),
                        };
                        assert!(equal,"association={association}, frame={f}, list={name}, index={i}: Rust={a:?}, reference={b}");
                        compared+=1;
                    }
                }
            }
        }
        println!("Compared {compared} source-reference values across 32 frames");
    }
}

