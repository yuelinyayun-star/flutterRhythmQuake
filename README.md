# FlutterRhythmQuake

FlutterRhythmQuake 是一个使用 Flutter 构建的跨平台实时地震与多灾种监测客户端。项目将多个公开或经用户授权的数据源汇入统一事件生命周期，在地图、侧栏、通知和语音播报中保持一致的接纳、更新、去重与过期行为。

当前版本：`1.0.5+9`

> 开发状态：项目仍在持续完善，功能和文档会随代码更新。

> 本项目不是官方预警终端。地震、海啸、火山、台风和气象信息应以对应机构正式发布为准，不应仅依赖本软件进行避险决策。

## 主要能力

- 地震预警与地震信息：多来源 EEW、地震目录、正式测定和历史事件。
- 实时测站：NIED、S-net、KMA、FDSN、P-Alert、SeisJS 等测站或网格数据。
- 烈度与震度：JMA 震度、中国烈度、MMI、LPGM 以及 CENC 烈度速报。
- CMT：多来源矩张量、震源球、节线和断层类型参考判断。
- 多灾种信息：JMA 火山与降灰预报、海啸、台风、气象预警和本地气象站实况。
- 统一交互：地图图层、侧栏、自动视角、系统通知、轻通知和 TTS 播报。
- 桌面能力：Windows 托盘、窗口管理、本地缓存和安装包构建。

数据源是否可用取决于网络、平台限制、用户设置和来源授权。FAN Studio API Key 由用户自行申请并在应用设置中保存；WAuth 数据源必须完成官方登录与 API 授权后才能开启。

## 平台状态

| 平台 | 工程支持 | 当前仓库验证 |
| --- | --- | --- |
| Windows | 是 | Release 构建和 Inno Setup 安装包已验证 |
| Android | 是 | APK 构建链已配置 |
| macOS | 是 | 平台工程已配置，发布前需在 macOS 主机验证 |
| Linux | 是 | 平台工程已配置，发布前需在 Linux 主机验证 |
| iOS | 是 | 平台工程已配置，发布前需在 macOS/Xcode 验证 |
| Web | 是 | 部分原生能力使用平台适配层，发布前需单独验证 |

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

运行 Windows 调试版：

```powershell
flutter run -d windows
```

构建 Windows Release：

```powershell
.\build_windows.ps1 -Release
```

生成 Windows 安装包：

```powershell
.\package_windows.ps1
```

安装包输出到 `build\installer\`。Android Release 可使用：

```powershell
flutter build apk --release
```

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
- [震源推算路线图](docs/source_estimation_roadmap.md)
- [FAN API 字段说明](FAN_API字段说明.md)
- [Wolfx 字段说明](Wolfx字段说明.md)

## 仓库边界

本地构建产物、服务器压缩包、虚拟环境、调试报告、临时抓取文件和新下载的研究输入均由 `.gitignore` 排除。公开提交前仍应检查暂存内容，确认没有凭据、个人数据和非必要二进制文件。

本仓库目前没有声明开源许可证。在许可证明确之前，公开可见不等于获得复制、修改或再分发授权。
