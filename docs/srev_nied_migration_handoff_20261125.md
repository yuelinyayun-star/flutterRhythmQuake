# RhythmQuake — SREV NIED 检出迁移交接

日期：2026-11-25（UTC+8）
状态：独立 Rust 移植及回放 A/B 已完成；**RhythmQuake 正式 NIED 体系尚未切换**。

## 1. 唯一主开发入口

- Windows 主机：Rhythm。
- 主工作目录：`D:\flutterApp\flutterrhythmquake`，Git 分支 main，检查时 HEAD 为 e52a8ac3f695c92966b5d1f10beac3b37af88324。
- 主线认定证据：实际运行的 Release 进程 PID 37664 来自 `D:\flutterApp\flutterrhythmquake\build\windows\x64\runner\Release\flutterrhythmquake.exe`；2026-11-25 仍有主目录源码修改，检查时 Git 状态为 100 条已跟踪改动、65 条未跟踪记录（编写本文前）。
- 不要用远端 main、旧 worktree、历史快照覆盖当前未提交开发成果。
- 现有完整源码副本中保留 `D:\flutterApp\tmp\rq_20261119_dyfi_win`（2026-11-19 的 DYFI Windows 调试副本；检查存在 lib、Rust crate、Android、iOS、Web、Windows、assets、tests、docs、tools）。没有为本次新建备份。此副本不是 11 月 25 日主线的无损还原点，未验证完整构建。
- `tmp\weather_win_engine_ab` 是 11 月 25 日的专项 Windows 实验，缺少 Android/iOS 等平台源码；不是完整版本备份。
- KMA Android/KMA dev/Web diagnostics worktree 有各自未提交修改，不能当旧备份清理。独立实验、回放数据、阶段性差异文件、测试报告及历史研究资料也不等于完整备份版本。

## 2. 已完成 SREV 移植

独立工程：`D:\flutterApp\srev-chinese-translation-tauri`（并非 RhythmQuake Git 分支）。
原始算法来自改造版 `srev-s\assets\project.json`，不是通用 SREV 或 KA 的猜测实现。

Rust crate：`src-tauri\detector`。主要文件：
- `src\lib.rs`：Detector、状态及公共调用入口。
- `src\generated.rs`、`src\state.json`、`src\static_texts.rs`：原积木转换、状态表及常量。
- `src\hyp.rs`：JMA2001 走时、HYP 随机搜索、事件轮询、P/S 到时重算。
- `src\magnitude.rs`：原版震级公式。
- `src-tauri\tools\compile_detector.py`：源码转换器（路径相对 SREV 工程）。
- 原版授权 CC BY-SA 2.0；整合前核对许可证、来源和署名，不默认可以任意去除原作者信息。

验证情况：
| 模块 | 已验证结果 | 范围 |
|---|---|---|
| 检出 | 32帧合成及373帧真实回放；与原始积木解释器比较约1151.8万项零差异；实际打包 TurboWarp 数值语义等价 | v3 优化后的历史基准；HYP 后的三角函数修正没有重新跑全套373帧严格对照 |
| 检出性能 | v3 平均3.375 ms，历史 TurboWarp 5.439 ms | 历史测量，并非最新完整应用 benchmark |
| HYP | 8组冻结快照（7次实际搜索、1次超龄跳过）；140160项等价，随机调用次数一致 | 注入相同LCG种子；非原始 JS 随机流或并发调度等价 |
| 震级 | 14组原版对照、192项零差异；11项 Rust 测试通过 | 原版公式等价，不代表官方震级准确 |
| 震度敏感性 | 373帧，同档位的细震度上下限可影响后期检测解除及到时 | `validation/intensity_resolution_audit.json` |

SREV 原版 HYP 和震级均已移植，但下一步用户明确只要求先替换 NIED 震度体系及检出；保留 RhythmQuake 自有 HYP/震级，不能自动全量替换。

## 3. 震度转换：必须区分编码、代表值和显示震度

原版两位数字报文 q=00..98，细震度 I=(q-30)/10（-3.0..6.8）；q=99 是缺测。SREV 内部档位 0=缺测，1..30 为有效观测：

```text
q < 15: 1 + floor(q/5)
15 <= q < 75: 4 + floor(3*(q-15)/10)
75 <= q < 95: 22 + floor(4*(q-75)/10)
95 <= q <= 98: 30
```

代表震度表（1..30）：
```text
-3,-2.5,-2,-1.5,-1.17,-0.84,-0.5,-0.17,0.16,0.5,
0.83,1.16,1.5,1.83,2.16,2.5,2.83,3.16,3.5,3.83,
4.16,4.5,4.75,5,5.25,5.5,5.75,6,6.25,6.5
```

主工程 `lib/services/sources/jp_shindo_scale.dart` 的 scratchValues 有相同的30个代表值，但 levelFromShindo 的索引为0..29、-1缺测，且按代表值下界查找，不能当作原报文分档公式直接使用。KA 源编码 -1缺测、0为恰好-3，1..19区间为 [(k-7)/2,(k-6)/2)，20为>=6.5；0..20 的旧编号不可直接传给 SREV。

A/B 测试按0.1原报文刻度枚举 KA 档位的物理震度区间，取区间中间刻度（另测上下限）；对应 k=0..20 的 SREV 档位：
```text
1,1,2,3,4,6,7,9,10,12,13,15,16,18,19,21,22,24,26,28,30
```
缺测映射0；KA 已经量化，无法无损恢复细震度。实际具有连续计测震度的数据源优先使用真实值；必须独立定义浮点边界、量化和超范围规则，并测试0.1档位附近的值。不要把原版用于触发的代表值当成真实观测值。显示震度7是计测震度>=6.5，不要求7.0。

## 4. NIED 检出及完整推算 A/B 结果

测试资料根目录：`D:\flutterApp\srev-chinese-translation-tauri\src-tauri\detector\validation\rq_srev_ab`。
- `summary.json`：三样本、三种档位映射的检出比较（535个观测帧，1605 variant-frames）。
- `hyp_ab_summary.json`：535帧/方案的完整 HYP 对照，包含逐帧估计、官方参考、误差及测试范围。
- `input_hyp_frames.ndjson`、`rq_hyp_frames.ndjson`：小笠原逐帧结果。
- `20260610_180130_jst_nara_m36_hyp_frames.ndjson`、`nara_rq_hyp_frames_tz.ndjson`：奈良。
- `yahoo_20260906_144219_snapshot_hyp_frames.ndjson`、`weak_rq_hyp_frames_tz.ndjson`：大隅半岛。
- 旧的未加 _tz 的原始 Yahoo RQ 推算结果存在时间区处理问题，以 _tz 版本为准。Windows UTC+8 输出须规范化为 JST 后比较。
- SREV crate `examples/rq_srev_ab.rs`、`examples/rq_srev_hyp_ab.rs`，SREV `src-tauri/tools/prepare_rq_srev_ab.py`、`prepare_rq_raw_ab.py`、`prepare_rq_hyp_ab.py`、`prepare_rq_raw_hyp_ab.py`、`summarize_rq_hyp_ab.py`。RQ 测试入口位于主工程 `.dart_tool/srev_hyp_ab_test.dart` 和 `srev_hyp_*_tz_ab_test.dart`，为临时测试文件，可能随缓存清理消失。
- 小笠原原始回放位于 Downloads：`2026-10-25_10-09-21_UTC+8_小笠原諸島西方沖_M7.5_jmaEew_20261025111028_7dad4023.rqreplay`；M7.5 是 EEW 最终报值，目录测定值为 M6.8。
- 奈良及大隅半岛原始 Yahoo 数据位于主工程 `tmp/captures/20260610_180130_jst_nara_m36` 与 `tmp/captures/yahoo_20260906_144219_snapshot`。

以本地已保存的 JMA 日别震源目录参考为准（官方 EEW 最终报不是最终测定值）。以下误差均为水平震央距离：

| 样本、帧数 | 官方深度/M | 首次误差 SREV/RQ (km) | 最小误差 | 最后误差 | 最后深度 SREV/RQ | 最后M |
|---|---|---|---|---|---|---|
| 小笠原西方冲，373 | 507/6.8 | 696.63/187.31 | 20.78/79.37 | 63.26/79.37 | 440/520 | 5.89/6.11 |
| 奈良，71 | 50/3.6 | 1.24/5.38 | 0.36/5.38 | 2.48/5.75 | 30/50 | 3.01/3.39 |
| 大隅半岛东方冲，91 | 40/3.3 | 57.88/171.63 | 2.82/18.03 | 31.11/18.03 | 10/10 | 1.54/2.50 |

- 检出测试：三种映射均检出三场事件；小笠原相对历史 KA 活动状态早1秒，奈良同秒，弱震晚1秒。完整推算首次输出两方案在各场同秒（小笠原11:11:13、奈良18:01:31、大隅14:41:36 JST）。
- 小笠原 SREV 首次进入100km后又恶化，11:12:53才连续10帧进入50km内，之后冻结到63km；RQ 从未进入50km。SREV 接入连续反馈后累计事件ID由7降到3、同时活动峰值4降到2，但次事件真伪未核实。
- SREV 原算法在检出后120秒停止 HYP 搜索，不能把后期重复输出视作新定位成功。小笠原 RQ 在最后一帧前关闭，最后有效估计为第347帧，SREV到第372帧。
- SREV 中间值方案检出平均单帧约3–4ms；含推算帧的平均耗时 SREV/RQ 分别为26.36/649.28、15.02/132.06、10.62/75.97ms。Release 与 Flutter Test 不同，非严格同条件 benchmark。
- 实验非生产等价：SREV 1748站目录中匹配1710站，RQ用1725站；小笠原 RQ直接用原始保存的有效测站快照，另两场由原始 Yahoo 和 KA 核心重建，10.5秒保持为测试框架模型；SREV每观测帧轮询一次、固定种子12345、P/S反馈，未完全复现原版实时调度。没有噪声、并发真事件、长期稳定性、全量弱震或新生产集成验证。不能以这三场宣布全面优于 KA。
- 震级原版：M=max(0,Imax-0.94+1.73*log10(R))，R=到最近目录测站的震央距离，下限20km；不直接使用深度，多事件使用原版事件震度转换。普遍低估，用户要求保留现有 RQ 震级。

## 5. 下一步：用户授权范围（尚未执行）

只切换 NIED 的震度体系及检出为 SREV。现有 HYP、震级、其他独立信源算法保留，先核对输入适配，禁止全局替换 KA 档位编号。当前主线源码/分支不可错用。

当前关键入口：
- `lib/services/sources/nied_monitor.dart`、`nied_yahoo_service.dart`、`nied_realtime_pipeline.dart`、`native_nied_detection_owner_io.dart`：数据接收及 NIED 原生所有权。
- `native/station_core/src/nied_detection_state.rs`（当前 KA 关联、保持、网格、通知、投影所有者）、`ka_detector.rs`、`ka_history.rs`、`nied_topology.rs`；原生桥接及构建注册在 `native/station_core/src/lib.rs` 等。
- `lib/services/sources/nied_source_estimation_driver.dart`、`nied_source_estimation_worker.dart`：现有推算入口，继续使用。需明确 SREV 检出状态、事件ID、到时及活动/震度输入转换；不能把仅显示的 KA 状态混为 HYP 输入。
- `lib/services/sources/jp_shindo_scale.dart`：KA、Scratch、JMA 映射；保留旧回放及非NIED调用兼容。
- `lib/widgets/map/nied_intensity_layer.dart`、`ka_shindo_marker_style.dart`、`quake_map_view.dart`：地图显示与多信源复用。不要盲目更改 shared marker 影响 P-Alert/KMA/长周期。
- 先查所有 level、kaLevel、rawShindo、activityLevel、jmaIndex、阈值、FFI字段、历史序列化、网格、统计、警报及推算使用者；按实际物理震度逐项核对，区分 NIED、独立检出、公共 UI。

### 当前 NIED 显示基准（2026-11-25 直接核对代码）

- 缺测灰点 `0x4D888888`；非缺测但 level<0 时 idle 蓝点 `0x4D0003CF`，保持不同语义。
- NIED 数值图标原阈值：默认 KA level>=8（I>=0.5），开启 displayShindo0 时 level>=6（I>=-0.5），且 zoom>=4；informationFocusDotsOnly 始终点模式，达到阈值的点改用对应 JMA 色。注意“显示震度0”开关实际下界为-0.5，不要擅自改成0。
- 低档点色：`0x4D0003CF,0x4D0014DA,0x4D0037F0,0x4D006CDC,0x4D00B3A2,0x4D12DC72`（旧 level 0..5，超出夹紧）；应按原物理区间保持。
- JMA 图标色索引0..9：`FF888888,FF8282FF,FF46B4FF,FF00DC8C,FFFFFF00,FFFFB400,FFFF6400,FFFF0000,FFB40000,FF640096`；标签0,1,2,3,4,5-,5+,6-,6+,7。
- JMA 分类下界：0.5、1.5、2.5、3.5、4.5、5.0、5.5、6.0、6.5。旧网格边框 level<=7绿、<=13黄、其他红，对应 I<0.5、0.5<=I<3.5、I>=3.5；保留边框含义，单独适配。
- 数值图标14.0逻辑像素；高强度JMA索引>=7（6弱以上）白色2px边框，其余1px半透明白；文字色原以JMA索引>=4为黑，否则白（支持明确 foregroundColor 覆盖）。不要把通用 KaShindoMarkerStyle 的配色当成 NIED 专用色。
- 点大小公式 (0.9+(zoom-3)*0.95).clamp(0.9,7.5)，点描边按 overview 缩放；保持原缓存、绘制路径和信息聚焦表现。若只有 KA 原始档位，优先保留原编码的显示投影，不能把 SREV 档位代表值跨过 UI 边界误判。
- 已有测试/参考：`test/jp_shindo_scale_mapping_test.dart`、`test/nied_station_layer_role_audit_test.dart`、`test/nied_missing_map_preview_test.dart`、`docs/baselines/nied_station_layer_role_audit.generated.md`、`tmp/jma_lpgm_combined_nied_numeric_icons_font_verified_20261108` 中历史渲染截图。检查实际 NIED、KMA、P-Alert 与长周期共用标记回归。

### 验收顺序

1. 只读盘点所有震度字段及调用者；制定清晰的输入/输出档位契约和旧记录兼容策略。不要创建或切换旧支线来冒充主线。
2. 在 Rust 接入 SREV NIED 检出，保留其他独立算法；对接原生 owner 的状态、事件、到时、网格、失效、通知、数据源切换、生命周期。验证不静默退回旧算法。
3. 按每个计测震度边界、缺测、缩放4、displayShindo0 和信息聚焦核对显示颜色、点/图标、文字描边、缩放及网格。真实 Windows/移动端适用入口渲染验证；非NIED独立检出及共享图标不受影响。
4. 同一原始回放对比 KA 基准与 SREV检出+现有RQ推算（这组尚未测过，不能引用第4节两套完整算法作为混合方案已经通过）。扩大到弱震、静默/误检、多事件、远海、数据缺失及回放兼容；对比到时、漏检/误检、收敛、最终深度/震级、性能和释放。
5. 只有实际编译、测试、渲染及正式调用链验证通过才能声称切换完成；保持当前主线其他未提交改动，不擅自修改无关信源及功能。

## 6. 可复现命令（在独立SREV crate目录执行）

```powershell
cargo test --offline
cargo run --release --offline --example rq_srev_ab -- input
cargo run --release --offline --example rq_srev_hyp_ab -- input
python -X utf8 ../tools/summarize_rq_hyp_ab.py
```

其他样本的参数分别为 20260610_180130_jst_nara_m36 和 yahoo_20260906_144219_snapshot。测试输入及输出已经存在；重新运行会覆盖对应测试输出，保留需要对比的历史记录时先审阅文件。当前没有改动任何 RhythmQuake 业务代码。
