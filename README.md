# RhythmQuake

RhythmQuake 是一个使用 Flutter 构建的跨平台实时地震与多灾种监测客户端，支持地震预警、地震信息、实时测站、历史回放，以及海啸、火山、台风和气象信息展示。

当前公开版本：`1.0.5+21`。

[下载最新版本](https://github.com/yuelinyayun-star/flutterRhythmQuake/releases/latest) · [打开 Web 版](https://eew.yuelinrhythm.top/) · [查看文档](docs/README.md)

> 开发状态：项目仍在持续完善，功能和文档会随代码更新。

> 本项目不是官方预警终端。地震、海啸、火山、台风和气象信息应以对应机构正式发布为准，不应仅依赖本软件进行避险决策。

## 主要能力

- 地震预警与地震信息：多来源 EEW、地震目录、正式测定和历史事件。
- 实时测站：NIED、S-net、KMA、SeisJS、TREM，以及通过 SeedLink 接入的全球测站。
- 烈度与震度：JMA 震度、中国烈度、MMI、LPGM 以及 CENC 烈度速报。
- 历史与回放：保存预警各报和已启用测站的数据，支持回放包导入、导出和时间轴联动回放。
- CMT：多来源矩张量、震源球、节线和断层类型参考判断。
- 多灾种信息：JMA 火山与降灰预报、海啸、台风、气象预警和本地气象站实况。
- 地图与交互：图层开关、自动视角、侧栏信息和地震信息复制；移动端可长按地震条目复制，列表时间与复制内容均显示到秒。
- 通知与播报：系统通知、轻通知和语音播报，具体能力取决于平台。
- 桌面能力：Windows 托盘、窗口管理和本地缓存。

### SeedLink 全球测站

可分别开启 EarthScope、GEOFON、GeoNet、RESIF、IPGP、ORFEUS 和 BGR。多来源测站按标识去重，优先订阅区域来源，EarthScope 补充其他来源没有的测站。

地图支持三角形、圆形和按类别三种测站样式，以及信号比值、MMI 和中国烈度估算显示。默认使用圆形与信号比值；标记大小随地图视野变化。来源状态区分别显示连接站数，并用颜色区分正常、延迟和连接失败。

### 历史记录与回放

- 默认每个预警源保留最近 15 个事件，每个事件包含收到的各报；高级设置可调整每源保存上限或开启永久保存。
- 预警记录可同时保存已启用测站的数据，用于回放当时的测站状态，包括 S-net 和 LPGM。
- 回放包使用 `.rqreplay` 格式，支持导入、导出、播放、重新回放、停止和进度显示；报时缺失或冲突时可逐报播放。
- 开启“时间轴联动回放”后，播放一个事件时会按共同时间轴播放时间重叠的其他有效事件。
- 测站记录使用 JSON 分块压缩和按需读取，减少重复存储，以及启动和回放时一次性加载的数据量。

### 本次更新

`1.0.5+21` 重点优化历史回放存储、测站记录加载和全球测站地图绘制，完善测站样式、信号比值与数值显示，并调整 NIED、LPGM、S-net 数据更新处理。完整说明见 [版本发布页](https://github.com/yuelinyayun-star/flutterRhythmQuake/releases/tag/v1.0.5.21-public)。

数据源是否可用取决于网络、平台限制、用户设置和来源授权。FAN Studio API Key 由用户自行申请并在应用设置中保存；WAuth 数据源必须完成官方登录与 API 授权后才能开启。

## 下载与平台

当前公开版提供以下文件，发布页同时附有对应的 SHA-256 校验文件：

| 平台 | 下载 / 使用入口 | 文件形式 |
| --- | --- | --- |
| Windows x64 | [下载安装包](https://github.com/yuelinyayun-star/flutterRhythmQuake/releases/download/v1.0.5.21-public/RhythmQuake_Setup_1.0.5.21_public_x64.exe) | Inno Setup 安装包 |
| Android | [下载 APK](https://github.com/yuelinyayun-star/flutterRhythmQuake/releases/download/v1.0.5.21-public/RhythmQuake_1.0.5.21_public.apk) | APK |
| Linux x64 | [下载完整包](https://github.com/yuelinyayun-star/flutterRhythmQuake/releases/download/v1.0.5.21-public/RhythmQuake_1.0.5.21_public_linux_x64.tar.gz) | `.tar.gz` 便携包 |
| Web | [在线使用](https://eew.yuelinrhythm.top/) / [下载静态包](https://github.com/yuelinyayun-star/flutterRhythmQuake/releases/download/v1.0.5.21-public/RhythmQuake_1.0.5.21_public_web.zip) | 浏览器 / 静态站点文件 |

Linux 请解压完整目录并保留其中的 `lib` 和 `data`。依赖安装、启动方法和 WSLg 验证范围见 [Linux 运行说明](docs/linux_runtime.md)。

| 平台 | 工程支持 | 当前仓库验证 |
| --- | --- | --- |
| Windows | 是 | 已发布 `1.0.5+21` x64 安装包 |
| Android | 是 | 已发布 `1.0.5+21` APK |
| Linux | 是 | 已发布 `1.0.5+21` x64 完整包；另有 Ubuntu 24.04 WSLg 基础运行验证记录 |
| Web | 是 | 已上线，并提供 `1.0.5+21` 静态包 |
| macOS | 是 | 平台工程已配置，发布前需在 macOS 主机验证 |
| iOS | 是 | 平台工程已配置，发布前需在 macOS/Xcode 验证 |

Web 的数据连接受浏览器跨域与协议限制，原生桌面能力不适用于浏览器。Linux 系统 TTS 尚不受当前依赖支持；各平台的运行与验证范围请结合对应文档确认。

## 开发环境

- Flutter `3.41.x` 或与 `pubspec.lock` 兼容的稳定版本
- Dart `3.11.x`
- Windows 桌面构建需要 Visual Studio 的 Desktop development with C++ 工作负载
- Android 构建需要 Android SDK 与对应工具链
- Windows 安装包需要 Inno Setup 6 或 7

检查环境并获取依赖：

```powershell
flutter doctor
flutter pub get
```

运行 Windows 公开版调试构建：

```powershell
flutter run -d windows --dart-define=RQ_EDITION=public
```

构建 Windows 公开版 Release：

```powershell
.\build_windows.ps1 -Release -Edition public
```

生成 Windows 安装包：

```powershell
.\package_windows.ps1 -Edition public
```

安装包输出到 `build\installer\`。构建并归档 Android 公开版：

```powershell
.\build_android_edition.ps1 -Edition public
```

在 Linux 环境中构建并打包 Linux 公开版：

```bash
flutter pub get
bash build_linux_edition.sh public
```

构建 Web 公开版：

```powershell
flutter build web --release --dart-define=RQ_EDITION=public
```

Web 输出到 `build/web/`，需要由 HTTP 服务提供访问。

## 配置与凭据

- 不要把 FAN API Key、WAuth AppSecret、访问令牌、服务器密码或个人账号提交到仓库。
- FAN API Key 仅由客户端设置页保存到本地偏好设置。
- WAuth AppSecret 只允许通过网关服务器环境变量 `WAUTH_CLIENT_SECRET` 提供，不能放入 Flutter 客户端。
- KMA Relay 的端口、上游地址和访问令牌使用服务器环境变量配置。
- 服务器部署说明分别位于 [WAuth Gateway](server/wauth_gateway/README.md) 和 [KMA PEWS Relay](server/kma_pews_relay/README.md)。

## 目录结构

```text
lib/          Flutter 生产代码：模型、Provider、服务、信源、地图和 UI
assets/       运行时地图、地区索引、图标、字体、声音和接收器资源
test/         产品单元测试、组件测试、回放测试和研究诊断测试
tool/         当前项目使用的离线构建、探测和科研诊断工具
tools/        历史工具、数据采集脚本和参考实现移植
docs/         架构、设置、数据字段、研究记录和生成基线
references/   可追溯论文、网页证据和离线研究输入
server/       WAuth 网关与 KMA PEWS Relay
windows/      Windows Runner；其他平台目录遵循 Flutter 标准结构
```

`references/`、`tool/` 和 `tools/` 中的内容服务于算法复核与可追溯实验，不属于应用运行时资产。不要在不了解引用关系时移动这些目录。

## 质量检查

生产代码和测试目录的静态检查：

```powershell
flutter analyze lib test --no-fatal-warnings --no-fatal-infos
```

运行指定产品测试：

```powershell
flutter test test/whews_event_lifecycle_test.dart
flutter test test/cenc_unified_ui_lifecycle_test.dart
flutter test test/volcano_sidebar_panel_test.dart
```

完整 `flutter test` 还会运行耗时较长、依赖离线夹具的回放和科研诊断测试。发布验证应记录实际运行的测试文件，不能把未执行的离线测试声明为通过。

服务器测试：

```powershell
python -X utf8 -m unittest discover -s server/wauth_gateway -p "test_*.py" -v
python -X utf8 -m unittest discover -s server/kma_pews_relay -p "test_*.py" -v
```

服务器测试需要先安装各目录 `requirements.txt` 中的依赖。

## 文档

从 [文档索引](docs/README.md) 开始阅读。常用入口：

- [架构与数据流](docs/ARCHITECTURE.md)
- [设置页面结构](docs/settings_page_structure.md)
- [数据字段与注册映射](docs/字段获取与注册映射.md)
- [Linux 运行说明](docs/linux_runtime.md)
- [FAN API 字段说明](FAN_API字段说明.md)
- [Wolfx 字段说明](Wolfx字段说明.md)

## 仓库边界

本地构建产物、服务器压缩包、虚拟环境、调试报告、临时抓取文件和新下载的研究输入均由 `.gitignore` 排除。公开提交前仍应检查暂存内容，确认没有凭据、个人数据和非必要二进制文件。

本仓库目前没有声明开源许可证。在许可证明确之前，公开可见不等于获得复制、修改或再分发授权。
