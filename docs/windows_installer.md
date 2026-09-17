# RhythmQuake Windows 安装器

## 构建

在项目根目录使用 UTF-8 PowerShell 运行：

```powershell
.\package_windows.ps1
```

脚本依次执行：

1. 从 `pubspec.yaml` 读取 `x.y.z+build` 版本号。
2. 调用 `build_windows.ps1 -Release` 构建 Flutter x64 Release。
3. 校验必需运行文件并生成 `release_manifest.json`。
4. 下载或复用经过 SHA-256 校验的 Inno Setup 简体中文语言文件。
5. 编译 `installer_rhythmquake.iss`，生成单文件 x64 安装器。
6. 在安装器旁生成 `.sha256` 校验文件。

输出示例：

```text
build/installer/RhythmQuake_Setup_1.0.4.5_x64.exe
build/installer/RhythmQuake_Setup_1.0.4.5_x64.exe.sha256
```

`installer.iss` 是旧版通用安装器脚本，仅保留作发布回退。正常发布入口使用
`installer_rhythmquake.iss`。

界面调试时可额外定义 `InstallerPreview`。预览包固定输出到
`build/installer/preview/RhythmQuake_UI_Preview.exe`，标题和品牌区标明不可安装，
准备安装页禁用安装按钮，并阻止静默安装。不要把预览包当作安装包分发。
正常打包不定义此宏，输出的 `RhythmQuake_Setup_*.exe` 使用实际安装流程。

## 界面规范

- 安装窗口使用 RhythmQuake 自绘深色标题栏，不显示 Windows 默认标题栏。
- 标题栏只保留拖动、最小化和关闭操作，不重复显示应用图标、产品名，不提供最大化。
- 窗口客户区保持背景图片的 1708:921 比例，宽度按字体/DPI 缩放。
- 整页背景使用当前 RhythmQuake 主界面的客户端区域截图，不包含 Windows 系统标题栏；背景经过虚化、降亮度和冷色毛玻璃处理，源文件为 `assets/installer/rhythmquake_frosted_background.png`。
- 应用图标、产品名、产品定位和版本集中在左侧独立毛玻璃区域；玻璃底图从整页背景的对应位置采样并叠加色层，初始化时生成，不在重绘时重复处理。
- 当前步骤标题和说明位于右侧内容上方，避免挤占左侧品牌区域及底栏。
- 每次切换步骤后按当前语言测量标题、说明的实际高度，内容区从说明下方留出 24 个缩放单位后开始，不与原生步骤提示重叠。
- 右侧只承载安装目录、可选任务、安装确认和完成操作等当前步骤内容。
- 底部固定放置进度条和取消、上一步、下一步或安装按钮，页面切换不得改变底栏尺寸或把按钮推到窗口外。
- 底栏使用独立深色半透明背景。安装前进度为空，安装中使用引擎真实进度，完成后显示满进度；不使用页面序号模拟安装百分比。
- 欢迎页不重复显示升级时保留哪些用户数据；相关行为由安装和卸载流程实际保证。

## 安装身份与升级

- 安装器固定使用 `AppId=FlutterRhythmQuake`，与旧版卸载标识兼容。
- 新安装使用 x64 安装模式和原生 `Program Files` 目录。
- 发现旧版 32 位安装模式的卸载项时，安装器先调用其原卸载器静默移除旧程序，
  再把新版安装到旧目录，避免产生两份卸载项或两套程序目录。
- 旧卸载器缺失或迁移失败时中止安装，不以并行安装作为兜底。
- 安装过程中重新注册开始菜单、桌面快捷方式和 `rhythmquake://` 协议。

## 用户数据

程序文件和用户数据严格分离。升级与普通卸载默认保留：

```text
%APPDATA%/com.example/flutterrhythmquake
%LOCALAPPDATA%/com.example/flutterrhythmquake
```

交互式卸载结束后会询问是否删除个人设置、登录状态、历史记录和地图缓存，
默认选择为“否”。静默卸载始终保留用户数据。

## 发布检查

发布前至少确认：

- 安装器和 `.sha256` 文件一致。
- `release_manifest.json` 的版本、文件数量、大小和 SHA-256 全部通过校验。
- 从当前线上旧版覆盖升级后只有一个卸载项。
- 应用启动、托盘退出和 `rhythmquake://` 回调正常。
- 普通卸载保留用户数据，明确选择清除后才删除数据。
- 完成 Authenticode 签名；未签名构建只用于内部测试。
