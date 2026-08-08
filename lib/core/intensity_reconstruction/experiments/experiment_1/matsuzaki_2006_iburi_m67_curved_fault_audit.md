# 松崎式胆振东部 M6.7 曲面有限断层审计

日期：2026-07-29

状态：JMA 暂定近地反演、Kubo 等（2020）修订同行评审论文、NIED 修订说明页和
150 个子断层数字模型已归档；曲面几何有完整来源，但当前清单没有点源近场站，因此
不制造距离改善结果，也不把曲面压成单矩形。

## 输入事件

实验 1 严格 JMA 基线中的目标事件为：

```text
eventId = 2018090603075933-42.6908-142.0067
区域 = 胆振地方中東部（rawRegionHex 按 Windows-31J/CP932 解码）
originTime = 2018-09-05T18:07:59.33Z
JST = 2018-09-06 03:07:59.33
Mj = 6.7
JMA 目录深度 = 37.04 km
最大震度代码 = 7（震度 7）
严格接受站 = 625
点源距 <30 km 测站 = 0
```

年度原始事件和逐站观测不因震源反演结果而修改。

## JMA 暂定近地反演

JMA 官方来源：

- PDF：<https://www.data.jma.go.jp/eqev/data/sourceprocess/event/2018090603075933near.pdf>
- 原始数据：<https://www.data.jma.go.jp/eqev/data/sourceprocess/data/2018090603075933near.zip>

本地原始文件及 SHA-256：

```text
references/papers/2018_JMA_Iburi_M67_source_process.pdf
3973CCC7256BB7D745125292E62F670737EF344C03402201E43298F61F58FBF1

references/papers/2018_JMA_Iburi_M67_source_process_data.zip
9746B1B27240A9540E16EE698E338BCAA584F695E5F63461A573D8D9FFF14239
```

JMA ZIP 给出：

```text
last updated = 2018-10-05
type = near02
strike = 0 degrees
dip = 70 degrees
rake = 99 degrees
rupture start = 42.6908 N, 142.0067 E, depth 37.04 km
Xorg = 6
Worg = 8
subfault size = 4 km x 4 km
assumed grid = 10 x 10
assumed plane = 40 km x 40 km
Mw = 6.72
maximum slip = 1.65 m
```

100 个单元全部为 `Mark=1`。PDF 正文和图面明确将主滑移区描述为走向约 `15 km`、
下倾约 `10 km`，位于破裂点西南侧较浅处；但没有报告该区域的四边索引或破裂点到
边界的数值偏移。因此不能把 `40 km x 40 km` 计算面当成实际主滑移区，也不能从
等值线量出 `15 km x 10 km` 矩形。

## Kubo 等（2020）修订模型

同行评审论文：

```text
Kubo, Iwaki, Suzuki, Aoi and Sekiguchi (2020)
Estimation of the source process and forward simulation of long-period
ground motion of the 2018 Hokkaido Eastern Iburi, Japan, earthquake
Earth, Planets and Space 72:20
DOI: 10.1186/s40623-020-1146-z
```

本地开放获取原文：

```text
references/papers/2020_Kubo_et_al_Iburi_source_process.pdf
D68630179F61AD8BDDC6DB151340710731D39855A5098E7ABA738F1237598964
```

论文明确指出余震分布的走向沿断层变化，使用单一矩形不合理，因此建立多个矩形单元
拼接的曲面模型：

```text
dip = 65 degrees
top depth = approximately 22 km
width = 20 km
subfault grid = 15 along strike x 10 along dip
maximum subfault size = 2 km x 2 km
top length = approximately 22.2 km
bottom length = approximately 25.4 km
total area = approximately 476.6 km2
rupture start = 42.6908 N, 142.0067 E, depth 37.04 km
large-slip area = depth 25-30 km, horizontal along-strike extent about 10 km
```

论文还说明 2019 年版本因破裂起点位置错误已撤回；本实验只归档 2020 年修订论文和
2020-02-21 发布的 NIED `Version 1` 数字模型，不使用被撤回版本。

## NIED 数字曲面模型

官方说明页和数字模型：

- <https://www.kyoshin.bosai.go.jp/ja/inversion/Iburi_20180906/inversion/>
- NIED 反演目录中的 `src_nied_180906Hokkaido-eastern-Iburi_v1.txt`

本地快照：

```text
references/web_sources/2026-07-29_nied_iburi_20180906_inversion.html
references/web_sources/2026-07-29_nied_iburi_20180906_source_model_v1.txt
references/web_sources/2026-07-29_nied_iburi_20180906_fig2.png
references/web_sources/2026-07-29_nied_iburi_20180906_fig3.png
references/web_sources/2026-07-29_nied_iburi_20180906_fig4.png
```

严格解析数字文件得到：

```text
subfault rows = 150
ix = 1..15
iy = 1..10
subfault center latitude = 42.5920..42.8102 N
subfault center longitude = 141.9159..142.0326 E
subfault center depth = 22.539..38.852 km
sum of supplied subfault areas = 476.568725 km2
subfault width = 2 km
subfault along-strike length = 0.440..2.032 km
maximum slip = 3.8113 m at ix=7, iy=4
rupture-start subfault = ix=7, iy=9
```

破裂起点单元的中心正是 `42.6908, 142.0067, 37.040 km`，触发时间为零。数字文件
逐单元给出 `Lat/Lon/Dep/Strike/Dip/Lx/Ly/Area/Slip/Rake/Ttrg`，因此曲面反演模型本身
具有可复现几何，不需要从图面量取，也不应简化成平均走向单矩形。

这套完整曲面是反演使用的震源断层模型；论文讨论的约 10 km 大滑移区不是另一套带
数值四边的独立边界。若未来要计算曲面最短距离，应直接解析 150 个子断层并计算到其
联合表面的距离，同时保留来源给出的变长单元，不能拿外包矩形替代。

## 决定

本事件记为 `source_backed_curved_fault_model_archived_no_nearfield_diagnostic`：

- 目标事件有修订后的同行评审曲面模型和官方逐单元数字数据；
- 单矩形近似被论文明确否定；
- 当前实验的矩形几何工具不适合这套曲面；
- 清单中点源距 `<30 km` 的测站为零，当前没有可运行的同配对近场诊断。

因此本轮完成来源和几何归档，但不新增残差结果、不改生产算法、不扩展近场站定义。
将来若建立统一曲面距离目录，应另写有测试的数字模型解析器，并先明确松崎式距离域中
对深部曲面断层的选站规则。

