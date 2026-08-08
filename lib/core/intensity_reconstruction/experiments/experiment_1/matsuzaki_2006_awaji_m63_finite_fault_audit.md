# 松崎式淡路岛 M6.3 有限断层边界审计

日期：2026-07-29

状态：JMA 修订近地反演和 Imanishi 等（2020）同行评审模型已核对；实际同震破裂尺度
有来源，但三维边界没有可复现的唯一数值定义，因此不运行距离诊断、不生成经验矩形。

## 输入事件

实验 1 严格 JMA 基线中的目标事件为：

```text
eventId = 2013041305331775-34.4188-134.8290
区域 = 淡路島付近（rawRegionHex 按 Windows-31J/CP932 解码）
originTime = 2013-04-12T20:33:17.75Z
JST = 2013-04-13 05:33:17.75
Mj = 6.3
JMA 目录深度 = 14.85 km
最大震度代码 = C（震度 6 弱）
严格接受站 = 1399
点源距 <30 km 测站 = 13
```

年度原始记录不因震源过程资料而改写。JMA 震源过程反演使用的 13 个强震站也不是年度
震度数据中的 13 个点源近场站，两者不能因数量相同而互相替代。

## JMA 修订近地反演

JMA 震源过程目录为目标事件单独提供：

- PDF：<https://www.data.jma.go.jp/eqev/data/sourceprocess/event/2013041305331775near.pdf>
- 原始数据：<https://www.data.jma.go.jp/eqev/data/sourceprocess/data/2013041305331775near.zip>

本地原始文件及 SHA-256：

```text
references/papers/2013_JMA_Awaji_M63_source_process.pdf
47B8C05B72FF872764CEA284699F81B4E68F58CB8DBC95A08CC84E6193CDB754

references/papers/2013_JMA_Awaji_M63_source_process_data.zip
7A032DA337C2D838C68627334D3BD447C7603081F5CC8A779B430E54A930132B
```

修订 ZIP 的 `01event.txt` 和 `02fault.txt` 给出：

```text
last updated = 2017-03-13
type = near02
fault plane count = 1
strike = 175 degrees
dip = 60 degrees
rake = 95 degrees
rupture start = 34.4188 N, 134.8290 E, depth 14.85 km
Xorg = 4
Worg = 4
subfault size = 2 km x 2 km
assumed grid = 7 x 7
assumed plane = 14 km x 14 km
rupture speed = 2.7 km/s
Mw = 5.75
maximum slip = 0.71 m
```

49 个假定单元全部为 `Mark=1`，这只证明它们都参与反演。JMA PDF 对物理结果另有明确
解释：实际断层大小约为长 `6 km`、宽 `5 km`，主要滑移集中在破裂起点附近；东北端
约破裂开始 5 秒后的滑移是分析产生的表观结果，“不是实际滑移”。因此不能把
`14 km x 14 km` 假定计算面直接当成松崎式需要的实际有限断层边界。

PDF 的断层坐标图和地图图面均已核对。它们显示破裂起点、滑移等值线和余震震央，但
没有给出 `6 km x 5 km` 破裂矩形的四边坐标、格点范围或破裂起点相对边界的数值偏移。
从图面量取边界或默认以星号为中心都会制造来源中没有的坐标。

## Imanishi 等（2020）

同行评审论文：

```text
Imanishi, Ohtani and Uchide (2020)
Driving stress and seismotectonic implications of the 2013 Mw5.8 Awaji
Island earthquake, southwestern Japan, based on earthquake focal
mechanisms before and after the mainshock
Earth, Planets and Space 72:158
DOI: 10.1186/s40623-020-01292-1
```

本地开放获取原文：

```text
references/papers/2020_EPS_Awaji_M58_driving_stress_source_model.pdf
D05F44B97F30E4C18F94D616253992AB13F2E57BAF77F1931BC1FAD98071B841
```

正文和 Appendix B 明确给出：

```text
on-fault aftershock plane strike = 175 degrees
dip = 62 degrees
inversion plane = 12 km along strike x 16.5 km along dip
rupture start = relocated hypocenter 34.426 N, 134.831 E, depth 14.4 km
slip grid interval = 1.5 km
high-slip threshold discussed = 15 cm
inferred coseismic slip dimension = approximately 6 km x 6 km
```

论文 Fig. 15 显示滑移集中在震源更深侧，星号位于断层坐标原点附近；但正文没有把
约 `6 km x 6 km` 高滑移区定义为具有四条数值边界的矩形，也没有报告破裂起点到该
区域各边的偏移。`12 km x 16.5 km` 同样是反演模型覆盖面，不等于论文根据
`>=15 cm` 滑移和 on-fault 余震推断出的约 `6 km x 6 km` 同震尺度。

JMA 的约 `6 km x 5 km` 和 EPS 的约 `6 km x 6 km` 对实际尺度相互支持，但二者采用
不同反演面、不同震源位置和不同网格，不能拼接成一个“精确”矩形。

## 决定

本事件记为 `audited_no_unambiguous_finite_rupture_boundary`，含义是：

- 事件专属震源过程模型确实存在；
- 实际同震破裂尺度约为 6 km，有正式来源；
- 可复现的大计算面和实际破裂区不是同一个物理边界；
- 当前来源没有提供实际破裂区完整、唯一的三维数值边界。

因此不使用 JMA `14 x 14 km` 或 EPS `12 x 16.5 km` 计算面做最短距离，不按震级生成
尺寸，不从滑移图量坐标，也不把约 `6 km` 区域默认放在破裂点中心。若后续取得原始
滑移网格或作者给出的实际破裂多边形，可重新打开本项并运行同配对诊断。

