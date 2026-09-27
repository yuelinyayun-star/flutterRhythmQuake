# Web 适配状态

Web 分支保留 Flutter 主入口 `lib/main.dart` 和现有地图、预警界面。以下浏览器适配已落地：

- Wolfx 使用浏览器 WebSocket；原生客户端仍使用原有连接方式。
- 浏览器校时只尝试 HTTP 时间接口；浏览器无法使用 UDP NTP。
- 回放包从浏览器选中的文件字节导入，导出时交给浏览器下载。
- 设置页可在浏览器选取背景图，最多 2 MiB，保存在浏览器本地存储中。
- 应用标签和安装清单使用 RhythmQuake 名称。

## 验证与后续工作

在有 Flutter 构建环境的机器上运行：

```sh
flutter pub get
flutter build web --release
flutter run -d chrome
```

目前尚未取得 Web 构建通过的证据。主入口仍引用若干 `dart:io` 和原生插件路径，需根据编译输出继续拆分条件导入，包括 TTS、NIED 监测和本地注入等模块。即使编译通过，第三方地震数据接口及地图瓦片能否在浏览器直接访问，仍取决于服务端 CORS、HTTPS 和 WebSocket 策略；应逐个在部署域名下验证。浏览器不提供原生后台常驻、系统托盘和 UDP 能力。
