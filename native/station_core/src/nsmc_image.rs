//! NSMC EPSG:4326 images -> unchanged-RGBA Mercator display tiles.
use image::{ImageDecoder, ImageEncoder};

pub(crate) fn bounds(z:i32,x:i32,y:i32)->Option<[f64;4]> {
    if !(0..=8).contains(&z) {return None;}
    let n=1i32<<z;
    if y<0||y>=n {return None;}
    let x=x.rem_euclid(n);
    let lat=|v:f64| (2.0*((std::f64::consts::PI*(1.0-2.0*v/n as f64)).exp()).atan()-std::f64::consts::FRAC_PI_2).to_degrees();
    Some([x as f64/n as f64*360.0-180.0,lat((y+1) as f64),(x+1) as f64/n as f64*360.0-180.0,lat(y as f64)])
}
fn row(y:usize,height:usize,source_height:usize,z:i32,tile_y:i32)->usize {
    let fraction=if z<0 {(y as f64+0.5)/height as f64} else {(tile_y as f64+(y as f64+0.5)/height as f64)/(1u32<<z) as f64};
    let lat=(2.0*(std::f64::consts::PI*(1.0-2.0*fraction)).exp().atan()-std::f64::consts::FRAC_PI_2).to_degrees();
    let (south,north)=if z<0 {(-85.0511287798066,85.0511287798066)}else{let b=bounds(z,0,tile_y).unwrap();(b[1],b[3])};
    (((north-lat)/(north-south)*source_height as f64).floor() as i64).clamp(0,source_height as i64-1) as usize
}
pub(crate) fn project(bytes:&[u8],z:i32,y:i32)->Result<Vec<u8>,String> {
    if z < -1 || (z>=0&&bounds(z,0,y).is_none()) {return Err("Invalid cloud tile".into());}
    let decoder=image::codecs::png::PngDecoder::new(std::io::Cursor::new(bytes)).map_err(|e|e.to_string())?;
    let expected=if z<0 {(2048,1024)}else{(256,256)};
    if decoder.dimensions()!=expected {return Err("Unexpected NSMC image dimensions".into());}
    let source=image::DynamicImage::from_decoder(decoder).map_err(|e|e.to_string())?.into_rgba8();
    // Empty tiles at sea/poles are valid transparent map content. A global
    // legacy frame, however, must retain the original non-empty validation.
    if z<0 && !source.pixels().any(|p|p.0[3]>0) {return Err("Empty NSMC cloud image".into());}
    let width=expected.0 as usize;
    let height=if z<0 {2048}else{256};
    let stride=width*4;let mut output=vec![0u8;height*stride];
    for y_out in 0..height {
        let from=row(y_out,height,expected.1 as usize,z,y)*stride;
        output[y_out*stride..(y_out+1)*stride].copy_from_slice(&source.as_raw()[from..from+stride]);
    }
    let mut encoded=Vec::new();
    image::codecs::png::PngEncoder::new_with_quality(&mut encoded,image::codecs::png::CompressionType::Fast,image::codecs::png::FilterType::Adaptive)
        .write_image(&output,width as u32,height as u32,image::ExtendedColorType::Rgba8).map_err(|e|e.to_string())?;
    Ok(encoded)
}
#[no_mangle]
pub unsafe extern "C" fn rq_nsmc_tile_bounds(z:i32,x:i32,y:i32,output:*mut f64)->u32 {
    if output.is_null(){return 1;}
    let Some(b)=bounds(z,x,y)else{return 2;};
    unsafe{std::ptr::copy_nonoverlapping(b.as_ptr(),output,4);}0
}
#[no_mangle]
pub unsafe extern "C" fn rq_nsmc_project(input:*const u8,len:usize,z:i32,y:i32,size:*mut usize)->*mut u8 {
    if size.is_null(){return std::ptr::null_mut();}
    unsafe{*size=0;}
    if input.is_null()||len>16*1024*1024{return std::ptr::null_mut();}
    std::panic::catch_unwind(|| {
        let result=project(unsafe{std::slice::from_raw_parts(input,len)},z,y).ok()?;
        let bytes=result.into_boxed_slice();unsafe{*size=bytes.len();}Some(Box::into_raw(bytes).cast())
    }).ok().flatten().unwrap_or(std::ptr::null_mut())
}
#[no_mangle]
pub unsafe extern "C" fn rq_nsmc_project_free(input:*mut u8,len:usize) {
    if !input.is_null(){drop(unsafe{Box::from_raw(std::ptr::slice_from_raw_parts_mut(input,len))});}
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]fn tile_edges_wrap_and_have_no_dateline_gap(){
        for z in 0..7 {let n=1<<z;for y in 0..n {let a=bounds(z,0,y).unwrap();let b=bounds(z,n-1,y).unwrap();assert_eq!(a[0],-180.0);assert_eq!(b[2],180.0);assert_eq!(bounds(z,-1,y),Some(b));if y+1<n {assert!((a[1]-bounds(z,0,y+1).unwrap()[3]).abs()<1e-10);}}}
        assert!(bounds(3,0,8).is_none());
    }
    #[test]fn legacy_rows_preserve_original_projection(){assert_eq!(row(0,2048,1024,-1,0),0);assert_eq!(row(2047,2048,1024,-1,0),1023);assert_eq!(row(1023,2048,1024,-1,0),511);assert_eq!(row(1024,2048,1024,-1,0),512);}
    #[test]fn original_tile_rgba_is_preserved_and_outputs_are_released(){
        let path=std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../test/fixtures/nsmc_viewport_20261105/tile-z3-x6-y3.png");
        let bytes=std::fs::read(path).unwrap();let before=bytes.clone();
        let source=image::load_from_memory(&bytes).unwrap().into_rgba8();
        let output=project(&bytes,3,3).unwrap();let image=image::load_from_memory(&output).unwrap().into_rgba8();
        for y in (0..256).step_by(13){for x in (0..256).step_by(11){assert_eq!(image.get_pixel(x,y),source.get_pixel(x,row(y as usize,256,256,3,3) as u32));}}
        assert_eq!(bytes,before);
        for _ in 0..10 {let mut len=0;unsafe{let p=rq_nsmc_project(bytes.as_ptr(),bytes.len(),3,3,&mut len);assert!(!p.is_null());rq_nsmc_project_free(p,len);}}
    }
}
