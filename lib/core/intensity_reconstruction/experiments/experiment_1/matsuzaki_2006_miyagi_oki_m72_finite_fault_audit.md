# 松崎式宫城县冲 M7.2 有限断层边界审计

日期：2026-07-29

状态：JMA 近地强震与远地体波两套震源过程解析均已核对；远地结果报告约
`30 km x 20 km` 的实际尺度，但没有给出该区域相对破裂起点的唯一数值边界，因此
不运行距离诊断、不把反演计算面冒充实际破裂面。

## 输入事件

实验 1 严格 JMA 基线中的目标事件为：

```text
eventId = 2011040723324346-38.2042-141.9202
区域 = 宮城県沖（rawRegionHex 按 Windows-31J/CP932 解码）
originTime = 2011-04-07T14:32:43.46Z
JST = 2011-04-07 23:32:43.46
Mj = 7.2
JMA 目录深度 = 65.89 km
最大震度代码 = D（震度 6 强）
严格接受站 = 1585
点源距 <30 km 测站 = 0
```

年度原始事件、逐站震度和目录深度保持不变。震源过程资料只用于审计有限断层几何。

## JMA 近地强震反演

JMA 官方来源：

- PDF：<https://www.data.jma.go.jp/eqev/data/sourceprocess/event/2011040723324346near.pdf>
- 原始数据：<https://www.data.jma.go.jp/eqev/data/sourceprocess/data/2011040723324346near.zip>

本地原始文件及 SHA-256：

```text
references/papers/2011_JMA_Miyagi_Oki_M72_source_process.pdf
C14AFB19F1A5BDFA369411EE03A41AF5B4C7B01BF71C09A0F75020414E633F3D

references/papers/2011_JMA_Miyagi_Oki_M72_source_process_data.zip
D96D3BDC950F7971EC75708FF1CFE6C3E0EB9DD0B9BEDA1360C4C25C7D03FE3B
```

修订 ZIP 的 `01event.txt`、`02fault.txt` 和 `04slip.txt` 给出：

```text
last updated = 2017-03-13
type = near01
strike = 24 degrees
dip = 37 degrees
rake = 87 degrees
rupture start = 38.2028 N, 141.9237 E, depth 65.73 km
Xorg = 3
Worg = 6
subfault size = 5 km x 5 km
assumed grid = 10 x 7
assumed plane = 50 km x 35 km
rupture speed = 3.5 km/s
Mw = 7.08
maximum slip = 2.50 m
```

70 个假定单元全部为 `Mark=1`，只表示它们参与反演。`W=7` 的 10 个单元最终滑移
全部为零，其余边缘仍有非零滑移。PDF 正文只说明主要滑移位于破裂起点北侧较浅处、
主要破裂约 10 秒，没有报告实际断层长宽。因而 `50 km x 35 km` 只能识别为可复现的
反演覆盖面，不能自动作为松崎式所需的物理破裂边界。

## JMA 远地体波反演

同一官方目录还提供：

- PDF：<https://www.data.jma.go.jp/eqev/data/sourceprocess/event/2011040723324346far.pdf>
- 原始数据：<https://www.data.jma.go.jp/eqev/data/sourceprocess/data/2011040723324346far.zip>

本地原始文件及 SHA-256：

```text
references/papers/2011_JMA_Miyagi_Oki_M72_teleseismic_source_process.pdf
134086DD11F4ED8AAB8DF9FFFB8E45879407C1FBA41D05D8BC97E6FEF1260ABC

references/papers/2011_JMA_Miyagi_Oki_M72_teleseismic_source_process_data.zip
66B488E9AD9F03E056B706A21D2B453BB1F0295DF354FB6414741410D0E8BD2A
```

远地解析使用同一 `24 degrees / 37 degrees / 87 degrees` 节面，数字数据给出破裂起点
`38.2042 N, 141.9202 E, 60.00 km`、`Xorg=4/Worg=6`、`9 x 7` 个 `5 km`
单元，即 `45 km x 35 km` 假定计算面。63 个单元全部为 `Mark=1`，滑移也全部非零。

远地 PDF 正文进一步报告：

```text
主要破裂持续时间约 15 秒
断层大小约 30 km x 20 km
最大滑移约 2.7 m
Mw = 7.1
```

这是目标事件实际尺度的正式来源，但正文和数字文件没有定义这块 `30 km x 20 km`
区域在 `45 km x 35 km` 计算面中的四条边，也没有报告破裂起点到各边的数值偏移。
滑移图可显示主要滑移位于陆侧浅部，却没有给用于切出边界的滑移阈值。按等值线量图、
任选连续 `6 x 4` 单元或把破裂起点默认放在矩形中心，都会制造来源中不存在的坐标。

近地和远地计算面尺寸不同，也进一步证明不能把任一完整计算网格直接称为实际断层。

## 决定

本事件记为 `audited_no_unambiguous_finite_rupture_boundary`：

- 两套目标事件专属 JMA 震源过程模型存在；
- 远地正文明确给出约 `30 km x 20 km` 的实际尺度；
- 两套数字文件给出的是更大的反演覆盖面；
- 当前来源没有提供实际区域完整、唯一的三维数值边界。

该事件点源距 `<30 km` 的测站为零，即使将来恢复边界，也不会产生当前近场清单的
同配对残差。因此本轮不创建诊断工具，不从图面量取坐标，不生成经验矩形。若后续取得
带明确边界索引的修订滑移模型，可重新打开本项。

