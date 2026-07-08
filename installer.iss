; FlutterRhythmQuake Windows Installer
; Inno Setup 脚本
; 使用前请先运行: .\build_windows.ps1 -Release

#define MyAppName "FlutterRhythmQuake"
#define MyAppVersion "1.0.1"
#define MyAppPublisher "com.example"
#define MyAppURL ""
#define MyAppExeName "flutterrhythmquake.exe"

[Setup]
; 基本设置
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
; 安装包文件
OutputDir=build\installer
OutputBaseFilename=FlutterRhythmQuake_v{#MyAppVersion}_Setup
; 安装包图标（使用项目的 app icon）
SetupIconFile=windows\runner\resources\app_icon.ico
; 压缩设置
Compression=lzma2/max
SolidCompression=yes
; 权限 - 需要管理员安装（写入 Program Files）
PrivilegesRequired=admin
; 语言
LanguageDetectionMethod=locale
; 卸载相关
UninstallDisplayIcon={app}\{#MyAppExeName}
; 禁用 "正在使用" 页面
DisableProgramGroupPage=yes

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "ja"; MessagesFile: "compiler:Languages\Japanese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
; 主程序和库文件
Source: "build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\native_assets.json"; DestDir: "{app}"; Flags: ignoreversion
; data 目录（包含 app.so, icudtl.dat, flutter_assets 等）
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; 安装完成后可选启动程序
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
{ 安装前检查是否已存在旧版本，提示卸载 }
function InitializeSetup: Boolean;
begin
  Result := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    { 安装前关闭正在运行的旧版本 }
  end;
end;
