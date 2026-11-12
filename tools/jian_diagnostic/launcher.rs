#![windows_subsystem = "windows"]
use std::{fs, io::Write, os::windows::process::CommandExt, process::Command, time::{SystemTime, UNIX_EPOCH}};
const SCRIPT: &str = include_str!("JianDiagnostic.ps1");
#[link(name="user32")] extern "system" { fn MessageBoxW(window:*mut std::ffi::c_void,text:*const u16,title:*const u16,flags:u32)->i32; }
fn main() {
    if let Err(error) = run() {
        let text: Vec<u16> = format!("诊断程序启动失败：{error}").encode_utf16().chain(Some(0)).collect();
        let title: Vec<u16> = "Jian 诊断".encode_utf16().chain(Some(0)).collect();
        unsafe { MessageBoxW(std::ptr::null_mut(),text.as_ptr(),title.as_ptr(),0x10); }
        std::process::exit(1);
    }
}
fn run()->Result<(),Box<dyn std::error::Error>> {
    let base=std::env::var_os("LOCALAPPDATA").ok_or("LOCALAPPDATA unavailable")?;
    let stamp=SystemTime::now().duration_since(UNIX_EPOCH)?.as_millis();
    let root=std::path::PathBuf::from(base).join("RhythmQuake").join("diagnostic_tools").join(format!("jian-{stamp}-{}",std::process::id()));
    fs::create_dir_all(&root)?;
    fs::write(root.join("rq_station_core_licenses.txt"),include_str!("../../native/station_core/THIRD_PARTY_NOTICES.txt"))?;
    let script=root.join("JianDiagnostic.ps1");
    let mut file=fs::File::create(&script)?;file.write_all(b"\xef\xbb\xbf")?;file.write_all(SCRIPT.as_bytes())?;drop(file);
    let powershell=std::env::var_os("SystemRoot").map(std::path::PathBuf::from).ok_or("SystemRoot unavailable")?.join("System32/WindowsPowerShell/v1.0/powershell.exe");
    let mut command=Command::new(powershell);
    command.args(["-NoLogo","-NoProfile","-STA","-ExecutionPolicy","Bypass","-File"]).arg(script).arg("-PayloadDir").arg(&root).creation_flags(0x08000000);
    command.arg("-BundleDir").arg(std::env::current_exe()?.parent().ok_or("Bundle directory unavailable")?);
    let args:Vec<String>=std::env::args().skip(1).collect();
    if args.iter().any(|a|a=="--self-test") {command.arg("-SelfTest");}
    if args.iter().any(|a|a=="--collect-only") {command.arg("-CollectOnly");}
    if args.iter().any(|a|a=="--ui-self-test") {command.arg("-UiSelfTest");}
    if let Some(index)=args.iter().position(|a|a=="--output") {command.arg("-OutputRoot").arg(args.get(index+1).ok_or("--output requires a directory")?);}
    let status=command.status()?;
    if !status.success(){return Err(format!("Windows PowerShell returned {}",status).into());}
    Ok(())
}
