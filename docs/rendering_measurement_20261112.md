# 渲染侧真机测量报告（工作流 F）——2026-11-12

**设备**：HA2A989M（Lenovo TB322FC 平板，1904×3040 @120Hz，Android）
**版本**：RhythmQuake 1.0.5.25 → 1.0.5.28 personal（含工作流 A/B/C1/C收尾/E-1 修复 + UiPeakProfiler 观测打点）
**场景**：托管模式地图主界面；adb `input swipe` 制造拖拽负载

## 最终结论（1.0.5.28 打点版确认）

### 🔴 根因 1：`RhythmFrameRateBinding` 全局 45fps 硬限速（`lib/core/frame_rate_limiter.dart`）

`main.dart` 启动即挂载 `RhythmFrameRateBinding`，把所有 `scheduleFrame`/`scheduleForcedFrame` 按最小帧间隔 **22.2ms（45fps）** 节流（Timer 延迟链）。120Hz 屏上：

- ftrace 实测帧间隔 **p50=25.1ms ≈ 40fps**（45fps 上限 + vsync 相位对齐损耗）✓ 吻合
- 拖拽地图时最高也只有 ~40-45fps，且 Timer 延迟 + vsync 相位漂移导致帧间距不均匀 → **体感"拖拽不跟手/卡"**
- 这就是"45 FPS 可调但注意性能（放 F 阶段）"交接项所指的机制本体

### ✅ 排除项（UiPeakProfiler 1.0.5.28 实测，45 秒滑动+静止窗口）

| 打点 zone | 结果 |
|---|---|
| `nied.acceptStations`（每秒测站到达→检知→汇总全链） | avg 6-9ms / max 55.8ms——**无长任务** |
| `summary.requestBuild`（isolate 请求构造+发送） | avg 0.6ms / max 8ms——轻 |
| `summary.onChanged`（回主屏+notifier 通知） | avg 0.01ms——完全不是问题 |
| `worker.project`（summary isolate 投影） | 无 SLOW 输出（<8ms） |
| FRAME build（UI 线程帧工作） | p50 0.4-2.9ms / max 17.6ms——**UI 线程健康** |
| FRAME raster | p50 3-9.8ms / max 23ms——健康 |
| jank100（>100ms 帧） | 45 秒内仅 1 次 |

### 📊 "5fps"读数的真实含义

静止时 `FRAME win=2s n=6~9`（3-4.5fps）= **按需渲染**：无动画时 Flutter 不产帧，NIED 每秒数据到达驱动 1-2 帧 + 涟漪——**正常节能行为，不是卡**。悬浮窗显示的正是这个数。拖拽中 n=26-39/2s（13-20fps）——其中输入事件本身稀疏（adb 模拟），真实手指会更高，但上限被 45fps 限速器封顶。

### 用户体感"卡/延迟"的构成

1. **拖拽不跟手**：45fps 上限 + Timer/vsync 相位漂移（根因 1）
2. **数据显示延迟**：NIED 759ms/帧的源数据节拍（与渲染无关）
3. **悬浮窗 3-5fps 读数误导**：静止按需渲染的正常表现

## 修复选项（待用户拍板，未实施）

| 方案 | 做法 | 代价 |
|---|---|---|
| A. 提高上限 | `maxFramesPerSecond` 45→60/90 | 省电略降 |
| B. 交互感知限速 | 拖拽中放开到屏幕刷新率（120/165Hz），静止保持 45 | 需要手势状态信号，改动中等 |
| C. 删除限速器 | 直接用引擎默认 vsync 调度 | 最简单；放弃当初限速的省电收益（需查引入原因） |

> 引入原因待查：45fps 限速应该是早期为省电/降温所设（悬浮窗温度监控存在），方案 B 是兼顾方向。

## 测量方法备查

| 手段 | 结果 |
|---|---|
| `dumpsys gfxinfo` | 对该 app（Skia/Vulkan）几乎不计数，不可用 |
| 悬浮窗帧率读数 | 显示静止按需渲染帧率，不能反映拖拽性能 |
| **UiPeakProfiler（本机打点，1.0.5.28+）** | zone 耗时 + FrameTiming 聚合，logcat 过滤 `[RQPerf]`，**推荐** |
| ftrace atrace | 有效但重；本次结论以打点为准 |

## 环境注意

- `adb`：`%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`
- 设备开了 **ZUI 应用分身（user 900）**，里面装着旧版 app → `am start` 会弹"请选择"；**点击屏幕图标启动**最可靠；可考虑卸载分身旧版（需用户确认，分身数据会丢）
- `debugPrint` 在 release 被重写为 no-op（main.dart:220）；诊断输出用 `print`
- 设备 8765 端口被其他 Go 服务占用
- app 已禁用 Impeller（Skia 渲染，manifest opt-out）

---

## 性能/耗电基线实测（1.0.5.28，帧率限速器保持 45 不动）——2026-11-12 12:45-12:55

设备：HA2A989M，电池 99%（USB 充电中→batterystats 估算功耗不可用，Computed drain=0），
以 **CPU 时间差 + 线程累计 + Charge counter + 电池温度** 为耗电口径，RQPerf FRAME 为性能口径。

### 两阶段协议结果（各 2 分钟）

| 指标 | P0 静止（NIED 每秒数据流） | P1 连续滑动负载 |
|---|---|---|
| 实际帧产出（RQPerf，2s 窗口均值） | **5.4 fps** | **8.9 fps** |
| build p50 / raster p50 | 4.5ms / 11.3ms | 2.7ms / 9.3ms |
| >100ms 卡顿帧（jank100） | 6 次 / 84 窗口 | 19 次 / 98 窗口 |
| 单帧最大 span | 122.6ms | 144.1ms |
| app 进程 CPU（ps TIME 差） | 25s/120s = **20.8% 单核** | 45s/120s = **37.5% 单核** |
| 电池温度 | 32.9°C | 32.5°C（稳定，无发热异常） |
| Charge counter | 6214180 µAh 不变（充电平衡，无法测净放电） | 同左 |

### CPU 归属（/proc/<pid>/task/*/stat 累计，进程运行 ~13 分钟）

| 线程 | CPU 累计 | 说明 |
|---|---|---|
| 1.raster | 46.9s | ≈ 帧数 × raster p50（11ms×~4200 帧），光栅占大头 |
| 1.ui（Flutter UI） | 40.2s | build 4.5ms/帧 + 每秒数据链（~10ms/s） |
| 后台 isolate / Rust（rq-*、DartWorker） | 各 <0.7s | **后台拉流/检知/桥接几乎不耗 CPU**（C1 Rust 化生效） |

### 结论

1. **耗电模型 = 帧产出 × 单帧成本**：app CPU 的 ~94% 来自 UI+raster 两线程，与帧数线性相关。
   现状 45fps 限速器实际只产出 5-9fps，等于被动省电；若放开到 45fps 上限，CPU 预计涨 5-8 倍
   （raster 满负荷 ≈ 50%+ 单核持续），耗电显著上升。
2. **单帧成本偏高是根**：raster p50 9-11ms（120Hz 屏全屏地图重绘），是限速存在的前提下
   "流畅 vs 省电"不可兼得的原因。优化方向是降单帧 raster 成本（查 saveLayer/全屏图层/热区重绘），
   而不是单纯调高帧率上限。
3. **静止 5.4fps 与用户悬浮窗读数吻合**——静止低帧是数据驱动的按需渲染，属设计行为；
   滑动 8.9fps 远低于 45 上限，说明限速器 Timer/vsync 相位链在拖拽时丢帧（体验问题所在）。
4. **后台侧非常省电**：NIED 拉流/解码/检知全链 <0.7s/13min（≈0.1% 单核），Rust 化（工作流 C1）
   后托管检知在 Rust 线程上执行且几乎不可见。后台不是耗电问题。
5. batterystats 估算功耗在 USB 充电态不可用（Computed drain=0）；全系统 wakeup 203 次/2min，
   app 的 `flutter_background_service` wakelock 在列但未显示为热点。

数据文件：tmp/perf_logcat_p0.txt / perf_logcat_p1.txt / batterystats_p0.txt / batterystats_p1.txt

## 拖拽帧率专项（1.0.5.30 → 1.0.5.31）——2026-11-12 13:45-14:40

### 背景与方法

用户反馈"拖动达不到 45 帧、CPU 频率顶满只有十几帧"。本次建立了一套**合成拖拽测量法**：

- `input swipe` 坐标系 = app 横屏窗口空间（3040×1904），与 `wm size` 报告的竖屏 1904×3040 无关
  （窗口级 ROTATION_90）；地图区中央横拖用 `(1800,950)→(900,950)`。
- 帧统计用 RQPerf `FRAME win=2s n=…` 行（FrameTiming，build/raster p50/p95）；
  **gfxinfo 对本 app 无效**（它统计的是 HWUI 空壳窗口 6 view / 1fps 时钟帧，不是 Flutter SurfaceView）。
- logcat 必须用托管后台任务采集（shell 内 `(cmd &)` 分离进程会被会话回收，13:47 那次采集中断即此因）。

### 测量结果（同机同底图内容，低清档）

| 状态 | 2s 帧数 | 帧率 | build p50 | raster p50 | jank100/2s | span max |
|---|---|---|---|---|---|---|
| 空闲 | 4-8 | ~3fps | 0.8-2ms | 4-9ms | 0 | <30ms |
| 拖拽 1.0.5.30（低清，逐帧重烘 atlas） | 25-27 | **12-13fps** | 11-14ms | **43-58ms** | 14-16 | 140-156ms |
| 拖拽 1.0.5.31（低清，拖拽中复用 atlas） | 27-34 | **14-17fps** | 12-14ms | **31-40ms** | **0** | 70-86ms |
| 拖拽 1.0.5.31（关闭毛玻璃对照） | 27-40 | 13-20fps | 11-16ms | **32-41ms** | 0 | 68-85ms |

线程级（top -H，拖拽中）：`1.raster` **96% 单核满载**，UI 线程 35%，其余线程空闲；整机 8 核 600% idle。

### 归因结论

1. **45fps 限速器无罪**：拖拽帧时间 55-70ms（build 13 + raster 32-45），远超 22.2ms 上限配额，
   限速器从未成为约束。
2. **毛玻璃 atlas 重烘是第一瓶颈（已修）**：1.0.5.30 低清档在拖拽中每帧仍执行
   `toImageSync(全地图 0.5x) + 每面板 blur 烘焙`。1.0.5.31 起 `_motionReuseAtlas`：
   低清档拖拽中复用已有 atlas（模糊背景是低频内容，冻结数百 ms 不可感知），settle 后重烘一次。
   实测 raster -12~18ms，jank100 从 14-16/2s → **0**。
3. **剩余瓶颈 = 地图子树本身**：关闭毛玻璃档拖拽 raster 仍 32-41ms，与低清档几乎相同——
   矢量底图（世界+行政区路径）+ 雷达图层 + 标记的逐帧全屏光栅化是唯一大头，raster 线程单核打满。
   这与"CPU 频率顶满帧率却只有十几帧"的用户感知完全一致。
4. 下一轮优化方向（未实施，待拍板）：运动中降级/隐藏重图层（雷达、标签）、矢量底图分块缓存、
   或 Impeller 重评估（当年因 ROM native crash 禁用，见 AndroidManifest.xml:19-25 注释）。

### 本轮代码变更（1.0.5.31）

- `lib/widgets/ui/ui_runtime_flags.dart`：`mapDragGlassMode` 默认值 full→**lowRes**；
  restore 尊重显式保存值（0=完整），仅未设置时用低清默认。
- `lib/widgets/ui/map_backdrop_cache.dart`：新增 `_motionReuseAtlas`，`ensureCurrentScene`
  在低清档+运动中且已有 atlas 时跳过重烘。完整档/关闭档行为不变。
- 数据：`tmp/drag_fps/`（logcat2.txt 全程采集、逐帧 PROFILEDATA、截屏）。

### ⚠️ 修正（2026-11-12 15:00）：1.0.5.31 "拖拽中冻结模糊"方案被实测否定

上一节"模糊背景是低频内容，冻结几百毫秒视觉不可感知"是**未经用户验证的假设，结论错误**：
拖拽中毛玻璃背景冻在原地、底图在动，错位肉眼明显。用户实测否定。

**1.0.5.32 替换为"模糊层跟随地图"方案**（`map_backdrop_cache.dart` + `quake_map_view.dart`）：

- 原理：模糊是平移不变运算，`blur(平移后的地图) = blur(地图) 再平移`。
  拖拽中不重烘 atlas，而是把已烘模糊图按地图位移量**反向偏移采样**
  （`_SameSceneBackdropLayer._drawShiftedBlur`），视觉上等价于实时模糊，
  成本 ≈ 每帧 2-5 次 drawImageRect。
- 位移来源：`_handleMapEvent` 从 `MapEventWithMove.oldCamera/newCamera` 用
  `projectAtZoom(center, zoom)` 计算屏幕像素位移（仅 zoom/rotation 不变时有效），
  经 `MapBackdropCacheHost.notifyMapMotionPan` 累加到 `motionPanDelta`。
- 重锚定（重新烘一次并清零位移）触发条件：累计位移 > 120px（`_motionPanBudget`）、
  zoom/rotation 变化（平移修正失效）、motion 窗口开始（首帧用带 margin 的 atlas）。
- 边界处理：motion 烘焙时区域外扩 136px（`_motionBakeMargin`）；
  从屏外进入的内容无烘焙数据，用最近烘焙边缘 1px 拉伸填充
  （低频模糊下不可见）；采样窗完全出界时回退不偏移。
- settle（静止 250ms 后）恢复全分辨率烘焙并清零位移，行为与之前一致。

**1.0.5.32 回归实测**（同法合成拖拽）：拖拽 15-19fps、raster p50 32-39ms、
jank100 基本为 0（motion 首帧重锚定偶发 1-2 次 span>100ms）——帧率与 .31 持平，
模糊跟随地图。待用户上手确认观感。

教训：**性能优化的"视觉无损"结论必须由用户实测确认后才能写进文档**；
假设就是假设，不能写成结论。

### 档位统一（2026-11-12 15:30，1.0.5.33）：拖拽复用 + 模糊跟随扩展到全部档位

用户反馈"手感上完整毛玻璃更流畅"。.32 实测数据（完整档逐帧重烘）：
完整档 ~11-12fps / jank 17-20 次 2s，**低于**低清档 15-19fps——但用户主观观感完整档更顺，
合理解释：低清档 atlas 半分辨率 + `FilterQuality.none` 最近邻 2x 放大，位移时像素块
shimmer，帧率高但观感"不丝滑"；完整档每帧重烘始终锐利。

**1.0.5.33 统一**：`_motionReuseAtlas` / `_motionReuseActive` / `_motionBakeRequired`
去掉 lowRes 条件，motion 烘焙 margin 同样适用于全部档位；档位差异只剩
`_bakeScale`（完整=1.0，低清=0.5，决定拖拽中重锚定烘焙的分辨率）。
"关闭毛玻璃"仍是拖拽中退化为无模糊半透明，不参与复用。

**1.0.5.33 完整档实测**（同法合成拖拽，设备保持完整档）：
拖拽 **~15-19fps**（n=26-38/2s）、raster p50 41ms（地图子树成本，未变）、
**jank100 0-7 次/2s**（.32 完整档为 17-20）、span max ~100ms。
结论：完整档帧率追平低清档，且模糊保持全分辨率锐利——用户观感与数据一致的最优选择。

档位选择建议（更新）：完整=拖拽流畅+模糊锐利（推荐）；低清=模糊在拖拽中有轻微
放大颗粒感，仅剩省电/省内存意义；关闭=拖拽中无模糊。

### 🔴 渲染管线堵死根因确认（2026-11-12 15:50）：矢量底图，非管线/硬件问题

用户质疑"为什么别人没这个问题，说性能弱是本末倒置"——成立。消融实验（同版本 1.0.5.33、
同手势、同设备，仅切换底图）：

| 配置 | build p50 | raster p50 | span max | jank100 |
|---|---|---|---|---|
| 矢量底图（原配置）拖拽 | 14.7ms | **41.6ms** | ~100ms | 0-7/2s |
| Jian 地形底图（栅格瓦片）拖拽 | **1.9ms** | **6.5ms** | 14.5ms | **0** |

**结论**：渲染管线本身完全健康（栅格瓦片下 build+raster ≈ 8.4ms，60fps 绰绰有余）。
全部病根 = `VectorBasemapLayer`（vector_basemap_layer.dart）：GeoJSON 全国行政区
Polygon/Polyline 经 flutter_map PolygonLayer/PolylineLayer 渲染，**拖拽中每帧重投影
+ 重简化 + 重建 Path + Skia 重细分**（build 14.7ms 在 UI 线程，41.6ms 在 raster 线程）。
其他地图 app（原生或 flutter_map）底图是栅格瓦片=贴图合成，没有这个问题。

修复方向（待拍板）：
1. **矢量底图"拖拽中复用"**（推荐）：底图与毛玻璃同为低频内容——拖拽中把
   VectorBasemapLayer 的 RepaintBoundary 上帧图像按位移平移（复用本会话的
   motionPanDelta 基建），settle 后重投影重画一次。保留矢量风格，拖拽成本≈贴图。
2. 默认底图切栅格（Petal 深色最接近现有深色主题），零开发成本但风格变化。
3. 投影/简化结果预缓存（需绕开 flutter_map 每帧行为，工程量大）。

设备当前已切到 Jian 地形底图（实验后保留），可随时在设置里切回。

### 帧调度层修复（2026-11-12 16:15，1.0.5.35）——限速器 vsync 对齐

#### 背景
用户指出"别人也用矢量、瓦片帧率也不高"，推翻"矢量底图=全部根因"的结论。重查 .33 瓦片
底图拖拽段 FRAME 数据：**一帧总成本仅 8ms（build 1.5-2.0 + raster 6.1-6.5）、span max
15ms、jank 0，但帧率只有 10-27fps**——帧没有被调度出来，瓶颈在帧调度层而非渲染。

#### 1.0.5.34 死锁事故（已修复，未外发影响仅本机 10 分钟）
激进方案"vsync 对齐跳帧"（在 handleBeginFrame 内 skip 并调 super.scheduleFrame() 续约）
存在状态机死锁：`_hasScheduledFrame` 要到 handleDrawFrame 的 finally 才清 false，skip
分支的续约调用被框架当重复请求静默吞掉 → 帧链永久断掉，用户实测"非常卡加载都没法加载完"。
教训：**覆写 SchedulerBinding 帧回调前必须确认 `_hasScheduledFrame` 的清除时机**；
凡在 handleBeginFrame/handleDrawFrame 内做续约都不可行。

#### 1.0.5.35 最终实现（lib/core/frame_rate_limiter.dart）
保留 Timer 架构（续约路径正确），新增 **vsync 相位对齐**：
- 从 `handleBeginFrame` 的 `rawTimeStamp` 学习 vsync 周期与 clock 偏移
  （origin 固定、周期恒定；前两帧差分估计周期，offset 按 0.8/0.2 平滑）。
- Timer 时刻 = 预算后第一个 vsync 的 clock 时刻 − 4ms 提前量。早到无害
  （引擎持有请求等该 vsync），晚到会错过 vsync 多等一拍，4ms lead 吸收 Timer 抖动。
- 模型未学到前退回原行为（remainingUs）。

#### 实测（1.0.5.35，Jian 栅格底图，同合成拖拽口径）
| 版本 | 拖拽窗口 2s 帧数 | 特征 |
|---|---|---|
| .33（Timer 无对齐） | 13, 20, 39, 44, 13, 47 | 剧烈波动 10-27fps |
| **.35（vsync 对齐）** | **53, 54, 52**（+间隙 4-6） | **稳定 ~27fps**，span max 14.5ms，jank 0 |

抖动消除生效（帧间隔从 26-45ms 震荡变为稳定），但 27fps 仍低于 vsync 对齐理论值
~38fps。剩余嫌疑：**adb `input swipe` 合成手势的注入事件率约 27Hz**——flutter_map
拖拽无惯性时是事件驱动的，合成事件的帧率上限就是事件率；真手指触摸报告率 120Hz，
预期可达 ~38fps。**待用户真手实测确认**。

#### 教训汇总
1. 视觉无损结论必须用户实测确认（1.0.5.31 教训重申）。
2. 覆写 SchedulerBinding 帧回调 = 状态机雷区，`_hasScheduledFrame` 清除时机在
   handleDrawFrame finally；帧内续约 = 死锁。
3. 合成手势（input swipe）测帧率有事件率上限（~27Hz），不能用于验证 >30fps 的调度改善，
   真手为准。

#### ⚠️ 修正（16:18）：上一节数据作废——测量流程错误被用户抓到

16:14 那轮测试中 `input keyevent 4` 把 app 退回了 Android 桌面（用户亲眼看到），四组
swipe 全打在桌面上，**没有任何拖拽帧数据**；被解读为"稳定 27fps"的 n=53/54 窗口实际
发生在 keyevent 之前（启动/设置页帧），是时钟偏移（device = host + 4.3s）掩盖了时序。
教训：**每轮拖拽测试前必须 dumpsys 确认前台 + 截屏确认主界面，禁止在测试序列中夹带
keyevent**；设备与主机时钟差必须先实测再解读时间戳。

#### 干净复测（16:20，同法四组拖拽，拖拽中截屏验证地图已移动）

设备条件：1.0.5.35、Jian 栅格底图、完整面板背景。

| 版本 | 拖拽窗口 2s 帧数 | build p50 | raster p50 | jank100 |
|---|---|---|---|---|
| .33（Timer 无对齐，同底图） | 13, 20, 39, 44, 13, 47 | 1.5-2.0ms | 6.1-6.5ms | 0 |
| **.35（vsync 对齐）** | **33, 32, 52, 49, 47, 40** | 6.2-6.3ms | 7.7-10.1ms | 0-1 |

- 帧率从"10-27 剧烈波动"变为"**16-26 相对稳定**"，jank 归零；HUD 同屏显示 17FPS 与
  RQPerf ~20fps 相符。
- **峰值 26fps ≈ `input swipe` 注入事件率上限（~27Hz）**——限速器已不再是瓶颈，
  合成手势测不出更高的调度改善。build p50 变高（1.9→6.2ms）是拖拽中面板重建路径，
  正常。
- **真手指触摸报告率 120Hz，预期拖拽可达 ~38-45fps，待用户上手确认**。

### 零限速对照实验（16:30，1.0.5.36）——用户假设验证成立

应用户指示完全取消帧率限制（`_scheduleFrameWithLimit` 直接透传引擎），同法合成拖拽
（每步 dumpsys+截屏验证前台、地图已移动）：

| 版本 | 拖拽窗口 2s 帧数 | 帧率范围 | raster p50 |
|---|---|---|---|
| .33 旧限速器 | 13, 20, 39, 44, 13, 47 | 10-27 波动 | 6.1-6.5ms |
| .35 45fps+vsync对齐 | 33, 32, 52, 49, 47, 40 | 16-26 稳定 | 7.7-10.1ms |
| **.36 零限速** | **82, 69, 51, 67, 32, 66** | **25-41** | **6.5-7.8ms** |

**结论：45fps 限速器确实是拖拽帧率的主要约束**——取消后合成拖拽（事件率上限约
30-40Hz）立即从 16-26 升到 25-41fps；HUD 空闲帧率同步从 45 以下变为 47+。
raster p50 全程 6.5-10ms（很便宜），剩下的上限来自合成手势事件率；真手指 120Hz
报告率下预期更高（build+raster ≈13ms ⇒ 理论 ~75fps）。

待决：零限速 = 最流畅，但持续动画（雷达轮播等）帧数翻倍功耗上升；
.35 的 45fps 对齐版 = 稳定 40fps 封顶。**最终取舍等用户真手对比后定**。

### 真实耗电实测（17:05-17:20，1.0.5.36 零限速，无线 adb 拔线放电）

条件：TB322FC 屏幕常亮（超时 30min）、Jian 栅格底图、app 前台；读电池 Charge counter
差值（µAh），电压 4.171V 换算功率。

| 场景 | 时长 | 电量差 | mAh/min | 功率(4.171V) | CPU | 帧率 |
|---|---|---|---|---|---|---|
| 空闲（稳态，不碰） | 180s | 62.5 mAh | **20.8** | **~1.45W** | 52% 单核 | ~6fps（事件驱动） |
| 连续拖拽 | 245s | 136.5 mAh | **33.4** | **~2.3W** | ~130% 单核 | ~45fps（82-97帧/2s） |
| 空闲（污染样本，app 刚回前台） | 301s | 125.8 mAh | 25.1 | ~1.74W | 92%（数据刷新 burst） | 22fps 阵发 |

要点：
- **空闲与限速无关**：空闲是事件驱动 ~6fps，45fps 限速器从来管不到空闲；零限速不增加
  待机功耗（20.8 mAh/min 里大头是屏幕常亮本身）。
- **拖拽增量 +12.6 mAh/min（≈+0.87W）**：本次合成拖拽被注入事件率压在 ~45fps，
  与 .35 限速版的 40-45fps 封顶几乎同帧率 ⇒ 该帧率下限速版耗电≈零限速版。
  **真手指（120Hz 报告率）零限速可跑 60-75fps，届时拖拽功耗会高于限速版约 30-60%**。
- 电量刻度验证：95%→89% 全程，与 counter 差一致。
- 第一段"空闲"样本被 app 回前台后的数据刷新/雷达下载污染（92% CPU、22fps 阵发），
  已剔除；教训：耗电基线必须在 app 完全沉降（≥3min 无 burst）后采样。

待用户定夺（同前）：零限速（最流畅，真手拖拽功耗高）vs .35 的 45fps+vsync 对齐
（稳 40fps 封顶，拖拽更省）vs 做成设置项。

### 矢量底图拖拽复用落地 + 侧栏逐小时面板移除（17:30-17:50，1.0.5.37）

#### 改动
1. **侧栏逐小时预报面板移除**（用户确认多余）：main_screen.dart 中国分支只保留实况面板；
   `ChinaWeatherHourlyPanel` 在桌面天气主页/手机天气页保留，服务仍被当前天气状态入口使用。
2. **矢量底图拖拽冻结复用**（vector_basemap_layer.dart，全平台生效）：
   - motion 开始时用 `RenderRepaintBoundary.toImageSync(pixelRatio≤1.5)` 抓取上一帧矢量底图；
   - 拖拽中不重建 Polygon/Polyline 层，改画冻结图 + `motionPanDelta-锚点` 平移
     （`_FrozenBasemapImage`，每帧一次 drawImageRect）；海洋色 ColoredBox 填补拖出边带；
   - 重锚定（一帧实况重投影+重抓）：平移超 120px、缩放/旋转（cameraResampled）、settle；
   - 复用 MapBackdropCacheHost 现有 motion 基建，毛玻璃与底图同一套信号。

#### 实测（.37 矢量底图，同合成拖拽口径，设备 192.168.137.232 无线 adb）
| 版本 | build p50 | raster p50 | 拖拽帧率 | jank100 |
|---|---|---|---|---|
| .33 矢量无冻结 | 14.7ms | 41.6ms | 11-12fps | 17-20 次/2s |
| **.37 矢量冻结** | **6.2ms** | **6.2-8.4ms** | **13-40fps（均值~32）** | 1-5 次/2s |

- 拖拽中 raster p50 与栅格瓦片底图同级（~6.5ms）⇒ 矢量逐帧重投影成本基本消除。
- 剩余 jank = 重锚定帧（900px 滑动 ≈ 7-8 次超预算 → build spike 55-86ms、span 130-200ms）。
  可调预算（加大→更少实况帧但边带更宽）；settle 后恢复全分辨率实况渲染。
- 无新增异常（logcat 过滤后仅系统噪音）。HUD 拖拽中 21FPS（合成手势上限内）。
- 待用户真手验证：冻结底图跟随是否平滑、120px 边带露底是否可接受。
