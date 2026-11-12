//! Image-only clipboard export. No event data, camera or feed policy changes.
use image::{ImageReader, Limits};
use std::io::Cursor;

fn dib_v5(png: &[u8]) -> Result<Vec<u8>, ()> {
    if png.is_empty() || png.len() > 32 * 1024 * 1024 {
        return Err(());
    }
    let mut reader = ImageReader::with_format(Cursor::new(png), image::ImageFormat::Png);
    let mut limits = Limits::default();
    limits.max_image_width = Some(4096);
    limits.max_image_height = Some(4096);
    limits.max_alloc = Some(128 * 1024 * 1024);
    reader.limits(limits);
    let rgba = reader.decode().map_err(|_| ())?.into_rgba8();
    let (width, height) = rgba.dimensions();
    let pixels = rgba.into_raw();
    let mut dib = vec![0u8; 124 + pixels.len()];
    for (offset, value) in [
        (0, 124u32),
        (4, width),
        (8, (-(height as i32)) as u32), // Top-down rows, as in the PNG.
        (16, 3),                        // BI_BITFIELDS
        (20, pixels.len() as u32),
        (40, 0x00ff0000),
        (44, 0x0000ff00),
        (48, 0x000000ff),
        (52, 0xff000000),
        (56, 0x73524742), // LCS_sRGB
        (108, 4),         // LCS_GM_IMAGES
    ] {
        dib[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
    }
    dib[12..14].copy_from_slice(&1u16.to_le_bytes());
    dib[14..16].copy_from_slice(&32u16.to_le_bytes());
    for (source, target) in pixels.chunks_exact(4).zip(dib[124..].chunks_exact_mut(4)) {
        target.copy_from_slice(&[source[2], source[1], source[0], source[3]]);
    }
    Ok(dib)
}

#[cfg(windows)]
mod windows {
    use std::{ffi::c_void, ptr::null_mut};
    type Handle = *mut c_void;
    #[link(name = "user32")]
    extern "system" {
        fn CreateWindowExW(
            ex: u32,
            class: *const u16,
            title: *const u16,
            style: u32,
            x: i32,
            y: i32,
            width: i32,
            height: i32,
            parent: Handle,
            menu: Handle,
            instance: Handle,
            param: Handle,
        ) -> Handle;
        fn DestroyWindow(window: Handle) -> i32;
        fn OpenClipboard(window: Handle) -> i32;
        fn CloseClipboard() -> i32;
        fn EmptyClipboard() -> i32;
        fn RegisterClipboardFormatW(name: *const u16) -> u32;
        fn SetClipboardData(format: u32, data: Handle) -> Handle;
    }
    #[link(name = "kernel32")]
    extern "system" {
        fn GlobalAlloc(flags: u32, bytes: usize) -> Handle;
        fn GlobalLock(memory: Handle) -> Handle;
        fn GlobalUnlock(memory: Handle) -> i32;
        fn GlobalFree(memory: Handle) -> Handle;
        fn GetLastError() -> u32;
    }
    fn error() -> i32 {
        unsafe { GetLastError().max(1) as i32 }
    }
    struct Memory(Handle);
    impl Memory {
        fn new(bytes: &[u8]) -> Result<Self, i32> {
            let memory = Self(unsafe { GlobalAlloc(2, bytes.len()) }); // GMEM_MOVEABLE
            if memory.0.is_null() {
                return Err(error());
            }
            let pointer = unsafe { GlobalLock(memory.0) };
            if pointer.is_null() {
                return Err(error());
            }
            unsafe {
                std::ptr::copy_nonoverlapping(bytes.as_ptr(), pointer.cast(), bytes.len());
                GlobalUnlock(memory.0);
            }
            Ok(memory)
        }
        fn transfer(&mut self, format: u32) -> Result<(), i32> {
            if unsafe { SetClipboardData(format, self.0) }.is_null() {
                return Err(error());
            }
            self.0 = null_mut(); // Windows owns this allocation after success.
            Ok(())
        }
    }
    impl Drop for Memory {
        fn drop(&mut self) {
            if !self.0.is_null() {
                unsafe {
                    GlobalFree(self.0);
                }
            }
        }
    }
    struct Owner(Handle);
    impl Drop for Owner {
        fn drop(&mut self) {
            unsafe {
                DestroyWindow(self.0);
            }
        }
    }
    struct Clipboard;
    impl Drop for Clipboard {
        fn drop(&mut self) {
            unsafe {
                CloseClipboard();
            }
        }
    }
    pub(super) fn write(png: &[u8], dib: &[u8]) -> Result<(), i32> {
        // Allocate and validate everything before replacing existing contents.
        let mut png_memory = Memory::new(png)?;
        let mut dib_memory = Memory::new(dib)?;
        let format_name: Vec<u16> = "PNG\0".encode_utf16().collect();
        let format = unsafe { RegisterClipboardFormatW(format_name.as_ptr()) };
        if format == 0 {
            return Err(error());
        }
        let class: Vec<u16> = "STATIC\0".encode_utf16().collect();
        let owner = Owner(unsafe {
            CreateWindowExW(
                0,
                class.as_ptr(),
                class.as_ptr(),
                0,
                0,
                0,
                0,
                0,
                -3isize as Handle,
                null_mut(),
                null_mut(),
                null_mut(),
            ) // HWND_MESSAGE, invisible
        });
        if owner.0.is_null() {
            return Err(error());
        }
        let mut opened = false;
        for attempt in 0..6 {
            if unsafe { OpenClipboard(owner.0) } != 0 {
                opened = true;
                break;
            }
            if attempt < 5 {
                std::thread::sleep(std::time::Duration::from_millis(20));
            }
        }
        if !opened {
            return Err(error());
        }
        let _clipboard = Clipboard;
        if unsafe { EmptyClipboard() } == 0 {
            return Err(error());
        }
        png_memory.transfer(format)?;
        dib_memory.transfer(17)?; // CF_DIBV5; Windows synthesizes CF_DIB / CF_BITMAP.
        Ok(())
    }
}

/// Copies an encoded PNG image. Input is borrowed for this call only.
/// Returns 0 on success, a positive Win32 error, -1 for invalid PNG,
/// -2 for unsupported platform, or -3 for an internal panic.
/// # Safety
/// `bytes` must point to `length` readable bytes for the duration of this call.
#[no_mangle]
pub unsafe extern "C" fn rq_event_render_copy_png(bytes: *const u8, length: usize) -> i32 {
    if bytes.is_null() || length == 0 || length > 32 * 1024 * 1024 {
        return -1;
    }
    std::panic::catch_unwind(|| {
        let png = unsafe { std::slice::from_raw_parts(bytes, length) };
        let Ok(dib) = dib_v5(png) else {
            return -1;
        };
        #[cfg(windows)]
        {
            windows::write(png, &dib).map_or_else(|error| error, |_| 0)
        }
        #[cfg(not(windows))]
        {
            let _ = dib;
            -2
        }
    })
    .unwrap_or(-3)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn clipboard_dib_preserves_channels_alpha_and_top_down_rows() {
        let image = image::RgbaImage::from_raw(1, 2, vec![255, 0, 0, 128, 0, 255, 0, 255]).unwrap();
        let mut png = Cursor::new(Vec::new());
        image.write_to(&mut png, image::ImageFormat::Png).unwrap();
        let dib = dib_v5(png.get_ref()).unwrap();
        assert_eq!(i32::from_le_bytes(dib[8..12].try_into().unwrap()), -2);
        assert_eq!(&dib[124..], &[0, 0, 255, 128, 0, 255, 0, 255]);
        assert_eq!(unsafe { rq_event_render_copy_png(std::ptr::null(), 1) }, -1);
        assert_eq!(
            unsafe { rq_event_render_copy_png(b"invalid".as_ptr(), 7) },
            -1
        );
    }
}
