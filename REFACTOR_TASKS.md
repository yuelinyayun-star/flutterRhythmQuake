# 地震预警系统 — 统一数据管道 + 统一 UI 重构任务清单

> 状态：历史规划记录。条目可能已经完成、被替代或与当前实现不一致；执行任何任务前必须先核对现有代码和 [架构总览](docs/ARCHITECTURE.md)，不要把本文直接当作当前待办列表。

## 重构目标

将当前"三套独立数据管道 + 三套独立 UI"重构为**"统一入口 → 统一模型 → 统一 UI"**的架构。

```
当前架构：
Wolfx ── 7 handler ──→ QuakeMessage ──→ emit ──→ Provider ──→ 预警卡
FAN   ── 1 parser  ──→ QuakeMessage ──→ emit ──→ Provider ──→ 信息卡
P2P   ── 3 handler ──→ QuakeMessage ──→ emit ──→ Provider ──→ 空闲卡

目标架构：
Wolfx ─┐
FAN   ─┤→ 统一适配器 → UnifiedQuakeData → Provider → 统一UI卡
P2P   ─┘
```

核心思路参考 kanameishi 项目：所有信源（Wolfx + FAN + P2PQuake）→ 单一入口方法 `setEqMessage()` → 统一模型 `eqMessage` → UI 按来源分列表展示。

### 合并范围

| 模块 | 处理方式 |
|------|----------|
| 预警卡片 (warning) | → 合并为统一 UI |
| 信息卡片 (info) | → 合并为统一 UI |
| 空闲状态 (idle) | → 删除，由统一 UI 空状态代替 |
| 气象卡片 (weather) | → 保持独立，不改 |
| 地震列表 (eqlist) | → 保持独立，不改 |
| SeisJS / NIED / StationDashboard | → 保持独立，不改 |

---

## 第一部分：统一数据模型 `UnifiedQuakeData`

所有信源的输出格式完全统一，UI 不再做任何 `switch(source)` 判断。

```dart
class UnifiedQuakeData {
  // ═══ 信源标识 ═══
  final String source;         // 'jmaEew', 'cenc', 'p2p', 'cea', ...
  final int origin;            // 0=Wolfx, 1=FAN, 2=P2PQuake

  // ═══ 事件基本属性 ═══
  final String eventId;
  final bool isEew;            // 是否为预警事件（区别于信息事件）
  final int timeZone;          // 时区偏移（8/9）

  // ═══ UI 上半部分：信源标题 ═══
  final String titleText;      // "緊急地震速報（警報）" / "中国地震台网正式测定"
  final String reportNumText;  // "第3報（最終）" / ""

  // ═══ UI 下半部分：微章 ═══
  final bool useShindo;        // true=震度微章, false=烈度微章
  final String maxIntensity;   // 已格式化: "6.5" / "5弱" / "不明"
  final String className;      // 颜色等级: "red" / "orange" / "gray" ...

  // ═══ UI 下半部分：右侧信息 ═══
  final String hypocenter;     // "四川甘孜州泸定县" / "茨城県沖"
  final DateTime? originTime;
  final double magnitude;
  final double depth;
  final String depthText;      // "深度: 10km" / "深さ: ごく浅い"

  // ═══ 源数据（地图层用） ═══
  final double lat;
  final double lng;

  // ═══ 标志 ═══
  final bool isWarn;
  final bool isFinal;
  final bool isCanceled;
  final bool isAssumption;

  // ═══ 预警区域（JSON 字符串） ═══
  final String warnArea;

  // ═══ 原始事件引用（兼容地图层） ═══
  final QuakeMessage? rawEvent;
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `source` | String | 信源标识符，如 `jmaEew`、`cenc`、`cea` |
| `origin` | int | 0=Wolfx, 1=FAN, 2=P2PQuake（用于判断双源备份去重） |
| `eventId` | String | 事件唯一标识 |
| `isEew` | bool | 预警事件=true，信息事件=false（替代 isInfoEvent） |
| `timeZone` | int | 时区偏移，中国=8，日本=9 |
| `titleText` | String | 信源名称+类型，直接渲染在 UI 上半部分 |
| `reportNumText` | String | 第N报，空字符串则不显示 |
| `useShindo` | bool | 震度微章=true（JMA/CWA），烈度微章=false（CENC/其他） |
| `maxIntensity` | String | 已格式化的微章值，如 "6.5"、"5弱"、"不明" |
| `className` | String | 颜色等级名，由 `setClassName(intensity, useShindo)` 计算 |
| `hypocenter` | String | 震源地名称 |
| `originTime` | DateTime? | 发震时间 |
| `magnitude` | double | 震级，-1 表示不明 |
| `depth` | double | 深度(km)，-1 表示不明 |
| `depthText` | String | 格式化深度文本 |
| `lat/lng` | double | 震中坐标 |
| `isWarn` | bool | 是否为警报（仅 JMA/CWA 有意义） |
| `isFinal` | bool | 是否为最终报 |
| `isCanceled` | bool | 是否为取消报 |
| `isAssumption` | bool | 是否为推定震源（PLUM法） |
| `warnArea` | String | 预警区域 JSON 字符串 |
| `rawEvent` | QuakeMessage? | 原始事件引用，供地图层和兼容逻辑使用 |

---

## 第二部分：统一适配器 `QuakeEventAdapter`

参考 kanameishi 的 `setEqMessage(source, data, origin)` 设计。所有数据源走同一个静态方法。

```dart
class QuakeEventAdapter {
  /// 统一入口 — 所有信源（Wolfx/FAN/P2PQuake）都调用此方法
  ///
  /// [source]: 信源标识符（如 'jmaEew', 'cenc', 'jmaEqlist'）
  /// [data]: 原始结构化数据 Map
  /// [origin]: 0=Wolfx, 1=FAN, 2=P2PQuake
  ///
  /// 返回: 统一格式的 UnifiedQuakeData，取消报/过滤返回 null
  static UnifiedQuakeData? convert(
    String source,
    Map<String, dynamic> data,
    int origin,
  );
}
```

### 2.1 覆盖的信源（从三服务合并）

| origin | 来源 | 覆盖的 source |
|--------|------|---------------|
| 0 (Wolfx) | Wolfx WebSocket | jmaEew, cwaEew, ceaEew, scEew, fjEew, jmaEqlist, cencEqlist |
| 1 (FAN) | FAN WebSocket | jmaEew, cwaEew, ceaEew, scEew, fjEew, kmaEew, cwaEqlist, cencEqlist, kmaEqlist, usgsEqlist, fssnEqlist, hko, sa, emsc, bcsf, gfz, usp, ningxia, guangxi, shanxi, beijing, yunnan, fssnCmt |
| 2 (P2P) | P2PQuake WebSocket | jmaEqlist |

### 2.2 适配器内部逻辑（按 source 分支）

以 JMA 为例：

**jmaEew (origin=0, Wolfx)**：
- `titleText` = 训练前缀 + `data.Title`（如 "緊急地震速報（警報）"）
- `isEew` = true
- `useShindo` = true
- `maxIntensity` = `data.MaxIntensity`（原始字符串 "5弱"）
- `className` = `setClassName(maxIntensity, useShindo)`
- 取消报时：hypocenter="取り消されました"，maxIntensity="なし"

**jmaEew (origin=1, FAN)**：
- `titleText` = 训练前缀 + `緊急地震速報（${data.infoTypeName}）`
- `maxIntensity` = `data.epiIntensity`（FAN 的震度在 epiIntensity 字段）
- `isWarn` = `data.infoTypeName == '警報'`
- 其余与 Wolfx 一致

**cencEqlist (origin=0/1, Wolfx + FAN)**：
- `isEew` = false
- origin=0 (Wolfx): `titleText` = `中国地震台网${data.type == 'reviewed' ? '正式' : '自动'}测定`
- origin=1 (FAN): `titleText` = `中国地震台网${reviewType}测定`
- `useShindo` = false
- `maxIntensity` = FAN 提供 `maxIntensity` 时直接用，否则 `calcCsisLevel(magnitude, depth, 0)` 计算

**jmaEqlist (origin=2, P2PQuake)**：
- 与 Wolfx jma_eqlist 使用相同的 source='jmaEqlist'（合并去重）
- issue.type = ScalePrompt: hypocenter=""，magnitude=-1（震度速报无震源）
- issue.type = Destination: maxIntensity="不明"（震源速报无震度）

### 2.2b 完整 isEew 对照表

每个 adapter source 的 `isEew` 值在其分支中直接写死，不需要运行时判断。

#### EEW 预警源（isEew = true）— 共 7 个

| adapter source | 数据来源 | 说明 |
|----------------|----------|------|
| `jmaEew` | Wolfx `jma_eew` + FAN `jma` | JMA 紧急地震速报 |
| `cwaEew` | Wolfx 空 type + FAN `cwa-eew` | 台湾地震预警 |
| `ceaEew` | Wolfx `cenc_eew` + FAN `cea`/`cea-pr` | 中国地震预警网 |
| `scEew` | Wolfx `sc_eew` + FAN `sichuan` | 四川地震预警 |
| `fjEew` | Wolfx `fj_eew` + FAN `fujian` | 福建地震预警 |
| `kmaEew` | FAN `kma-eew` | 韩国地震预警 |
| `sa` | FAN `sa` | ShakeAlert（美国西岸预警） |

#### Eqlist 信息源（isEew = false）— 共 6 个

| adapter source | 数据来源 | 说明 |
|----------------|----------|------|
| `jmaEqlist` | Wolfx `jma_eqlist` + P2PQuake `551` | JMA 地震情报 |
| `cwaEqlist` | FAN `cwa` | 台湾气象署地震报告 |
| `cencEqlist` | Wolfx `cenc_eqlist` + FAN `cenc` | 中国地震台网地震信息 |
| `kmaEqlist` | FAN `kma` | 韩国气象厅地震信息 |
| `usgsEqlist` | FAN `usgs` | USGS 地震信息 |
| `fssnEqlist` | FAN `fssn` | FSSN 地震信息 |

#### 独立信息源（isEew = false，仅来自 FAN）— 共 11 个

| adapter source | FAN source 字段 | 说明 |
|----------------|----------------|------|
| `hko` | `hko` | 香港天文台 |
| `emsc` | `emsc` | 欧洲地中海地震中心 |
| `bcsf` | `bcsf` | 法国地震监测网 |
| `gfz` | `gfz` | 德国地学研究中心 |
| `usp` | `usp` | 巴西圣保罗大学 |
| `ningxia` | `ningxia` | 宁夏地震局 |
| `guangxi` | `guangxi` | 广西地震局 |
| `shanxi` | `shanxi` | 山西地震局 |
| `beijing` | `beijing` | 北京地震局 |
| `yunnan` | `yunnan` | 云南地震局 |
| `fssnCmt` | `fssn-cmt` | FSSN 震源机制解 |

#### 汇总

| 分类 | 数量 | 列表 |
|------|------|------|
| isEew = true（EEW 预警） | 7 | jmaEew, cwaEew, ceaEew, scEew, fjEew, kmaEew, sa |
| isEew = false（信息） | 17 | jmaEqlist, cwaEqlist, cencEqlist, kmaEqlist, usgsEqlist, fssnEqlist, hko, emsc, bcsf, gfz, usp, ningxia, guangxi, shanxi, beijing, yunnan, fssnCmt |
| **总计** | **24** | — |

> **设计原则**：`isEew` 是信源的固有属性，适配器每个 case 分支直接写死，不需要 `_isWarningSource()` / `_isInfoEventSource()` 等运行时判断函数。

### 2.3 className 颜色计算

参考 kanameishi 的 `setClassName` 函数：

```
intensity < 1   → "gray"        (灰色)
intensity < 3   → "blue"        (蓝色)
intensity < 4.5 → "green"       (绿色)
intensity < 5.0 → "yellow"      (黄色)
intensity < 5.5 → "orange"      (橙色)
intensity >= 5.5 → "red"       (红色)
isCanceled      → "dark-gray"   (深灰)
```

---

## 第三部分：统一 UI 布局 `UnifiedAlertCard`

### 3.1 布局设计

```
┌──────────────────────────────────────────────┐
│  中国地震台网正式测定              ← 轮播导航  │  ← 上部分：信源名称栏
├──────────────────────────────────────────────┤
│  ┌──────┐                                   │
│  │ 6.5  │  四川甘孜州泸定县                   │  ← 下部分
│  │ 烈度  │  M 6.2   深度 10km                │    左边：烈度/震度微章
│  │ 微章  │  2026-05-22 14:30:52 CST          │    右边：地名 / 震级+深度 / 时间
│  └──────┘                                   │
└──────────────────────────────────────────────┘
```

- **上半部分**：信源名称（`titleText`）+ 可选轮播导航（事件数 > 1 时显示 `< 2/5 >`）
- **下半部分**：左边微章（烈度数值 或 震度等级）+ 右边三行信息
- **尺寸**：与原预警 UI 相同（宽度 `_s(420)`，高度自适应内容）
- **模糊背景**：`BackdropFilter(blur: 10)` + 半透明黑色底 `Color(0xCC0D0D0D)`
- **圆角**：`BorderRadius.circular(_s(10))`

### 3.2 卡片字段（全部从 UnifiedQuakeData 直接读取）

| 位置 | 来源字段 | 说明 |
|------|----------|------|
| 上半部分 | `titleText` | 信源名称 + 第N报 |
| 上半部分 | `eventCount` | 事件总数（Provider提供），>1 时显示轮播 |
| 下左 | `useShindo` | `true`=震度微章，`false`=烈度微章 |
| 下左 | `maxIntensity` | 微章数值/等级，如 `"6.5"`、`"5弱"` |
| 下左 | `className` | 微章颜色等级 |
| 下右第1行 | `hypocenter` | 地名 |
| 下右第2行 | `magnitude` + `depth` + `depthText` | 震级 + 深度 |
| 下右第3行 | `originTime` + `timeZone` | 发震时间 |
| 整体 | `className` | 卡片边框/头部栏颜色 |

### 3.3 微章组件

**烈度微章**（`useShindo == false`）：
- 尺寸：`_s(58) × _s(64)`
- 圆角：`_s(8)`，边框 `_s(1.2)`
- 内容：大字显示数值（如 `6.5`，字号 `_s(22)`），下方小字 `估测烈度`（字号 `_s(8)`）
- 配色：由 `className` 查找对应颜色

**震度微章**（`useShindo == true`）：
- 尺寸相同
- 内容：大写震度主字符（如 `5`，字号 `_s(28)`）+ 可能的下标（如 `弱`，字号 `_s(16)`），下方小字 `最大震度`
- 配色相同

### 3.4 卡片颜色映射

由 `className` 决定卡片各部分的颜色：

| className | 头部栏底色 | 边框色 | 左侧圆点色 |
|-----------|-----------|--------|-----------|
| `red` | `Color(0xCCD32F2F)` | `Color(0xCCD32F2F)` | `Colors.red` |
| `orange` | `Color(0xCCE65100)` | `Color(0xCCE65100)` | `Colors.orange` |
| `yellow` | `Color(0xCCFBC02D)` | `Color(0xCCFBC02D)` | `Colors.yellow` |
| `green` | `Color(0xCC388E3C)` | `Color(0xCC388E3C)` | `Colors.green` |
| `blue` | `Color(0xCC1976D2)` | `Color(0xCC1976D2)` | `Colors.blue` |
| `gray` | `Color(0xCC607D8B)` | `Color(0xCC607D8B)` | `Colors.grey` |
| `dark-gray` | `Color(0xCC37474F)` | `Color(0xCC37474F)` | `Colors.grey` |

### 3.5 空状态（无事件时）

同一布局框架，字段为空/占位：

| 字段 | 空状态值 |
|------|----------|
| `titleText` | `"暂无信息"` |
| `eventCount` | `0` |
| `useShindo` | `false` |
| `maxIntensity` | `"-"` |
| `className` | `"gray"` |
| `hypocenter` | `"等待地震事件..."` |
| `magnitude` | `-1`（UI 显示 `"--"`） |
| `depth` | `-1`（UI 显示 `"--"`） |
| `originTime` | `null`（UI 显示 `"--:--:--"`） |

### 3.6 轮播多事件

- 保留当前 `_buildCarouselNav` 逻辑：`< prev 2/5 next >` 左右箭头
- 事件数量 > 1 时显示，≤ 1 时隐藏
- Provider 提供 `eventCount` 和 `prev/next` 切换方法

### 3.7 卡片边框闪烁

- **普通事件**：固定边框色
- **严重事件**（`className == "red"`）：边框闪烁动画（0.3 ↔ 0.9）+ BoxShadow 呼吸效果
- 闪烁动画：`AnimationController(duration: 500ms).repeat(reverse: true)`

---

## 第四部分：服务层改造

### 4.1 Wolfx 服务改动

**文件**：`lib/services/sources/wolfx_service.dart`

**改动**：
1. 合并当前 7 个独立 handler（`_handleJmaEew` / `_handleCencEew` / `_handleFjEew` / `_handleCqEew` / `_handleScEew` / `_handleCencEqlist` / `_handleCwaNoType`）→ **1 个统一 handler**
2. 每个消息类型：构造结构化 `Map<String, dynamic>` → 调用 `QuakeEventAdapter.convert(source, data, 0)` → 如果非 null 则 emit
3. 添加订阅机制：连接后发送 `query_xxx` 只订阅启用的源（参考 kanameishi）
4. 添加备用 URL（`ws-api.wolfx.jp` 备用地址）

**Wolfx source 映射**：

| type 字段 | adapter source |
|-----------|---------------|
| `jma_eew` | `jmaEew` |
| `cenc_eew` | `ceaEew` |
| `fj_eew` | `fjEew` |
| `cq_eew` | 暂不使用（转 FAN cea-pr） |
| `sc_eew` | `scEew` |
| `cenc_eqlist` | `cencEqlist` |
| 空 type | `cwaEew` |

### 4.2 FAN 服务改动

**文件**：`lib/services/sources/fan_service.dart`

**改动**：
1. 修改 `_parseFanEvent` 的输出：构造 `Map<String, dynamic>` → 调用 `QuakeEventAdapter.convert(source, data, 1)` → 如果非 null 则 emit
2. 简化 `_detectSource`（FAN 报文自带 source 字段，kanameishi 直接 `fan2Source` 映射，不需要特征检测）
3. 保持现有的 `_dispatch` 消息路由逻辑不变
4. 保持多服务器（`fanstudio.tech` / `fanstudio.hk`）+ 重连逻辑不变

**FAN source 映射**（完整）：

| FAN source 字段 | adapter source | 说明 |
|-----------------|----------------|------|
| `cenc` | `cencEqlist` | 中国地震台网地震信息（与 Wolfx cenc_eqlist 合并为同一 source） |
| `cea` | `ceaEew` | 中国地震预警网 |
| `cea-pr` | `ceaEew` | 省级预警（与 cea 同源） |
| `jma` | `jmaEew` | 日本气象厅（与Wolfx同源合并） |
| `cwa` | `cwaEqlist` | 台湾气象署地震报告 |
| `cwa-eew` | `cwaEew` | 台湾地震预警（与Wolfx同源合并） |
| `hko` | `hko` | 香港天文台 |
| `kma` | `kmaEqlist` | 韩国气象厅地震信息 |
| `kma-eew` | `kmaEew` | 韩国地震预警 |
| `sa` | `sa` | ShakeAlert |
| `fssn` | `fssnEqlist` | FSSN地震信息 |
| `emsc` | `emsc` | 欧洲地中海 |
| `bcsf` | `bcsf` | 法国 |
| `gfz` | `gfz` | 德国 |
| `usp` | `usp` | 巴西 |
| `usgs` | `usgsEqlist` | USGS |
| `ningxia` | `ningxia` | 宁夏 |
| `guangxi` | `guangxi` | 广西 |
| `shanxi` | `shanxi` | 山西 |
| `beijing` | `beijing` | 北京 |
| `yunnan` | `yunnan` | 云南 |
| `fssn-cmt` | `fssnCmt` | 震源机制解 |
| `weatheralarm` | — | 不走 adapter，走独立气象处理 |
| `tsunami` | — | 独立海啸处理 |

> ⚠️ **cenc / cencEqlist 合并说明**：参考 kanameishi 设计，FAN 的 `cenc` 和 Wolfx 的 `cenc_eqlist` 统一映射为 adapter source `cencEqlist`。两个来源（origin=0/1）更新同一个 source，Provider 层通过 source+eventId 去重，FAN 数据优先级高于 Wolfx。
> 
> ⚠️ **kma / kmaEqlist 合并说明**：参照 kanameishi，FAN 的 `kma` 统一映射为 `kmaEqlist`（isEew=false），与 `kma-eew` → `kmaEew`（isEew=true）区分。不再保留独立的 `kma_eq` source。
> 
> ⚠️ **已排除的信源**：`iclEew`（成都高新减灾研究所 Lipo 接口）— kanameishi 独有，本项目不接入。

### 4.3 P2PQuake 服务改动

**文件**：`lib/services/sources/p2pquake_service.dart`

**改动**：
1. 合并 `_handleScalePrompt` / `_handleDestination` / `_handleFullReport` → **1 个统一 handler**
2. source 改为 `jmaEqlist`（与 Wolfx jma_eqlist **合并到同一个 source**，参考 kanameishi 设计）
3. 消息处理：构造 `Map<String, dynamic>` → 调用 `QuakeEventAdapter.convert('jmaEqlist', data, 2)` → 如果非 null 则 emit
4. 海啸 (code 552) 保持独立处理，不走 adapter

### 4.4 BaseSourceService 改动

**文件**：`lib/services/sources/base_source.dart`

**改动**：
- `emit` 方法签名改为接受 `UnifiedQuakeData`（替代 `QuakeMessage`）
- Stream 类型改为 `Stream<UnifiedQuakeData>`

---

## 第五部分：Provider 层改造

**文件**：`lib/providers/quake_provider.dart`

**改动**：

1. **移除分类标志**：
   - 删除 `isShowingInfoEvent`、`isShowingTempInfo`、`treatAsWarning` 等
   - 删除 `_isWarningSource()`、`_isInfoEventSource()` 分类方法

2. **新状态模型**：
   ```dart
   UnifiedQuakeData? currentEvent;       // 当前显示的统一事件
   List<UnifiedQuakeData> activeList;    // 活跃事件列表（轮播用）
   int get eventCount => activeList.length;
   ```

3. **事件接收**：
   - 所有源的 event → `_handleNewEvent(UnifiedQuakeData event)`
   - 按 `isEew` 字段决定进入哪个列表：
     - `isEew == true` → 预警列表（EEW）
     - `isEew == false` → 信息列表（Eqlist）
   - 同一 `source + eventId` 的事件更新而非新增

4. **合并去重逻辑**（参考 kanameishi）：
   - 同一 `source` 的事件，以 `origin` 优先级（FAN 优先于 Wolfx）决定是否更新
   - `jmaEqlist` 来自 Wolfx 和 P2PQuake 两个 origin，合并处理

5. **轮播**：
   - `prevEvent()` / `nextEvent()` 在 `activeList` 中导航
   - `currentEvent` 跟随切换

---

## 第六部分：alert_module.dart 改造

**文件**：`lib/widgets/ui/alert_module.dart`

**改动**：
1. 移除 `_buildWarningCard`、`_buildInfoEventCard`、`_buildIdleState` 及其所有子方法
2. 改为引用 `UnifiedAlertCard`：
   ```dart
   UnifiedAlertCard(
     event: provider.currentEvent,
     eventCount: provider.eventCount,
     onPrev: provider.prevEvent,
     onNext: provider.nextEvent,
   )
   ```
3. 气象卡片逻辑保持不变
4. 删除不再使用的业务方法：`_badgeIntensity`、`_eewBarColor`、`_safeWarningLabel`、`_infoEventTitle`、`_sourceTypeLabel`、`_infoSuffix`、`_buildIntensityBadge`、`_buildShindoBadge`

---

## 第七部分：地图显示与动画（参考 kanameishi 改进方向）

### 7.1 kanameishi 地图标注图标策略

kanameishi 的 `EewEqlistClasses.js` 定义了多种地图标记图标：

| 事件条件 | 图标 | 说明 |
|----------|------|------|
| 预警 + 正常震源 | `eewCross`（十字） | 正常 EEW 标记 |
| 预警 + PLUM法推定 | `eewCircle`（圆形） | 不确定的推定震源 |
| 预警 + 取消 | `cancelCross`（取消十字） | 已取消的 EEW |
| 信息事件（全部） | `eqlistCross`（信息十字） | 地震报告标记 |
| 历史事件 | `eqlistCross` + 测站层 | 历史地震 + 震度分布 |

**我们当前**：仅使用文字标签 `_drawEpicenterLabel()`，无图标区分。

**改进方向**：在 `QuakeWaveLayer` 中根据 `UnifiedQuakeData.isEew` / `isAssumption` / `isCanceled` 切换不同震中图标。

### 7.2 地图标记 Tooltip

kanameishi 每个标记附带相同格式的 Tooltip：

```
緊急地震速報（警報）
第3報（最終）
茨城県沖(36.1,140.2)
深さ: 10km
2026-05-22 14:30 (+9)
M6.2
最大震度 5弱
```

**消费的 eqMessage 字段**：
- `titleText`, `reportNumText`
- `hypocenter`, `lat`, `lng`
- `depthText`
- `originTime`, `timeZone`
- `magnitude`
- `maxIntensityText`

全部已在 `UnifiedQuakeData` 模型中定义。

### 7.3 视野自动定位（核心差异）

**kanameishi 的 `smartSetView` → `setView`**：

```
事件更新 → 遍历全部活跃图层 →
  预警标记 (eewMarkerPane) →
  信息标记 (eqlistMarkerPane) →
  底图着色区域 (eewBasePane) →
  计算包围盒 L.latLngBounds →
  自动缩放至能容纳所有标记的视野
```

- 不是飞到单个事件，而是**拟合全部标记的包围盒**
- 小幅度移动：`animate: true`（平滑飞行）
- 大幅度移动（超过4级缩放）：`animate: false`（瞬移，先隐藏底图防白屏）
- `isAutoZoom`：用户手动后 60s 无操作自动恢复

**我们当前**：`animatedMove(destLocation, zoom: 6.0)` — 只飞到 `currentEvent`，固定缩放。

**改进方向**：改为 Bounds 拟合模式，传入 `activeList` 所有事件坐标，计算包围盒自适应缩放。

### 7.4 地震波动画颜色

| 颜色模式 | kanameishi | 我们 | 统一后 |
|----------|-----------|------|--------|
| mode 0 (警报) | `isWarn ? red : orange` | 相同 | 不变，直接用 `UnifiedQuakeData.isWarn` |
| mode 1 (震级) | 按 `magnitude` 查表 | 相同 | 不变 |
| mode 2 (烈度) | 按 **`className`** 字符串查表 | 按 `maxIntensity` 数值 | 改为 `className` 查表 |

**改进方向**：mode 2 从 `maxIntensity` 数值改为 `UnifiedQuakeData.className` 字符串查表，与 UI 颜色体系一致。

### 7.5 波圈细节

| 功能 | kanameishi | 我们 | 说明 |
|------|-----------|------|------|
| P波圆环 | 白色 | ✅ 青色 | 已实现 |
| S波圆环 | ✅ | ✅ | 已实现 |
| S波径向渐变填充 | ✅ SVG radialGradient | ✅ Canvas createRadialGradient | 已实现 |
| P/S波到达进度环 | ✅ 双圈 SVG 进度条 | ❌ 未实现 | 可选增强 |
| 到达倒计时 | ✅ 秒数 + 语音 | ❌ 未实现 | 可选增强 |

### 7.6 震中图标动画

kanameishi 的 `EewEvent.update()`：
- 取消报时：更新 `className` 为 `dark-gray` → 图标变为取消十字 → 清除波圈
- 更新报时：`Object.assign(this.eqMessage, eqMessage)` → 更新所有地图字段 → 重绘标记 + 波圈

**改进方向**：`QuakeWaveLayer` 改为消费 `UnifiedQuakeData`（替代 `QuakeMessage`），根据 `isEew`/`isCanceled`/`isAssumption` 切换图标和波圈行为。

### 7.7 地图层改进汇总

| 改进项 | 优先级 | 说明 |
|--------|--------|------|
| S波颜色 mode 2 改用 `className` | 🟡 中 | 与 UI 颜色体系统一 |
| Bounds 拟合自动定位 | 🟡 中 | 多事件时能看到全部标记 |
| 震中图标区分（推定/取消） | 🟢 低 | 提升视觉区分度 |
| 标记 Tooltip | 🟢 低 | 点击显示详细信息 |
| 到达进度环 | 🟢 低 | 增强视觉冲击 |
| 到达倒计时 | 🟢 低 | 需要用户位置设定 |

---

## 📁 文件变更汇总

| 操作 | 文件 | 内容 |
|------|------|------|
| **新建** | `lib/models/unified_quake_data.dart` | 统一数据模型 `UnifiedQuakeData` |
| **新建** | `lib/services/quake_event_adapter.dart` | 统一适配器 `QuakeEventAdapter.convert()` |
| **新建** | `lib/widgets/ui/unified_alert_card.dart` | 统一卡片 UI 组件（含空状态 + 轮播 + 闪烁） |
| **修改** | `lib/services/sources/base_source.dart` | emit 类型改为 `UnifiedQuakeData` |
| **修改** | `lib/services/sources/wolfx_service.dart` | 合并 handler + 订阅 + 备用URL + 接入adapter |
| **修改** | `lib/services/sources/fan_service.dart` | 接入 adapter，简化 detectSource |
| **修改** | `lib/services/sources/p2pquake_service.dart` | 合并handler + 改source=jmaEqlist + 接入adapter |
| **修改** | `lib/providers/quake_provider.dart` | 改用 UnifiedQuakeData，移除 isWarning/isInfoEvent |
| **修改** | `lib/widgets/ui/alert_module.dart` | 替换为 UnifiedAlertCard，移除旧代码 |
| **修改** | `lib/widgets/map/quake_map_view.dart` | Bounds 拟合定位 + S波颜色改用 className |
| **修改** | `lib/widgets/map/wave_layer.dart` | 消费 UnifiedQuakeData，S波 mode 2 改用 className |
| **不改** | 气象卡片、eqlist列表、SeisJS、NIED、StationDashboard | 独立模块保持不变 |

---

## 📋 分步任务清单

### 第一步：创建统一数据模型
- [ ] 新建 `lib/models/unified_quake_data.dart`
- [ ] 定义 `UnifiedQuakeData` 类及其所有字段
- [ ] 实现 `copyWith` 方法

### 第二步：创建统一适配器
- [ ] 新建 `lib/services/quake_event_adapter.dart`
- [ ] 实现 `QuakeEventAdapter.convert()` 静态方法
- [ ] 按 source 分支实现所有信源的字段映射（Wolfx 部分）
- [ ] 按 source 分支实现所有信源的字段映射（FAN 部分）
- [ ] 按 source 分支实现所有信源的字段映射（P2PQuake 部分）
- [ ] 实现 `setClassName()` 辅助方法
- [ ] 实现 JMA 震度格式化辅助方法（`_normalizeJmaShindo`, `_formatShindo`）

### 第三步：创建统一 UI 组件
- [ ] 新建 `lib/widgets/ui/unified_alert_card.dart`
- [ ] 实现上半部分信源名称栏
- [ ] 实现下半部分：烈度微章 + 震度微章子组件
- [ ] 实现右侧信息三行（地名 / 震级深度 / 时间）
- [ ] 实现空状态布局
- [ ] 实现多事件轮播导航
- [ ] 实现 className 颜色映射到卡片各部分
- [ ] 实现严重事件闪烁边框动画
- [ ] 实现卡片模糊背景 + 尺寸 + 圆角 + 边框

### 第四步：改造 base_source.dart
- [ ] `emit` 方法签名改为 `UnifiedQuakeData`
- [ ] Stream 类型同步更新

### 第五步：改造 Wolfx 服务
- [ ] 合并 7 个 handler 为 1 个统一 handler
- [ ] 接入 `QuakeEventAdapter.convert()`
- [ ] 添加订阅机制（`query_xxx`）
- [ ] 添加备用 URL
- [ ] 移除旧 `QuakeMessage` 构造代码

### 第六步：改造 FAN 服务
- [ ] 修改 `_parseFanEvent` → 接入 adapter
- [ ] 简化 `_detectSource`（依赖 source 字段）
- [ ] 移除旧 QuakeMessage 构造代码
- [ ] 连接时发送 `query` 订阅（获取所有信源最新数据）
- [ ] `query_response` 与 `initial_all` 合并处理（不再丢弃）
- [ ] 添加 `autoMsg` 重连续订机制

### 第七步：改造 P2PQuake 服务
- [ ] 合并 3 个 handler 为 1 个统一 handler
- [ ] source 改为 `jmaEqlist`
- [ ] 接入 `QuakeEventAdapter.convert()`
- [ ] 552 海啸保持独立

### 第八步：改造 QuakeProvider
- [ ] 替换状态模型：`QuakeMessage` → `UnifiedQuakeData`
- [ ] 移除 `isWarning` / `isInfoEvent` / `treatAsWarning` 分类逻辑
- [ ] 实现 `_handleNewEvent(UnifiedQuakeData)` 统一接收
- [ ] 实现按 `isEew` 字段分类列表
- [ ] 实现同源合并去重逻辑
- [ ] 实现 `prevEvent()` / `nextEvent()` 轮播方法

### 第九步：改造 alert_module.dart
- [ ] 引用 `UnifiedAlertCard`
- [ ] 移除 `_buildWarningCard` / `_buildInfoEventCard` / `_buildIdleState`
- [ ] 移除不再使用的业务方法
- [ ] 气象卡片保持不变

### 第十步：地图层改进
- [ ] `wave_layer.dart` 改为消费 `UnifiedQuakeData`（替代 `QuakeMessage`）
- [ ] S波颜色 mode 2 改用 `className` 字符串查表（与 UI 颜色统一）
- [ ] `quake_map_view.dart` 改为 Bounds 拟合自动定位（多事件时看到全部标记）
- [ ] 根据 `isEew` / `isCanceled` / `isAssumption` 切换震中图标样式

### 第十一步：编译测试
- [ ] `flutter analyze` 无错误
- [ ] `flutter build windows` 编译通过
- [ ] 运行测试各信源数据是否正确显示
- [ ] 验证地图多事件 Bounds 定位
- [ ] 验证 S波颜色模式切换

---

## 补充：FAN 初始数据处理修复（2026-05-23）

### 对比 kanameishi 发现的差异

| 方面 | kanameishi | Flutter (我们) |
|------|-----------|------|
| `query` 订阅 | ✅ `autoMsg = ['query']` | ❌ 缺失 |
| `query_response` 处理 | ✅ 与 initial_all 合并 | ❌ 直接 `return` 丢弃 |
| `autoMsg` 重连续订 | ✅ 重连后自动重新发送 | ❌ 仅在首次连接时发送 |
| 初始数据 isHistory | 直接设为当前事件 | `isHistory: true`（旧管道不触发UI） |

### 修复内容

#### 1. 发送 `query` 订阅

在 `_onConnected()` 中**首条**发送 `query`，获取所有活跃信源最新一条数据：

```dart
void _onConnected() {
    _channel?.sink.add('query');   // ← 新增：请求所有信源最新数据
    _channel?.sink.add('cwalist');
    _channel?.sink.add('cenclist');
    _channel?.sink.add('cencirlist');
    _channel?.sink.add('fssnlist');
    _startKeepalive();
}
```

#### 2. `query_response` 与 `initial_all` 合并处理

kanameishi 中两者完全等同 — `query_response` 的数据格式与 `initial_all` 一致（信源 key 在根级别）：

```javascript
// kanameishi status.js:L1375
case 'initial_all': case 'query_response': {
    this.activeFanSources.forEach(source => {
        const Data = data[source2Fan[source]]?.Data
        if(Data) this.setEqMessage(source, Data, 1)
    })
}
```

我们改为将 `query_response` 走与 `initial_all` 相同的处理分支：

```dart
// 之前：query_response 直接 return
// 之后：与 initial_all 合并
if (type == 'query_response' || type == 'initial_all') {
    for (final entry in json.entries) {
        final sourceName = entry.key;
        if (sourceName == 'type' || sourceName == 'ver' || ...) continue;
        final value = entry.value;
        if (value is Map) {
            _parsePayload(Map<String, dynamic>.from(value),
                sourceHint: sourceName, isInitialLoad: true);
        }
    }
    return;
}
```

#### 3. `autoMsg` 重连续订机制

kanameishi 的 `WebSocketObj` 构造函数接受 `autoMsg` 数组，重连后自动重新发送：

```javascript
this.fanSocket = new WebSocketObj(fanUrls, autoMsg, initMsg)
// autoMsg: ['query', 'cwalist', 'cenclist', 'cencirlist', 'fssnlist']
// initMsg: ['cwalist', 'cenclist', 'cencirlist', 'fssnlist']
```

我们的实现：在 `_doConnect()` 成功后自动调用 `_onConnected()` 发送订阅消息。重连时走同样的 `_doConnect` 流程，自然会在 `_onConnected` 中重新发送。因此 `query` 直接加入 `_onConnected` 即可覆盖重连场景。

区别：kanameishi 的 `autoMsg` 是 Array，在 onopen 中自动发送；我们的 `_onConnected` 等效于这个机制，无需单独实现。

### 修改文件

| 文件 | 改动 |
|------|------|
| `lib/services/sources/fan_service.dart` | `_onConnected` 添加 `query`；`_dispatch` 中 `query_response` 与 `initial_all` 合并 |
