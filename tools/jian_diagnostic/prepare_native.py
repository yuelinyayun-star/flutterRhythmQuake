"""Create an isolated logging DLL build; never edit the production Rust tree."""
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[2]
source = root / 'native/station_core'
target = root / 'build/diagnostics/jian/native'
target.mkdir(parents=True, exist_ok=True)
shutil.copytree(source / 'src', target / 'src', dirs_exist_ok=True)
for name in ('Cargo.toml', 'Cargo.lock'):
    shutil.copy2(source / name, target / name)
shutil.copy2(Path(__file__).with_name('jian_diagnostic.rs'), target / 'src/jian_diagnostic.rs')
lib = target / 'src/lib.rs'
lib.write_text(lib.read_text(encoding='utf-8') + '\nmod jian_diagnostic;\n', encoding='utf-8')
path = target / 'src/websocket.rs'
text = path.read_text(encoding='utf-8')
patches = [
    ('struct Worker {', 'struct Worker {\n    diagnostic: Option<crate::jian_diagnostic::Trace>,'),
    ('        self.keepalive = config.keepalive;', '''        self.diagnostic = crate::jian_diagnostic::Trace::open(&config.host, &config.path, &config.headers);
        if self.diagnostic.as_ref().is_some_and(|trace| !trace.allowed) { return Err(87); }
        self.keepalive = config.keepalive;'''),
    ('                if code != 101 {', '''                if let Some(trace) = &self.diagnostic { trace.event("handshake_response", serde_json::json!({"httpStatus":code})); }
                if code != 101 {'''),
    ('                    self.session.event(Event {\n                        kind: 5,', '''                    if let Some(trace) = &self.diagnostic { trace.peer_close(code, &reason[..used as usize]); }
                    self.session.event(Event {
                        kind: 5,'''),
    ('                    if !self.session.event(Event {\n                        kind: if text', '''                    if let Some(trace) = &mut self.diagnostic { trace.message("incoming", &bytes); }
                    if !self.session.event(Event {
                        kind: if text'''),
    ('                    Command::Send(bytes, kind) => {', '''                    Command::Send(bytes, kind) => {
                        if let Some(trace) = &mut self.diagnostic { trace.message("outgoing", &bytes); }'''),
    ('        if let Err(code) = result {', '''        if let Some(trace) = &self.diagnostic { trace.event("worker_end", serde_json::json!({"errorCode":result.as_ref().err().copied()})); }
        if let Err(code) = result {'''),
    ('            let mut worker = Worker {', '            let mut worker = Worker {\n                diagnostic: None,'),
]
for old, new in patches:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'Expected exactly one instrumentation site, got {count}: {old[:80]}')
    text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')
print(target)
