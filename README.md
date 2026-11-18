<div align="center">

<img src="assets/icon/app_icon.png" alt="RhythmQuake" width="128" />

# RhythmQuake

**基于 Flutter 与 Rust 原生核心的跨平台实时地震与多灾种监测客户端**

<p>
  <a href="#下载与支持平台"><img src="https://img.shields.io/badge/Platform-Windows%20%7C%20Android%20%7C%20Linux%20%7C%20Web%20%7C%20macOS%20%7C%20iOS-blue" alt="Platform" height="20" /></a>
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.41.x-02569B?logo=flutter" alt="Flutter" height="20" /></a>
  <a href="https://dart.dev"><img src="https://img.shields.io/badge/Dart-3.11.x-0175C2?logo=dart" alt="Dart" height="20" /></a>
  <a href="native/station_core"><img src="https://img.shields.io/badge/Native%20Core-Rust-DEA584?logo=rust" alt="Rust" height="20" /></a>
</p>

[下载最新版本](https://github.com/yuelinyayun-star/flutterRhythmQuake/releases/latest) · [Web 在线版](https://eew.yuelinrhythm.top/) · [安装包归档](https://file.yuelinrhythm.top/public/share/Rfvwpk6z7f0uEcMWc_sa1g) · [回放文件夹](https://file.yuelinrhythm.top/public/share/2me6CJMrNsVOv_-aFfNePQ)

</div>

---

## 简介

**RhythmQuake** 是一款跨平台实时地震及多灾种监测客户端，采用 **Flutter** 构建全平台 UI 界面，并依托 **Rust** 原生核心处理高频测站解码、SeedLink 信号分析、网络传输与回放归档。软件聚合全球多个官方与公开地震台网、预警消息源及海啸/火山/气象信息，在地图上实时呈现地震波传播、测站地震动、烈度分布与震源反演动态，并提供历史时间轴联动回放、事件制图、系统通知与语音播报能力。

---

## 主要功能

* **地震预警接收**
  * 聚合中国地震台网（CENC 及各省台网）、台湾中央气象署（CWA）、日本气象厅（JMA）、韩国气象厅（KMA PEWS）、墨西哥 SASMEX 等来源的地震预警与速报。
  * 随各报实时更新震中、震级、深度、发震时刻与报文状态，在地图上动态绘制 P/S 波传播圈、本地预估烈度/震度与到达倒计时。
* **地震目录与专题情报**
  * 聚合 CENC、CWA、JMA、P2PQuake、USGS、EMSC 等地震情报与目录，支持按来源筛选与快捷复制。
  * 集成 **NowQuake**（CENC 烈度速报）、**USGS ShakeMap**、**USGS DYFI**（有感烈度反馈）、**JMA 长周期地震动阶（LPGM）**、**JMA 南海海槽地震临时情报**，以及 **CENC、USGS、JMA、F-net、Hi-net AQUA** 的 CMT 震源机制解（震源球与断层参数）。
* **实时测站与全球 SeedLink 监测**
  * 接入日本 **NIED**（強震モニタ K-moni / L-moni、長周期地震動モニタ）、**S-net**（日本海溝海底地震津波観測網 / MSIL）、韩国 **KMA** 实时测站、**ExpTech TREM RTS** 与 **Wolfx SeisJS** 社区观测网络。
  * 原生接入 **FDSN / SeedLink** 全球测站（EarthScope、GEOFON、GeoNet、RESIF、IPGP、ORFEUS、BGR），支持多来源自动去重与延迟诊断；支持多种测站标记样式，并可切换信号比值、MMI 或中国地震烈度（CSIS）估算显示。
* **实时震源反演与晃动检测**
  * 内置基于测站观测与走时表的实时震源反演与烈度估算引擎，支持单台/多台联合触发检测，并提供本地设备晃动检测。
* **海啸、火山与气象监测**
  * **海啸**：支持 JMA、P2PQuake、NOAA（PTWC / NTWC）、INCOIS 及中国自然资源部海啸预警中心（NMEFC）海啸预警图层与潮位站观测。
  * **火山与台风**：支持 JMA 火山喷发警报与降灰预报，以及台风实时路径与预报追踪。
  * **气象与遥感**：集成中国气象局（CMA）气象预警与逐小时/本地实况、JMA 气象实况、NOAA GFS 风场、全国与 JMA 雷达回波，以及 JMA 葵花、风云（NSMC）全球红外、东南沿海及西太卫星云图与回放，并提供桌面与移动端天气主视图。
* **地图展示、历史回放与联动工具**
  * **多源地图图层**：支持离线矢量底图，以及 [FAN Studio TileMap](https://tilemap.fanstudio.tech/)（Petal、ArcGIS、DEM 高程等）、Jian 地图服务、Mapbox Dark 等多套底图切换，叠加行政区划边界与中国、日本活动断层（GSJ）图层。
  * **历史回放与制图**：按来源保存历史事件及各报详情，录制预警时可同步记录已启用测站数据；支持 `.rqreplay` 回放包导入导出、逐报步进、多源时间轴联动回放，以及事件图片渲染导出。
  * **提醒与录制联动**：提供系统通知、应用内轻通知、TTS 语音播报、预警音效、桌面端托盘/窗口置顶管理，以及 OBS WebSocket 自动录制联动。

---

## API 与数据源

* **聚合与预警 API**：**FAN Studio**（支持 API Key 鉴权与多服务器切换）、**Wolfx Project**、**WHEWS**（支持 WAuth OAuth 2.0 授权登录）、**JIAN**（Jian Project，支持独立凭证与主备切换）、**Rhythm API**（含 KMA-PEWS 中继）、**FSSN**、**NowQuake**、**P2PQuake**（地震与海啸情报）、**KMA PEWS**、**SASMEX**
* **地震目录与专题接口**：中国地震台网（CENC / 烈度速报 / CMT）、台湾中央气象署（CWA）、日本气象厅（JMA 地震目录 / LPGM / 南海海槽临时情报 / CMT）、USGS（目录 / ShakeMap / DYFI / CMT）、EMSC、F-net CMT、Hi-net AQUA CMT
* **测站与波形网络**：NIED（強震モニタ / L-moni）、S-net（MSIL）、KMA 实时测站、ExpTech TREM RTS、Wolfx SeisJS、FDSN / SeedLink（EarthScope、GEOFON、GeoNet、RESIF、IPGP、ORFEUS、BGR）
* **海啸、火山与气象接口**：JMA（海啸 / 火山与降灰 / 雷达 / 葵花云图 / 气象实况）、NOAA（PTWC / NTWC 海啸与 GFS 风场）、INCOIS 海啸、NMEFC 沿岸海啸、CMA 气象预警与实况、NSMC 风云卫星云图、浙江省水利厅（台风路径与东南沿海/西太云图）
* **地图底图与地理数据**：离线矢量底图、[FAN Studio TileMap](https://tilemap.fanstudio.tech/)（Petal、ArcGIS、DEM 高程及实况云图/降水/中国等高线瓦片）、Jian 地图服务、Mapbox、日本产总研（GSJ）活断层数据库

---

## 下载与支持平台

各平台最新安装包及对应的 SHA-256 校验文件请前往 [GitHub Releases](https://github.com/yuelinyayun-star/flutterRhythmQuake/releases/latest) 下载；[安装包归档](https://file.yuelinrhythm.top/public/share/Rfvwpk6z7f0uEcMWc_sa1g) 亦会同步保留历史构建。

| 平台 | 获取方式 | 文件形式 | 说明 |
| --- | --- | --- | --- |
| Windows x64 | [GitHub Releases](https://github.com/yuelinyayun-star/flutterRhythmQuake/releases/latest) | `.exe` 安装包 | 支持系统托盘、窗口置顶与本地缓存 |
| Android | [GitHub Releases](https://github.com/yuelinyayun-star/flutterRhythmQuake/releases/latest) | `.apk` 安装包 | 支持后台服务与持续录制 |
| Linux x64 | [GitHub Releases](https://github.com/yuelinyayun-star/flutterRhythmQuake/releases/latest) | `.tar.gz` 便携包 | 解压完整目录后运行 |
| Web | [在线使用](https://eew.yuelinrhythm.top/) / [GitHub Releases](https://github.com/yuelinyayun-star/flutterRhythmQuake/releases/latest) | 浏览器 / 静态站点 | 受浏览器跨域与协议限制，部分原生能力不可用 |
| macOS / iOS | 源码构建 | 工程已配置 | 需在 macOS / Xcode 环境下构建 |

---

## 注意事项

1. 本软件**不是官方预警终端**，仅用于信息展示与技术研究。地震、海啸、火山、台风及气象信息均应以对应官方机构正式发布为准，切勿仅依赖本软件进行防灾避险决策。
2. 各数据源的可用性取决于网络环境、平台限制及来源授权状态；部分接口需要用户自行配置密钥或完成授权后方可使用（如 FAN Studio API Key、WHEWS 的 WAuth 账号授权、JIAN 个人凭证）。
3. 本仓库目前尚未声明开源许可证。在许可证明确之前，仓库公开可见并不代表授予复制、修改或再分发授权。

---

## 参考项目与致谢

本项目在开发过程中参考了以下开源项目、技术实现与公开资料，在此向各位作者与维护者表示感谢：

* **[要石 (kanameishi)](https://github.com/Lipomoea/kanameishi)**（`Lipomoea`，AGPL-3.0）
* **[GlobalQuake（旧版开源版本 `0.11.0`）](https://github.com/xspanger3770/GlobalQuake)**（`xspanger3770`，MIT）
* **[リアルタイム地震ビューアー (SREV)](https://github.com/kotoho7/scratch-realtime-earthquake-viewer-page)**（`kotoho7`，CC BY-SA 2.0）与 **[srev-chinese-translation](https://github.com/ZeroStar645/srev-chinese-translation)**（`ZeroStar645`）
* **[ZeroStar645（Relight）](https://github.com/ZeroStar645)** —— 火山图标协助
* **[ingen084/kyoshin-monitor-observation-points](https://github.com/ingen084/kyoshin-monitor-observation-points)**
* **[NoneType1 強震モニタ GIF 解析相关文章](https://qiita.com/NoneType1/items/a4d2cf932e20b56ca444)**
* **[ExpTechTW/TREM-Lite](https://github.com/ExpTechTW/TREM-Lite) / [TREM-Lite-v2](https://github.com/ExpTechTW/TREM-Lite-v2)**（AGPL-3.0）
* **[0Quake/JMA_Region](https://github.com/0Quake/JMA_Region)**
* **[p2pquake/epsp-specifications](https://github.com/p2pquake/epsp-specifications)**
* **[ObsPy](https://github.com/obspy/obspy)** 与 **[EarthScope `libslink`](https://github.com/EarthScope/libslink)** / **SeisComP SeedLink** 规范
* **公开数据与科研机构资料**：NIED（強震モニタ / L-moni / J-SHIS）、JMA（地震目录、多语言词典与走时/震度归档）、日本产总研（GSJ）、CENC、CWA、KMA、USGS、EMSC、NOAA、INCOIS、NMEFC、CMA、NSMC、NLSC、SGIS、Alibaba DataV.GeoAtlas、GeoJSON.cn 等
* **社区与 API 生态**：FAN Studio / FSSN、Wolfx（含 SeisJS）、P2PQuake、WHEWS、[Jian Project Center](https://github.com/Jian-Project-Center)、ExpTech TREM、NowQuake 等
