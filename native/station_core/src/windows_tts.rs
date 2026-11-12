//! Windows SAPI 5 capability probe and WAV synthesis without spawning powershell.exe.
//! All Windows COM calls run in-process under `#[cfg(windows)]` and degrade safely
//! when a device has no speech engine or installed voices.

use serde_json::{json, Value};
use std::sync::atomic::{AtomicUsize, Ordering};

static OUTPUTS: AtomicUsize = AtomicUsize::new(0);

fn failed(message: impl ToString) -> Value {
    json!({"state":"check_failed", "voices":[], "message":message.to_string()})
}

#[cfg(any(windows, test))]
fn unavailable(message: Option<String>, hresult: Option<i32>) -> Value {
    json!({
        "state": "unavailable",
        "voices": [],
        "message": message,
        "hresult": hresult,
    })
}

#[cfg(any(windows, test))]
fn interpret(bytes: &[u8]) -> Value {
    let body = match serde_json::from_slice::<Value>(bytes) {
        Ok(body) => body,
        Err(error) => return failed(format!("Invalid Windows speech probe response: {error}")),
    };
    let (Some(engine_error), Some(voices)) =
        (body["engineError"].as_bool(), body["voices"].as_array())
    else {
        return failed("Incomplete Windows speech probe response");
    };
    if voices.iter().any(|v| {
        v["name"].as_str().is_none_or(str::is_empty)
            || !v["culture"].is_string()
            || !v["enabled"].is_boolean()
    }) {
        return failed("Invalid Windows speech voice entry");
    }
    let available = !engine_error && voices.iter().any(|v| v["enabled"] == true);
    json!({
        "state":if available {"available"} else {"unavailable"},
        "voices":voices,
        "message":body["message"],
        "hresult":body["hresult"],
    })
}

#[cfg(windows)]
mod imp {
    use super::*;
    use std::ffi::c_void;
    use std::ptr::{null, null_mut};
    use std::sync::atomic::{AtomicU64, Ordering as AtomicOrdering};
    use std::sync::{mpsc, OnceLock};
    use std::time::{Duration, Instant};

    const COINIT_APARTMENTTHREADED: u32 = 0x2;
    const S_OK: i32 = 0;
    const S_FALSE: i32 = 1;
    const RPC_E_CHANGED_MODE: i32 = 0x8001_0106_u32 as i32;
    const REGDB_E_CLASSNOTREG: i32 = 0x8004_0154_u32 as i32;
    const CLASS_E_CLASSNOTAVAILABLE: i32 = 0x8004_0111_u32 as i32;
    const SPERR_NOT_FOUND: i32 = 0x8004_503A_u32 as i32;
    const CLSCTX_ALL: u32 = 1 | 2 | 4 | 16;

    const SPFM_CREATE_ALWAYS: u32 = 3;
    const SPF_ASYNC: u32 = 1 << 0;
    const SPF_PURGEBEFORESPEAK: u32 = 1 << 1;
    const SPF_IS_NOT_XML: u32 = 1 << 4;
    const WAVE_FORMAT_PCM: u16 = 1;

    static ABORT_GENERATION: AtomicU64 = AtomicU64::new(0);
    static WORKER: OnceLock<SapiWorker> = OnceLock::new();

    #[repr(C)]
    #[derive(Clone, Copy)]
    struct Guid {
        data1: u32,
        data2: u16,
        data3: u16,
        data4: [u8; 8],
    }

    impl Guid {
        const fn new(data1: u32, data2: u16, data3: u16, data4: [u8; 8]) -> Self {
            Self {
                data1,
                data2,
                data3,
                data4,
            }
        }
    }

    #[repr(C, packed)]
    struct WaveFormatEx {
        w_format_tag: u16,
        n_channels: u16,
        n_samples_per_sec: u32,
        n_avg_bytes_per_sec: u32,
        n_block_align: u16,
        w_bits_per_sample: u16,
        cb_size: u16,
    }

    // Verified against Windows SDK 10.0.26100.0 um/sapi.h and um/x64/sapi.lib.
    const CLSID_SP_OBJECT_TOKEN_CATEGORY: Guid =
        Guid::new(0xA910_187F, 0x0C7A, 0x45AC, [0x92, 0xCC, 0x59, 0xED, 0xAF, 0xB7, 0x7B, 0x53]);
    const IID_ISP_OBJECT_TOKEN_CATEGORY: Guid =
        Guid::new(0x2D3D_3845, 0x39AF, 0x4850, [0xBB, 0xF9, 0x40, 0xB4, 0x97, 0x80, 0x01, 0x1D]);
    const CLSID_SP_STREAM: Guid =
        Guid::new(0x715D_9C59, 0x4442, 0x11D2, [0x96, 0x05, 0x00, 0xC0, 0x4F, 0x8E, 0xE6, 0x28]);
    const IID_ISP_STREAM: Guid =
        Guid::new(0x12E3_CCA9, 0x7518, 0x44C5, [0xA5, 0xE7, 0xBA, 0x5A, 0x79, 0xCB, 0x92, 0x9E]);
    const CLSID_SP_VOICE: Guid =
        Guid::new(0x9674_9377, 0x3391, 0x11D2, [0x9E, 0xE3, 0x00, 0xC0, 0x4F, 0x79, 0x73, 0x96]);
    const IID_ISP_VOICE: Guid =
        Guid::new(0x6C44_DF74, 0x72B9, 0x4992, [0xA1, 0xEC, 0xEF, 0x99, 0x6E, 0x04, 0x22, 0xD4]);
    const SPDFID_WAVE_FORMAT_EX: Guid =
        Guid::new(0xC31A_DBAE, 0x527F, 0x4FF5, [0xA2, 0x30, 0xF6, 0x2B, 0xB6, 0x1F, 0xF7, 0x0C]);

    #[link(name = "ole32")]
    unsafe extern "system" {
        fn CoInitializeEx(pv_reserved: *mut c_void, dw_co_init: u32) -> i32;
        fn CoUninitialize();
        fn CoCreateInstance(
            rclsid: *const Guid,
            p_unk_outer: *mut c_void,
            dw_cls_context: u32,
            riid: *const Guid,
            ppv: *mut *mut c_void,
        ) -> i32;
        fn CoTaskMemFree(pv: *mut c_void);
    }

    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn LCIDToLocaleName(locale: u32, lp_name: *mut u16, cch_name: i32, dw_flags: u32) -> i32;
    }

    #[repr(C)]
    struct IUnknownVtbl {
        query_interface:
            unsafe extern "system" fn(*mut c_void, *const Guid, *mut *mut c_void) -> i32,
        add_ref: unsafe extern "system" fn(*mut c_void) -> u32,
        release: unsafe extern "system" fn(*mut c_void) -> u32,
    }

    #[repr(C)]
    struct ISpDataKeyVtbl {
        unknown: IUnknownVtbl,
        set_data: *const c_void,
        get_data: *const c_void,
        set_string_value: *const c_void,
        get_string_value:
            unsafe extern "system" fn(*mut c_void, *const u16, *mut *mut u16) -> i32,
        set_dword: *const c_void,
        get_dword: *const c_void,
        open_key: unsafe extern "system" fn(*mut c_void, *const u16, *mut *mut c_void) -> i32,
        create_key: *const c_void,
        delete_key: *const c_void,
        delete_value: *const c_void,
        enum_keys: *const c_void,
        enum_values: *const c_void,
    }

    #[repr(C)]
    struct ISpObjectTokenCategoryVtbl {
        data_key: ISpDataKeyVtbl,
        set_id: unsafe extern "system" fn(*mut c_void, *const u16, i32) -> i32,
        get_id: *const c_void,
        get_data_key: *const c_void,
        enum_tokens: unsafe extern "system" fn(
            *mut c_void,
            *const u16,
            *const u16,
            *mut *mut c_void,
        ) -> i32,
        set_default_token_id: *const c_void,
        get_default_token_id: *const c_void,
    }

    #[repr(C)]
    struct IEnumSpObjectTokensVtbl {
        unknown: IUnknownVtbl,
        next: *const c_void,
        skip: *const c_void,
        reset: *const c_void,
        clone: *const c_void,
        item: unsafe extern "system" fn(*mut c_void, u32, *mut *mut c_void) -> i32,
        get_count: unsafe extern "system" fn(*mut c_void, *mut u32) -> i32,
    }

    #[repr(C)]
    struct ISpStreamVtbl {
        unknown: IUnknownVtbl,
        read: *const c_void,
        write: *const c_void,
        seek: *const c_void,
        set_size: *const c_void,
        copy_to: *const c_void,
        commit: *const c_void,
        revert: *const c_void,
        lock_region: *const c_void,
        unlock_region: *const c_void,
        stat: *const c_void,
        clone: *const c_void,
        get_format: *const c_void,
        set_base_stream: *const c_void,
        get_base_stream: *const c_void,
        bind_to_file: unsafe extern "system" fn(
            *mut c_void,
            *const u16,
            u32,
            *const Guid,
            *const WaveFormatEx,
            u64,
        ) -> i32,
        close: unsafe extern "system" fn(*mut c_void) -> i32,
    }

    #[repr(C)]
    struct ISpVoiceVtbl {
        unknown: IUnknownVtbl,
        set_notify_sink: *const c_void,
        set_notify_window_message: *const c_void,
        set_notify_callback_function: *const c_void,
        set_notify_callback_interface: *const c_void,
        set_notify_win32_event: *const c_void,
        wait_for_notify_event: *const c_void,
        get_notify_event_handle: *const c_void,
        set_interest: *const c_void,
        get_events: *const c_void,
        get_info: *const c_void,
        set_output: unsafe extern "system" fn(*mut c_void, *mut c_void, i32) -> i32,
        get_output_object_token: *const c_void,
        get_output_stream: *const c_void,
        pause: *const c_void,
        resume: *const c_void,
        set_voice: unsafe extern "system" fn(*mut c_void, *mut c_void) -> i32,
        get_voice: *const c_void,
        speak: unsafe extern "system" fn(*mut c_void, *const u16, u32, *mut u32) -> i32,
        speak_stream: *const c_void,
        get_status: *const c_void,
        skip: *const c_void,
        set_priority: *const c_void,
        get_priority: *const c_void,
        set_alert_boundary: *const c_void,
        get_alert_boundary: *const c_void,
        set_rate: unsafe extern "system" fn(*mut c_void, i32) -> i32,
        get_rate: *const c_void,
        set_volume: unsafe extern "system" fn(*mut c_void, u16) -> i32,
        get_volume: *const c_void,
        wait_until_done: unsafe extern "system" fn(*mut c_void, u32) -> i32,
        set_sync_speak_timeout: *const c_void,
        get_sync_speak_timeout: *const c_void,
        speak_complete_event: *const c_void,
        is_ui_supported: *const c_void,
        display_ui: *const c_void,
    }

    struct ComPtr {
        ptr: *mut c_void,
    }

    impl ComPtr {
        unsafe fn from_raw(ptr: *mut c_void) -> Self {
            Self { ptr }
        }

        fn as_ptr(&self) -> *mut c_void {
            self.ptr
        }

        unsafe fn vtbl<V>(&self) -> &V {
            unsafe {
                let vtbl_ptr = *(self.ptr as *const *const V);
                &*vtbl_ptr
            }
        }
    }

    impl Drop for ComPtr {
        fn drop(&mut self) {
            if !self.ptr.is_null() {
                unsafe {
                    let vtbl = *(self.ptr as *const *const IUnknownVtbl);
                    ((*vtbl).release)(self.ptr);
                }
                self.ptr = null_mut();
            }
        }
    }

    struct CoTaskStr {
        ptr: *mut u16,
    }

    impl CoTaskStr {
        unsafe fn from_raw(ptr: *mut u16) -> Self {
            Self { ptr }
        }

        fn to_string_lossy(&self) -> String {
            if self.ptr.is_null() {
                return String::new();
            }
            unsafe {
                let mut len = 0usize;
                while *self.ptr.add(len) != 0 {
                    len += 1;
                }
                let slice = std::slice::from_raw_parts(self.ptr, len);
                String::from_utf16_lossy(slice)
            }
        }
    }

    impl Drop for CoTaskStr {
        fn drop(&mut self) {
            if !self.ptr.is_null() {
                unsafe { CoTaskMemFree(self.ptr as *mut c_void) };
                self.ptr = null_mut();
            }
        }
    }

    struct ComApartment {
        should_uninit: bool,
    }

    impl ComApartment {
        fn init() -> Result<Self, i32> {
            let hr = unsafe { CoInitializeEx(null_mut(), COINIT_APARTMENTTHREADED) };
            if hr == S_OK || hr == S_FALSE {
                Ok(Self { should_uninit: true })
            } else if hr == RPC_E_CHANGED_MODE {
                Ok(Self {
                    should_uninit: false,
                })
            } else {
                Err(hr)
            }
        }
    }

    impl Drop for ComApartment {
        fn drop(&mut self) {
            if self.should_uninit {
                unsafe { CoUninitialize() };
            }
        }
    }

    fn to_wide_null(s: &str) -> Vec<u16> {
        s.encode_utf16().chain(std::iter::once(0)).collect()
    }

    fn create_instance(clsid: &Guid, iid: &Guid) -> Result<ComPtr, i32> {
        let mut raw = null_mut();
        let hr = unsafe { CoCreateInstance(clsid, null_mut(), CLSCTX_ALL, iid, &mut raw) };
        if hr < 0 || raw.is_null() {
            Err(if hr < 0 { hr } else { -1 })
        } else {
            Ok(unsafe { ComPtr::from_raw(raw) })
        }
    }

    fn is_missing_speech_hr(hr: i32) -> bool {
        matches!(
            hr,
            REGDB_E_CLASSNOTREG | CLASS_E_CLASSNOTAVAILABLE | SPERR_NOT_FOUND
        )
    }

    fn data_key_get_string(key: &ComPtr, value_name: Option<&[u16]>) -> Option<String> {
        let mut raw = null_mut();
        let name_ptr = value_name.map_or(null(), |w| w.as_ptr());
        let hr = unsafe {
            let vtbl = key.vtbl::<ISpDataKeyVtbl>();
            (vtbl.get_string_value)(key.as_ptr(), name_ptr, &mut raw)
        };
        if hr < 0 || raw.is_null() {
            return None;
        }
        let guard = unsafe { CoTaskStr::from_raw(raw) };
        Some(guard.to_string_lossy())
    }

    fn token_open_attributes(token: &ComPtr) -> Option<ComPtr> {
        let subkey = to_wide_null("Attributes");
        let mut raw = null_mut();
        let hr = unsafe {
            let vtbl = token.vtbl::<ISpDataKeyVtbl>();
            (vtbl.open_key)(token.as_ptr(), subkey.as_ptr(), &mut raw)
        };
        if hr < 0 || raw.is_null() {
            None
        } else {
            Some(unsafe { ComPtr::from_raw(raw) })
        }
    }

    fn token_display_name(token: &ComPtr, attrs: Option<&ComPtr>) -> String {
        if let Some(attrs_key) = attrs {
            let key_name = to_wide_null("Name");
            if let Some(name) = data_key_get_string(attrs_key, Some(&key_name)) {
                let trimmed = name.trim();
                if !trimmed.is_empty() {
                    return trimmed.to_string();
                }
            }
        }
        data_key_get_string(token, None)
            .map(|s| s.trim().to_string())
            .unwrap_or_default()
    }

    fn token_culture(attrs: Option<&ComPtr>) -> String {
        let Some(attrs_key) = attrs else {
            return String::new();
        };
        let key_name = to_wide_null("Language");
        let Some(raw) = data_key_get_string(attrs_key, Some(&key_name)) else {
            return String::new();
        };
        let Some(lcid) = super::parse_primary_lcid(&raw) else {
            return String::new();
        };
        let mut buf = [0u16; 85];
        let written = unsafe { LCIDToLocaleName(lcid, buf.as_mut_ptr(), buf.len() as i32, 0) };
        if written <= 1 {
            return String::new();
        }
        String::from_utf16_lossy(&buf[..(written as usize - 1)])
    }

    fn enumerate_voice_tokens() -> Result<Vec<(ComPtr, String, String)>, i32> {
        let category = create_instance(
            &CLSID_SP_OBJECT_TOKEN_CATEGORY,
            &IID_ISP_OBJECT_TOKEN_CATEGORY,
        )?;
        let spcat_voices = to_wide_null("HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Speech\\Voices");
        let hr = unsafe {
            let vtbl = category.vtbl::<ISpObjectTokenCategoryVtbl>();
            (vtbl.set_id)(category.as_ptr(), spcat_voices.as_ptr(), 0)
        };
        if hr < 0 {
            return Err(hr);
        }

        let mut enum_raw = null_mut();
        let hr = unsafe {
            let vtbl = category.vtbl::<ISpObjectTokenCategoryVtbl>();
            (vtbl.enum_tokens)(category.as_ptr(), null(), null(), &mut enum_raw)
        };
        if hr < 0 || enum_raw.is_null() {
            return Err(if hr < 0 { hr } else { SPERR_NOT_FOUND });
        }
        let enum_tokens = unsafe { ComPtr::from_raw(enum_raw) };

        let mut count = 0u32;
        let hr = unsafe {
            let vtbl = enum_tokens.vtbl::<IEnumSpObjectTokensVtbl>();
            (vtbl.get_count)(enum_tokens.as_ptr(), &mut count)
        };
        if hr < 0 {
            return Err(hr);
        }

        let mut result = Vec::with_capacity(count as usize);
        for index in 0..count {
            let mut token_raw = null_mut();
            let hr = unsafe {
                let vtbl = enum_tokens.vtbl::<IEnumSpObjectTokensVtbl>();
                (vtbl.item)(enum_tokens.as_ptr(), index, &mut token_raw)
            };
            if hr < 0 || token_raw.is_null() {
                continue;
            }
            let token = unsafe { ComPtr::from_raw(token_raw) };
            let attrs = token_open_attributes(&token);
            let name = token_display_name(&token, attrs.as_ref());
            let culture = token_culture(attrs.as_ref());
            if !name.is_empty() {
                result.push((token, name, culture));
            }
        }
        Ok(result)
    }

    fn probe_in_apartment() -> Value {
        let voice = match create_instance(&CLSID_SP_VOICE, &IID_ISP_VOICE) {
            Ok(v) => v,
            Err(hr) if is_missing_speech_hr(hr) => {
                return unavailable(
                    Some("Windows speech synthesis engine is not installed.".to_string()),
                    Some(hr),
                );
            }
            Err(hr) => return failed(format!("SAPI ISpVoice creation failed (0x{hr:08X})")),
        };

        let tokens = match enumerate_voice_tokens() {
            Ok(list) => list,
            Err(hr) if is_missing_speech_hr(hr) => {
                return unavailable(
                    Some("No voice installed on the system.".to_string()),
                    Some(hr),
                );
            }
            Err(hr) => return failed(format!("SAPI voice enumeration failed (0x{hr:08X})")),
        };

        let mut voices = Vec::with_capacity(tokens.len());
        for (token, name, culture) in tokens {
            let set_hr = unsafe {
                let vtbl = voice.vtbl::<ISpVoiceVtbl>();
                (vtbl.set_voice)(voice.as_ptr(), token.as_ptr())
            };
            voices.push(json!({
                "name": name,
                "culture": culture,
                "enabled": set_hr >= 0,
            }));
        }

        let raw = json!({
            "engineError": false,
            "voices": voices,
        });
        let bytes = serde_json::to_vec(&raw).unwrap_or_default();
        interpret(&bytes)
    }

    pub fn probe() -> Value {
        let _com = match ComApartment::init() {
            Ok(com) => com,
            Err(hr) => return failed(format!("COM initialization failed (0x{hr:08X})")),
        };
        probe_in_apartment()
    }

    struct SynthJob {
        generation: u64,
        text: String,
        file: String,
        rate: i32,
        volume: u16,
        voice: String,
        reply: mpsc::SyncSender<Value>,
    }

    struct SapiWorker {
        sender: mpsc::Sender<SynthJob>,
    }

    impl SapiWorker {
        fn start() -> Self {
            let (sender, receiver) = mpsc::channel::<SynthJob>();
            std::thread::Builder::new()
                .name("rq-windows-sapi".to_string())
                .spawn(move || {
                    let Ok(_com) = ComApartment::init() else {
                        while let Ok(job) = receiver.recv() {
                            let _ = job.reply.send(json!({
                                "ok": false,
                                "error": "COM initialization failed for SAPI worker",
                            }));
                        }
                        return;
                    };
                    let mut voice: Option<ComPtr> = None;
                    while let Ok(job) = receiver.recv() {
                        let out = handle_job(&mut voice, &job);
                        let _ = job.reply.send(out);
                    }
                    drop(voice);
                })
                .expect("spawn rq-windows-sapi thread");
            Self { sender }
        }
    }

    fn select_voice_by_name(voice: &ComPtr, requested: &str) {
        let requested_trimmed = requested.trim();
        if requested_trimmed.is_empty() {
            unsafe {
                let vtbl = voice.vtbl::<ISpVoiceVtbl>();
                let _ = (vtbl.set_voice)(voice.as_ptr(), null_mut());
            }
            return;
        }
        if let Ok(tokens) = enumerate_voice_tokens() {
            if let Some((token, _, _)) = tokens
                .into_iter()
                .find(|(_, name, _)| name.eq_ignore_ascii_case(requested_trimmed))
            {
                let hr = unsafe {
                    let vtbl = voice.vtbl::<ISpVoiceVtbl>();
                    (vtbl.set_voice)(voice.as_ptr(), token.as_ptr())
                };
                if hr >= 0 {
                    return;
                }
            }
        }
        unsafe {
            let vtbl = voice.vtbl::<ISpVoiceVtbl>();
            let _ = (vtbl.set_voice)(voice.as_ptr(), null_mut());
        }
    }

    fn synth_error(message: impl Into<String>, hresult: Option<i32>, aborted: bool) -> Value {
        json!({
            "ok": false,
            "aborted": aborted,
            "error": message.into(),
            "hresult": hresult,
        })
    }

    fn handle_job(cached_voice: &mut Option<ComPtr>, job: &SynthJob) -> Value {
        if ABORT_GENERATION.load(AtomicOrdering::Acquire) != job.generation {
            return synth_error("Windows SAPI synthesis cancelled", None, true);
        }

        let voice = match cached_voice.as_ref() {
            Some(existing) => existing,
            None => match create_instance(&CLSID_SP_VOICE, &IID_ISP_VOICE) {
                Ok(created) => {
                    *cached_voice = Some(created);
                    cached_voice.as_ref().unwrap()
                }
                Err(hr) => {
                    return synth_error(
                        format!("Windows SAPI voice unavailable (0x{hr:08X})"),
                        Some(hr),
                        false,
                    );
                }
            },
        };

        select_voice_by_name(voice, &job.voice);

        let hr_rate = unsafe {
            let vtbl = voice.vtbl::<ISpVoiceVtbl>();
            (vtbl.set_rate)(voice.as_ptr(), job.rate.clamp(-10, 10))
        };
        if hr_rate < 0 {
            *cached_voice = None;
            return synth_error(
                format!("SAPI SetRate failed (0x{hr_rate:08X})"),
                Some(hr_rate),
                false,
            );
        }

        let hr_vol = unsafe {
            let vtbl = voice.vtbl::<ISpVoiceVtbl>();
            (vtbl.set_volume)(voice.as_ptr(), job.volume.clamp(0, 100))
        };
        if hr_vol < 0 {
            *cached_voice = None;
            return synth_error(
                format!("SAPI SetVolume failed (0x{hr_vol:08X})"),
                Some(hr_vol),
                false,
            );
        }

        let stream = match create_instance(&CLSID_SP_STREAM, &IID_ISP_STREAM) {
            Ok(s) => s,
            Err(hr) => {
                return synth_error(
                    format!("SAPI ISpStream creation failed (0x{hr:08X})"),
                    Some(hr),
                    false,
                );
            }
        };

        let wfx = WaveFormatEx {
            w_format_tag: WAVE_FORMAT_PCM,
            n_channels: 1,
            n_samples_per_sec: 22_050,
            n_avg_bytes_per_sec: 44_100,
            n_block_align: 2,
            w_bits_per_sample: 16,
            cb_size: 0,
        };
        let wide_file = to_wide_null(&job.file);
        let hr_bind = unsafe {
            let vtbl = stream.vtbl::<ISpStreamVtbl>();
            (vtbl.bind_to_file)(
                stream.as_ptr(),
                wide_file.as_ptr(),
                SPFM_CREATE_ALWAYS,
                &SPDFID_WAVE_FORMAT_EX,
                &wfx,
                0,
            )
        };
        if hr_bind < 0 {
            return synth_error(
                format!("SAPI BindToFile failed (0x{hr_bind:08X})"),
                Some(hr_bind),
                false,
            );
        }

        let hr_out = unsafe {
            let vtbl = voice.vtbl::<ISpVoiceVtbl>();
            (vtbl.set_output)(voice.as_ptr(), stream.as_ptr(), 1)
        };
        if hr_out < 0 {
            unsafe {
                let s_vtbl = stream.vtbl::<ISpStreamVtbl>();
                let _ = (s_vtbl.close)(stream.as_ptr());
            }
            let _ = std::fs::remove_file(&job.file);
            *cached_voice = None;
            return synth_error(
                format!("SAPI SetOutput failed (0x{hr_out:08X})"),
                Some(hr_out),
                false,
            );
        }

        let wide_text = to_wide_null(&job.text);
        let hr_speak = unsafe {
            let vtbl = voice.vtbl::<ISpVoiceVtbl>();
            (vtbl.speak)(
                voice.as_ptr(),
                wide_text.as_ptr(),
                SPF_ASYNC | SPF_IS_NOT_XML | SPF_PURGEBEFORESPEAK,
                null_mut(),
            )
        };
        if hr_speak < 0 {
            unsafe {
                let v_vtbl = voice.vtbl::<ISpVoiceVtbl>();
                let _ = (v_vtbl.set_output)(voice.as_ptr(), null_mut(), 1);
                let s_vtbl = stream.vtbl::<ISpStreamVtbl>();
                let _ = (s_vtbl.close)(stream.as_ptr());
            }
            let _ = std::fs::remove_file(&job.file);
            *cached_voice = None;
            return synth_error(
                format!("SAPI Speak failed (0x{hr_speak:08X})"),
                Some(hr_speak),
                false,
            );
        }

        let started = Instant::now();
        let timeout = Duration::from_secs(30);
        let outcome: Result<(), (String, Option<i32>, bool)> = loop {
            if ABORT_GENERATION.load(AtomicOrdering::Acquire) != job.generation {
                unsafe {
                    let vtbl = voice.vtbl::<ISpVoiceVtbl>();
                    let _ = (vtbl.speak)(voice.as_ptr(), null(), SPF_PURGEBEFORESPEAK, null_mut());
                    let _ = (vtbl.wait_until_done)(voice.as_ptr(), 500);
                }
                break Err((
                    "Windows SAPI synthesis cancelled".to_string(),
                    None,
                    true,
                ));
            }
            let hr_wait = unsafe {
                let vtbl = voice.vtbl::<ISpVoiceVtbl>();
                (vtbl.wait_until_done)(voice.as_ptr(), 25)
            };
            if hr_wait == S_OK {
                break Ok(());
            }
            if hr_wait < 0 {
                break Err((
                    format!("SAPI WaitUntilDone failed (0x{hr_wait:08X})"),
                    Some(hr_wait),
                    false,
                ));
            }
            if started.elapsed() >= timeout {
                unsafe {
                    let vtbl = voice.vtbl::<ISpVoiceVtbl>();
                    let _ = (vtbl.speak)(voice.as_ptr(), null(), SPF_PURGEBEFORESPEAK, null_mut());
                    let _ = (vtbl.wait_until_done)(voice.as_ptr(), 500);
                }
                break Err((
                    "Windows SAPI synthesis timed out".to_string(),
                    None,
                    false,
                ));
            }
        };

        unsafe {
            let v_vtbl = voice.vtbl::<ISpVoiceVtbl>();
            let _ = (v_vtbl.set_output)(voice.as_ptr(), null_mut(), 1);
            let s_vtbl = stream.vtbl::<ISpStreamVtbl>();
            let _ = (s_vtbl.close)(stream.as_ptr());
        }

        match outcome {
            Ok(()) => json!({"ok": true}),
            Err((msg, hr, aborted)) => {
                let _ = std::fs::remove_file(&job.file);
                if !aborted {
                    *cached_voice = None;
                }
                synth_error(msg, hr, aborted)
            }
        }
    }

    pub fn synthesize(payload: &[u8]) -> Value {
        let body = match serde_json::from_slice::<Value>(payload) {
            Ok(v) => v,
            Err(error) => return synth_error(format!("Invalid synthesis payload: {error}"), None, false),
        };
        let Some(text) = body["text"].as_str() else {
            return synth_error("Missing synthesis text", None, false);
        };
        let Some(file) = body["file"].as_str() else {
            return synth_error("Missing synthesis output file path", None, false);
        };
        if file.trim().is_empty() {
            return synth_error("Empty synthesis output file path", None, false);
        }
        let rate = body["rate"].as_i64().unwrap_or(0).clamp(-10, 10) as i32;
        let volume = body["volume"].as_i64().unwrap_or(100).clamp(0, 100) as u16;
        let voice = body["voice"].as_str().unwrap_or("").to_string();

        let generation = ABORT_GENERATION.load(AtomicOrdering::Acquire);
        let worker = WORKER.get_or_init(SapiWorker::start);
        let (tx, rx) = mpsc::sync_channel(1);
        let send_result = worker.sender.send(SynthJob {
            generation,
            text: text.to_string(),
            file: file.to_string(),
            rate,
            volume,
            voice,
            reply: tx,
        });
        if send_result.is_err() {
            return synth_error("Windows SAPI worker is unavailable", None, false);
        }
        rx.recv().unwrap_or_else(|_| {
            synth_error("Windows SAPI worker dropped reply", None, false)
        })
    }

    pub fn abort() -> u64 {
        ABORT_GENERATION.fetch_add(1, AtomicOrdering::AcqRel) + 1
    }
}

#[cfg(not(windows))]
mod imp {
    use super::*;

    pub fn probe() -> Value {
        failed("Windows speech detection is only supported on Windows")
    }

    pub fn synthesize(_payload: &[u8]) -> Value {
        json!({
            "ok": false,
            "aborted": false,
            "error": "Windows speech synthesis is only supported on Windows",
        })
    }

    pub fn abort() -> u64 {
        0
    }
}

#[cfg(any(windows, test))]
fn parse_primary_lcid(raw: &str) -> Option<u32> {
    let first = raw.split(';').next()?.trim();
    if first.is_empty() {
        return None;
    }
    let hex = first
        .strip_prefix("0x")
        .or_else(|| first.strip_prefix("0X"))
        .unwrap_or(first);
    u32::from_str_radix(hex, 16).ok()
}

fn allocate_json_output(value: &Value, size: *mut usize) -> *mut u8 {
    let mut bytes = serde_json::to_vec(value).unwrap().into_boxed_slice();
    unsafe {
        *size = bytes.len();
    }
    let ptr = bytes.as_mut_ptr();
    std::mem::forget(bytes);
    OUTPUTS.fetch_add(1, Ordering::Relaxed);
    ptr
}

#[no_mangle]
pub unsafe extern "C" fn rq_windows_tts_probe(size: *mut usize) -> *mut u8 {
    if size.is_null() {
        return std::ptr::null_mut();
    }
    unsafe {
        *size = 0;
    }
    std::panic::catch_unwind(|| allocate_json_output(&imp::probe(), size))
        .unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn rq_windows_tts_synthesize(
    payload_ptr: *const u8,
    payload_len: usize,
    out_size: *mut usize,
) -> *mut u8 {
    if out_size.is_null() {
        return std::ptr::null_mut();
    }
    unsafe {
        *out_size = 0;
    }
    std::panic::catch_unwind(|| {
        let value = if payload_ptr.is_null() || payload_len == 0 {
            json!({
                "ok": false,
                "aborted": false,
                "error": "Empty synthesis request payload",
            })
        } else {
            let payload = unsafe { std::slice::from_raw_parts(payload_ptr, payload_len) };
            imp::synthesize(payload)
        };
        allocate_json_output(&value, out_size)
    })
    .unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn rq_windows_tts_abort() -> u64 {
    std::panic::catch_unwind(imp::abort).unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn rq_windows_tts_free(ptr: *mut u8, size: usize) {
    if !ptr.is_null() {
        drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, size)) });
        OUTPUTS.fetch_sub(1, Ordering::Relaxed);
    }
}

#[no_mangle]
pub extern "C" fn rq_windows_tts_outputs() -> usize {
    OUTPUTS.load(Ordering::Relaxed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unknown_result_is_never_reported_as_missing_voices() {
        assert_eq!(interpret(b"not json")["state"], "check_failed");
        assert_eq!(interpret(b"{}")["state"], "check_failed");
        assert_eq!(
            interpret(br#"{"engineError":false,"voices":[{}]}"#)["state"],
            "check_failed"
        );
    }

    #[test]
    fn original_available_and_unavailable_voice_results_are_distinct() {
        let local = include_bytes!("../../../test/fixtures/windows_tts/local-voices.original.json");
        let cloud =
            include_bytes!("../../../test/fixtures/windows_tts/cloud-no-voices.original.json");
        let expected: Value = serde_json::from_slice(local).unwrap();
        assert_eq!(interpret(local)["state"], "available");
        assert_eq!(interpret(local)["voices"], expected["voices"]);
        let unavailable = interpret(cloud);
        assert_eq!(unavailable["state"], "unavailable");
        assert_eq!(unavailable["voices"].as_array().unwrap().len(), 0);
        let expected: Value = serde_json::from_slice(cloud).unwrap();
        assert_eq!(unavailable["hresult"], expected["hresult"]);
        assert_eq!(unavailable["message"], expected["message"]);
    }

    #[test]
    fn parses_primary_lcid_hex_with_optional_secondary_tags() {
        assert_eq!(parse_primary_lcid("804"), Some(0x804));
        assert_eq!(parse_primary_lcid("409;809"), Some(0x409));
        assert_eq!(parse_primary_lcid("0x0804"), Some(0x0804));
        assert_eq!(parse_primary_lcid(""), None);
        assert_eq!(parse_primary_lcid("invalid"), None);
    }

    #[test]
    fn invalid_synthesize_payload_returns_error_and_releases_output() {
        assert_eq!(rq_windows_tts_outputs(), 0);
        let mut size = 0usize;
        let ptr = unsafe { rq_windows_tts_synthesize(std::ptr::null(), 0, &mut size) };
        assert!(!ptr.is_null());
        assert_eq!(rq_windows_tts_outputs(), 1);
        let value: Value =
            serde_json::from_slice(unsafe { std::slice::from_raw_parts(ptr, size) }).unwrap();
        assert_eq!(value["ok"], false);
        unsafe {
            rq_windows_tts_free(ptr, size);
        }
        assert_eq!(rq_windows_tts_outputs(), 0);
    }

    #[test]
    fn actual_ffi_probe_releases_its_owned_output() {
        assert_eq!(rq_windows_tts_outputs(), 0);
        for _ in 0..2 {
            let mut size = 0;
            let ptr = unsafe { rq_windows_tts_probe(&mut size) };
            assert!(!ptr.is_null());
            assert_eq!(rq_windows_tts_outputs(), 1);
            let result: Value =
                serde_json::from_slice(unsafe { std::slice::from_raw_parts(ptr, size) }).unwrap();
            assert!(result["state"].is_string());
            unsafe {
                rq_windows_tts_free(ptr, size);
            }
            assert_eq!(rq_windows_tts_outputs(), 0);
        }
    }

    #[cfg(windows)]
    #[test]
    fn native_com_sapi_synthesizes_wav_and_aborts_without_powershell() {
        assert_eq!(rq_windows_tts_outputs(), 0);
        let temp_dir = std::env::temp_dir().join(format!(
            "rq_windows_tts_rust_test_{}",
            std::process::id()
        ));
        let _ = std::fs::create_dir_all(&temp_dir);
        let out_wav = temp_dir.join("probe.wav");
        let _ = std::fs::remove_file(&out_wav);

        let payload = serde_json::to_vec(&json!({
            "text": "地震预警测试，震级五点零",
            "file": out_wav.to_string_lossy(),
            "rate": 1,
            "volume": 50,
            "voice": "",
        }))
        .unwrap();

        let mut size = 0usize;
        let ptr = unsafe { rq_windows_tts_synthesize(payload.as_ptr(), payload.len(), &mut size) };
        assert!(!ptr.is_null());
        assert_eq!(rq_windows_tts_outputs(), 1);
        let result: Value =
            serde_json::from_slice(unsafe { std::slice::from_raw_parts(ptr, size) }).unwrap();
        unsafe {
            rq_windows_tts_free(ptr, size);
        }
        assert_eq!(rq_windows_tts_outputs(), 0);
        assert_eq!(result["ok"], true, "unexpected synth error: {result}");
        let meta = std::fs::metadata(&out_wav).unwrap();
        assert!(meta.len() > 44);

        // Verify probe returns the expected voice entries without spawning powershell.exe.
        let probe_result = imp::probe();
        assert_eq!(probe_result["state"], "available");
        assert!(probe_result["voices"].as_array().is_some_and(|v| !v.is_empty()));

        // Verify abort + subsequent synthesis recovers cleanly.
        rq_windows_tts_abort();
        let next_wav = temp_dir.join("recovered.wav");
        let next_payload = serde_json::to_vec(&json!({
            "text": "重启以后恢复合成",
            "file": next_wav.to_string_lossy(),
            "rate": 1,
            "volume": 50,
            "voice": "",
        }))
        .unwrap();
        let mut size2 = 0usize;
        let ptr2 =
            unsafe { rq_windows_tts_synthesize(next_payload.as_ptr(), next_payload.len(), &mut size2) };
        assert!(!ptr2.is_null());
        let result2: Value =
            serde_json::from_slice(unsafe { std::slice::from_raw_parts(ptr2, size2) }).unwrap();
        unsafe {
            rq_windows_tts_free(ptr2, size2);
        }
        assert_eq!(rq_windows_tts_outputs(), 0);
        assert_eq!(result2["ok"], true, "unexpected synth error after abort: {result2}");
        assert!(std::fs::metadata(&next_wav).unwrap().len() > 44);

        let _ = std::fs::remove_dir_all(&temp_dir);
    }
}
