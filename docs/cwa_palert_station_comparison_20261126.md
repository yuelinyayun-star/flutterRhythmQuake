# CWA–P-Alert 逐测站 PGA/PGV 对照（2026-11-26）

**范围：离线研究；不修改生产检出、定位或振幅校正。**

## 一、结论摘要

1. 已下载 CWA 官方逐测站事件参数（E-A0015-002、E-A0016-002），并下载 2026-11-25 事件的 E-A0015-004 原始强地动波形。
2. 已将 CWA 测站坐标与 P-Alert 786 个测站元数据做全局一对一坐标匹配。两边站号不相同，不能按站号直接 join。
3. 对三个同时具有事件级 P-Alert PGAList 的事件，在名义 250m 近邻范围内得到 31 组有效事件—测站观测。P-Alert/CWA 的 PGA 中位比值为 1.137，PGV 为 1.077；对数振幅相关系数分别为 0.757、0.737。
4. 整体相关性不错，但存在明显测站/频带相关差异；ECL/W12F 在 11/25 的 PGA 比值达到 4.20，频谱差异集中在 3–10Hz。不能用一个全局比例系数校正全部 P-Alert 测站。
5. CWA 原始波形重算验证通过：47 个测站的原始三分量 PGA 与官方 PGA(SUM) 中位比值 1.004；采用 0.2Hz 高通、去趋势、积分计算的 PGV 与官方 PGV(SUM) 中位比值 1.0035。
6. 11/17 的 P-Alert GraphQL 没有事件级 PGAList，也没有可用 waveform 预览；仅有本地回放帧的 PGA 快照。该部分不能伪装成完整事件峰值，也没有 PGV 对照。

## 二、数据来源与口径

### CWA

- [E-A0015-002：显著有感地震报告](https://opendata.cwa.gov.tw/dataset/earthquake/E-A0015-002)
- [E-A0016-002：小区域有感地震报告](https://opendata.cwa.gov.tw/dataset/earthquake/E-A0016-002)
- [E-A0015-004：强地动波形](https://cwaopendata.s3.ap-northeast-1.amazonaws.com/Earthquake/E-A0015-004.zip)

CWA 事件站点数据包含 StationID、站名、坐标、震度、PGA/PGV 的 EW/NS/V 分量和 IntScaleValue。11/25 官方参数页将标量字段显示为 PGA(SUM)、PGV(SUM)，本研究将 API 的 IntScaleValue 作为官方 SUM 值使用。

CWA PGA 单位为 gal（cm/s²）；PGV 单位为 kine（cm/s）。

### P-Alert

- [P-Alert 数据库](https://palert.earth.sinica.edu.tw/database/)
- [P-Alert 数据说明](https://palert.earth.sinica.edu.tw/help)
- GraphQL：`https://palert.earth.sinica.edu.tw/graphql/`

事件级 PGAList 的 PGA 使用 gal，PGV 使用 cm/s。公开 GraphQL 的 waveforms 查询返回的是 25Hz、120s 的绘图预览，不是完整 SAC 文件。网站的完整 SAC 下载为 100Hz、10min；下载表单要求邮箱、单位/机构并经过 reCAPTCHA。本轮没有伪造用户资料或绕过下载表单，故只使用公开 GraphQL 预览。

## 三、先修正事件参考值

上一轮的 10/13 正式参考值曾被误写。重新核对 CWA 官网后，正确值为：

- 10/13 M4.3：23.56N、121.45E、深33.8km；[CWA第069号报告](https://scweb.cwa.gov.tw/zh-tw/earthquake/details/2026101317301043069)。不是此前写的 23.57N、121.43E、30km。
- 10/17 M4.6：目前只保留 TECDC/CWA Rapid 记录 24.5153N、121.7560E、深67.1km；此前提供的所谓正式详情页链接返回404，故不标成正式 CWA 详情页。
- 11/1 M5.6：24.89N、122.11E、深119.5km；[CWA第075号报告](https://scweb.cwa.gov.tw/zh-tw/earthquake/details/2026075)。
- 11/17 M4.0：23.41N、121.52E、深33.7km；[CWA小区域报告](https://scweb.cwa.gov.tw/zh-tw/earthquake/details/2026111716460540)。
- 11/25 M5.5：21.88N、121.46E、深16.7km；[CWA第081号报告](https://scweb.cwa.gov.tw/zh-tw/earthquake/details/2026112516471755081)。

10/13、11/1、11/17、11/25 的 Rapid 与正式详情页坐标差异均小于约0.34km，深度和震级一致；差异主要来自坐标精度取整，不是上一轮所说的深度修订。10/17 仍是 Rapid-only。

## 四、事件级数据覆盖

| 事件（UTC+8） | CWA站点行 | 有PGA/PGV的CWA站点 | P-Alert PGAList行 | 250m候选配对 | 有效PGA/PGV配对 |
|---|---:|---:|---:|---:|---:|
| 10/13 17:30:10 | 33 | 31 | 715 | 9 | 7 |
| 11/1 16:20:07 | 99 | 94 | 714 | 20 | 15 |
| 11/25 16:47:17 | 51 | 47 | 713 | 9 | 9 |
| 11/17 16:46:05 | 15 | 13 | 0 | 2 | 0（仅本地回放帧补充） |

P-Alert 事件级数据没有 11/17 的 PGAList；HTTP 200 但空记录是产品数据缺项，不是网络断连。

## 五、测站匹配方法

- CWA 这四场报告合计 128 个唯一 StationID；P-Alert 测站元数据 786 个。
- 两套站号没有直接重合，按坐标做全局最小距离一对一分配，避免多个 CWA 站重复匹配同一个 P-Alert 站。
- 全局配对中，27 个站点坐标距离不超过250m，35个不超过500m；250m内的27对均为互为最近邻。
- CWA 坐标精度约0.001°，P-Alert 坐标更精细。250m 是名义近邻门槛，不等于同一台仪器、同一建筑或同一地基；500m仅作为敏感性分析。

## 六、逐站峰值对照结果

主统计只用250m名义近邻、且双方 PGA/PGV 均为正值的31组事件—测站观测。

| 指标 | PGA | PGV |
|---|---:|---:|
| 有效观测数 | 31 | 31 |
| P-Alert/CWA 中位比值 | 1.137 | 1.077 |
| 对数振幅 Pearson 相关 | 0.757 | 0.737 |
| 比值在0.5–2.0内 | 90.3% | 87.1% |
| 比值在2/3–1.5内 | 77.4% | 74.2% |

500m敏感性范围有40组有效观测：PGA中位比值1.131、PGV 1.087；两者90%落在0.5–2.0内。扩大半径没有改变“总体接近、但有站点异常”的结论。

### 重复站点偏差

同一候选站点跨事件重复出现时，部分比值比较稳定：

- EDH/W451：三场 PGA 比值约0.71–0.77，PGV约0.74–0.97。
- WCKO/W205：三场 PGA约1.11–1.40，PGV约0.95–1.40。
- ECS/W39B：两场 PGA约0.90–0.97，PGV约1.00–1.18。
- ECB/W395：PGA在1.00–2.36之间，11/1出现异常；PGV在0.38–0.82之间。

这表明不能只用一个全局增益系数；部分差异有站点特征，部分又随事件变化。

### 异常配对

- 11/25 ECL/W12F：PGA 4.95/1.18=4.20；PGV 0.190/0.10=1.90。
- 11/1 ECB/W395：PGA 3.59/1.52=2.36；PGV 0.123/0.32=0.38。
- 10/13 ELD/W12D：PGV 0.193/0.03=6.43；CWA值接近低值区，2位小数取整会放大比值。
- 10/13 WHY/W099：PGA比值2.73，PGV比值2.53。

这些异常不能直接归因于传感器故障；可能涉及场址/楼层响应、局部高频放大、仪器处理口径或数据完整性，需要波形级复核。

## 七、11/25 原始波形交叉验证

### CWA波形重算

下载的 CWA E-A0015-004 ZIP 包含47个测站 ASCII 三分量波形，100Hz、120s，单位 gal；与 E-A0015-002 中47个有 PGA/PGV 参数的测站数量一致。

- 原始三分量向量峰值 vs CWA 官方 PGA(SUM)：47站中位比值1.004；95.7%在±10%内，97.9%在±20%内。
- 对加速度去趋势，做0.2Hz四阶高通并积分得到 PGV：与官方 PGV(SUM) 的中位比值1.0035；83.0%在±10%内，93.6%在±20%内；对数振幅相关约0.98。

这是对11/25单场事件的处理验证，不代表已证明 CWA 对所有事件都使用完全相同的滤波设置。

### P-Alert波形预览

公开 GraphQL 为9个近邻 P-Alert 测站返回 25Hz、120s、三分量预览。预览的三分量 PGA 与事件级 PGAList 中位比值1.063，范围0.921–1.201；14个已下载预览站中92.9%在±20%内，说明 PGAList 的异常值在波形预览中也能看到，不是单纯的事件列表提取错误。

PGV 不同：用同样的0.2Hz处理预览数据，得到的 PGV 与事件级 PGVList 中位比值1.268、范围0.587–1.581。预览已降采样且只有120s，不能代替完整100Hz/10min SAC，因此本轮不把预览积分PGV作为最终P-Alert PGV。

### 11/25九组波形近邻配对

| CWA站 | P-Alert站（位置） | 距离 | CWA PGA/PGV | P-Alert PGA/PGV | PGA/PGV比值 |
|---|---|---:|---:|---:|---:|
| LDU | W390（绿岛国中） | 154m | 2.05 / 0.20 | 3.35 / 0.280 | 1.63 / 1.40 |
| ECL | W12F（嘉兰国小） | 84m | 1.18 / 0.10 | 4.95 / 0.190 | 4.20 / 1.90 |
| EDH | W451（东河国小） | 230m | 1.71 / 0.13 | 1.31 / 0.099 | 0.77 / 0.76 |
| ECS | W39B（万安国小） | 88m | 1.99 / 0.20 | 1.79 / 0.200 | 0.90 / 1.00 |
| ECB | W395（长滨国小） | 158m | 1.22 / 0.13 | 1.44 / 0.107 | 1.18 / 0.82 |
| HEN | W143（恒春国小） | 210m | 2.67 / 0.25 | 2.08 / 0.253 | 0.78 / 1.01 |
| SCZ | W149（春日国小） | 154m | 1.41 / 0.15 | 1.64 / 0.144 | 1.16 / 0.96 |
| C015 | W213（白河国小） | 89m | 1.79 / 0.18 | 2.04 / 0.163 | 1.14 / 0.91 |
| WCKO | W205（黎明国小） | 33m | 1.44 / 0.12 | 1.60 / 0.114 | 1.11 / 0.95 |

波形分量相关性最好的控制配对是 ECS/W39B：三个方向相关系数约0.86、0.95、0.94，PGA/PGV也接近。ECL/W12F 的三个方向相关约0.63、0.40、0.36，明显弱于 ECS/W39B。

ECL/W12F 的频带峰值比（P-Alert/CWA）：

| 频带 | 三分量峰值比 |
|---|---:|
| 0.2–1Hz | 1.25 |
| 1–3Hz | 1.02 |
| 3–6Hz | 4.66 |
| 6–10Hz | 2.68 |

异常主要集中在3–10Hz，而不是低频整体放大。ECS/W39B 的对应频带比约0.93、0.87、1.25、0.95，作为对照明显更接近。这提示 ECL/W12F 需要调查局部结构/场址高频响应或传感器数据质量；目前不能直接断言是哪一种原因。

## 八、11/17补充

- CWA E-A0016-002 有13个有效测站的 PGA/PGV。
- P-Alert GraphQL 对事件时间 08:46:03Z 的 W395/W451 查询返回 HTTP 200，但 waveform 对象为空；没有事件级 PGAList。
- 本地回放保存145帧 PGA 快照：
  - ECB/W395：CWA最终 PGA 8.86gal；回放中观测到的最大帧 PGA 9.33gal，发震后约14s，比值1.05。
  - EDH/W451：CWA最终 PGA 2.32gal；回放最大帧 PGA 1.19gal，发震后约21s，比值0.51。
- CWA报告发震时刻为16:46:05+08，P-Alert回放事件起点为16:46:03+08，相差2s。该补充仅是回放窗口内PGA快照；P-Alert帧文件没有PGV，不能当成事件级最终峰值。

## 九、结论与下一步

- 事件级最终 PGA/PGV 的跨网峰值总体相符，但存在站点和频率依赖差异。
- 不做全局PGA/PGV校正；不把这些峰值统计直接用于早期EEW似然。
- ECL/W12F 是当前优先复核点：PGA约4.2倍，差异集中在3–10Hz；ECS/W39B可作为较好对照。
- 要最终判定高频差异来自结构响应、场址、仪器还是数据处理，需要取得 P-Alert 完整100Hz/10min SAC，再对齐CWA原始波形、统一滤波/基线/分量口径。本轮未提交下载表单，也未伪造邮箱或机构资料。
- 本轮 CWA HTTP、P-Alert GraphQL 请求均成功；11/17空waveform是产品缺项，不是连接断开。没有测试 APP 实时 WebSocket，不能据此声称实时WS永不掉线。
- 本轮没有修改生产代码或检出V1。

## 十、复现文件

工作目录：`tmp/srev_nied_migration_20261125/`

**下载与原始数据**
- `download_cwa_event_station_pga_pgv.py`（需设置环境变量 `CWA_API_KEY` 才能刷新官方API快照）
- `E-A0015-002_api.json`
- `E-A0016-002_api.json`
- `palert_event_pga_pgv_20261126.json`
- `cwa_E-A0015-004_latest_20261126.zip`
- `palert_20261125_matched_waveforms_graphql.json`
- `palert_earlier_event_outlier_waveforms_graphql.json`
- `palert_20261117_waveforms_graphql_empty.json`

**匹配、分析脚本**
- `audit_cwa_palert_station_match.py`
- `audit_cwa_palert_station_supplement.py`
- `audit_cwa_palert_station_summary.py`
- `audit_cwa_20261125_waveforms.py`
- `audit_cwa_palert_20261125_waveform_crosscheck.py`
- `audit_palert_waveform_preview_eventlist.py`
- `audit_palert_cwa_official_reference_correction.py`
- `audit_palert_amplitude_final_cwa_rescore.py`

**结果文件**
- `cwa_station_peak_pga_pgv_20261126.csv`（198条CWA逐站记录）
- `cwa_palert_station_crosswalk_20261126.csv`（128个唯一CWA站点的候选一对一映射）
- `cwa_palert_station_pairs_20261126.csv`
- `cwa_palert_station_match_20261126.json`
- `cwa_palert_station_analysis_20261126.json`
- `cwa_palert_20261117_frame_pga_supplement.json`
- `cwa_20261125_waveform_reprocess_20261126.json`
- `cwa_palert_20261125_waveform_crosscheck_20261126.json`
- `palert_waveform_preview_eventlist_validation_20261126.json`
- `cwa_palert_station_raw_manifest_20261126.json`
- `cwa_palert_waveform_manifest_20261126.json`



## 追加：W12F事件特定高频响应复核（2026-11-26）

ECL/W12F近邻波形对照和W39B/ECS控制站的分量峰值、时间窗RMS、5.9Hz HLE窄带分析已独立成专题报告：`docs/palert_w12f_resonance_audit_20261126.md`。关键结论：W12F的异常集中在11/25水平向高频，垂直峰时与CWA一致但水平峰时早约8秒；W39B控制站正常。异常与建筑/安装或局部场址响应相容，但25Hz预览的抗混叠细节和完整100Hz SAC仍未核实，不能定因或加入固定校正。


## 追加：完整100Hz SAC复核（2026-11-26）

完整100Hz SAC已经从本机归档取得并完成W12F/W39B两站三分量分析。完整报告：`docs/palert_full_sac_100hz_validation_20261126.md`。

关键更新：
- W12F HLE的5.933Hz峰在100Hz原始SAC中真实存在；可能折叠到5.9Hz附近的18.5–19.5、30.5–31.5、43.5–44.5Hz候选频带能量极低，混叠不是主要解释。
- 20–35秒W12F/ECL 3C PGA比为4.274；HLE 5.5–6.5Hz RMS为0.7749/0.05096gal，比值15.20。35–50秒比值7.18，50–70秒13.70；100–120秒后回到W12F自身基线附近。
- W39B/ECS 0–100秒3C PGA比为0.98，作为对照基本正常。
- 100Hz 1–3Hz互相关时差约0.03–0.06秒，纠正此前将单分量绝对峰值时刻差误判为约8秒全局时钟偏移的解释。
- GraphQL 25Hz预览与100Hz SAC降采样波形相关性较高，但预览RMS普遍高约10–30%；定量振幅以完整SAC为准。
- 异常仍可能来自建筑响应、安装/通道或局部场址，尚不能定因；不做固定增益，不改生产算法。

