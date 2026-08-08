# FlutterRhythmQuake 架构与项目总览

> 本文档基于 **2026-07-08** 对实际代码（`lib/`、`tools/`、`docs/`、`references/`）的核查整理，用于替代已过时的 `README.md`（仍为 Flutter 默认模板）与 `PROJECT_STRUCTURE.md`（未覆盖 `core/` 三大引擎与新增信源）。
>
> 适用读者：新接手开发者、需要理解整体架构者、想扩展数据源/图层者。

---

## 1. 项目定位

FlutterRhythmQuake 是一个**跨平台实时地震（及多灾种）监测与预警应用**，对标国产开源预警前端 **要石 kanameishi**（作者 Lipomoea，Vite+Vue3+Leaflet+Tauri，AGPL-3.0，GitHub: `Lipomoea/kanameishi`）。

> ⚠️ 勘误：早期文档称 kanameishi 为"日本知名预警前端"，实为**中国开发者 Lipomoea 的开源项目**（仅项目名/图标借用了日语《铃芽之旅》元素）。FlutterRhythmQuake 与 kanameishi 均为国产项目。

核心理念：**多信源实时聚合 → 震源/烈度估算 → 地图可视化 + 语音播报 + 桌面通知**。

从代码看，项目已从"纯地震预警"演进为**多灾种监测终端**：除地震 EEW 外，已包含火山（JMA 火山）、台风、中国气象预警、强震动（FDSN/Hinet）、本地晃动检测（shake detection）等模块。

### 快速事实

| 项 | 值 |
|----|----|
| 框架 | Flutter (Dart SDK `^3.11.0`) |
| 平台 | Windows / macOS / Linux / Android / iOS / Web |
| Dart 文件数 | `lib/` 共 **179** 个；`tools/` 共 **224** 个辅助工具 |
| 状态管理 | Provider（`QuakeProvider` + `MapStateProvider`） |
| 本地存储 | SQLite（`sqflite` / `sqflite_common_ffi`，桌面走 FFI） |
| 地图 | `flutter_map` + Leaflet 风格瓦片；中国区合规底图（天地图/高德） |
| 网络 | HTTP 轮询 + WebSocket 推送 |
| 语音 | `flutter_tts` |
| 桌面增强 | `window_manager` / `tray_manager` / `local_notifier` |
| 时间同步 | NTP（`ntp` 包）保证预警时间戳准确 |

---

## 2. 系统架构与数据流

```
┌──────────────────────────────────────────────────────────────────────┐
│                        数据源层 (services/sources)                      │
│  Wolfx(WS) │ FanStudio(WS) │ P2PQuake(WS) │ GlobalQuake │ NIED │ KMA │ │
│  S-net │ FDSN │ 列表服务(eqlist) │ 火山/台风/气象 │ shake detection      │
└───────────────┬──────────────────────────────────────────────────────┘
                │  BaseSourceService.emit(QuakeMessage / 领域事件)
                ▼
        ┌──────────────────────────┐
        │      SourceManager        │  统一注册、连接、事件分发
        └─────────────┬────────────┘
                      ▼
        ┌──────────────────────────┐
        │   EventBus + QuakeProvider│  全局状态、过期/静默策略、合并
        └─────────────┬────────────┘
                      ▼
   ┌──────────────┬───────────────┬────────────────┬──────────────┐
   ▼              ▼               ▼                ▼              ▼
 地图视图      预警面板         历史/列表面板      数据源仪表板    语音播报
 (widgets/    (widgets/ui/    (widgets/ui/      (widgets/      (tts_service)
  map/)        alert_*)        eqlist/history)   source_dashboard)
```

**关键抽象**：所有信源继承 `BaseSourceService`（`connect` / `disconnect` / `emit`），由 `SourceManager` 统一管理。`main.dart` 中显式注册：`WolfxService`、`FanService`、`P2PQuakeService`、`MockInputService`、`GlobalQuakeService`；其余服务（NIED 后台 worker、FDSN、shake detection、火山/台风/气象等）在 `SourceManager().startAll()` 或各自的 manager 中按需启动。

---

## 3. 目录结构（实际）

```
lib/
├── main.dart                         # 入口：初始化绑定、数据库、NTP、注册信源、MultiProvider
├── main_screen.dart                  # 主屏幕：整合地图/预警/历史/状态栏
├── core/                             # 算法与计算核心（非 UI）
│   ├── calculator.dart               # P/S 波速、震中距、到时估算
│   ├── intensity_calculator.dart     # 烈度估算（JMA/MMI/中国烈度）
│   ├── hypocenter_estimator.dart     # 震中估计
│   ├── travel_time_service.dart      # 走时表加载服务
│   ├── jma_grid_data.dart            # JMA 网格数据
│   ├── frame_rate_limiter.dart       # 渲染帧率限制
│   ├── event_animation_clock.dart    # 事件动画时钟
│   ├── nied_replay_logger.dart       # NIED 回放日志
│   ├── source_estimation/            # ★ 实时震源/烈度估计算法引擎（21 文件）
│   ├── event_detection/              # ★ 事件检测（4 文件）
│   ├── replay/                       # ★ 回放数据集与指标（16 文件）
│   └── utils/                        # 通用工具
├── models/                           # 数据模型（QuakeMessage、烈度主题、各机构模型）
├── providers/                        # QuakeProvider、MapStateProvider
├── services/                         # 服务层（含 sources/ 子目录）
│   ├── sources/                      # 40 个信源/服务文件 + eqlist/ 子目录
│   ├── database_helper.dart          # SQLite
│   ├── event_bus.dart                # 跨组件事件总线
│   ├── location_service.dart         # 用户位置（估算烈度/P-S 波到达）
│   ├── ntp_service.dart              # 网络时间同步
│   ├── tts_service.dart              # 语音合成
│   ├── boundary_service.dart         # GeoJSON/TopoJSON 行政区划边界
│   └── windows_manager.dart          # 桌面窗口管理
├── utils/                            # fe_regions（Flinn-Engdahl 中文地名）
├── widgets/
│   ├── map/                          # 地图视图与图层（33 文件）
│   └── ui/                           # 预警卡、状态栏、烈度徽章、历史/列表面板（14 文件）
└── screens/

tools/                                # 224 个数据/研究工具（Dart/Python/JS）
docs/                                 # 研究文档、交接单、基线报告
references/                           # リアルタイム地震ビューアー、地震模拟 等参考实现
temp_kanameishi/                      # kanameishi 的 Vue 参考组件（KmaNet/NiedNet 等）
```

---

## 4. 数据源层（`lib/services/sources/`）

按职责分组（共 40 个文件）：

### 4.1 核心预警推送
| 文件 | 职责 |
|------|------|
| `wolfx_service.dart` | Wolfx WebSocket，推送 JMA/CENC/CWA/SC 等预警 |
| `fan_service.dart` | FanStudio 聚合 WS，自动识别 19+ 数据源（JMA/CWA/CEA/KMA/HKO/EMSC/BCSF/GFZ/USP/各省台网…） |
| `p2pquake_service.dart` | 日本 P2PQuake 情报网络 |
| `global_quake_service.dart` (+ `_io`/`_stub`) | 可配置服务器（GlobalQuake）接入，支持主备 host/port |
| `mock_input_service.dart` | 手动注入地震数据，用于测试 |

### 4.2 日本震度 / 监测
`nied_monitor` / `nied_gif_observation` / `nied_gif_value_decoder` / `nied_station_observation_adapter` / `nied_source_estimation_driver` / `nied_background_worker` / `kma_monitor` / `snet_service` / `seisjs_service` / `kmoni_webview_bridge` / `lmoni_image_service` / `lpgm_monitor_service` / `nied_yahoo_service` / `cwa_station_service`

### 4.3 地震列表服务（`eqlist/` 子目录 + 顶层）
`jma_eqlist_service` / `cenc_eqlist_service` / `cwa_eqlist_service` / `usgs_eqlist_service` / `emsc_eqlist_service` + `eqlist_manager`（统一聚合 6 个机构目录，每源最多缓存 50 条）。

### 4.4 多灾种（火山 / 台风 / 气象 / 烈度标度）
`jma_volcano_service` / `jma_volcano_map_service` / `typhoon_service` / `china_weather_alert_service` / `jp_shindo_scale` / `shindo_color_util`

### 4.5 强震 / 运动学 / 本地检测
`fdsn_motion_service` (+ `_io`/`_stub`) / `fdsn_station_service` / `shake_detection_service`

### 4.6 基础设施
`base_source.dart`（抽象基类）、`source_manager.dart`（统一注册/分发）

> 列表/预警经 `EqlistManager` → `QuakeProvider` → UI 面板；支持震级(M0.0~M8.0+)与数据源筛选。

---

## 5. 三大算法引擎（`lib/core/`）

这是项目**技术含量最高、文档从未描述**的部分，也是近期开发重心。

### 5.1 实时震源/烈度估计 — `core/source_estimation/`（21 文件）
从台站观测实时反演震中位置与烈度，参考 kotoho7 / kanameishi 的算法体系：
- `jma2001_travel_time_approximation.dart`：JMA2001 走时表近似（1704 系数、71 深度分箱）。
- `kotoho7_js_eew_bridge*` / `kotoho7_js_receiver_bridge*`：通过 `node` 进程桥接 kotoho7 的 JS 实现（圆触发 `circleTrigger`、接收器逻辑），带 `_io`/`_stub` 条件导入。
- `source_estimator.dart` / `seismic_source_tracker.dart` / `source_candidate_region_tracker.dart`：震源估计与候选区追踪。
- `source_station_phase_classifier.dart` / `source_trigger_continuity_gate.dart`：台站相位分类与触发连续性门控。
- `source_estimate_quality.dart` / `static_intensity_attenuation.dart`：估计质量评估、静态烈度衰减。
- `station_event_tracker.dart` / `station_observation_history.dart`：台站事件与观测历史。
- 配套 `docs/source_estimation_*.md`：**PLUM 证据稳健性校准**（非抑制型，含 `branchAgreement × robustnessScore` 联合校准、confidence band、预注册验收标准 F1-F4 / C1-C4）。

### 5.2 事件检测 — `core/event_detection/`（4 文件）
- `robust_station_trigger_detector.dart`：稳健单台触发检测。
- `spatiotemporal_event_detector.dart`：时空联合事件判定。
- `legacy_shake_event_detector_adapter.dart`：旧 shake 检测器适配层。
- `event_detection_models.dart`：检测模型定义。

### 5.3 回放系统 — `core/replay/`（16 文件）
用于算法验证与演示：
- `jma_catalog.dart` / `jma_hypocenter_record.dart` / `jma_intensity_archive.dart` / `jma_intensity_dataset.dart`：JMA 目录/震中/烈度数据集。
- `knet_waveform_archive.dart` / `knet_waveform_event_manifest.dart` / `knet_waveform_features.dart` / `knet_gif_domain_alignment.dart`：K-NET 波形归档与特征。
- `nied_gif_observation_export.dart` / `synthetic_reveal_dataset.dart`：NIED 导出 / 合成揭示数据集。
- `replay_dataset.dart` / `replay_package.dart` / `replay_metrics.dart` / `replay_versions.dart`：回放数据包与指标（schema 见 `docs/replay_package_schema.md`）。
- `waveform_projected_gif.dart` / `_baseline.dart`：波形投影 GIF 生成。

---

## 6. 地图与可视化（`lib/widgets/map/`，33 文件）

- `quake_map_view.dart`：主视图，集成底图、NIED/KMA/S-net 图层、CENC 仪器烈度、地震波动画；预警自动定位震中。
- `wave_layer.dart`：P 波(青)/S 波扩散动画，支持按警报级/震级/烈度三色模式，含用户位置 P-S 波到达进度环。
- `nied_intensity_layer` / `kma_intensity_layer` / `snet_layer` / `cenc_ir_layer`：各机构实时震度图层。
- `vector_boundary_layer.dart`：行政区划边界。
- `history_marker_layer.dart`：历史地震标记。
- `compliance_map_view.dart` / `compliance_map.dart` / `map_sources.dart`：**中国合规地图**（天地图/高德底图）。
- `map_config.dart`：瓦片 URL 模板配置。
- `source_dashboard.dart`：数据源连接状态仪表板。

---

## 7. 状态管理与 UI（`providers/` + `widgets/ui/`）

- `QuakeProvider`：管理预警事件列表、历史、活跃预警、数据源状态；EEW 统一处理取消报（20s 短计时）、同事件多次更新；过期策略参考 kanameishi（警报级 `max(震级,6)*60`s，普通 `max(震级,3)*60`s）。
- `MapStateProvider`：地图中心/缩放/动画/选中历史事件。
- UI 组件：`alert_panel` / `alert_module`（EEW 顶栏配色参考 kanameishi `getBarClass`：取消报=深灰、警报级=红、普通=橙）/ `top_status_bar` / `intensity_badge` / `history_panel` / `eqlist_panel`。

---

## 8. 工具链（`tools/`，224 文件）

研究与数据管道工具集，Dart 为主，含 Python/JS 辅助：
- **PLUM 报告**：`build_plum_*.dart`（证据稳健性、confidence band 冻结评估、验收报告）。
- **Hi-net / K-NET**：`build_hinet_*.dart`、`build_knet_*.dart`（捕获、修订、对齐、质量审核）。
- **JMA 目录/烈度**：`build_jma_*.dart`（可用性、最终目录、烈度数据集、预训练）。
- **kotoho7 真值**：`build_kotoho7_*.dart`（raw id 诊断、真值分探测、成员重注册）。
- **辅助脚本**：`_check_topo.py`、`_generate_calibration.py`、`_extract_*.js` 等。

---

## 9. 文档与研究（`docs/`）

含 `source_estimation_research.md`、`source_estimation_roadmap.md`（超 5000 行，持续记录 PLUM 诊断）、`event_detection_research.md`、`replay_package_schema.md`、`jma_catalog_schema.md`、`fdsn_seedlink_relay.md`、`nied_relay_setup.md`、多份 `handover_*` 交接单、以及 `baselines/` 自动生成报告。

---

## 10. 当前状态、债务与建议

### 已完成
- 多信源实时预警与地图可视化主链路完整可用。
- 三大算法引擎（震源估计 / 事件检测 / 回放）已具规模，并配预注册验收流程。
- 多灾种（火山/台风/气象/强震）模块已落地。

### 文档债务（建议优先处理）
1. **`README.md` 是 Flutter 默认模板**，应替换为真实项目描述、运行方式、支持数据源。
2. **`PROJECT_STRUCTURE.md` 已过时**，未含 `core/` 三大引擎与 40 个信源文件；本文档可作为其替代/补充。
3. `REFACTOR_TASKS.md` 提出的 **"统一 `UnifiedQuakeData` 模型"** 重构（三套管道 → 单入口 `setEqMessage()`，UI 不再 `switch(source)`）仍是未完成的主线，建议作为下一阶段规划。

### 工程注意
- Git 历史仅有 2 次提交（Initial + Publish），大量工作可能未进版本库，**注意备份** `lib/`、`tools/`、`docs/`。
- Windows 端对无障碍语义做了屏蔽（`_disableWindowsAccessibilitySemantics`），排查渲染问题时需注意。
- 桌面端 SQLite 走系统 `winsqlite3`（见 `pubspec.yaml` hooks），避免构建期从 GitHub 下载预编译二进制。

---

*文档生成时间：2026-07-08 ｜ 基于代码核查，非文档推测。*
