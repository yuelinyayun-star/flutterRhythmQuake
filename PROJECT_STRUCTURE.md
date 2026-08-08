# Flutter RhythmQuake 项目结构文档

> 状态：历史结构文档。本文保留用于追溯早期模块划分，当前目录和数据流请以 [README.md](README.md)、[文档索引](docs/README.md) 与 [架构总览](docs/ARCHITECTURE.md) 为准。

## 项目概述

Flutter RhythmQuake 是一个跨平台地震预警应用，支持实时接收和显示来自多个地震监测机构的数据，包括中国地震台网中心(CENC)、日本气象厅(JMA)、韩国气象厅(KMA)等。

---

## 目录结构

```
lib/
├── main.dart                    # 应用入口
├── main_screen.dart             # 主屏幕
├── core/                        # 核心计算模块
├── models/                      # 数据模型
├── providers/                   # 状态管理
├── screens/                     # 页面
├── services/                    # 服务层
├── utils/                       # 工具类
└── widgets/                     # UI组件
```

---

## 文件详细说明

### 📱 入口文件

| 文件 | 用途 |
|------|------|
| `main.dart` | 应用程序入口点，负责初始化 Flutter 绑定、设置主题、配置多语言支持、初始化服务和注册数据源。 |
| `main_screen.dart` | 主屏幕组件，整合地图视图、预警面板、状态栏和历史记录面板等核心 UI 组件。 |

---

### 🔧 核心计算模块 (core/)

#### 计算器

| 文件 | 用途 |
|------|------|
| `calculator.dart` | 地震波计算核心类，包含 P 波/S 波速度常量、震中距离计算、震度衰减公式、到时估算等功能。 |
| `intensity_calculator.dart` | 烈度计算器，根据震级、深度、距离计算预估烈度，支持多种烈度标准（JMA、MMI、中国烈度）。 |

#### 工具类 (core/utils/)

| 文件 | 用途 |
|------|------|
| `alert_voice_helper.dart` | 预警语音辅助类，根据地震参数生成语音播报文本，支持多语言预警信息生成。 |
| `geo_loader.dart` | 地理数据加载器，负责加载 GeoJSON 边界数据和城市坐标信息。 |
| `quake_time.dart` | 地震时间处理工具，处理发震时刻的时区转换、格式化和相对时间计算。 |

---

### 📦 数据模型 (models/)

| 文件 | 用途 |
|------|------|
| `quake_message.dart` | 地震消息数据模型，定义地震事件的核心数据结构，包括震级、位置、深度、时间、烈度等字段。**支持 EEW 特有字段**：`isWarn`(警报级)、`isFinal`(最终报)、`isCanceled`(取消报)、`isAssumption`(假定震源)、`reportNumText`(报告编号文本)。提供 `copyWith` 方法用于同一事件的多次更新。 |
| `intensity_theme.dart` | 烈度主题配置，定义不同烈度等级对应的颜色方案（JMA、MMI、中国烈度标准）。 |
| `source_status.dart` | 数据源状态模型，定义数据源的连接状态枚举（连接中、已连接、断开、错误）。 |
| `cenc_ir_data.dart` | CENC 仪器烈度数据模型，存储中国地震台网中心发布的仪器烈度分布数据。 |
| `nied_station_db.dart` | NIED 测站数据库，内置日本 K-NET/KiK-net 测站的元数据（代码、名称、坐标、网络类型）。 |
| `snet_station.dart` | S-net 海底测站模型，表示日本海底地震观测网的测站数据。 |

---

### 🔄 状态管理 (providers/)

| 文件 | 用途 |
|------|------|
| `quake_provider.dart` | 地震数据状态管理，管理预警事件列表、历史地震、活跃预警、数据源状态等全局状态。ActiveWarning 类支持 `update()` 事件更新、`mute` 静默、`dismissTimer` 自动移除。EEW 事件统一处理取消报(20秒短计时)、同一事件多次更新。信息事件 120 秒自动关闭。参考 kanameishi 的过期策略：警报级 `max(震级,6)*60` 秒，普通 `max(震级,3)*60` 秒。 |
| `map_state_provider.dart` | 地图状态管理，控制地图的中心位置、缩放级别、动画移动和选中的历史事件。 |

---

### 🖥️ 页面 (screens/)

| 文件 | 用途 |
|------|------|
| `main_screen.dart` | 主页面，整合所有 UI 组件，处理页面布局和导航。 |

---

### ⚙️ 服务层 (services/)

#### 基础服务

| 文件 | 用途 |
|------|------|
| `database_helper.dart` | 数据库辅助类，管理本地 SQLite 数据库，存储历史地震记录和配置信息。 |
| `event_bus.dart` | 事件总线，实现跨组件通信，用于广播地震预警事件。 |
| `location_service.dart` | 位置服务，获取用户当前位置，用于计算震中距离和预估烈度。 |
| `ntp_service.dart` | NTP 时间服务，与网络时间服务器同步，确保预警时间戳的准确性。 |
| `tts_service.dart` | 语音合成服务，将预警信息转换为语音播报。 |
| `windows_manager.dart` | 窗口管理器，管理桌面平台的窗口状态（置顶、最小化等）。 |
| `boundary_service.dart` | 边界服务，加载和解析 GeoJSON/TopoJSON 边界数据，用于地图行政区划显示。 |
| `quake_message.dart` | 地震消息服务（可能是重复文件，需确认）。 |

#### 数据源服务 (services/sources/)

| 文件 | 用途 |
|------|------|
| `base_source.dart` | 数据源服务基类，定义所有数据源的通用接口（connect、disconnect、emit）和事件流机制。 |
| `source_manager.dart` | 数据源管理器，统一管理所有数据源的连接、断开和事件分发。 |
| `wolfx_service.dart` | Wolfx WebSocket 服务，接收 Wolfx 平台推送的地震预警数据（JMA、CENC、CWA 等）。 |
| `fan_service.dart` | FanStudio 服务，接收 FanStudio 聚合平台的地震数据。支持 JMA/CWA/CWA-EEW/CEA/CEA-PR/FSSN/KMA/HKO/SA/EMSC/BCSF/GFZ/USP/Ningxia/Guangxi/Shanxi/Beijing/Yunnan 等 19 种数据源的自动识别。支持 CENC 列表订阅（`cenclist` 指令），HKO 数据源的 `verify` 映射（Y→已核实/N→待核实）和 `citystring`/`region` 地点描述增强。 |
| `p2pquake_service.dart` | P2PQuake 服务，接收日本 P2PQuake 地震信息网络的数据。 |
| `nied_monitor.dart` | NIED 强震监测服务，获取日本防灾科学技术研究所的实时震度数据。 |
| `kma_monitor.dart` | KMA 监测服务，获取韩国气象厅的实时震度数据。 |
| `snet_service.dart` | S-net 海底观测服务，获取日本海底地震观测网的实时数据。 |
| `mock_input_service.dart` | 模拟输入服务，用于测试，支持手动注入地震数据。 |
| `usgs_eqlist_service.dart` | USGS 地震列表服务，通过 USGS GeoJSON API 获取全球 2.5 级以上地震目录。使用 Flinn-Engdahl 区域数据库转换中文地名，自动计算 CSIS 烈度。 |

#### 地震列表服务 (services/sources/eqlist/)

地震列表系统负责从多个地震监测机构获取历史地震目录，支持按震级和数据源筛选。

##### 架构概览

```
┌─────────────────────────────────────────────────────────────────────┐
│                         EqlistManager                              │
│                    (统一聚合管理器，单例模式)                          │
├──────────┬──────────┬──────────┬──────────┬──────────┬─────────────┤
│ JMA列表  │ CENC列表 │ USGS列表 │ FSSN列表 │ KMA列表  │ CWA列表     │
│ (HTTP)   │ (FAN推送)│ (HTTP)   │ (FAN推送)│ (FAN推送)│ (FAN+HTTP)  │
└──────────┴──────────┴──────────┴──────────┴──────────┴─────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │   QuakeProvider   │
                    │  (合并/过滤/排序)  │
                    └──────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │   EqlistPanel     │
                    │  (UI展示/交互)     │
                    └──────────────────┘
```

##### 数据源详情

| 文件 | 用途 | API地址 | 轮询间隔 | 数据格式 |
|------|------|---------|----------|----------|
| `eqlist_manager.dart` | 地震列表管理器，统一管理6个数据源的列表缓存，提供聚合访问接口和更新回调。每个数据源最多缓存50条记录。 | - | - | - |
| `jma_eqlist_service.dart` | JMA地震列表服务，通过P2PQuake API获取日本气象厅的地震目录。解析震度等级并转换为JMA震度格式（如"5-"、"6+"）。支持多种情报类型：震度速报、震源情报、震度・震源情报等。 | `api.p2pquake.net/v2/history` | 30秒 | P2PQuake JSON |
| `cenc_eqlist_service.dart` | CENC地震列表服务（备用），通过Wolfx代理API获取中国地震台网中心的地震目录。自动计算CSIS烈度，区分自动测定和正式测定。**主数据源已改为FAN WebSocket推送**（`cenclist` 订阅 + `initial_all`/`update` 实时推送）。 | `api.wolfx.jp/cenc_eqlist.json` | 120秒 | Wolfx JSON |
| `cwa_eqlist_service.dart` | CWA地震列表服务（备用），通过Exptech API获取台湾中央气象署的地震目录。自动转换CWA震度等级为JMA格式（0-9对应震度0-7），提取地点名称中的行政区划信息。**主数据源已改为FAN WebSocket推送**。 | `exptech.com.tw/api/v1/earthquake/report` | 90秒 | Exptech JSON |
| `usgs_eqlist_service.dart` | USGS地震列表服务，通过USGS GeoJSON API获取全球2.5级以上地震。自动计算CSIS烈度，根据 `status` 字段区分正式测定（reviewed）和自动测定（automatic）。时间自动转换为UTC+8。 | `earthquake.usgs.gov/.../2.5_week.geojson` | 60秒 | GeoJSON |

##### 数据流说明

1. **HTTP轮询**: JMA(30s)、CENC(120s备用)、USGS(60s)、CWA(90s备用) 通过定时器周期性发起HTTP请求
2. **FAN列表订阅**: FSSN 通过 `fssnlist` 指令获取初始列表，CWA 通过 `cwalist` 指令获取，CENC 通过 `cenclist` 指令获取
3. **FAN实时推送**: FSSN、KMA、CWA、CENC 数据通过 FanService 的 WebSocket 实时推送（`/fssn`、`/kma`、`/cwa`、`/cenc` 路径）
4. **列表更新**: 
   - HTTP轮询服务通过 `onListUpdated` 回调
   - FAN列表订阅通过 `onFssnListUpdated`、`onCwaListUpdated`、`onCencListUpdated` 回调
   - FAN实时推送通过 `_routeToBucket` 路由到对应列表
5. **缓存管理**: EqlistManager维护6个独立列表，每个列表最多保留50条记录
6. **UI刷新**: QuakeProvider监听 `onAnyUpdated` 回调，触发UI重建
7. **时间排序**: 所有数据源时间统一转换为UTC后排序，确保不同时区事件正确排序

##### 筛选功能

EqlistPanel提供两种筛选方式：
- **震级筛选**: 支持 M0.0 ~ M8.0+ 共14个档位
- **数据源筛选**: 支持 JMA/CENC/USGS/FSSN/KMA/CWA 六个数据源的独立开关

---

### 🛠️ 工具类 (utils/)

| 文件 | 用途 |
|------|------|
| `fe_regions.dart` | Flinn-Engdahl 区域数据库，根据经纬度查询地震位置的中文名称。 |

---

### 🎨 UI 组件 (widgets/)

#### 地图组件 (widgets/map/)

| 文件 | 用途 |
|------|------|
| `quake_map_view.dart` | 地震地图主视图，集成底图、NIED/KMA/S-net 图层、CENC 仪器烈度、地震波动画等。预警事件自动定位到震中。波传播图层支持用户位置传入用于显示 P/S 波到达进度。 |
| `compliance_map_view.dart` | 合规地图视图，用于显示符合中国法规的地图。 |
| `compliance_map.dart` | 合规地图组件封装。 |
| `map_config.dart` | 地图瓦片配置，定义各种地图瓦片源的 URL 模板。 |
| `map_sources.dart` | 中国地图数据源配置，定义天地图、高德地图等合规地图服务的 URL。 |
| `wave_layer.dart` | 地震波传播动画图层，显示 P 波(青色)和 S 波(径向渐变)的扩散动画。S 波支持 3 种颜色模式：alert(按警报级别)、magnitude(按震级大小)、intensity(按烈度颜色)。基于深度修正波速。支持用户位置 P/S 波到达进度环（弧线进度指示）。震中十字标记带发光效果，标签支持"已取消"/"假定震源"/"Mx.x" 显示。 |
| `nied_intensity_layer.dart` | NIED 震度图层，在地图上显示日本测站的实时震度。 |
| `kma_intensity_layer.dart` | KMA 震度图层，在地图上显示韩国测站的实时震度。 |
| `snet_layer.dart` | S-net 海底观测图层，显示海底测站的实时数据。 |
| `cenc_ir_layer.dart` | CENC 仪器烈度图层，显示中国地震台网中心的仪器烈度分布。 |
| `history_marker_layer.dart` | 历史地震标记图层，在地图上显示选中的历史地震位置。 |
| `vector_boundary_layer.dart` | 矢量边界图层，显示行政区划边界。 |
| `source_dashboard.dart` | 数据源仪表板，显示各数据源的连接状态。 |

#### UI 面板 (widgets/ui/)

| 文件 | 用途 |
|------|------|
| `alert_panel.dart` | 预警面板，显示当前活跃的地震预警信息。 |
| `alert_module.dart` | 预警模块组件，处理单个预警的显示和交互。EEW 顶栏颜色参考 kanameishi 的 `getBarClass` 逻辑（取消报=深灰、警报级=红色、普通=橙色）。信息事件支持震度(JMA/CWA)和烈度(CENC/USGS/FSSN)两种徽章显示模式，标题自动生成（如"中国地震台网正式测定"）。支持 20+ 数据源的标题和标签映射。 |
| `top_status_bar.dart` | 顶部状态栏，显示时间、连接状态、数据源状态等信息。 |
| `intensity_badge.dart` | 烈度徽章组件，显示烈度等级的彩色标签。 |
| `history_panel.dart` | 历史记录面板，显示历史地震列表。 |
| `eqlist_panel.dart` | 地震列表面板，显示各机构的地震目录。支持震级筛选(M0.0~M8.0+)和数据源筛选(JMA/CENC/USGS/FSSN/KMA/CWA)。每个地震卡片显示烈度徽章(JMA震度或CSIS烈度)、震级、深度、发震时间和数据源标签，点击可跳转到震中位置。 |

---

## 数据流架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        数据源层 (Sources)                         │
├─────────────┬─────────────┬─────────────┬─────────────┬─────────┤
│   Wolfx     │     FAN     │   P2PQuake  │    NIED     │   KMA   │
│  WebSocket  │    HTTP     │  WebSocket  │    HTTP     │   WS    │
└──────┬──────┴──────┬──────┴──────┬──────┴──────┬──────┴────┬────┘
       │             │             │             │           │
       └─────────────┴──────┬──────┴─────────────┴───────────┘
                            │
                            ▼
              ┌─────────────────────────┐
              │     SourceManager       │
              │   (统一事件分发)          │
              └───────────┬─────────────┘
                          │
                          ▼
              ┌─────────────────────────┐
              │     QuakeProvider       │
              │   (全局状态管理)          │
              └───────────┬─────────────┘
                          │
          ┌───────────────┼───────────────┐
          │               │               │
          ▼               ▼               ▼
    ┌──────────┐   ┌──────────┐   ┌──────────┐
    │ 地图视图  │   │ 预警面板  │   │ 历史面板  │
    └──────────┘   └──────────┘   └──────────┘
```

---

## 支持的数据源

| 数据源 | 类型 | 覆盖区域 | 数据内容 |
|--------|------|----------|----------|
| Wolfx | WebSocket | 全球 | JMA/CENC/CWA/SC/FJ/CQ 预警 |
| FanStudio | WebSocket | 全球 | JMA/CWA/CWA-EEW/CEA/CEA-PR/FSSN/KMA/KMA-EEW/HKO/SA/EMSC/BCSF/GFZ/USP/Ningxia/Guangxi/Shanxi/Beijing/Yunnan 等 19 种数据源 |
| P2PQuake | WebSocket | 日本 | 日本地震情报(551) |
| NIED | HTTP | 日本 | 实时震度数据 |
| KMA | WebSocket | 韩国 | 韩国震度数据(测站) |
| S-net | HTTP | 日本海域 | 海底观测数据 |
| CENC | HTTP/WS | 中国 | 地震目录(HTTP备用)、仪器烈度、地震预警 |
| CWA | HTTP/WS | 台湾 | 地震目录、地震报告 |
| JMA | HTTP/WS | 日本 | 地震目录(HTTP)、预警(WS) |
| USGS | HTTP/WS | 全球 | 地震目录(HTTP)、地震情报(FAN) |
| EMSC | FAN WS | 欧洲 | 地震信息 |
| BCSF | FAN WS | 法国 | 地震信息 |
| GFZ | FAN WS | 德国 | 地震信息 |
| USP | FAN WS | 巴西 | 地震信息 |
| HKO | FAN WS | 香港 | 地震信息 |
| ShakeAlert | FAN WS | 美国西海岸 | 地震预警 |
| 宁夏/广西/山西/北京/云南 | FAN WS | 各省 | 地震信息 |

---

## 烈度标准对照

| 等级 | JMA 震度 | MMI 烈度 | 中国烈度 |
|------|----------|----------|----------|
| 无感 | 0 | I-II | I-II |
| 微震 | 1 | III | III |
| 轻震 | 2-3 | IV-V | IV-V |
| 中震 | 4 | VI | VI-VII |
| 强震 | 5弱/5強 | VII-VIII | VIII |
| 烈震 | 6弱/6強 | IX-X | IX-X |
| 激震 | 7 | XI-XII | XI-XII |

---

## 技术栈

- **框架**: Flutter (跨平台)
- **地图**: flutter_map + Leaflet 风格瓦片
- **状态管理**: Provider
- **数据库**: SQLite (sqflite)
- **网络**: HTTP + WebSocket
- **语音**: flutter_tts

---

## 开发说明

1. **添加新数据源**: 继承 `BaseSourceService` 类，实现 `connect()` 和 `disconnect()` 方法。
2. **添加新图层**: 参考 `nied_intensity_layer.dart` 创建自定义图层组件。
3. **修改烈度配色**: 编辑 `intensity_theme.dart` 中的颜色定义。
4. **添加地图底图**: 在 `map_config.dart` 中添加新的瓦片 URL 模板。

---

*文档生成时间: 2026-05-04*
