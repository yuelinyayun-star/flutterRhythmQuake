# Scratch/JQ HYP 深度与震级参考笔记

本笔记记录从 `scratch-realtime-earthquake-viewer-page` 的
`docs/assets/project.json` 里直接拆出的 HYP/深度/震度-震级相关逻辑。
编码必须保持 UTF-8。

## 当前阅读范围标记：先看文章算法，暂缓云变量/EEW 辅助链

`kotoho7｜揺れ検知から震央を検出してみる` 这篇文章本体讲的是：

- 从强震モニタ/JQuake 式 `揺れ検知` 反推震央/震源；
- JMA2001 P/S 走时；
- `誤差レベル`、权重、发震时刻方差；
- 未检知点/着未着惩罚；
- 候选震源的水平、深度、发震时刻迭代搜索。

文章本体没有解释以下在线运行时/EEW 接收协议：

- `☁ c2h` / `☁ c2b0..c2b7`
- `クラウド変数更新したら`
- `雲変化` / `雲変化チェック`
- `#r:最新クラウド変数`
- `0EEW` / `0-1EEW発表中` / `0-2EEW追加情報`
- `EEW情報の処理`
- `円の中トリガ`

这些属于 Scratch 在线版的云变量接收、EEW 辅助圆和站点许可状态机，
会影响部分站点是否被允许进入检测链，但不是文章公开的 HYP 主算法。
当前复刻重点先固定为文章算法部分：`JMA2001距離近似`、
`HYP:誤差レベル計算`、`HYP:誤差レベル比較/繰り返し`、
`HYP:震源検出`、未着站和深度/时刻搜索。

云变量/EEW 辅助链另见：

```text
docs/reference/kotoho7_cloud_eew_source_logic.md
```

### 当前工作锁定：先复刻文章 HYP 算法

从这里开始，除非显式切回云变量/EEW 运行时，否则当前实现与审查只看
`揺れ検知から震央を検出してみる` 文章和本地 Scratch procedure 中的 HYP 主链。

当前优先级固定为：

1. `HYP:誤差レベル計算`：已检知站的 origin-time 方差、权重、P/S 走时、未着站惩罚。
2. `HYP:誤差レベル比較`：同一候选周围的经纬度/深度候选比较。
3. `HYP:誤差レベル比較繰り返し`：按阶段重复移动到更低误差候选。
4. `HYP:震源検出`：从初始临时震源到最终 `lat/lon/depth/originTime` 的完整搜索顺序。

`円の中トリガ`、`EEW情報の処理`、`☁ c2h/c2b*` 只标记为后续输入/许可链，
现在不拿它们解释 HYP 误差或替代文章算法。

## 震源推算不是只推震中

参考 Scratch HYP 的 `4-4 検出id震源要素` 至少包含：

| 位置 | 含义 |
|---|---|
| `+2` | 经度 |
| `+3` | 纬度 |
| `+4` | 深度 |
| `+5` | 发震时刻 |

也就是说完整 hypocenter/source 推算应覆盖：

- 震中：`lat/lon`
- 深度：`depth`
- 发震时刻：`origin time`
- 后续震度/震级链：`M` 与预测震度/最大震度

我们不能把“震源推算”只理解成震中坐标。

## 深度在 Scratch HYP 里怎么推

核心 procedure：

- `HYP:震源検出 %s %s`
- `HYP:誤差レベル比較繰り返し %s %s %s %b %b %s %s`
- `HYP:誤差レベル比較 %s %s %s %b %b %s`
- `HYP:誤差レベル計算 %s %s %s %s %s %s`
- `JMA2001距離近似: %s %s %b %b`

`HYP:震源検出` 的搜索阶段会依次执行：

| 阶段名 | 水平移动 | 深度移动 | 含义 |
|---|---:|---:|---|
| `start-h2` | `0.5` | 空/默认 | 初期较粗水平搜索 |
| `start-h10` | `0.1` | 空/默认 | 细水平搜索 |
| `start-h10-v50` | `0.1` | `50` | 显式尝试深度/时刻移动 |
| `start-h10-v10` | `0.1` | `10` | 更细深度/时刻移动 |
| `start-h60` | 动态 | 空/默认 | 后续扩展/收束阶段 |

`HYP:誤差レベル比較` 在 `深さ時刻移動あり` 为 true 时会尝试：

```text
depthMove
-depthMove
```

并调用：

```text
HYP:誤差レベル計算(lon, lat, depth, id, offset, 4-3offset)
```

因此参考算法不是固定深度，也不是简单 depth penalty；它是把
`lat/lon/depth/originTime` 放在同一个误差最小化流程里搜索。

## 误差计算里影响深度的量

`HYP:誤差レベル計算` 会：

1. 使用 `JMA2001距離近似`，对给定深度计算 P/S 走时或震央距。
2. 对已触发站构建：
   - `@hyp:時間差リスト`
   - `@hyp:重みリスト`
3. 对未着站构建：
   - `@hyp:時間差リスト未着`
4. 计算：
   - 时间差平均 `@hyp:差の平均`
   - 二乘误差合计 `@hyp:2乗誤差の合計`
   - S 计数 `@hyp:Sカウント`
   - 最终 `@hyp:誤差レベル`
5. 如果误差更小，就更新候选：
   - `@hyp:震源候補 経度X`
   - `@hyp:震源候補 緯度Y`
   - `@hyp:震源候補 深さ`
   - `@hyp:震源候補 発生時刻`

这说明深度必须由 P/S 走时、未着站、权重和 origin time 一起约束。

## 视频复查：深度搜索不是闭式公式，而是候选步进比较

用户提供的 Bilibili 视频：

```text
【摇晃检测 本地计算震源】
https://b23.tv/6Z3SdKe
BV1aF4m177kW
```

视频说明里的参考事件为：

```text
苫小牧冲
42°33.5′ N, 141°54.9′ E
M6.2
震源深度 136 km
2023/06/11 18:54:44.6
```

从视频帧可以直接看到它的深度搜索语义：

1. 先维护一个“仮の震源”候选：

   ```text
   仮の震源の位置
   緯度: ...
   経度: ...
   深さ: ...
   ```

2. 每轮在当前候选周围试探多个邻居候选：

   ```text
   経度 -0.5°
   経度 +0.5°
   緯度 -0.5°
   緯度 +0.5°
   深さ -50km / +50km
   深さ -10km / +10km
   ```

   后期会缩小水平步长，例如：

   ```text
   移動量
   緯経度: ±0.1度
   深さ: ±10km
   ```

3. 对每个候选都画“距离 km - 时刻”关系，并计算：

   ```text
   誤差レベル
   ```

   画面下方六宫格就是当前候选、经纬度正负移动、深度正负移动的
   误差比较。候选曲线越贴合测站点，误差越低。

4. 选择误差最低的候选并移动：

   ```text
   current candidate
     -> try lon ± step
     -> try lat ± step
     -> try depth ± step
     -> choose lowest 誤差レベル
     -> repeat
     -> reduce step
   ```

5. 视频最终收敛到大约：

   ```text
   緯度: 42.5
   経度: 142.0
   深さ: 140 km
   ```

   这与视频说明里的真值深度 `136 km` 接近。

结论：

- 这个深度不是一次公式直接算出来；
- 也不是由震级或震度大小单独决定；
- 它是把 `lat/lon/depth` 作为同一个候选 state，
  通过 P/S 到时曲线残差或类似 `誤差レベル` 的目标函数做局部搜索；
- 这与当前公开 Scratch HYP 里 `start-h10-v50`、`start-h10-v10`
  等深度移动阶段是一致的；
- 我们实现时应优先复刻这个候选步进比较，而不是继续只调一个
  depth penalty。

## 震度/震级相关公式

参考 Scratch 里有 procedure：

```text
距離の震度(距離, M, 深さ, 増幅)
```

它先计算震源距修正项：

```text
hypDistance = sqrt(distance^2 + depth^2)
nearFieldCorrection = 10 ^ (0.5 * (M - 0.171) - 1.85) * 0.5
多目的0 = hypDistance - nearFieldCorrection
if 多目的0 < 3:
  多目的0 = 3
```

然后计算预测震度：

```text
距離の震度 =
  2.54
  + 1.82 * log10(
      1.31 * amplification
      * 10 ^ (
          (
            (0.58 * (M - 0.171))
            + (0.0038 * depth)
            - 1.29
            - log10(
                多目的0
                + 0.0028 * 10 ^ (0.5 * (M - 0.171))
              )
          )
          - 0.002 * 多目的0
        )
    )
```

当前确认到的调用点：

1. `EEW情報の処理`
   - 距离：`tjma3:波震央距離`
   - M：`0EEW[カウント1 + 9]`
   - 深度：`0EEW[カウント1 + 8]`
   - 增幅：`1`
2. `単独トリガ 状態 ...`
   - 距离：`ten c:震源距離[...]`
   - M：`0EEW[((カウント2 * 14) + 9)]`
   - 深度：`0EEW[((カウント2 * 14) + 8)]`
   - 增幅：`1`

这表示公开 Scratch 里的这个公式主要是用已有 `M + depth + distance`
去算预测震度。

## M 字段来源复查

继续追踪 `0EEW` 列表后，确认 `M` 不是从 GIF 站点值反推出来的。

`0EEW` 是 14 字段一组的 EEW 记录。`EEW %s %s` procedure 的参数为：

```text
内容, おふせ
```

调用来源：

```text
EEW(
  内容 = #r:最新クラウド変数[2],
  おふせ = 14 * letter(30, #r:最新クラウド変数[2])
)
```

在这个 procedure 里：

| `0EEW` offset | 含义 | 写入方式 |
|---|---|---|
| `+8` | 深度 | `letter(21, 内容) + letter(22, 内容) + letter(23, 内容)`，转数值 |
| `+9` | M | `letter(24, 内容) + "." + letter(25, 内容)` |
| `+10` | 最大震度/等级类字段 | `letter(26, 内容)` |

全项目检索到的 `0EEW +8/+9` 写入只有这一处：

```text
0EEW[おふせ + 8] = n
0EEW[おふせ + 8] = numeric(letter 21..23 of 内容)
0EEW[おふせ + 9] = n
0EEW[おふせ + 9] = letter(24, 内容) + "." + letter(25, 内容)
```

因此公开 Scratch 实现中的 `M` 是 EEW/cloud message 字段，不是 GIF
反推结果。它后续被 `距離の震度(距離, M, 深さ, 増幅)` 用来计算预测震度。

### 2026-07-01 再复查记录

为避免把 EQuake 显示出来的 `M3.x` 误认为 Scratch 公开 HYP 里已经有
GIF→M 反演，这里再次按 block AST 复查：

1. `距離の震度 %s %s %s %s` 的参数名是：
   `距離, M, 深さ, 増幅`。
2. 两个调用点的 `M` 参数均来自 `0EEW`：
   - `EEW情報の処理`：
     `M = 0EEW[(カウント1 + 9)]`，
     `深さ = 0EEW[(カウント1 + 8)]`。
   - `単独トリガ 状態 ...`：
     `M = 0EEW[((カウント2 * 14) + 9)]`，
     `深さ = 0EEW[((カウント2 * 14) + 8)]`。
3. `0EEW +9` 的写入链只看到：
   `join(letter(24, 内容), join(".", letter(25, 内容)))`；
   `0EEW +8` 的写入链只看到：
   `letter(21..23, 内容)`。
4. `内容` 来自 `#r:最新クラウド変数[2]`，不是从 GIF 站点列表、
   `ten:*` 强震站历史或 HYP `4-4` source cache 反推出来。
5. `SeriesNotFound/EQuake` 公开仓库 README 声明主程序闭源，公开代码为
   GeoJson parser；仓库内没有可审计的 GIF→M 反演实现。README 只说明
   震源推算参考 `scratch-realtime-earthquake-viewer-page`，实时震度/加速度提取
   参考 JQuake。

所以当前可审计事实是：

- Scratch 公开 HYP：反推 `lat/lon/depth/originTime`；
- Scratch 公开震度公式：用已有 `M + depth + distance` 算预测震度；
- 公开资料中没有找到 GIF 站点值直接反推 `M` 的 Scratch/JQ block；
- EQuake 软件本体可能有闭源实现，但不能从公开仓库直接复现或引用。

如果我们需要“EQuake 式仅供参考震源推算”里那种从 GIF 反推出的 `M3.x`
能力，需要在我们侧额外实现 M 反演：

```text
已估 source cache(lat/lon/depth/origin)
+ 各站 GIF 反解震度/加速度
+ 距離の震度(distance, M, depth, amplification)
=> 搜索/拟合 M
```

这个 M 反演不在当前 Scratch HYP procedure 的公开 `0EEW` 写入链里。

## 对我们实现的直接要求

下一步不应继续凭权重慢慢调，而应按参考拆成两条链：

1. HYP hypocenter 链：
   - 搜索 `lat/lon/depth/originTime`
   - 用 JMA2001 P/S 走时
   - 构建时间差列表、权重列表、未着列表
   - 用误差最小化更新 `4-4 +2/+3/+4/+5`
2. M/震度链：
   - 用 `距離の震度(distance, M, depth, amplification)` 做 forward model
   - Scratch 公开实现里的 M 来自 EEW/cloud message 字段；
   - 如果要从 GIF 反推 M，需要我们额外做 M-grid 或最小二乘反演：
     `observedIntensity ≈ 距離の震度(distance, M, depth, amplification)`
   - 这个反演不能混进 HYP 坐标搜索前半段，应在 source cache 有候选后执行。

## 用户提供 SB3 复查：v1.6.3 与旧版模拟器

2026-07-01 继续检查用户提供的两个 `.sb3`：

- `D:/Users/Rhythm/Downloads/リアルタイム地震ビューアー v1.6.3.sb3`
- `D:/bdwp/地震模拟(存档恢复）.sb3`

### リアルタイム地震ビューアー v1.6.3.sb3

这个文件比当前 GitHub `docs/assets/project.json` 更旧。它有：

- `距離の震度 %s %s %s %s`
- `JMA2001距離近似: %s %s %b %b`
- `EEW %s %s`
- `単独トリガ 状態 ...`
- `複数トリガ 状態 ...`
- `最短7点決定`
- `推定用リセット`

但没有找到当前公开工程里的完整：

- `HYP:震源検出 %s %s`
- `HYP:誤差レベル比較...`
- `HYP:誤差レベル計算...`
- `4-4 検出id震源要素`

`@1 hyp:震源計算`、`@hyp計算中`、`@hyp前回計算` 在 v1.6.3 中主要表现为
初始化、显示/隐藏或占位，未看到真正写入 `lat/lon/depth/originTime`
的 HYP source cache。

`距離の震度` 公式与前面记录一致，仍是 forward model。`M` 来源同样是
`0EEW +9`：

```text
0EEW[おふせ + 8] = numeric(letter 21..23 of 内容) 或 n
0EEW[おふせ + 9] = letter(24, 内容) + "." + letter(25, 内容) 或 n
```

因此 `v1.6.3` 也不能证明 GIF→M 反演。它更像旧版 EEW/检测/预测震度链，
不是我们要找的完整 HYP+M 反演实现。

### 地震模拟(存档恢复）.sb3

这个模拟器有清楚的 `P/S计算` 链：

- `Init`
  - 初始化 `[P/SCal]EarthquakeIn = [0, 0, 10, "未检测到地震"]`
  - 清空 `[P/SCal]检测P#`、`[P/SCal]计算录入点x/y` 等列表。
- `根据震波检测点计算Epicenter`
  - 调用 `计算震中`
  - 若结果非 `NaN`，写入 `[P/SCal]EarthquakeIn[1..2]`。
- `计算震中`
  - 取 3 个 P 检测点；
  - 用三点几何中垂线求交点，得到二维 epicenter。
- `change depth`
  - 调整 `[P/SCal]EarthquakeIn[3]`；
  - 用 `Rad_p_wave(depth)` 与“震中到检测点距离”的误差比较；
  - 在 `depth ± 5 km` 附近迭代 50 次，选择误差更小的方向。
- `Rad_p_wave(dep)`
  - 使用类似：
    `sqrt((6.5 * (timer + #deltat + dep / 6.5))^2 - dep^2)`
  - 也就是固定 P 波速度 `6.5 km/s` 的几何波前半径模型。

模拟器的 `震级M` 是 Stage 全局输入变量；没有发现任何 block 写入或反推
`震级M`。`震级标志/描画` 中的站点震度是用：

```text
震级M + 震源深度 km + 震中距离 + 观测点_表层地基放大度
```

正向生成 `观测点_观测震度`。所以这个模拟器对我们有用的是：

- 三个 P 检测点中垂线求二维震中；
- 固定速度波前半径反推深度的直觉模型；
- 震级/震度正向衰减模型的一个旧版玩具实现。

它不是 EQuake/JQ 的 GIF→M 反演证据，也不能直接替代 JMA2001
P/S 走时残差搜索。

## kotoho7 note / scratchrev 视频复查：誤差レベル、着未着、深度搜索

2026-07-02 复查：

- 文章：<https://note.com/kotoho7/n/n59e423877b1b>
  - 标题：`揺れ検知から震央を検出してみる`
  - 作者：`ことほ`
  - 该文直接说明从强震モニタ/JQuake 式揺れ検知推算震央/震源的思路。
- 文章内嵌 `Scratch動作チェック用` / `@scratchrev` 视频：
  - `MaWB39GiZ64`：`仮の震源を移動させる`
  - `v85t4Dwu60Y`：`苫小牧沖 M6.2 深さ136km`
  - `doUBJoIUJLs`：`岩手県沖 M3.6 深さ40km`
  - `i0Tgp3vwadU`：`千葉県北西部 M3.5 深さ90km`
  - `UXRYI5TcGtU`：`能登半島沖 M2.8 深さ12km`
  - `p4YmrE5mgGA`：`十勝沖 M4.6 深さ30km`
  - `SIt-ZB9c7IM`：`東海道南方沖 M4.5 深さ33km`
  - `gLp88jlZz3A`：`日本海中部 M6.1 深さ394 km`

这篇文章比普通回放视频更有参考价值，因为它直接公开了算法图和
Scratch block 截图。复查到的关键点如下。

### 误差水平不是简单线性拟合

文章的核心流程是：

```text
候选震源(lat, lon, depth, originTime)
  -> 对每个站计算震央距
  -> 用 JMA2001 走时表/近似从 distance + depth 得到 P/S 走时
  -> 由「检知时刻 - 走时」反推出每站的发震时刻
  -> 计算发震时刻的平均与加权二乘误差
  -> 得到 誤差レベル
```

也就是说 `誤差レベル` 的本质是“同一个候选震源能不能让各站反推出来的
发震时刻聚在一起”。这比只看 P/S 到时点在一条线上的拟合更接近真正 HYP。

文章截图中能直接看到以下 Scratch 变量/列表：

- `@hyp:発生時刻リスト`
- `@hyp:発生時刻の平均`
- `@hyp:重みリスト`
- `@hyp:未着走時リスト`
- `@hyp:2乗誤差の合計`
- `@hyp:誤差レベル`
- `JMA2001時刻`

权重逻辑也不是统一权重。文章说明按震央距给权重，近站更重；截图里还能看到
“震央距 50km 以内固定为 1”的处理语义。这解释了为什么深度/震中必须一起算：
深度会改变同一震央距下的理论走时，从而改变每站反推出的发震时刻聚类。

### 着未着法是防止错位的核心

文章明确展示了一个负例：只使用已检知站时，某个远离真实震源的候选也可能让
少数已检知点很好贴合走时曲线，导致 `誤差レベル` 极低，但候选位置落在很多
未检知站附近，明显不合理。

为解决这个问题，文章引入参考 `着未着法` 的处理：

```text
如果候选震源预测某些未检知站在当前时刻前应该已经到波，
但这些站实际还未检知，则向 誤差レベル 加惩罚。
```

截图中同一 Osaka North 案例显示：

- 未加入未着站时，错误候选可以得到很低 `誤差レベル`；
- 加入未着站后，错误候选的 `誤差レベル` 被显著抬高；
- 真实附近候选仍保持较低误差。

这对我们非常关键：外海/陆地漂移、少站早期过拟合，不能只靠 phase balance
或几何距离惩罚解决；必须显式使用“未触发站不该已经到波”的约束。

### 深度搜索是 staged local search

文章截图和 `MaWB39GiZ64` 缩略图都能直接看到：

```text
仮の震源を移動中
移動量:
  緯経度: ±0.1度
  深さ: ±10km

仮の震源の位置:
  緯度: 42.5度
  経度: 142度
  深さ: 140km
```

同一画面下方有多个候选图，每个候选都有 `誤差レベル`；红框标出最低误差的
候选。结合文章和公开 Scratch AST，可以确认搜索阶段语义为：

```text
初始化:
  first detected station 的经纬度附近
  depth = 10 km
  originTime = firstDetectionTime - 2 s

搜索:
  0.5° 水平粗搜索
  0.1° 水平细搜索
  0.1° + depth ±50 km
  0.1° + depth ±10 km
  每阶段最多约 150 次，若没有更低誤差レベル则进入下一阶段或停止
```

因此“深度怎么推”的答案不是闭式公式，而是：

```text
depth 是候选 state 的一个维度；
每次和 lon/lat 一样尝试 ±depthStep；
通过 JMA2001 走时 + 发震时刻聚类 + 未着惩罚的 誤差レベル 来选择。
```

`v85t4Dwu60Y` 的苫小牧缩略图显示推算深度约 `140 km`，与文章/Bilibili 说明的
`136 km` 接近；`gLp88jlZz3A` 的日本海中部缩略图也显示了数百公里级深源显示。
这些视频支持“深度参与本地搜索并可给出深源解”，但视频本身仍没有给出
GIF→M 反演 block。

### 对 M 的再确认

这篇 note 和嵌入视频主要解释/展示的是：

- 揺れ検知时刻；
- JMA2001 P/S 走时；
- 候选 `lat/lon/depth/originTime`；
- `誤差レベル`、权重、未着站；
- 候选移动和收敛。

没有看到从 GIF 站点震度/加速度直接反推 `M` 的公开算法。文中提到
緊急地震速報的条件、IPF 法以及 `震源・マグニチュード`，但这属于 JMA EEW
机制说明，不等于 Scratch HYP 已公开 GIF→M 反演。

所以当前证据链仍保持：

```text
公开 Scratch / note / scratchrev 视频:
  可参考 lat/lon/depth/originTime 的 HYP 搜索；
  可参考 JMA2001 走时、发震时刻聚类、未着惩罚；
  不可证明 GIF-derived M 已公开。

我们的实现:
  HYP source cache 先做完整；
  M 作为 post-source intensity inversion 单独做。
```

### 本地文章缓存与第一版复刻结果

2026-07-02 已把文章作为研究缓存下载到：

```text
.dart_tool/reference_cache/kotoho7_yure_detection_note/article.html
.dart_tool/reference_cache/kotoho7_yure_detection_note/article_text.txt
.dart_tool/reference_cache/kotoho7_yure_detection_note/assets/
.dart_tool/reference_cache/kotoho7_yure_detection_note/manifest.json
```

注意：这只是本地研究缓存；项目 docs 不转载原文全文，只保留链接、摘要和实现结论。

同日新增了一个 diagnostic-only 复刻入口：

```text
nied_gif_hyp_kotoho7_reference_replay_v1
```

它做的是 kotoho7/Scratch 文章式的第一版复刻：

- 从最初检知站初始化 source cache：
  - `lat/lon` 取最初检知站并四舍五入到 `0.01°`；
  - `depth = 10 km`；
  - `originTime = firstDetectionTime - 2 s`。
- 每帧执行 staged neighbor descent：
  - `start-h2`: 水平 `±0.5°`；
  - `start-h10`: 水平 `±0.1°`；
  - `start-h10-v50`: 水平 `±0.1°` + 深度 `±50 km`；
  - `start-h10-v10`: 水平 `±0.1°` + 深度 `±10 km`。
- 每个候选按文章主体的 P 波誤差レベル计算：
  - 每站 `observedTime - travelTime` 的发震时刻样本；
  - 发震时刻样本使用普通平均；
  - 权重只用于二乘分散：`firstDetectedStationDistance / stationDistance`，
    但 `stationDistance <= 50 km` 时固定为 `1`；
  - 只使用文章这一节明确描述的 P 波走时，不在 reference 版里混入 S gate；
  - 着未着只在早期窗口启用：`elapsed <= 3s`，或
    `elapsed <= 10s && detectedCount < 30`；
  - 未着站若位于 `maxDetectedEpicentralDistance + 30 km` 内且按 P 波已应到达，
    则 `誤差レベル + 1`。

这版是“复刻文章思路的 stateless diagnostic”，不是生产候选。它每次 estimator
调用都会从最初检知站重新初始化，而 kotoho7/Scratch 运行时实际是持续维护
`仮の震源/source cache` 的 state-machine。因此这版只能用来验证 scoring/search
形状，不能当作最终接入方案。

已验证命令：

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart test\source_estimator_test.dart test\source_hyp_jma2001_experiment_report_test.dart test\support\source_estimation_benchmark.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=tomakomai --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=iwate_east --concurrency=1
```

两组 replay 的第一版结果：

| Case | JQ scoring best/final | kotoho7 stateless best/final | 观察 |
|---|---:|---:|---|
| `20260622_iwate_east_offshore_m30_hinet` | `4 km / 10 km` | `12 km / 37 km` | 早期能靠近，但后期会漂；说明 scoring 方向有价值，但缺少稳定 source cache |
| `20260622_tomakomai_south_offshore_m35_hinet` | `1 km / 18 km` | `22 km / 100 km` | stateless 复刻会被后期站点/未着惩罚牵走，不能直接接生产 |

随后按文章运行形态补上 stateful source cache：

```text
Kotoho7ReferenceHypSourceEstimator
method: nied_gif_hyp_kotoho7_reference_replay_v1
```

stateful 版不再从 hybrid diagnostics 桥接，也不再每帧重新初始化。它作为独立
estimator 接入 benchmark runner，并按 `sourceId:eventId` 维护：

- 最初检知站；
- 初始 `lat/lon/depth/originOffset`；
- 当前 `sourceCache(lat, lon, depth, originOffset)`；
- revision。

每帧流程：

```text
如果 event 没有 cache:
  用最初检知站初始化 cache

如果 firstDetection 后仍在 10 秒窗口内:
  按文章注释重新用最初检知站 seed 临时震源

每帧:
  从当前 sourceCache 重新计算 誤差レベル
  按 staged neighbor descent 更新 sourceCache
```

新增验证：

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=tomakomai --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=iwate_east --concurrency=1
```

2026-07-02 按文章重新收敛后的 P-only reference 版结果：

| Case | kotoho7 reference best | median / p90 | final | 观察 |
|---|---:|---:|---:|---|
| `20260622_iwate_east_offshore_m30_hinet` | `32 km` | `33 km / 83 km` | `83 km` | P-only 文章誤差レベル在后期不能解释混入的 S/噪声触发，最终深度顶到 `700 km` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `8 km` | `45 km / 50 km` | `140 km` | 早期可接近，但后期被 P-only origin scatter 推到 `700 km` 深度上限 |

结论更新：

- 2026-07-02 追加复查文章代码截图和公开 `scratch-realtime-earthquake-viewer-page`
  `project.json` 后，发现上一版“P-only reference”仍不完整：
  - 正文誤差レベル段落用 P 波说明流程；
  - 但实际 Scratch 代码在 `HYP:誤差レベル計算` 中消费 `ten:推定用 +6`
    作为 S 波标记；
  - 已检知站调用 `JMA2001距離近似` 时的 P/S 条件是：
    `P波 = NOT ((@hyp:最初検知時刻 + 15 < 現在時刻) AND ten:推定用[station+6])`；
  - 因此 15 秒后，若该站被检测侧标为疑似 S，则誤差レベル应使用 S 走时。
- `JMA2001距離近似: 経過時間or距離 深さ P波 走時計算` 是双用途：
  - `走時計算=false`：从经过时间反推 P/S 波前半径；
  - `走時計算=true`：从震源距離/深度计算 P/S 走时。
- 下一步不是把 S 选择当优化项塞进 JQ-derived 方法，而是先补齐
  kotoho7 article reference 的 `ten:推定用 +6` 等价输入。
  当前项目没有直接保存这个 Scratch 字段，因此需要实现一个明确标注的
  `article_s_flag_proxy`，或把检测侧真正维护的 S flag 接进 HYP。

随后补上文章代码里的 `ten:推定用 +6` S-flag 语义和 Scratch 误差等级缩放：

```text
scoring_model: kotoho7_article_error_level_with_s_flag_proxy_v2
station_s_flag_model: article_s_flag_proxy_candidate_origin_closeness_after_15s_v1
```

实现细节：

- 15 秒 gate 前：所有已检知站按 P 走时；
- 15 秒 gate 后：若 S-origin 比 P-origin 更接近当前 source cache origin，
  则作为 `ten+6` 等价 S flag proxy，并用 S 走时；
- 误差等级不再直接使用平方误差和，而是按 Scratch 代码形态：
  `S-factor * ((weightedResidualSquares + unarrivedCount) / weightSum) *
  (30 + 20000/(1+n^2) + 2000/(50+n))`；
- 第（4）节的移动流程已由 staged neighbor descent 实现：
  `±0.5°` horizontal、`±0.1°` horizontal、
  `±0.1° + depth ±50km`、`±0.1° + depth ±10km`。

v2 replay 结果：

| Case | kotoho7 reference best | median / p90 | final | 观察 |
|---|---:|---:|---:|---|
| `20260622_iwate_east_offshore_m30_hinet` | `4 km` | `12 km / 68 km` | `94 km` | S flag/完整误差公式让早期显著接近；后期仍会漂，最终深度约 `360 km` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `8 km` | `8 km / 50 km` | `28 km` | 相比 P-only final `140 km` 大幅改善，最终深度约 `300 km`，但深度仍偏大 |

## Scratch 项目继续核对：`4-3+5`、动态迭代、`start-h60`

继续按 `scratch-realtime-earthquake-viewer-page/docs/assets/project.json`
核对后，确认上一版 stateful replay 还少了几处 Scratch 项目代码行为。

`4-3 検出id別情報 +5` 的真实语义：

```text
検出id距離計算(番号, 4-3おふせ):
  dx = (dtc:Xpix[firstStation] - dtc:Xpix[番号]) * 11
  dy = (dtc:Ypix[firstStation] - dtc:Ypix[番号]) * 11
  ten:推定用[station+4] = sqrt(dx^2 + dy^2)
  if 4-3[offset+5] < ten:推定用[station+4]:
    4-3[offset+5] = ten:推定用[station+4]
```

也就是说它是同一 detection id 已吸收站点相对最初检知站的最大扩展距离。
我们当前实现仍使用地理球面距离作为 proxy：

```text
scratch_4_3_offset4_count_offset5_distance_proxy_from_current_usable_v1
```

这个 proxy 语义接近，但不完全等价 Scratch 的 `dtc:Xpix/Ypix * 11` 平面距离。
后期如果 detection id 被远距离噪声/其他事件站点污染，`4-3+5` 会急剧变大，
从而放宽允许最大深度和允许最大距离。

同时补齐 Scratch 项目里的搜索阶段与迭代限制：

| Scratch phase | 水平步长 | 深度步长 | iteration limit |
|---|---:|---:|---:|
| `start-h2` | `0.5°` | none | `30 - early*(15 + 14*(count<10))` |
| `start-h10` | `0.1°` | none | `80 - early*(40 + 34*(count<10))` |
| `start-h10-v50` | `0.1°` | `±50 km` | `100` |
| `start-h10-v10` | `0.1°` | `±10 km` | `100` |
| `start-h60` | `1/60°` | none | `10` |

其中 `early` 是 first detection 后 `<5s`。`start-h60` 是之前漏掉的最后水平细修。

验证：

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\source_estimator_test.dart test\support\source_estimation_benchmark.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=tomakomai --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=iwate_east --concurrency=1
```

Replay 结果：

| Case | best | median / p90 | final | 深度观察 |
|---|---:|---:|---:|---|
| `20260622_tomakomai_south_offshore_m35_hinet` | `2 km` | `5 km / 50.9 km` | `50 km` | best frame 深度 `100 km`，贴近 reference `100 km`；最后几秒被远距离触发拉到 `240–300 km` |
| `20260622_iwate_east_offshore_m30_hinet` | `4 km` | `13 km / 65 km` | `101 km` | best frame 震中很好，但 final 被 late membership 拉到 `310–350 km` |

结论：

- 深度搜索本身不是没有做；按文章/Scratch 补齐后，苫小牧 best frame 能推到
  `100 km` 深度。
- 仍未忠实复刻的是 detection-id membership 的维护方式，特别是哪些站点会进入
  `ten:推定用 +3`、何时清退、以及 `4-3+5` 如何随同一 id 成员变化。
- 下一步应继续沿 Scratch 的 detection id 管线复刻，不要用额外生产锁定去掩盖：
  `検出id4-2_適用id震源から候補選択`、
  `検出id_同一震源統合`、
  `検出id適用数カウント追加` / 清退路径。

## Detection id 成员入口修正：当前成员与 continuity 历史分离

继续对照 Scratch 的 `ten:推定用 +3` / `4-3` 语义后，确认一个进入 HYP
前的错误：我们把 `source_trigger_member_ids` 填成了
`SourceTriggerContinuityGate.effectiveMemberStationIds`。这个集合是 continuity
历史并集，会随着同一 source event 不断 `addAll(rawMembers)`。Scratch 的 HYP
不应消费这种“历史所有出现过的成员”，而应消费当前 detection id 有效成员；
continuity 历史只能用于 replacement hold / 诊断。

实现调整：

- `source_trigger_member_ids` 改为当前 continuity-aware detection 的
  `memberStationIds`；
- 历史并集另存为 `source_trigger_continuity_member_ids`；
- 如果 `heldReplacement=true`，当前 detection 的 `memberStationIds` 本来就会切回
  continuity accepted members，因此 HYP 仍会保持旧 id；
- 同一个 `eventId` 内，如果当前 raw cluster 与 anchor 低重叠且 centroid 过远，
  也视为 `same_event_member_replacement` 并 hold，避免 confirmed/coasting 后把
  另一个远处 cluster 当成同一 id 主体。

同时补了 benchmark JSON 清洗：diagnostic 里的非有限数值只在本地报告序列化时转
`null`，避免当前成员不足时的 debug-only `Infinity` 阻塞 replay 生成。

验证：

```powershell
flutter analyze lib\core\source_estimation\source_trigger_continuity_gate.dart lib\services\sources\nied_source_estimation_driver.dart test\nied_source_estimation_driver_test.dart test\support\source_estimation_benchmark.dart lib\core\source_estimation\source_estimator.dart
flutter test test\nied_source_estimation_driver_test.dart test\source_estimator_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=tomakomai --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=iwate_east --concurrency=1
```

Replay 结果：

| Case | best | median / p90 | final | 观察 |
|---|---:|---:|---:|---|
| `20260622_tomakomai_south_offshore_m35_hinet` | `3 km` | `28 km / 49.7 km` | `9 km` | 后期同 eventId 远处替换被 hold；final 深度保持约 `100 km` |
| `20260622_iwate_east_offshore_m30_hinet` | `4 km` | `12 km / 90 km` | `85 km` | 后期替换被 hold，但主体切换在 `11:27:38–11:27:41` 已经造成一次漂移 |

结论：

- “远站为什么会进”已经从 HYP 端定位到成员入口：历史 continuity 并集和同
  eventId 主体切换。
- 这次修正解决了苫小牧最终漂移，并降低岩手最终漂移，但岩手仍需要继续复刻
  Scratch detection id 的前置候选选择/清退，而不是继续调 HYP 深度搜索。

## Estimator-local detection-id station set

继续按文章/Scratch 的状态机语义补了一层：HYP 不应只吃外层 driver
当前 frame 的 cluster，而应吃已登记到该 detection id 的 station set
（`ten:推定用 +3`）。这次把 station-set 维护放进
`Kotoho7ReferenceHypSourceEstimator`，因为它自己才有 kotoho7/JQ 的
`4-4` source cache。

实现：

- 每个 `sourceId:eventId` 维护一个 assigned station-code set，作为
  `ten:推定用 +3` 的 Dart 侧近似；
- 新的当前 detection member 只有在靠近已 assigned station，或用 estimator
  自己的 source cache + JMA2001 P/S 走时能解释时才进入 assigned set；
- HYP 评分使用所有 assigned 且有 first trigger/rise time 的记录，不再要求
  station 当前仍 `activeLike`，更接近 Scratch 持久 `ten` 表；
- 外层 `SourceTriggerContinuityGate` 的 current/continuity-union 拆分仍保留，
  但 kotoho7 replay 的 P/S source-cache 语义不再依赖生产 hybrid estimate。

验证：

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\source_trigger_continuity_gate.dart lib\services\sources\nied_source_estimation_driver.dart test\source_trigger_continuity_gate_test.dart
flutter test test\source_trigger_continuity_gate_test.dart test\nied_source_estimation_driver_test.dart test\source_estimator_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=tomakomai --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=iwate_east --concurrency=1
```

Replay 结果：

| Case | median / p90 | final | 观察 |
|---|---:|---:|---|
| `20260622_tomakomai_south_offshore_m35_hinet` | `11 km / 52 km` | `10 km` | final 深度 `90 km`，assigned set `32`、current raw `4`，接近 reference 深度 `100 km` |
| `20260622_iwate_east_offshore_m30_hinet` | `55 km / 55 km` | `55 km` | final 深度 `10 km`，assigned set `10`、current raw `9`；深漂消失，但稳定卡在错误 shallow id |

结论：

- 苫小牧证明 persistent detection-id station set 是必要的：后期 S-rich /
  深源支持不会因当前 cluster 变小而丢失。
- 岩手证明这仍不是完整复刻。现在剩下的缺口更具体：`検出id4-2_適用id震源から候補選択`
  的候选进入、`検出id_同一震源統合` 的 same-source merge、以及
  `ten:推定用 +3` 的清退规则。
- 深度搜索不能标记为完成。搜索本身在跑，苫小牧能推出接近参考的深度；但
  detection-id 状态机仍可能把浅源错误 id 稳定下来。

## Detection-id station-set no-loss timing and clear/removal pass

继续复刻 Scratch `ten:推定用 +3` 后，确认前一版还有一个 Dart 侧偏差：
kotoho7 本地 assigned station set 虽然已经存在，但读取 `allTimingUsable`
时仍经过共享 `_usableTimingRecords` 的 24 站 earliest/strongest 裁剪。Scratch
的 `ten:推定用` 是 detection-id 自己的持久表，已经挂到该 id 的站不应因为
全局裁剪而从 HYP 输入里消失。

实现：

- kotoho7 replay 内部读取 uncapped timing records；其他 estimator 仍保留默认
  24 站裁剪；
- assigned timing 因此能保留当前/source-member 站，再进入 HYP 评分；
- 增加保守 clear/removal pass，近似 `推定用tenPS時間計算` 清空 `+7/+8`：
  不再属于当前成员、且不再符合当前 `4-4` source cache 的 P/S 到时窗口时，
  从本地 assigned set 清退；
- first detected station 作为 detection-id anchor 被保护，不参与普通清退；
- diagnostics 增加 `last_assignment_removed_count` 与
  `last_assignment_removed_station_codes`。

验证：

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart test\seismic_source_tracker_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=iwate_east --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=tomakomai --concurrency=1
```

最新 replay：

| Case | kotoho7 median / p90 | kotoho7 final | 深度 | 观察 |
|---|---:|---:|---:|---|
| `20260622_iwate_east_offshore_m30_hinet` | `10 km / 44 km` | `11 km` | `10 km` | assigned `28`，P/S/O `11/13/4`，不再 low-support hold |
| `20260622_tomakomai_south_offshore_m35_hinet` | `11 km / 23.2 km` | `11 km` | `60 km` | assigned `39`，P/S/O `7/25/7`，clear pass 在 1 帧清退 2 站 |

结论：

- 岩手此前的大问题不是 HYP 分数，而是 assigned/source-member timing 被全局
  24 站裁剪提前丢掉；
- clear/removal pass 对岩手/苫小牧两个压力样本安全，但仍是 Dart 侧对
  Scratch `grid/ten/4-3/4-4` 表的近似；
- 下一步仍应补 `検出id4-2_適用id震源から候補選択` 的完整候选选择与
  `検出id_同一震源統合`，而不是继续调 HYP score。

## Existing source-cache candidate selection and same-source merge scaffold

继续补 Scratch detection-id 管线，这次实现的是 `検出id4-2_適用id震源から候補選択`
和 `検出id_同一震源統合` 的最小可验证 Dart 侧形态。

实现：

- `Kotoho7ReferenceHypSourceEstimator` 不再只按当前 `sourceId:eventId` 新建
  state；当当前 key 没有 state 时，会扫描已有 kotoho7 source caches；
- 对每个候选 source cache，按 Scratch 4-2 的相位窗口计算当前站的 residual：
  先用 P 预测，到时不在 `5 + distance/120` 容差内再看 S，仍不满足则拒绝；
- 候选需要至少 3 个 fit station，并通过 mean/p90 residual gate，才允许当前
  event key 复用已有 source state；
- state 现在记录 `source_keys`，表示多个 event/detection keys 已被合到同一
  kotoho7 source id；
- 增加 same-source merge scaffold：两个本地 state 若 first detection time 接近
  且 source cache 空间距离小于 `50 + assigned radius / 2`，会合并 assigned
  station sets，并移除被合并 key；
- diagnostics 增加 `source_selection_*` 与 `same_source_merge_*` 字段。

新增回归测试：

```powershell
flutter test test\source_estimator_test.dart --concurrency=1
```

## 2026-07-03 update: diagnostic shadow cache for `ten:推定用 +6/+7/+8`

Added a diagnostic-only shadow cache for the Scratch `ten:推定用` phase slots:

- `+6`: S flag
- `+7`: predicted P arrival
- `+8`: predicted S arrival

This is intentionally **not** used by the production HYP result. Production still
uses the current full recompute model:

```text
scratch_suiteitenten_ps_time_recompute_stateful_v1
```

The shadow cache is updated only when a decoded Scratch-like slot event occurs:

- station assignment;
- state-6 rerise re-registering the station through the assignment/count path;
- reset / invalidate / same-source merge clear-copy paths.

The extracted sb3 now includes the previously missing phase-cache procedures:

- `推定用tenPS時間計算(多目的0,2使用) %s %s`
- `検出id_推定PS時間id別再計算 %s`

Decoded `推定用tenPS時間計算` formula:

```text
+7 = source origin offset + JMA2001 P travel time
+8 = source origin offset + JMA2001 S travel time
+6 = abs(+1 - +8) < abs(+1 - +7)
```

Its invalid-source branch clears `+7/+8`; ordinary state-5 `+2` refresh does
not call this procedure.

Execution-order check from the sb3 block graph:

```text
揺れ検出許可
→ 検出許可震度算出
→ 検出id1_全点へ適用
→ 円検出の毎処理
→ broadcast 推定震源計算
→ HYP:震源検出
```

So station membership / `ten:+3` assignment is updated before the HYP source
cache is refreshed. The production Dart full-refresh after HYP is therefore
kept as a next-frame phase-cache update. This is documented as a deliberate
bridge for the sb3-defined but currently uncalled
`検出id_推定PS時間id別再計算`; it should not be confused with the event-only
shadow path.

Hot-path caution:

- `検出id3_点にIDを登録` can decrement an existing `ten:+3` id and increment the
  newly selected id with `距離セット=true`, which would call
  `推定用tenPS時間計算`.
- A replay-runner probe that tries to account for existing-member re-registers
  inside every frame is too expensive for the current benchmark path; keep that
  as a separate offline report instead of adding it to estimator metadata.

The purpose is to compare the event-driven slot lifecycle against the current
production full-refresh behavior without changing estimates.

Fukushima Aizu M4.6 replay result:

| Case | Production final | Shadow rescore at same source | Finding |
|---|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `17.95 km`, depth `40 km`, score `156.05`, `P/S/O=89/20/25` | score `347.52`, `P/S/O=64/13/57` | event-driven shadow remains much worse than production, even after removing the incorrect state-5 `+2` refresh |

Final-frame shadow diagnostics:

- assigned count: `134`
- shadow `+7/+8` count: `112`
- missing shadow `+6` count: `22`
- shadow true-S count: `27`
- production-vs-shadow S flag disagreements: `21`
- mean P-arrival absolute delta: `5.34 s`
- mean S-arrival absolute delta: `10.36 s`

Interpretation:

- A naive event-driven-only `+6/+7/+8` cache should not replace the production
  full-refresh path.
- The gap is now more specifically in when Scratch bulk-recomputes phase cache
  for `ten:+3` members, not in the local HYP search cap.
- Next work should continue reading the article / sb3 procedures around
  `検出id2`, `推定用 +3`, `+6/+7/+8`, and PS cache refresh timing, then use this
  shadow comparison to tell whether the decoded behavior is moving toward or
  away from Scratch.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
python tools\extract_scratch_hyp_algorithm.py
python -m py_compile tools\extract_scratch_hyp_algorithm.py
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
```

## 2026-07-03 update: exact `検出id_消えたidに対応する検出無効化` slot mapping

Decoded the local sb3 block graph for
`検出id_消えたidに対応する検出無効化` instead of relying on the Markdown block-id
summary.

Scratch logic:

```text
if len(@1 grid存在id) == 0:
  clear 4-3 検出id別情報
  clear 4-4 検出id震源要素
else:
  for each 20-slot 4-3 detection-id row:
    if @1 grid存在id contains id:
      if +4 < 200:
        count2 = (3 + +4) * 2
      else:
        count2 = 400

      if +9 < +3 + count2:
        +9 = +3 + count2

      if +9 < now:
        +2 = false
      else:
        +7 = +6

      if now - +3 > 150 and +4 < 50:
        +2 = false

      if +4 < 5 and +5 < 80 and +11 > 3000 and +6 < 3 and now - +3 > 10:
        +2 = false
    else:
      if now - +3 > 2:
        +2 = false
```

Important slot interpretation for the Dart proxy:

- `+2`: active flag (`scratch43Active`);
- `+3`: first/base detection time used for lifetime checks;
- `+4`: assigned/apply count;
- `+5`: max first-station distance proxy;
- `+6`: current max shindo/status proxy;
- `+7`: previous/latched current max shindo, assigned from `+6` when not
  expired;
- `+9`: expiry/lifetime timestamp;
- `+11`: best HYP/source score.

Dart implementation update:

- `_updateScratch43ActiveState` now follows the extracted order:
  grid-presence gate, `+9` extension, `+9` expiry or `+7 = +6`, then the
  150-second and weak-small-id gates.
- Diagnostics now expose the observable slots:
  - `expire_window_s`;
  - `grid_presence_count`;
  - `grid_presence_disappeared_age_s`;
  - `slot_plus_6_current_max_shindo`;
  - `slot_plus_7_previous_max_shindo`.
- The old unused grid-presence helper was removed after replacing it with the
  direct `grid存在id` carrier count.

Remaining protected boundary:

- Scratch's `len(@1 grid存在id) == 0` branch clears all `4-3/4-4` rows. Dart
  still keeps the existing current-frame evidence guard so local replay/capture
  gaps are not misread as a true empty live frame. A future strict-live mode can
  enable this full-clear branch once the frame stream is known complete.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

## 2026-07-03 update: `4-4 検出id震源要素` source-cache slot mapping

Decoded the local sb3 writes to `4-4 検出id震源要素` from:

- `epi最大距離(多目的1)or仮震央(カウント3id)`;
- `HYP:震源検出`;
- `HYP:誤差レベル計算`;
- `検出id_新規id追加`.

Scratch source-cache row:

```text
4-4 offset = (id - 1) * 10

+2 = source longitude X, rounded to 1/60 degree
+3 = source latitude Y, rounded to 1/60 degree
+4 = source depth, rounded km
+5 = source origin time / 発生時刻, rounded cloud-time seconds
```

Initial source-cache seed:

```text
epi最大距離(..., 仮震央=true):
  +2 = rounded average longitude of assigned points
  +3 = rounded average latitude of assigned points
  +4 = 10
  +5 = 4-3 +3
```

`HYP:震源検出` seed decision:

```text
if 4-4 +2 is empty OR now - firstDetection < 10:
  temporary source = first detection station rounded to 1/60 degree
  depth = 10
  origin = firstDetection - 2
else:
  temporary source = 4-4 +2/+3/+4/+5
```

Search stages from `HYP:震源検出`:

```text
if 4-3 +4 > 10:
  start-h2: horizontal step 0.5, no depth step
  limit = 30 - (age < 5) * (15 + 14 * (4-3 +4 < 10))

start-h10: horizontal step 0.1, no depth step
limit = 80 - (age < 5) * (40 + 34 * (4-3 +4 < 10))

start-h10-v50: horizontal step 0.1, depth step 50, limit 100
start-h10-v10: horizontal step 0.1, depth step 10, limit 100
start-h60: horizontal step 1/60, no depth step, limit 10
```

Implementation update:

- Dart now uses the exact `<10s` reseed condition, not `<=10s`.
- `start-h2` is now skipped unless the assigned/detected count is greater than
  10, matching `4-3 +4 > 10`.
- Diagnostics now expose `stateful_source_cache.scratch_4_4_source_cache` with:
  - seed mode (`slot +2 empty`, `<10s reseed`, or reuse previous source);
  - `+2/+3/+4/+5` source-cache proxy fields;
  - Scratch stage limits and whether `start-h2` was enabled.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

## 2026-07-03 update: `HYP:誤差レベル計算` score-component diagnostics

Decoded the final score expressions in the local sb3 `HYP:誤差レベル計算`.

Important Scratch expressions:

```text
weightedResidualSquares += weight * (originTime - meanOriginTime)^2
weightSum += weight

if len(unarrivedList) > 0:
  for each unarrived predicted P:
    if predictedArrival + meanOriginTime < now:
      weightedResidualSquares += 1

SFactor = 1 - (SCount * 3 / detectedTimeListLength)
if SFactor < 0.25:
  SFactor = 0.25

stationCountScale =
  30
  + 20000 / (1 + detectedTimeListLength^2)
  + 2000 / (50 + detectedTimeListLength)

errorLevel =
  SFactor
  * ((weightedResidualSquares + unarrivedCount) / weightSum)
  * stationCountScale

if errorLevel < minErrorLevel:
  update candidate lon/lat/depth/origin and first-detection distance
```

Clarification:

- `@hyp:Sカウント` is transformed into a multiplier, not merely reported as a
  phase count.
- More S-classified stations reduce the final error level, but only down to
  `0.25`.
- The unarrived branch is count-like: each predicted-arrived but undetected
  station contributes `+1`.

Dart status:

- `_scoreKotoho7HypCandidate` already follows this Scratch score shape:
  weighted origin-time variance, count-like unarrived penalty, S-factor floor,
  and station-count scale.
- Added diagnostics under:
  - `scratch_error_level_components`;
  - each search stage row.
- Exposed fields:
  - `s_factor`;
  - `s_flag_count`;
  - `weighted_residual_squares`;
  - `weight_sum`;
  - `station_count_scale`;
  - `unarrived_gate_open`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

## 2026-07-03 update: `HYP:誤差レベル計算` stop gates and grid-scan boundary

Decoded the front-half gate and grid scanning conditions in the local sb3
`HYP:誤差レベル計算`.

Candidate stop gates:

```text
stop if depth < 10
stop if depth > 700
stop if depth > @hyp:許可最大深さ
stop if longitude < 115 or longitude > 155
stop if latitude < 15 or latitude > 55
stop if distance(candidate, firstDetectedStation) > @hyp:許可最大距離
```

Scratch allowed-depth / allowed-distance setup from `HYP:震源検出`:

```text
@hyp:許可最大深さ =
  round(11 + (4-3 +5)^3 * 0.00008)

@hyp:許可最大距離 =
  round(50 + 0.3 * ((4-3 +4) * 10 + 4-3 +5))
```

Grid scan behavior:

```text
for each populated grid:
  compute distance from candidate to grid center

  scan points in the grid if:
    grid:検出id[grid] > 0
    OR gridDistance < PRadius + 130

  if point ten:+3 == target id:
    add detected origin-time sample and weight
  else:
    if 4-3 +4 < 30 OR random thinning accepts this point:
      if pointDistance < PRadius + 30
         OR (point's grid id == target id AND random(1,2) == 1):
        add predicted P travel time to unarrived list
```

Current Dart boundary:

- `_scoreKotoho7HypCandidate` is deterministic and does not use Scratch's
  random grid thinning.
- It scores the assigned timing records as detected samples, and receives a
  deterministic `unarrived` record list from the replay/request layer.
- The unarrived list is still filtered by the Scratch-like
  `maxDetectedDistance + 30 km` radius before count-like penalties are applied.

Added diagnostics:

- `reject_reason` for invalid candidates:
  - `scratch_stop_depth_lt_10`;
  - `scratch_stop_depth_gt_700`;
  - `scratch_stop_depth_gt_allowed_max`;
  - `scratch_stop_distance_from_first_gt_allowed_max`;
  - `scratch_stop_no_detected_time_samples`.
- `distance_from_first_detected_km`;
- `max_allowed_depth_km`;
- `max_allowed_distance_km`;
- `unarrived_input_count`;
- `unarrived_within_radius_count`;
- `grid_scan_proxy` description.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

## 2026-07-03 update: deterministic Scratch grid-scan proxy diagnostics

Added a diagnostic-only deterministic proxy for the Scratch grid scan inside
`HYP:誤差レベル計算`.

Why diagnostic-only:

- Scratch scans populated grids and uses random thinning for non-target points
  when the detection count is high.
- Reproducing that randomness inside production scoring would make replay
  comparisons noisy.
- The new proxy therefore counts what the Scratch-like grid scan would consider,
  but it does not replace the current scoring inputs yet.

Proxy behavior:

```text
for each populated grid:
  scan grid if:
    grid has any active detection id
    OR grid distance from candidate source < P-surface-radius + 130 km

  target-id station:
    counted as detected if it has timing

  non-target station:
    counted as deterministic unarrived candidate if:
      station distance < P-surface-radius + 30 km
      OR station is in a grid currently carried by the target id
```

Diagnostics exposed under
`scratch_error_level_components.grid_scan_proxy_diagnostics`:

- `p_surface_radius_km`;
- `source_elapsed_s`;
- `grid_count`;
- `scanned_grid_count`;
- `scanned_point_count`;
- `detected_sample_count`;
- `detected_without_timing_count`;
- `current_assigned_timing_count`;
- `non_target_scanned_count`;
- `deterministic_unarrived_candidate_count`;
- `deterministic_unarrived_inactive_count`;
- `deterministic_unarrived_active_or_other_count`;
- `target_grid_fallback_candidate_count`;
- `current_unarrived_input_count`;
- `random_thinning_bypassed_count`;
- `sample`.

Current boundary:

- This is still a diagnostic proxy. `_scoreKotoho7HypCandidate` continues to
  score assigned timing records plus the deterministic request/replay unarrived
  list.
- Next step is to add an experiment branch that feeds the deterministic
  grid-scan detected/unarrived sets into scoring and compares it against the
  current input model.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

## 2026-07-03 update: deterministic grid-scan score comparison branch

Extended the diagnostic-only Scratch grid-scan proxy so it now returns:

- deterministic detected records;
- deterministic inactive unarrived candidate records;
- the previous grid-scan count diagnostics.

The final best source is then rescored with those deterministic grid-scan sets
using `_scoreKotoho7HypCandidate`, without changing the production estimate.

Diagnostics exposed under
`scratch_error_level_components.grid_scan_score_comparison`:

- `status`;
- `current_score`;
- `grid_scan_score`;
- `score_delta`;
- `current_detected_count`;
- `grid_scan_detected_count`;
- `current_unarrived_penalty`;
- `grid_scan_unarrived_penalty`;
- `grid_scan_unarrived_input_count`;
- `grid_scan_unarrived_within_radius_count`;
- `current_s_factor`;
- `grid_scan_s_factor`;
- `current_weight_sum`;
- `grid_scan_weight_sum`;
- `grid_scan_phase_mean_residual_s`;
- `grid_scan_phase_p_count`;
- `grid_scan_phase_s_count`;
- `grid_scan_phase_other_count`;
- `grid_scan_reject_reason`.

Current boundary:

- The branch rescored the already-selected final source. It does not yet run
  the full staged HYP local search with grid-scan detected/unarrived sets.
- Random thinning remains disabled; this remains deterministic for replay
  comparability.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
flutter test test\iwate_offshore_reference_replay_test.dart --concurrency=1
```

## 2026-07-03 update: capped deterministic grid-scan staged search comparison

Added a parallel diagnostic search branch that runs a capped staged local search
where each candidate is scored from deterministic Scratch grid-scan
detected/unarrived sets.

This is still diagnostic-only:

- production `SourceEstimate` remains the current `best`;
- no random thinning is enabled;
- the search is capped for replay latency:
  - h2: max `8`;
  - h10: max `12`;
  - v50: max `16`;
  - v10: max `16`;
  - h60: max `6`.

Diagnostics exposed under
`scratch_error_level_components.grid_scan_search_comparison`:

- current vs grid-scan lat/lon/depth/origin/score;
- horizontal shift and depth delta;
- grid-scan residual, phase counts, unarrived penalty, S-factor, weight sum;
- per-stage capped search rows.

Boundary:

- This branch now performs candidate-by-candidate grid-scan scoring, unlike the
  previous final-source-only rescore.
- It is still capped and deterministic, so it is not yet a full Scratch runtime
  reproduction.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
flutter test test\iwate_offshore_reference_replay_test.dart --concurrency=1
```

其中 `kotoho7 replay reuses an existing detection-id source cache` 会先建立
`event-a` 的 source cache，再让 `event-b` 用同一批站点进入，确认：

- `source_selection_model =
  scratch_detection_id_4_2_existing_source_cache_candidate_v1`
- `source_selection_selected_key = nied:event-a`
- `source_keys` 同时包含 `nied:event-a` 与 `nied:event-b`

Replay 回归：

```powershell
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=iwate_east --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=tomakomai --concurrency=1
```

结果与上一轮保持：

| Case | kotoho7 median / p90 | kotoho7 final | 观察 |
|---|---:|---:|---|
| `20260622_iwate_east_offshore_m30_hinet` | `10 km / 44 km` | `11 km` | 单 eventId replay，selection/merge 未触发 |
| `20260622_tomakomai_south_offshore_m35_hinet` | `11 km / 23.2 km` | `11 km` | 单 eventId replay，selection/merge 未触发 |

当前结论：

- `検出id4-2` 的“从已有 source cache 选择适用 id”已经有可执行路径和测试；
- `検出id_同一震源統合` 已有 station-set 合并 scaffold；
- 真正还缺的是更完整的 Scratch 4-3 metadata 字段复制/比较，以及在真实多
  detection-id replay 中验证 merge 触发路径。

## `4-3` metadata proxy and real raw/effective id audit

继续补 `検出id_同一震源統合` 后，Dart state 现在不只合并 assigned station
set，也维护一个 `scratch_4_3_proxy`，用于记录 Scratch `4-3 検出id別情報`
里会影响合并/清退/候选选择的核心字段。

实现：

- `scratch_4_3_proxy.first_detection_at`：proxy for first detection time；
- `scratch_4_3_proxy.last_detection_at` 与 `stale_age_ms`：proxy for
  `4-3 +11` stale/age 判断；
- `scratch_4_3_proxy.assigned_count`：当前 `ten:推定用 +3` assigned station
  count；
- `scratch_4_3_proxy.max_first_station_distance_km`：proxy for `4-3 +5`
  max first-detected-station expansion distance；
- `scratch_4_3_proxy.best_score` /
  `best_phase_mean_residual_s` / `best_source_keys`：proxy for copied best
  quality metadata；
- same-source merge now copies/compares metadata by:
  - earlier `first_detection_at`;
  - later `last_detection_at`;
  - max `max_first_station_distance_km`;
  - max assigned count;
  - lower best score, and copies that source cache as the better cache.

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=iwate_east --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=tomakomai --concurrency=1
flutter test test\iwate_east_offshore_reference_replay_test.dart --concurrency=1
```

Replay metrics remain unchanged:

| Case | kotoho7 median / p90 | kotoho7 final | 4-3 proxy |
|---|---:|---:|---|
| `20260622_iwate_east_offshore_m30_hinet` | `10 km / 44 km` | `11 km` | assigned `28`, max first-station distance `131.1 km`, best score `58.474` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `11 km / 23.2 km` | `11 km` | assigned `39`, max first-station distance `204.3 km`, best score `43.513` |

Real multi-id audit:

- `.dart_tool/event_detection_benchmark/20260622_iwate_east_offshore_m30_hinet.reference.json`
  contains multiple raw ids.
- The production-style `SourceEstimationBenchmarkRunner` for the same case shows
  raw continuity ids:
  - `nied_gif-2026-06-22T11:27:05.000`: `43` frames;
  - `nied_gif-2026-06-22T11:28:20.000`: `9` frames.
- But effective id is held as
  `nied_gif-2026-06-22T11:27:05.000` for `106` frames, with `13` held
  replacement frames.
- Therefore kotoho7 `source_selection_model` remains
  `current_key_existing_state` after the first frame and `same_source_merge`
  does not naturally trigger in the production-style replay. This is expected:
  continuity has already done the id hold before kotoho7 receives the frame.

Next step:

- Add a raw-id diagnostic replay mode or script that feeds
  `source_trigger_continuity_raw_event_id` into kotoho7 while preserving
  production metadata. That is the right place to verify natural
  `検出id4-2` selection / `検出id_同一震源統合` merge on real multi-id data,
  without changing production effective-id behavior.

## Raw-id diagnostic replay path

Implemented the diagnostic path described above without changing the production
effective-id kotoho7 replay:

- Added `SourceEstimationBenchmarkRunner.kotoho7RawIdDiagnosticMethod`:
  `nied_gif_hyp_kotoho7_reference_raw_id_diagnostic_v1`.
- This method uses the same `Kotoho7ReferenceHypSourceEstimator`, but feeds
  `rawSourceEventDetection.eventId` as the event id.
- `SeismicSourceTracker.ingestFrame` gained a default-off
  `splitOnEventIdChange` option. It is enabled only for the raw-id diagnostic
  path, so raw id changes create a new tracker event while the estimator's
  internal kotoho7 source-cache states remain available for 4-2 selection /
  same-source merge.
- Candidate raw frames are allowed into the diagnostic path by using the raw
  detection state's stage name; production effective-id replay still uses the
  existing `SourceEstimationTriggerGate` ingest behavior.
- Added `tools/build_kotoho7_raw_id_diagnostic_report.dart` to scan
  `.dart_tool/source_estimation_benchmark/*.json` and summarize raw/effective
  id counts, raw existing-source selections, raw merges, and final estimates.

Validation:

```powershell
flutter analyze lib\core\source_estimation\seismic_source_tracker.dart test\support\source_estimation_benchmark.dart
flutter test test\iwate_east_offshore_reference_replay_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\iwate_offshore_m30_reference_replay_test.dart --concurrency=1
flutter analyze tools\build_kotoho7_raw_id_diagnostic_report.dart
dart run tools\build_kotoho7_raw_id_diagnostic_report.dart
```

Current report summary:

```text
caseCount=14
casesWithRawMultiId=5
casesWithRawSelection=0
casesWithRawMerge=0
```

Important real-case findings:

- `20260622_iwate_east_offshore_m30_hinet`:
  - production effective-id replay remains unchanged: final `11 km`;
  - raw diagnostic now creates a second raw-id kotoho7 event at
    `2026-06-22T11:28:20.000`;
  - that raw replacement does **not** pass existing-source selection or merge;
    last raw diagnostic error is `66 km`, so the current gate correctly avoids
    merging a later poor replacement cluster into the good source.
- `20260622_iwate_offshore_m30_eq10`:
  - raw ids: `09:28:49` and `09:30:02`;
  - raw diagnostic creates the later raw event, but does not merge it;
    last raw diagnostic error is `76 km`.
- `20260622_tomakomai_south_offshore_m35_hinet`:
  - source benchmark has only one raw id; raw diagnostic final is `8 km`,
    production effective-id final remains `11 km`.

Conclusion:

- The raw-id diagnostic path is now available and proves that the current
  4-2/merge gate is conservative on real held-replacement data.
- We still need either a real case where raw ids are close enough to be true
  same-source fragments, or a dedicated fixture that simulates such a split,
  to exercise natural `same_source_merge_count > 0`.

## 2026-07-02 article S-flag source-cache correction and P2PQuake check

Re-reading the article/Scratch extracted blocks after the within-retention
P2PQuake captures showed one more important semantic mismatch in the Dart
kotoho7 reference replay.

The Scratch `ten:推定用 +6` S flag is not recomputed independently for every
candidate inside `HYP:誤差レベル計算`. It is maintained by the detection-id
state machine from the current `4-4 検出id震源要素` source cache:

```text
+7 = sourceCacheOrigin + JMA2001(sourceCacheDistance, sourceCacheDepth, P)
+8 = sourceCacheOrigin + JMA2001(sourceCacheDistance, sourceCacheDepth, S)
+6 = abs(observedTime - +8) < abs(observedTime - +7)
```

Then HYP consumes that fixed flag during the staged neighbor search:

```text
useS = now > firstDetection + 15s && ten:推定用[station + 6]
```

Previous Dart code used the candidate currently being scored to derive the
S flag. That made phase assignment move together with the candidate and was
not faithful to the article/Scratch state-machine semantics. The reference path
now freezes a `phaseReference = state.sourceCache` before a HYP search and uses
that source cache for the `+6` proxy while candidates only affect the actual
P/S travel-time residual being scored.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

New within-3h P2PQuake/JMA reference captures:

| Case | GIFs | kotoho7 best | kotoho7 median / p90 | kotoho7 final | Depth observation |
|---|---:|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `302/302` | `3 km` | `103 km / 278 km` | `81 km` | Early HYP locks the epicenter well at `40 km`, but late membership pollution pushes final to `70 km` and far west. JMA/P2P reference depth is `150 km`. |
| `20260702_shizuoka_west_m36_jma_p2p` | `302/302` | `2 km` | `4.5 km / 9 km` | `3 km` | Final depth becomes `20 km`, closer to the JMA/P2P reference `30 km` than the previous `10 km`. |

Interpretation:

- The article HYP/depth search is running. Static proof: shallow Shizuoka
  improves and the best Fukushima early frame reaches a strong epicentral fit.
- The remaining Fukushima failure is not primarily a missing `±50/±10 km`
  depth search. By the final frame the assigned station set has grown to
  `100+` stations with many residual outliers (`P/S/O = 44/18/42`), and the
  source cache no longer represents the same clean detection id.
- Therefore the next faithful-replication target remains Scratch detection-id
  membership, especially `検出id4-2_適用id震源から候補選択` and the clear/removal
  behavior around `ten:推定用 +3/+4/+5/+6/+7/+8`. Continuing to tune HYP score
  or depth regularization would hide the state-machine mismatch rather than
  reproducing the article.

## 2026-07-02 Scratch `検出id4-2` station selection replication pass

The next replication pass replaced the Dart-only station membership heuristics
inside `Kotoho7ReferenceHypSourceEstimator` with a closer Scratch
`検出id4-2_適用id震源から候補選択` proxy.

Confirmed directly from the sb3/project.json blocks:

- `検出id4-2_適用id震源から候補選択` does not accept a station simply because it
  is near an already assigned station. It compares the station against candidate
  detection-id source caches and chooses the candidate with the smallest P/S
  arrival residual.
- The P window is `5 + distance / 120` seconds.
- If P does not fit, the S window is checked; values outside
  `[PArrival - PTolerance, SArrival + (8 + distance / 120)]` are rejected.
- HYP `@hyp:誤差レベル` is not a plain raw weighted-squared sum. The sb3 block
  `azB` is:

```text
SFactor * ((weightedResidualSquares + unarrivedCount) / weightSum)
  * (30 + 20000 / (1 + n^2) + 2000 / (50 + n))
```

where:

```text
SFactor = max(0.25, 1 - SCount * 3 / n)
```

Therefore the existing S-factor and station-count scale are part of the
Scratch implementation, not an external Dart tuning term.

Code changes in this pass:

- Removed the previous kotoho7 reference-path global recovery sweep that scanned
  all timing records and added up to 24 residual-fitting stations.
- Removed the near-assigned-station `35 km` absorption rule from kotoho7
  reference membership.
- Added Scratch-like station candidate selection against source-cache/first-
  station candidates with the P/S windows above.
- Added benchmark metadata `source_trigger_raw_member_ids` and a
  `kotoho7_prefer_raw_member_ids` switch so reference replay can avoid using
  continuity-held member buckets when raw detection-id members are available.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Latest benchmark results with the sb3 `azB` score restored:

| Case | kotoho7 best | kotoho7 median / p90 | kotoho7 final | Final depth | Observation |
|---|---:|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `8 km` | `100 km / 278 km` | `94 km` | `80 km` | Early source is good, but final still accumulates `136` assigned stations and drifts. This is now a `ten:推定用 +3` lifecycle / detection-id membership problem, not an HYP formula mismatch. |
| `20260702_shizuoka_west_m36_jma_p2p` | `3 km` | `5.5 km / 9 km` | `3 km` | `20 km` | Stable and close to JMA/P2P reference (`30 km` depth). |

Next faithful-replication target:

- Continue extracting the station lifecycle around `ten:推定用 +3` writes,
  overwrites, and clearing. The current Dart state keeps historical assigned
  stations once accepted; Fukushima shows that this over-retention can dominate
  the late HYP solution.
- Do not replace this with an ad-hoc depth regularizer. The remaining mismatch
  is upstream of depth scoring: which station rows are allowed to remain in the
  detection-id HYP sample.

## 2026-07-02 correction: reset is station-state based, not HYP residual based

A follow-up inspection of the actual sb3 procedure order corrected an important
wrong turn in the Dart reproduction.

The Scratch reset path is:

```text
検出id2_各点の許可idと推定用をセット
  -> 検出id3_点にIDを登録
  -> 検出id_点の推定用をリセット
```

`検出id_点の推定用をリセット` clears:

```text
ten:推定用 +1
ten:推定用 +2
ten:推定用 +3
ten:推定用 +4
ten:推定用 +6
ten:推定用 +7
ten:推定用 +8
```

The reset is driven by station lifecycle/status conditions, not by rescoring
the station against the HYP candidate:

- current `ten:震度[$番号] <= 0` while `ten:推定用 +1` exists;
- detection-id list is empty or the assigned id is no longer active;
- long stale conditions such as `now - (+2) > 200s`, or the more restrictive
  `90s` branch when station state/change-speed conditions are also false;
- registering a point to an id fails.

Therefore the Dart attempt to re-evaluate already-assigned stations against
source-cache P/S residuals was not faithful and was removed. The reference path
now uses a closer station-state reset proxy:

- assigned stations are removed when their current record is no longer
  `isActiveLike`, corresponding to Scratch `ten:震度 <= 0`;
- assigned stations are removed if their `lastObservedAt` is stale beyond the
  Scratch `200s` long-timeout branch;
- new station entry still uses the Scratch-like `検出id4-2` P/S arrival-window
  selection.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Result after this correction:

| Case | best | median / p90 | final | Depth note |
|---|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `4 km` | `25.5 km / 278 km` | `65 km` | Best depth is `130 km`, close to the JMA/P2P `150 km`; final remains imperfect but station over-retention is much lower (`40` assigned at final). |
| `20260702_shizuoka_west_m36_jma_p2p` | `4 km` | `9 km / 13 km` | `10 km` | Final worsens compared with the retention-heavy version, but this is the expected cost of following Scratch-style station reset rather than keeping stale stations for stability. |

Next target:

- Implement more of the exact `検出id2_各点の許可idと推定用をセット` station state
  machine instead of relying only on `isActiveLike`.
- In particular, map Scratch station states `5/6`, `変化速度`, `+2` update time,
  and the `90s` stale branch to our GIF-derived station record fields.

## 2026-07-02 update: `検出id2` station lifecycle cache (`+1/+2`, state `5/6`)

The sb3 block inspection for `検出id2_各点の許可idと推定用をセット %s %s %s %s`
shows that the previous `isActiveLike` reset proxy was too coarse. The relevant
Scratch inputs are:

```text
番号, 変化速度, 現在状態, 7点スタート
```

and the important branch structure is:

```text
if 0 < ten:震度[番号]:
  update ten:推定用 +5 while the recent shindo-history delta is positive

  if 現在状態 != 6 and ten:推定用 +1 == '':
    when neighboring permitted stations support the point:
      ten:推定用 +1 = pre-trigger cache or now
      ten:推定用 +2 = same time
      検出id3_点にIDを登録

  else if 現在状態 > 3.5 and 変化速度 > 0:
    for state 5/6 re-acceleration:
      state 5 refreshes ten:推定用 +2
      state 6 can become state 5 and refresh +1/+2

  else:
    reset if now - +2 > 200s
    reset if now - +2 > 90s
      and 現在状態 < 2
      and 変化速度 <= 0
      and now - +1 > 10s
      and now - 揺れ検出トリガー時間 > 10s

  if 現在状態 == 5 and +2 is old:
    set station state to 6
else:
  if ten:推定用 +1 exists:
    reset
```

`ten:震度` is not continuous JMA shindo. It is the 30-step shindo index
(`震度30`) written by `ten震度更新`; `点震度の処理` only enters its active branch
when `0 < 震度`, then stores that value into `ten:震度`. Therefore the Dart GIF
mapping is:

- `ten:震度 > 0` -> `lastRawLevel > 0`;
- fallback when raw level is unavailable: `lastDetectLevel > 0` or
  `lastValue > -3.0`;
- `変化速度 > 0` -> `lastAscend > 0`.

The reference estimator now keeps a per-source station lifecycle cache:

- `scratchStationFirstUseAt` as `ten:推定用 +1`;
- `scratchStationLastUpdateAt` as `ten:推定用 +2`;
- `scratchStationPermissionState` for Scratch-like state `5/6`.

This replaces the earlier direct `isActiveLike` reset. Diagnostics now expose
`stateful_source_cache.station_lifecycle` with state counts, sample `+1/+2`
rows, and max `+2` age.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Result after the `検出id2` lifecycle cache:

| Case | best | median / p90 | final | Lifecycle observation |
|---|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `8 km` | `100 km / 278 km` | `94 km` | Final keeps `135` assigned stations (`118` state 6, `17` state 5), max `+2` age `86s`; this shows the remaining mismatch is probably the exact `検出id3/+3` and inactive-id clearing path, not a depth-score issue. |
| `20260702_shizuoka_west_m36_jma_p2p` | `3 km` | `5.5 km / 9 km` | `3 km` | Final keeps `95` assigned stations (`59` state 6, `36` state 5), and remains stable near the JMA/P2P reference. |

Next faithful-replication target:

- Continue from `検出id3_点にIDを登録`, `検出id適用数カウント追加`,
  and the `4-3 検出id別情報` inactive-id branch. Fukushima's late over-retention
  is now visible as a `ten:+3`/active-id lifecycle problem: the station state
  cache itself is keeping `+2` under the 90/200s reset limits, so the remaining
  clearing must come from id registration/count/inactive-id semantics.

## 2026-07-02 update: `検出id3` / `検出id適用数カウント追加` / `4-3 +2` active gate

The next sb3 pass inspected:

```text
検出id3_点にIDを登録
検出id適用数カウント追加
検出id_消えたidに対応する検出無効化
検出id1_全点へ適用
```

Confirmed Scratch semantics:

- `検出id3_点にIDを登録`:
  - if the point already has `ten:推定用 +3`, it first calls
    `検出id適用数カウント追加(..., 変更数=-1)`;
  - it then selects or creates an id and writes `ten:推定用 +3`;
  - finally it calls `検出id適用数カウント追加(..., 距離セット=true, 変更数=+1)`.
- `検出id適用数カウント追加`:
  - uses `4-3 検出id別情報[(id-1)*20 + 2]` as the active flag;
  - only when active does it update `4-3 +4` assigned count and, when requested,
    recompute `ten:+7/+8/+6` and `ten:+4` distance;
  - if the id is inactive and the change is positive, it resets the point.
- `検出id1_全点へ適用` sets `4-3 +2 = false` when active id count `+4 < 2`.
- `検出id_消えたidに対応する検出無効化` additionally sets `4-3 +2 = false`
  for:
  - id missing from `grid存在id` after 2s;
  - `now > 4-3 +9` expiry;
  - age > 150s and assigned count < 50;
  - small/weak/bad-score detections:
    `count < 5`, `4-3+5 < 80`, `4-3+11 > 3000`, `4-3+6 < 3`, age > 10s.

Dart reference changes:

- Added `scratch43Active`, `scratch43InactiveAt`, `scratch43InactiveReason`,
  and `scratch43ExpireAt` to the kotoho7 state.
- The reference path now blocks HYP when the proxy `4-3 +2` is inactive.
- `ten:震度` reset now reads the current observation-history frame when
  available, because `lastRawLevel` is a stale last-known value in Dart, while
  Scratch `ten:震度` is the current list value.
- Synthetic tests without current GIF frame history skip the current-frame
  active expiry proxy and fall back to the record fields; this keeps the
  non-replay source-cache unit test meaningful.

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay result after the active gate:

| Case | best | median / p90 | final | Active-gate observation |
|---|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `8 km` | `100 km / 278 km` | `94 km` | No inactive trigger. Final remains active with `135` assigned stations; `+9` expiry extends to `2026-07-02T20:53:10` because count growth extends the Scratch expiry window. |
| `20260702_shizuoka_west_m36_jma_p2p` | `3 km` | `5.5 km / 9 km` | `3 km` | No inactive trigger. Final remains active with `95` assigned stations; `+9` expiry extends to `2026-07-02T20:17:06`. |

Interpretation:

- This pass is useful even though the headline metrics did not change: the
  remaining Fukushima over-retention is not caused by the basic `4-3 +2`
  inactive rules.
- The next difference is narrower: reproduce `grid存在id` and `grid:検出id`
  more literally, and audit why distant weak stations enter `ten:+3` in the
  first place. In particular, continue through
  `検出id4_点に適用するべきIDを検索`, `検出id_グリッド別idと存在idをセット`,
  and `検出id_周囲gridの最新ID検索`.

## 2026-07-02 update: `grid:検出id` carrier and `検出id4` entry-source diagnostics

The next pass followed the sb3 / article carrier path rather than HYP scoring.
The implemented proxy follows this `検出id4_点に適用するべきIDを検索` order:

```text
1. current grid id, when grid:検出id for the point was updated within 2s
2. 検出id4-2_適用id震源から候補選択
3. 周囲grid latest id fallback
```

The full Scratch project has more exact data structures (`dc ten:点からグリッド番号`,
`dc grid:グリッドに含まれる点番号`, 9-grid neighborhood, and the 70-point grid
carrier). The Dart reference path now has a diagnostic proxy:

- `_scratchGridByStationCode`, a station-code based stand-in for
  `grid:検出id` / `grid:検出id時間`;
- selection source labels:
  - `scratch_grid_current`;
  - `scratch_4_2_source_cache`;
  - `scratch_grid_around`;
  - `no_candidate`;
- diagnostics under
  `stateful_source_cache.station_assignment_selection`.

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay result:

| Case | best | median / p90 | final | Entry-source finding |
|---|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `8 km` | `97 km / 278 km` | `16 km` | Aggregate added sources: `scratch_4_2_source_cache=136`, `scratch_grid_around=30`, `no_candidate rejects=12`. Final assigned `160` stations; improvement came from carrier/source-cache evolution, but over-retention still mostly enters through `4-2`. |
| `20260702_shizuoka_west_m36_jma_p2p` | `3 km` | `5.5 km / 9 km` | `3 km` | Aggregate added sources: `scratch_4_2_source_cache=91`, `no_candidate rejects=3`; stable final with assigned `95`. |

Interpretation:

- Fukushima's late over-retention is now attributed mostly to
  `検出id4-2_適用id震源から候補選択`, not to the current-grid carrier.
- The around-grid proxy helps Fukushima final location, but it is still only a
  station-code stand-in for Scratch's actual grid arrays.
- Next faithful-replication target:
  - tighten `検出id4-2` against the exact Scratch conditions around source-cache
    candidate windows;
  - replace the station-code grid proxy with a closer `dc ten:点からグリッド番号`
    / 9-grid neighborhood model;
  - audit how Scratch's `4-3+5` and `4-4+6/+7` source radius constraints limit
    station absorption.

## 2026-07-02 update: `検出id4-2` `+5/+10` split and reason counters

The next pass went back to the generated sb3 extraction instead of tuning HYP
scores. The expanded `検出id4-2_適用id震源から候補選択` condition shows two
different distance gates:

```text
5  = max distance from the first detected station to assigned stations
+10 = max epicentral/source distance proxy used by the old-wide rejection

if station-source distance > 900 km:
  reject when age > 100s and 1.5 * (+10) < distance
  reject when age > 15s  and 1.4 * (+5)  < distance
```

The Dart reference path now keeps these as separate diagnostics:

- `scratch43MaxFirstStationDistanceKm` / `max_first_station_distance_km`
  remains the `4-3 +5` proxy from `検出id距離計算`;
- `scratch43MaxSourceDistanceKm` / `max_source_distance_km` is a new `4-3 +10`
  proxy, initialized at `25 km` and refreshed from the current source cache to
  assigned-station epicentral distances;
- `stateful_source_cache.station_assignment_selection.candidate_reason_counts`
  records why `4-2` accepted or rejected candidates.

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay result:

| Case | best | median / p90 | final | `4-2` reason finding |
|---|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `8 km` | `97 km / 278 km` | `16 km` | Added aggregate remains `scratch_4_2_source_cache=136`, `scratch_grid_around=30`; final assigned `160`. Reason aggregate: `accept_p_window=81`, `accept_s_range=55`, `reject_before_p_window=32`, `reject_after_s_window=10`, no wide-distance rejection. |
| `20260702_shizuoka_west_m36_jma_p2p` | `3 km` | `5.5 km / 9 km` | `3 km` | Added aggregate `scratch_4_2_source_cache=91`; final assigned `95`. Reason aggregate: `accept_p_window=57`, `accept_s_range=34`, `reject_before_p_window=3`, no wide-distance rejection. |

Interpretation:

- The previous proxy had indeed conflated `+5` and `+10`; that is now split in
  the code and diagnostics.
- Fukushima over-retention is not being limited by the wide-distance branch in
  these local P2P replays. Stations enter because they satisfy the Scratch
  P-window or S-range timing condition against an existing source cache.
- The next faithful-replication target should therefore be earlier than HYP
  scoring: reproduce the full grid-number / 9-grid carrier and `grid存在id`
  path that decides which station even reaches `検出id4-2`, and continue
  checking the exact `ten:推定用 +1/+2/+6/+7/+8` PS-time state updates.

## 2026-07-03 update: grid-number carrier and 9-grid latest-id proxy

The next pass followed the sb3 entry path around:

```text
検出id3_点にIDを登録
検出id4_点に適用するべきIDを検索
検出id_周囲gridの最新ID検索
周囲9grid最大震度or上昇
```

Expanded Scratch expressions confirm:

```text
grid number = dc ten:点からグリッド番号[点番号]
grid:検出id[grid number] = ten:推定用[(point-1)*10 + 3]
grid:検出id時間[grid number] = #r:最新クラウド変数[1]

current-grid branch:
  if grid:検出id[grid] > 0 and now - grid:検出id時間[grid] < 2:
    use that id

around-grid latest-id branch:
  scan 9 grids with offsets -24,-23,-22,-1,0,+1,+22,+23,+24
  choose the newest grid:検出id時間
```

The Dart reference path now replaces the previous station-code carrier with a
grid-number carrier:

- `_scratchGridByNumber` stores one carrier entry per grid cell, mirroring
  `grid:検出id` / `grid:検出id時間`;
- current-grid selection reads the current station's grid cell and applies the
  2-second freshness rule;
- around-grid fallback scans the Scratch 23-column 9-grid offsets and chooses
  the newest carrier within 5 seconds;
- diagnostics expose
  `grid_model: grid_number_23_column_025deg_latlon_proxy_v2`.

Important limitation: this is still a proxy. The public replay records do not
carry Scratch's original `dc ten:点からグリッド番号` table, so the Dart path maps
station latitude/longitude to a `0.25°` grid while preserving the Scratch
23-column neighbor offsets. A coarser whole-Japan 23-column grid was tested and
rejected because it collapsed too many stations into only 9 final grid cells and
hurt the Shizuoka replay.

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay result:

| Case | best | median / p90 | final | Grid-carrier finding |
|---|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `8 km` | `97 km / 278 km` | `16 km` | Added aggregate changed to `scratch_4_2_source_cache=113`, `scratch_grid_current=35`, `scratch_grid_around_9=18`; final assigned `160`, final grid carrier size `91`. |
| `20260702_shizuoka_west_m36_jma_p2p` | `3 km` | `5.5 km / 9 km` | `3 km` | Added aggregate `scratch_grid_current=25`, `scratch_4_2_source_cache=66`; final assigned `95`, final grid carrier size `50`. |

Interpretation:

- The entry path is now closer to Scratch than the previous station-code
  carrier, and the stable Shizuoka replay keeps its previous accuracy.
- Fukushima's headline metrics do not improve yet because most late stations
  still satisfy `検出id4-2` P/S timing windows; the grid carrier mainly changes
  attribution and makes the replay trace more faithful.
- Next target should continue within the same upstream area:
  - map/derive a closer `dc ten:点からグリッド番号` table if station ordering can be
    recovered from the sb3 assets;
  - implement the `周囲9grid最大震度or上昇` guard more literally before
    around-grid fallback;
  - continue auditing `ten:推定用 +6/+7/+8` PS-time recomputation because those
    fields decide whether `4-2` accepts as P or S.

## 2026-07-03 update: `周囲9grid最大震度or上昇` guard proxy

The next pass implemented a conservative replay-side proxy for the Scratch guard
called from `検出id4_点に適用するべきIDを検索` before the around-grid latest-id
fallback.

Expanded sb3 condition:

```text
周囲9grid最大震度or上昇(多目的0,1)

if current point is strong enough and the 9-grid surroundings do not provide
enough rise/support, stop before borrowing the surrounding grid's latest id.
```

The exact Scratch data arrays are still not present in the replay package:

- `grid:検出グリッド最大震度`
- `grid:長期上昇観測点数`
- the original `dc ten:点からグリッド番号`

Therefore the Dart path uses the same 0.25-degree / 23-column grid proxy added
in the previous pass and computes the guard from current-frame station records:

- current point level from latest `rawLevel`, then `detectLevel`, then numeric
  `value`;
- surrounding 9-grid max level from current-frame records;
- surrounding rise support from current-frame records with `lastAscend > 0`;
- block around-grid borrowing when the current point is at least `1.5`, is not
  weaker than the surrounding 9-grid max, and surrounding rise support is below
  `10`.

Diagnostics:

```text
stateful_source_cache.station_assignment_selection.model =
  scratch_detection_id4_order_current_grid_4_2_around_9_grid_guard_v3
stateful_source_cache.station_assignment_selection.around_grid_guard_model =
  scratch_surrounding_9_grid_max_shindo_or_rise_proxy_v1
candidate_reason_counts.around_9_grid_guard_current_activity
```

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay result:

| Case | best | median / p90 | final | Guard finding |
|---|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `8 km` | `97 km / 278 km` | `16 km` | `around_9_grid_guard_current_activity=14`; around-grid additions dropped `18 -> 15`, no headline metric change. |
| `20260702_shizuoka_west_m36_jma_p2p` | `3 km` | `5.5 km / 9 km` | `3 km` | `around_9_grid_guard_current_activity=3`; stable case remained unchanged. |

Interpretation:

- The guard is active and does not regress the stable Shizuoka replay.
- Fukushima over-retention still mainly enters through `検出id4-2`
  (`accept_p_window=70`, `accept_s_range=46` in this pass), so the next
  faithful-replication target remains `ten:推定用 +6/+7/+8` PS-time
  recomputation and S/P classification, not score tuning.

## 2026-07-03 update: stateful `推定用tenPS時間計算` cache

The next pass implemented the Scratch `推定用tenPS時間計算(多目的0,2使用)` semantics
as a stateful per-station cache rather than a per-candidate heuristic.

Expanded sb3 offsets:

```text
offset = (id - 1) * 20

if 3000 < 4-3 検出id別情報[offset + 11]
   or 4-4 検出id震源要素[offset/2 + 2] is empty:
  ten:推定用[(point-1)*10 + 7] = empty
  ten:推定用[(point-1)*10 + 8] = empty
else:
  +7 = 4-4 origin + JMA2001(source distance, depth, P)
  +8 = 4-4 origin + JMA2001(source distance, depth, S)
  +6 = abs(+1 - +8) < abs(+1 - +7)
```

Implemented Dart state:

- `scratchStationPArrivalSeconds` mirrors `ten:推定用 +7`;
- `scratchStationSArrivalSeconds` mirrors `ten:推定用 +8`;
- `scratchStationSFlag` mirrors `ten:推定用 +6`;
- after each accepted HYP update, all currently assigned stations are
  recomputed, matching `検出id_推定PS時間id別再計算` for the next frame;
- HYP scoring now uses cached `+6` when available; only the first/no-cache frame
  falls back to computed arrival closeness.

Diagnostics:

```text
stateful_source_cache.station_ps_cache.model =
  scratch_suiteitenten_ps_time_recompute_stateful_v1
scoring_config.station_s_flag_model =
  scratch_stateful_ten_plus_6_from_cached_plus_7_plus_8_v3
```

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay result:

| Case | best | median / p90 | final | PS-cache finding |
|---|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `8 km` | `97 km / 278 km` | `16 km` | Final `+7/+8` cache count `160`, `+6` true count `46`; final HYP phase counts `P=85`, `S=34`, `other=41`. |
| `20260702_shizuoka_west_m36_jma_p2p` | `3 km` | `5.5 km / 9 km` | `3 km` | Final `+7/+8` cache count `95`, `+6` true count `35`; final HYP phase counts `P=57`, `S=27`, `other=11`. |

Interpretation:

- This pass makes P/S classification stateful and reviewable without changing
  the stable headline metrics.
- Fukushima still over-retains stations, but now the trace shows whether each
  station was classified from cached `+6`, and whether it was then accepted as P
  or S after residual gating.
- Next faithful-replication target should inspect the call timing around
  `検出id適用数カウント追加(... 距離セット=true ...)` and
  `検出id_推定PS時間id別再計算(id)`: specifically, whether Scratch recomputes
  `+6/+7/+8` immediately when a station joins, or only after the next source
  cache update in some branches.

## 2026-07-03 update: `検出id適用数カウント追加(... 距離セット=true ...)`

The next pass confirmed and implemented the Scratch immediate side effects for
station assignment.

Expanded sb3 behavior:

```text
検出id3_点にIDを登録:
  before switching ids:
    検出id適用数カウント追加(point, 距離セット=false, -1)
  after writing ten:+3 and grid id/time:
    検出id適用数カウント追加(point, 距離セット=true, +1)

検出id適用数カウント追加(point, 距離セット=true, +1):
  推定用tenPS時間計算(point, id)   # refresh ten:+7/+8/+6
  検出id距離計算(point, offset)   # refresh ten:+4 and 4-3 +5 max
```

Implemented Dart state:

- `scratchStationFirstDistanceKm` now mirrors `ten:推定用 +4`, the distance
  from the first detected station to each assigned station.
- When a station joins an existing kotoho7 detection id, Dart immediately runs
  the single-station equivalent of `推定用tenPS時間計算` and
  `検出id距離計算`.
- The full post-HYP refresh remains in place, matching
  `検出id_推定PS時間id別再計算(id)` after source-cache updates.
- Diagnostics now expose:

```text
stateful_source_cache.station_distance_cache.model =
  scratch_ten_plus_4_first_station_distance_immediate_set_v1
stateful_source_cache.station_ps_cache.last_assignment_immediate_ps_recompute_count
stateful_source_cache.station_distance_cache.last_assignment_immediate_distance_update_count
```

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay result:

| Case | best | median / p90 | final | Immediate-cache finding |
|---|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `8 km` | `97 km / 278 km` | `16 km` | Best frame: immediate PS/distance recompute `18/18`, distance cache `23`; final frame: recompute `2/2`, distance cache `160`, max `+4=341.5 km`. |
| `20260702_shizuoka_west_m36_jma_p2p` | `3 km` | `5.5 km / 9 km` | `3 km` | Best frame: immediate PS/distance recompute `8/8`, distance cache `70`; final frame: recompute `0/0`, distance cache `95`, max `+4=202.9 km`. |

Interpretation:

- The newly joined station path now matches Scratch's `距離セット=true` branch
  instead of waiting only for the later full source-cache refresh.
- Headline metrics stayed unchanged on these two replay cases, which indicates
  this pass closed a state-machine semantic gap rather than masking Fukushima's
  remaining over-retention.
- Next faithful-replication target should continue below this layer:
  `検出id適用数カウント追加(..., -1)` / `検出id_点の推定用をリセット` cleanup
  semantics, including whether `+4/+6/+7/+8` and assigned counts are decremented
  exactly like Scratch when a station switches id or is cleared.

## 2026-07-03 update: `検出id適用数カウント追加(..., -1)` reset accounting

The follow-up pass implemented the negative/reset side of the same Scratch
assignment pipeline.

Scratch behavior being mirrored:

```text
検出id3_点にIDを登録:
  if ten:+3 already exists:
    検出id適用数カウント追加(point, 距離セット=false, -1)

検出id_点の推定用をリセット:
  clear +1/+2/+3/+4/+6/+7/+8
```

Dart changes:

- assigned-station reset now has an explicit reason string rather than only a
  boolean;
- station cleanup goes through a single reset helper, which:
  - removes the point from the Dart `ten:+3` equivalent
    (`assignedStationCodes`);
  - applies an immediate `scratch43AssignedCount -= 1` proxy for
    `検出id適用数カウント追加(..., -1)`;
  - clears `+1/+2`, station permission state, `+6/+7/+8`, and `+4`;
  - clears the grid carrier row for that station;
- diagnostics now expose:

```text
last_assignment_reset_reason_counts
last_assignment_negative_count_delta
last_assignment_reset_cleared_plus3_count
last_assignment_reset_cleared_ps_cache_count
last_assignment_reset_cleared_distance_count
```

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay result:

| Case | best | median / p90 | final | Reset finding |
|---|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `8 km` | `97 km / 278 km` | `16 km` | Reset aggregate: `scratch_reset_current_shindo_zero=2`, negative delta `-2`, cleared `+3/+6/+7/+8/+4` for 2 stations. |
| `20260702_shizuoka_west_m36_jma_p2p` | `3 km` | `5.5 km / 9 km` | `3 km` | Reset aggregate: `scratch_reset_current_shindo_zero=1`, negative delta `-1`, cleared `+3/+6/+7/+8/+4` for 1 station. |

Interpretation:

- The reset path is now visible and stateful, but these two replay cases only
  naturally trigger a few current-shindo-zero resets, so headline metrics remain
  unchanged.
- This confirms the remaining Fukushima over-retention is not solved by the
  basic negative-count cleanup alone.
- Next faithful-replication target should inspect the station switch/reassignment
  branch more deeply: when `検出id4` selects a different active id, Scratch first
  decrements the old id and then increments the new id. The Dart reference path
  currently records non-current selections as rejected during a state's own
  update pass; a closer reproduction needs a point-centric assignment pass that
  can move a station between ids in the same frame.

## 2026-07-03 update: would-switch-to-other-id diagnostic

Before changing assignment behavior, a diagnostic-only pass was added for the
point-centric reassignment hypothesis.

Diagnostic semantics:

- during a state-local assignment update, if `検出id4` selects a different active
  kotoho7 detection id for a station, Dart still rejects it for the current
  state, but now records:
  - station code;
  - selection source;
  - residual;
  - current/source `sourceKeys`;
  - selected/target `sourceKeys`;
  - target assigned count and active flag.

No production assignment behavior changed.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay finding:

| Case | would-switch total | max per frame | Interpretation |
|---|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `0` | `0` | No point naturally selected another active id in this replay. Best frame had only `no_candidate=1`; final had no rejected station. |
| `20260702_shizuoka_west_m36_jma_p2p` | `0` | `0` | No point naturally selected another active id; stable case unchanged. |

Interpretation:

- For these two current P2P replay windows, the remaining Fukushima
  over-retention is not caused by missed old-id/new-id reassignment.
- The next faithful-replication target should shift back to the selected
  `検出id4-2` source-cache acceptance path: when stations are accepted into the
  same id, record the selected candidate's exact accept reason, source distance,
  first-station distance, current shindo/rise support, and P/S timing window.
  That should show why the late Fukushima state still reaches `160` cached
  stations.

## 2026-07-03 update: accepted same-id `検出id4-2` diagnostics

Added a diagnostic-only pass for stations that are accepted into the current
kotoho7 detection id.

For each sampled accepted station, diagnostics now include:

- selection source (`scratch_4_2_source_cache`, `scratch_grid_current`,
  `scratch_grid_around_9`);
- exact accept reason (`4_2_accept_p_window`, `4_2_accept_s_range`, or grid
  carrier source);
- source-cache/fallback branch;
- current `ten:震度` proxy, `lastAscend > 0`, and current-frame evidence;
- source distance, first-station distance, `4-3 +5` and `4-3 +10` limits;
- station observed time, P/S arrival predictions, residuals, and tolerance
  windows.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay finding:

| Case | Accepted reason totals | Notable finding |
|---|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `4_2_accept_p_window=70`, `4_2_accept_s_range=46`, `scratch_grid_current=35`, `scratch_grid_around_9=15` | Far stations can enter through the wide P window. Examples around `260-332 km` still pass because `pTolerance = 5 + distance/120`, giving roughly `7.1-7.8s` tolerance. |
| `20260702_shizuoka_west_m36_jma_p2p` | `4_2_accept_p_window=37`, `4_2_accept_s_range=29`, `scratch_grid_current=25` | No far-distance samples over `250 km`; stable case remains compact. |

Late Fukushima final-frame detail:

```text
2026-07-02T20:50:00 JST
YMNH10: S-range, distance 214.1 km, S residual 0.41s, S tolerance 9.78s
NGN021: S-range, distance 212.8 km, S residual 0.88s, S tolerance 9.77s
```

Interpretation:

- The final two Fukushima additions are not obvious bad accepts; both fit the
  S-arrival window tightly.
- The larger over-retention signature is earlier: many stations enter through
  `4_2_accept_p_window`, including far stations, because the current proxy
  tolerance scales generously with distance.
- Next faithful-replication target should inspect Scratch's actual constants and
  branch guards inside `検出id4-2_適用id震源から候補選択`: especially whether the
  P/S windows, the wide-distance gates (`4-3 +5`, `4-3 +10`), and the source-cache
  score/age gates match the sb3 exactly.

## 2026-07-03 update: exact `検出id4-2` constants from sb3

The sb3 block tree for
`検出id4-2_適用id震源から候補選択 %s %s %s %s %s %s` was expanded directly from
`docs/assets/project.json`. The constants and branch guards are not proxy
values; the Dart implementation already matches the important thresholds.

Top-level candidate scan when `x == ''`:

```text
multi1 = infinity
count3 = length(4-3 検出id別情報) / 20
repeat length(4-3) / 20:
  offset = (count3 - 1) * 20
  if 4-3[offset + 2] active:
    if age > 5
       and 4-3[offset + 11] < 500
       and 4-4[(offset / 2) + 2] is not empty:
      recurse using 4-4 source cache (+2/+3/+4/+5)
    else if 4-3[offset + 4] > 4:
      recurse using first station, depth 10km, origin ten:+1 - 3
  count3 -= 1
```

Per-candidate distance and time gates:

```text
distance = station-to-candidate-source km

if distance > 900
   and (
     (age > 100 and 1.5 * 4-3[offset + 10] < distance)
     or
     (age > 15 and 1.4 * 4-3[offset + 5] < distance)
   ):
  reject

pArrival = origin + JMA2001(distance, depth, P)
pTolerance = 5 + distance / 120

if abs(pArrival - observed) <= pTolerance:
  select using P residual
else:
  sArrival = origin + JMA2001(distance, depth, S)
  sTolerance = 8 + distance / 120
  if observed < pArrival - pTolerance
     or observed > sArrival + sTolerance:
    reject
  else:
    select using S residual
```

Diagnostics now label these as exact Scratch gates:

```text
source_cache_gate_model =
  scratch_exact_age_gt_5s_score_lt_500_and_source_present_v1
first_point_fallback_gate_model =
  scratch_exact_assigned_count_gt_4_v1
timing_window_model =
  scratch_exact_p_abs_le_5_plus_distance_over_120_else_s_between_p_minus_tol_and_s_plus_8_plus_distance_over_120_v1
wide_distance_gate_model =
  scratch_exact_distance_gt_900_and_age100_1p5_plus10_or_age15_1p4_plus5_v1
```

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
```

Interpretation:

- The generous P window (`5 + distance/120`) is not a Dart tuning artifact; it is
  exactly present in the sb3.
- The remaining Fukushima over-retention should not be fixed by arbitrarily
  tightening this window if the goal is faithful reproduction.
- Next target should inspect data/ordering differences around which stations
  reach `検出id4-2` at all: exact `ten:震度` current-frame mapping, grid carrier
  freshness, and whether GIF-derived station histories are feeding the same
  points into the Scratch membership path.

## 2026-07-03 update: pre-`4-2` entry pipeline audit

Added a diagnostic-only entry audit before `_updateAssignedStationCodes`.

The audit records:

- capped candidate count actually passed to assignment;
- uncapped candidate pool count before the current Dart `24` record cap;
- current-frame `ten:震度` proxy counts;
- current-frame evidence counts;
- `lastAscend > 0` counts;
- already-assigned count;
- current-grid and around-grid carrier pre-hit counts;
- samples with raw/detect/value/rise fields.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay finding:

| Case | Capped total | Uncapped total | Avg capped/frame | Avg uncapped/frame | Max uncapped/frame | Current-frame finding |
|---|---:|---:|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `1588` | `13333` | `23.4` | `196.1` | `365` | All capped and uncapped candidates had current-frame positive shindo/evidence. |
| `20260702_shizuoka_west_m36_jma_p2p` | `1128` | `3773` | `18.2` | `60.9` | `109` | All capped and uncapped candidates had current-frame positive shindo/evidence. |

Final-frame detail:

```text
Fukushima final:
  capped candidates = 20
  uncapped eligible pool = 43
  assigned already = 18

Shizuoka final:
  capped candidates = 3
  uncapped eligible pool = 3
  assigned already = 3
```

Interpretation:

- The current-frame `ten:震度` proxy is not feeding stale/empty stations into
  `4-2` on these two cases; every eligible station has positive current-frame
  evidence.
- Fukushima's raw eligible pool is much larger than the capped assignment input.
  Therefore the remaining retention is not caused by a too-large Dart entry
  pool; if Scratch processes all positive points, the faithful loop may have
  even more station membership pressure unless another Scratch branch clears or
  orders points differently.
- Next target should inspect the exact Scratch point-loop ordering and cap
  semantics in `検出id1_全点へ適用` / `検出id2_各点の許可idと推定用をセット`:
  whether it iterates all points, only changed/rising points, or a prefiltered
  grid-local subset.

## 2026-07-03 update: exact `検出id1/2/3/4` point-loop ordering

The sb3 point-loop procedures were expanded directly from
`docs/assets/project.json`.

Confirmed Scratch ordering:

```text
検出id1_全点へ適用:
  検出id_同一震源統合('', '', '')

  count1 = 1
  repeat len(d ten:x):                  # all points, no 24-record cap
    検出id2_各点の許可idと推定用をセット(
      番号 = count1,
      変化速度 = ten:震度変化速度[count1],
      現在状態 = ten c:揺れ検出許可[count1],
      7点スタート = 1 + 14 * (count1 - 1)
    )
    count1 += 1

  検出id_グリッド別idと存在idをセット(...)
  検出id_消えたidに対応する検出無効化()
  coastal grid-id cleanup / coastal assist
  active id count and max-shindo bookkeeping
  if 4-3 +4 < 2: set 4-3 +2 inactive
```

`検出id2_各点の許可idと推定用をセット` is not a simple "all positive shindo
points immediately enter id selection" function. It gates `検出id3` through:

```text
if ten:震度[point] > 0:
  maintain ten:+5 when current shindo history is rising

  if current state != 6 and ten:+1 is empty:
    if 変化速度 > 0 and 現在状態 < 4:
      inspect the 7 nearest/support points from dc ten:最短7点
      require permitted neighbor support before setting +1/+2
    else if 現在状態 == 5:
      allow initial +1/+2
    if allowed:
      set +1/+2
      検出id3_点にIDを登録(point, 再上昇=false)

  else if 現在状態 > 3.5 and 変化速度 > 0:
    inspect 7 nearest/support points again
    if re-rise support is strong:
      state 6 can become 5, refresh +1/+2
      検出id3_点にIDを登録(point, 再上昇=true)
    else state 5 refreshes +2

  else:
    reset on 200s stale or 90s low-state stale branch

  if state 5 and +2 old enough:
    state -> 6
else:
  if +1 exists: reset

if +1 exists and assigned id is missing/inactive:
  reset, and state 5 can become 6
```

`検出id3_点にIDを登録` ordering:

```text
if ten:+3 already exists:
  検出id適用数カウント追加(point, distanceSet=false, -1)

if timer < 10 and ids exist:
  count2 = latest id
else:
  検出id4_点に適用するべきIDを検索(point, 再上昇)

if count2 > 0:
  ten:+3 = count2
else if count2 is not negative:
  検出id_新規id追加(...)
  ten:+3 = latest id
else:
  reset point
  stop

grid:検出id[current grid] = ten:+3
grid:検出id時間[current grid] = now
検出id適用数カウント追加(point, distanceSet=true, +1)
```

`検出id4_点に適用するべきIDを検索` ordering:

```text
1. 検出id4-1_適用id最短7から候補選択
2. recent latest-id shortcut:
   if latest id is young and first-station distance < 400km, use latest id
3. if not 再上昇:
   current grid id if grid:検出id age < 2s
4. 検出id4-2_適用id震源から候補選択
5. 周囲9grid最大震度or上昇 guard
6. around-grid latest id search
   only if no current grid id or local permitted shindo < 1.5
   and source-distance margin passes
7. if still no id and there are more than one/two ids, return -1
```

Important reproduction implication:

- Dart currently feeds at most `24` timing records per frame into the
  state-local assignment path (`earliest16 + strongest16` merged), while Scratch
  loops over every point in `d ten:x`.
- However, Scratch's all-point loop is constrained by `検出id2` station state and
  7-neighbor support before `検出id3/4` is reached.
- The next faithful-replication target is therefore not "remove the Dart cap"
  immediately. It should first add a diagnostic/full-loop simulation of
  `検出id2` gates over the uncapped positive-shindo pool and compare how many
  points would actually reach `検出id3`.

## 2026-07-03 update: diagnostic `検出id2` full-loop gate simulation

Added a diagnostic-only simulation over the uncapped positive-shindo pool. This
does **not** change production assignment and does **not** remove the Dart 24-row
cap. It estimates how many stations would reach `検出id3` if the Scratch full
point loop were approximated with current Dart state.

Important caveat:

- Scratch uses `ten c:揺れ検出許可` and `dc ten:最短7点`.
- Historical note: this diagnostic originally used
  `scratchStationPermissionState` / `_initialKotoho7StationPermissionState`.
  That is now superseded by the 2026-07-04 correction below: `検出id2`
  current state is `ten c:揺れ検出許可`, and unknown stations enter as `0`.
- geographic nearest-7 as a proxy for `dc ten:最短7点`.

Therefore this diagnostic is intentionally labeled as a proxy. Its purpose is to
show whether the current Dart state mapping would explode under a full Scratch
loop.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay finding:

| Case | Uncapped pool | Would call `id3` | Avg would-id3/frame | Max would-id3/frame | Main reason |
|---|---:|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `13333` | `11143` | `163.9` | `315` | `initial_state5_direct=11143` |
| `20260702_shizuoka_west_m36_jma_p2p` | `3773` | `2434` | `39.3` | `89` | `initial_state5_direct=2434` |

Final-frame detail:

```text
Fukushima final:
  pool = 43
  would call id3 = 25
  plus1 missing = 25
  plus1 present = 18
  all current_state = 5 under current Dart proxy

Shizuoka final:
  pool = 3
  would call id3 = 0
  plus1 present = 3
```

Interpretation:

- With the current Dart permission proxy, removing the 24-row cap would
  massively increase station membership pressure, especially in Fukushima.
- This does **not** prove Scratch would behave that broadly; it more likely
  shows that the Dart fallback `activeLike -> state 5` is too permissive for
  stations that have not gone through Scratch's true `ten c:揺れ検出許可` state
  machine.
- Next faithful-replication target should inspect and replicate the upstream
  `ten c:揺れ検出許可` / `点許可状態更新` / `gridトリガ` permission-state pipeline.
  Until that is mapped, removing the cap would be unsafe and probably less
  faithful.

## 2026-07-03 update: `単独トリガ` / `複数トリガ` permission audit

The sb3 inspection now confirms the root mismatch: Scratch does **not** treat a
never-registered active point as permission state `5`. State `5` is produced by
the trigger-state procedures before `検出id2` is allowed to register the point.

Relevant procedures in target `受信と検出`:

- `揺れ検出許可`
  - loops all points and calls `複数トリガ 状態`;
  - if the testing setting is enabled, it can force state `5`, but that is a
    setting-specific branch and not a general active-point rule;
  - then calls `grid:上昇中割合計算&トリガ`.
- `点許可状態更新`
  - writes `ten c:揺れ検出許可`;
  - refreshes `ten c:揺れ検出トリガー時間` for forced updates, most states above
    `1`, and first-trigger cases;
  - state `6` intentionally does not refresh trigger time unless forced or the
    trigger time is still zero.
- `単独トリガ 状態`
  - demotes suspicious or stale points to `0/1`;
  - creates state `3` for normal trigger, state `4` for one-point provisional
    permission, and state `5` only after stronger checks such as
    `時間overから上昇`, `円の中トリガ`, `通常許可`, or nearby auxiliary permission.
- `複数トリガ 状態`
  - demotes weak / too-old / low-surrounding-support points to `1` or `0`;
  - creates state `5` from neighboring-trigger support such as
    `検出ありの周りで加速だから`, `トリガーが多いから`,
    `1点の近くで許可があったから`, and `周りの多くが許可or揺れてるから`;
  - can create state `6` in the same surrounding-support branch. In `検出id2`,
    state `6` is not an immediate first registration path; it waits for a
    re-rise with nearest-7 support.
- `gridトリガ`
  - upgrades only points that already have `ten c:揺れ検出許可 > 0`;
  - it is not a blanket active-point-to-state-5 conversion.

Diagnostic change in Dart:

- Historical `scratch_id2_full_loop_simulation` numbers in this section used
  the old proxy
  (`existing_scratchStationPermissionState_else_dart_initial_active_like_to_5`)
  for comparison.
- Superseded on 2026-07-04: the live diagnostic now uses
  `scratchDetectionPermissionState` / `ten c:揺れ検出許可` as the `検出id2`
  current state, with unknown stations starting at `0`.
- This is diagnostic-only and does not change production assignment.

Replay result for `nied_gif_hyp_kotoho7_reference_replay_v1`:

| Case | Pool | Old proxy would call `id3` | Strict unknown=0 would call `id3` | Main finding |
|---|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `13333` | `11143` | `617` | old proxy direct state-5 path dominates |
| `20260702_shizuoka_west_m36_jma_p2p` | `3773` | `2434` | `96` | same mismatch, smaller magnitude |

Final-frame detail:

```text
Fukushima final:
  pool = 43
  old proxy would call id3 = 25
  strict unknown=0 would call id3 = 0
  current_state_counts = {5: 43}
  strict_unknown0_state_counts = {5: 18, 0: 25}

Shizuoka final:
  pool = 3
  old proxy would call id3 = 0
  strict unknown=0 would call id3 = 0
  strict_unknown0_state_counts = {5: 3}
```

Interpretation:

- The next faithful step is to implement a real permission-state cache fed by
  GIF history proxies for `単独トリガ 状態` and `複数トリガ 状態`.
- Do **not** remove the current 24-row cap yet. Under the old proxy it is
  provably too broad; under strict unknown=0 it becomes plausible, but still
  lacks Scratch's actual trigger-state transitions.
- The key missing state is not HYP score tuning. It is upstream
  `ten c:揺れ検出許可` creation and demotion.

## 2026-07-03 update: first `ten c:揺れ検出許可` cache scaffold

Implemented the first independent Scratch-like detection permission cache inside
`Kotoho7ReferenceHypSourceEstimator`.

What changed:

- Added state separate from detection-id `+1/+2/+3` lifecycle:
  - `scratchDetectionPermissionState` = proxy for `ten c:揺れ検出許可`;
  - `scratchDetectionTriggerAt` = proxy for `ten c:揺れ検出トリガー時間`;
  - `scratchDetectionPermissionReason` = diagnostic reason for the latest
    permission write.
- `station_lifecycle` initialization now prefers the detection permission cache
  before falling back to the old Dart initial permission guess.
- `検出id2` full-loop diagnostic now reports:
  - old activeLike proxy;
  - strict unknown=0 comparison;
  - `permission_cache_*` comparison using the new cache.
- nearest-7 support now reads the detection permission cache first.
- `ten:震度変化速度` proxy was corrected to prefer current GIF frame history:
  compare the latest decodable frame against the previous decodable frame, and
  only fall back to `lastAscend` when history is unavailable. This avoids using
  sticky event-level `lastAscend` as if it were current Scratch frame speed.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimator_test.dart --concurrency=1
```

Replay result:

| Case | Pool | Old proxy would call `id3` | Strict unknown=0 would call `id3` | Permission cache would call `id3` | Final error |
|---|---:|---:|---:|---:|---:|
| `20260702_fukushima_aizu_m46_jma_p2p` | `13333` | `10934` | `820` | `8362` | `16 km` |
| `20260702_shizuoka_west_m36_jma_p2p` | `3773` | `2424` | `106` | `2329` | `3 km` |

Interpretation:

- The architecture is now closer to Scratch: permission is a separate upstream
  layer, not a direct `activeLike` fallback.
- However, this first cache is still too broad. It lowers the old proxy pressure
  but remains much closer to the old activeLike proxy than to the strict
  unknown=0 comparison.
- The remaining mismatch is now specifically inside `複数トリガ 状態`:
  `加速追加`, `NG加速`, threshold-letter checks, and the exact nearest-7 support
  scoring must be reproduced before using this cache to remove the 24-row cap or
  to drive production all-point assignment.

## 2026-07-03 update: `複数トリガ` low-state cleanup and promotion gate

Expanded the sb3 `複数トリガ 状態` procedure with expression rendering. The key
confirmed branches are:

- If `現在状態 > 4`, `経過時間 > 10`, no positive speed, and the converted
  shindo is below the threshold expression, Scratch demotes the point to state
  `1` (`震度一定以下`).
- For `現在状態 < 5`, Scratch's direct state-5 promotions are not a plain
  active/rising rule:
  - `検出ありの周りで加速だから`: requires positive current speed, recent nearby
    permitted points, and short nearest-7 distance;
  - `トリガーが多いから`: requires more than two nearby recent triggered /
    permitted points;
  - `1点の近くで許可があったから`: state `4` plus at least one nearby permission;
  - `周りの多くが許可or揺れてるから`: uses nearby permission count, high-shindo
    count, and average surrounding shindo;
  - `通常許可`: uses the `@1 c:揺れ検出用` accumulated acceleration score.
- `加速追加` only adds to `@1 c:揺れ検出用[4]`; `NG加速` filters candidate
  neighbors using relative screen geometry before acceleration can be counted.

Implemented a closer cache proxy:

- state `5/6` now demotes to `1` after 10s when the current converted shindo is
  low and the point is not rising;
- state `5` promotion now requires a stronger current signal
  (`convertedShindo >= -0.35` or raw level at least `8`) instead of any tiny
  current-frame rise;
- one-point provisional state `4` now also requires a stronger current signal
  (`convertedShindo >= 0.0` or raw level at least `7`).

Replay result after this tightening:

| Case | Pool | Old proxy would call `id3` | Strict unknown=0 would call `id3` | Permission cache would call `id3` | Final error |
|---|---:|---:|---:|---:|---:|
| `20260702_fukushima_aizu_m46_jma_p2p` | `13333` | `10934` | `625` | `3109` | `16 km` |
| `20260702_shizuoka_west_m36_jma_p2p` | `3773` | `2424` | `84` | `435` | `3 km` |

Interpretation:

- This is a material improvement over the first permission cache scaffold:
  Fukushima `permission_cache_would_call_id3_count` dropped from `8362` to
  `3109`; Shizuoka dropped from `2329` to `435`.
- The cache is still broader than strict unknown=0, so the 24-row cap should
  remain.
- The next exact-replication target is to replace the rough promotion proxy with
  the sb3 acceleration score:
  `@1 c:揺れ検出用[1..10]`, `加速追加`, `NG加速`, and the final `通常許可`
  checks.

## 2026-07-03 update: SB3 `@1 c:揺れ検出用[1..10]` accumulator pass

Re-read the local `リアルタイム地震ビューアー v1.6.3.sb3` instead of the web
`project.json` copy. The local sb3 contains the actual procedures:

- `揺れ検出許可`
- `複数トリガ 状態 %s %s %s %s %s %s 番号 %s 7 %s %s`
- `加速追加 %s %s`
- `NG加速 %s`
- `最短7点決定`

Implemented the first literal accumulator pass in
`Kotoho7ReferenceHypSourceEstimator`:

- station index alignment now follows NIED/Scratch order (`NiedStationDb`
  order + 1), and permission diagnostics expose `scratch_station_index`;
- NIED descriptors now carry `scratch_station_index`, `threshold_code`,
  `pixel_x`, and `pixel_y`;
- `@1 c:揺れ検出用[1]` maps to nearest-7 points outside
  `5 * 経過時間 - 2`;
- `@1 c:揺れ検出用[2]` maps to those also inside
  `12 * (経過時間 + 4)`;
- `@1 c:揺れ検出用[3]` counts close points with
  `ten c:揺れ検出許可 > 1`;
- `@1 c:揺れ検出用[4]` is now updated only through a Dart equivalent of
  Scratch `加速追加`: add the supplied score value;
- `@1 c:揺れ検出用[5..10]` are represented by the two cached `NG加速`
  screen-geometry boundaries using `dtc:Xpix/Ypix` from station tags;
- `通常許可` now uses the sb3 gate:
  `最低点数 - 2 < c[3]` and `0.3 + c[2] / 22.5 < c[4]`.

Important non-equivalences still documented in code:

- replay records do not yet carry exact Scratch
  `ten c:検出許可済み震度`;
- replay records do not yet carry exact Scratch `@1 ten:最高震度更新時刻`;
- nearest-7 still uses runtime geographic nearest records, not the serialized
  `dc ten:最短7点` table, although station index alignment is now available for
  that next step.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart lib\services\sources\nied_source_estimation_driver.dart lib\core\source_estimation\station_event_tracker.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\services\sources\nied_source_estimation_driver.dart lib\core\source_estimation\station_event_tracker.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

## 2026-07-03 update: grid-scan search comparison error audit

Read the replay outputs for the current deterministic
`grid_scan_search_comparison` branch.

Current kotoho7 replay / grid-scan diagnostic horizontal errors:

| Case | Current final error | Grid-scan final error | Depth error | Finding |
| --- | ---: | ---: | ---: | --- |
| `20260702_fukushima_aizu_m46_jma_p2p` | `18 km` | `17.95 km` | `110 km` | Final point is close horizontally but depth remains `40 km` vs reference `150 km`. |
| `20260622_tomakomai_south_offshore_m35_hinet` | `53 km` | `52.92 km` | `90 km` | Deep event is still pulled to `10 km`. |
| `20260620_iwate_offshore_m34_ref` | `7 km` | `6.60 km` | `28 km` | Epicenter is good; depth remains shallow. |
| `20260622_iwate_offshore_m30_eq10` | `47 km` | `46.70 km` | `10.2 km` | Depth is reasonable, but epicenter stays west of the reference. |

Added diagnostic-only fields to each capped grid-scan local-search stage:

- `evaluated_candidate_count`
- `finite_candidate_count`
- `rejected_candidate_count`
- `first_iteration_candidates[]`

The first-iteration candidate diagnostics show that the search cap is not the
reason for non-movement. For the Fukushima M4.6 final frame:

- current candidate score: `156.05`;
- `+0.1°` latitude: `183.62`;
- `+0.1°` longitude: `166.43`;
- `+50 km` depth: `366.09`;
- `+10 km` depth: `166.89`;
- every stage stops after one iteration with `moved=false`.

Interpretation:

- The capped grid-scan branch is currently only re-scoring the existing
  assigned timing set plus deterministic unarrived candidates.
- In late frames with many detected stations, the Scratch unarrived gate is
  closed (`detected >= 30` and elapsed after the early window), so hundreds of
  unarrived candidates do not contribute to the score.
- Therefore widening the iteration cap or replacing Scratch random thinning is
  not the next useful step for these final-frame depth errors.
- The next useful reproduction target remains the upstream Scratch semantics
  that decide which points are in `ten:推定用` for the target id, and the exact
  `ten:+6/+7/+8` S-flag / PS cache lifecycle that controls whether a detected
  point contributes as P or S in `HYP:誤差レベル計算`.

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
```

## 2026-07-03 update: `ten:+7/+8/+6` refresh boundary check

Checked the next suspected gap: whether Dart should stop recomputing the
station PS cache on every HYP source update.

Scratch evidence:

- `検出id適用数カウント追加` calls `推定用tenPS時間計算` only in the
  `距離セット` branch.
- `検出id_点の推定用をリセット` clears the station's `ten:推定用` slots and
  decrements the applied count.
- This means the full Scratch behavior is not a simple per-frame recompute.

Diagnostic attempt:

- Temporarily changed Dart to an event-driven-only PS cache:
  update on station assignment / rerise refresh / merge / reset, but do not
  recompute all assigned stations after each HYP source update.
- Fukushima M4.6 final frame worsened from `17.95 km` to about `172 km`, and
  phase support collapsed from `P/S/O=89/20/25` to `32/7/39`.
- Depth remained wrong (`30 km` vs reference `150 km`), so the naive
  event-driven-only rule was not promoted.

Conclusion:

- The current full-refresh Dart behavior is not exact Scratch, but simply
  disabling full refresh is also not exact.
- The missing piece is the middle path inside `検出id2_各点の許可idと推定用をセット`:
  existing assigned points can still write/copy `ten:推定用` slots under
  state-5/state-6 and rerise conditions.
- Next reproduction target: decode those `ten:推定用` slot writes and implement
  explicit per-station slot state rather than only `assignedStationCodes` plus
  derived PS maps.

Validation after restoring default behavior:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
```

## 2026-07-03 update: explicit `ten:推定用` slot layout diagnostics

Decoded the `ten:推定用` write indexes from the Scratch block JSON.

Scratch uses a 10-slot stride per station:

| Slot | Meaning observed from writes | Dart representation |
| --- | --- | --- |
| `+1` | first/current use time written/copied by `検出id2` | `scratchStationFirstUseAt` |
| `+2` | last update time written/copied by `検出id2` | `scratchStationLastUpdateAt` |
| `+3` | detection id assigned by `検出id3` | `assignedStationCodes` / target id membership |
| `+4` | distance cache from first detected station | `scratchStationFirstDistanceKm` |
| `+5` | pending/latest cloud time candidate | new diagnostic map `scratchStationPendingCloudAt` |
| `+6` | S flag | `scratchStationSFlag` |
| `+7` | predicted P arrival | `scratchStationPArrivalSeconds` |
| `+8` | predicted S arrival | `scratchStationSArrivalSeconds` |

Implemented:

- added `scratchStationPendingCloudAt` as a diagnostic-only `+5` slot;
- populated it when a station is initialized or updated through the assigned
  station lifecycle path;
- cleared/copied it with the same station lifecycle operations as `+1/+2`;
- exposed the full slot layout and `plus_5_pending_cloud_time_count` under
  `stateful_source_cache.station_lifecycle`.

Fukushima M4.6 replay check:

- final horizontal error remains `17.95 km`;
- depth remains `40 km` vs reference `150 km`;
- final phase counts remain `P/S/O=89/20/25`;
- `+5` diagnostic count is `134`, matching the assigned station count.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
```

## 2026-07-03 update: `検出id2` `+1/+2/+5` slot-write diagnostics

Decoded the parent conditions for the main `検出id2_各点の許可idと推定用をセット`
slot writes.

Important Scratch branches:

- If current shindo is positive and the history-based change speed is positive:
  - set `+5` to the latest cloud time only when `+5` is empty.
- If current shindo is positive but change speed is not positive:
  - clear `+5` when it is not empty.
- In state `5` with positive change:
  - write `+2` to the latest cloud time.
- In state `6` with positive change and nearest/support conditions:
  - refresh `+1/+2` and move the point back toward state `5`.

Implemented as diagnostics:

- `estimated_slot_write_reason_counts`
- `estimated_slot_write_samples`

These are exposed under `stateful_source_cache.station_lifecycle`. The HYP
inputs are not changed by this update.

Fukushima M4.6 replay result:

- final source unchanged: `17.95 km` horizontal error, `40 km` depth,
  `P/S/O=89/20/25`;
- final `+5` pending count: `2`;
- aggregate slot-write diagnostics over the replay:
  - `scratch_id2_positive_change_set_plus5_if_empty`: `197`
  - `scratch_id2_no_positive_change_clear_plus5`: `195`
  - `scratch_id2_state5_positive_change_update_plus2`: `177`

Interpretation:

- The explicit `+5` pending slot is transient, not equivalent to assigned
  station membership.
- The next connection point is to use these slot-write diagnostics to decide
  when `+7/+8/+6` should be refreshed, instead of choosing between the two
  extremes already tested: full refresh every HYP update vs event-driven only.

2026-07-04 correction:

- Re-expanded `検出id_点の推定用をリセット(point)`.
- The reset procedure clears `ten:推定用 +1/+2`, calls
  `検出id適用数カウント追加(point, -1)` while `+3` is still present, then clears
  `+3/+4/+6/+7/+8`.
- It does not clear `+5`.
- New assignment/registration also should not blindly write `+5`; `+5` is only
  controlled by the decoded `検出id2` positive-change set-if-empty branch and
  no-positive-change clear branch.

Dart correction:

- `_initializeKotoho7StationLifecycle` no longer writes
  `scratchStationPendingCloudAt` on every assignment.
- `_resetKotoho7AssignedStation` / `_clearKotoho7StationLifecycle` no longer
  clears `scratchStationPendingCloudAt`; full detection-id invalidation still
  clears the whole map.

2026-07-04 rerise correction:

- In `検出id2`, state `5` is not merely a `+2` update path. It first evaluates
  the same nearest-7 rerise accumulator as state `6`.
- If a neighbor with positive change and permission `>4` has a newer `ten:+3`
  id, Scratch sets `多目的0 = Infinity`.
- `Infinity` enters the rerise branch, writes permission state `5`, refreshes
  `+1/+2` from `+5` or current cloud time, and calls `検出id3`.

Dart correction:

- `_kotoho7Id2ReriseScore` now maps the newer-neighbor-id branch to
  `double.infinity`.
- state `5` now evaluates the rerise branch before the ordinary `+2` update.
- rerise `+1/+2` refresh uses `scratchStationPendingCloudAt[code] ??
  observedAt`.

Remaining gap:

- Dart currently refreshes the existing state on this rerise. Full Scratch
  `検出id3` can reselect/switch ids after the `-1` count update. That exact
  cross-id rerise registration still needs a later pass.

Validation after `+5` and state5-rerise corrections:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart `
  lib\core\source_estimation\kotoho7_scratch_reference_tables.dart `
  test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\fukushima_offshore_reference_replay_test.dart `
  test\iwate_east_offshore_reference_replay_test.dart `
  test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
```

All passed.

Effective-id replay metrics remained essentially unchanged:

| Case | best | median / p90 | final | Note |
|---|---:|---:|---:|---|
| `20260621_fukushima_offshore_m32_eq6` | `57 km` | `72 / 151 km` | `57 km` | final `+5` pending count `6` |
| `20260622_iwate_east_offshore_m30_hinet` | `13 km` | `19 / 36.5 km` | `19 km` | final `+6 true` changed `27 -> 26` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `49 km` | `54 / 65 km` | `54 km` | final `+5` pending count `0` |

Interpretation:

- Correcting `+5` and state5 rerise made the slot lifecycle closer to Scratch,
  but these three effective-id samples do not materially improve.
- The remaining likely gap is not same-id rerise refresh; it is full
  `検出id3` cross-id re-registration: after the Scratch `-1` count update, a
  station can be assigned to a different active id or a new id.

## 2026-07-05 update: rerise now re-enters `検出id3` selection

Implemented the next faithful step for the rerise branch.

When `検出id2` decides that a point should rerise, Dart now:

1. preserves the refreshed `ten:+1/+2/+5` timing state;
2. removes only the current detection-id membership, matching the `-1` side of
   `検出id適用数カウント追加`;
3. re-enters the existing `検出id4` selection path;
4. assigns the point back to the same id, another active id, or a new mid-frame
   id depending on the selection result.

This is intentionally different from a normal reset: it does not clear
`ten:+1/+2/+5`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart `
  lib\core\source_estimation\kotoho7_scratch_reference_tables.dart `
  test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\fukushima_offshore_reference_replay_test.dart `
  test\iwate_east_offshore_reference_replay_test.dart `
  test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
```

All passed.

Observed rerise activity in the narrow replay set:

| Case | method | max rerise | max switch-other-id | max mid-frame new id |
|---|---|---:|---:|---:|
| `20260621_fukushima_offshore_m32_eq6` | effective id | `1` | `0` | `0` |
| `20260621_fukushima_offshore_m32_eq6` | raw id | `1` | `0` | `0` |
| `20260622_iwate_east_offshore_m30_hinet` | effective id | `1` | `14` | `2` |
| `20260622_iwate_east_offshore_m30_hinet` | raw id | `3` | `12` | `3` |
| `20260622_tomakomai_south_offshore_m35_hinet` | effective id | `2` | `1` | `1` |
| `20260622_tomakomai_south_offshore_m35_hinet` | raw id | `4` | `2` | `1` |

Headline effective-id metrics stayed essentially unchanged:

| Case | best | median / p90 | final |
|---|---:|---:|---:|
| `20260621_fukushima_offshore_m32_eq6` | `57 km` | `72 / 151 km` | `57 km` |
| `20260622_iwate_east_offshore_m30_hinet` | `13 km` | `19 / 36.5 km` | `19 km` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `49 km` | `54 / 65 km` | `54 km` |

Interpretation:

- The cross-id rerise path is now active and no longer just a same-id refresh.
- Since headline metrics did not improve, the next gap is probably the exact
  `検出id4` selection predicates or the permission/nearest-7 inputs feeding
  rerise, not the absence of cross-id re-registration itself.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
```

## 2026-07-03 update: per-frame `grid存在id` / `grid:検出id` rebuild

Expanded the extraction helper to include the upstream detection-id procedures:

- `検出id1_全点へ適用`
- `検出id2_各点の許可idと推定用をセット`
- `検出id3_点にIDを登録`
- `検出id4_点に適用するべきIDを検索`
- `検出id_グリッド別idと存在idをセット`
- `検出id_周囲gridの最新ID検索`
- `検出id_消えたidに対応する検出無効化`

Generated reference files:

- `docs/reference/scratch_hyp_algorithm_extracted.md`
- `docs/reference/scratch_hyp_algorithm_blocks.json`

Scratch finding:

```text
検出id1_全点へ適用:
  loop every point through 検出id2
  then 検出id_グリッド別idと存在idをセット("", "", "")
  then 検出id_消えたidに対応する検出無効化

検出id_グリッド別idと存在idをセット("", "", ""):
  clear @1 grid存在id
  scan grid/point membership
  clear grid:検出id for each grid
  if a point's ten:+3 belongs to that grid:
    grid:検出id[grid] = ten:+3
    add ten:+3 to @1 grid存在id if missing
```

Dart implementation:

- added `_rebuildKotoho7GridCarrierFromAssignedStates`;
- it rebuilds `_scratchGridByNumber` from all active states'
  `assignedStationCodes`, approximating Scratch `ten:+3` membership;
- it removes stale grid carriers that no longer have an assigned station;
- it preserves the previous carrier timestamp for the same source id, or falls
  back to that station's first-registration time, so the current-grid 2-second
  branch is not accidentally refreshed every frame;
- diagnostics now expose `grid_presence_active_id_count`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

## 2026-07-03 update: `検出id_消えたidに対応する検出無効化` grid-presence gate

Continued from the extracted `検出id_グリッド別idと存在idをセット` and
`検出id_消えたidに対応する検出無効化` procedures.

Scratch finding:

```text
検出id_グリッド別idと存在idをセット("", "", ""):
  clear @1 grid存在id
  rebuild grid:検出id from each point's ten:+3
  add each present id to @1 grid存在id

検出id_消えたidに対応する検出無効化:
  for each 4-3 detection id:
    if id is not contained in @1 grid存在id:
      after the disappearance/stale window, mark the id inactive
```

Implementation update:

- `_kotoho7ScratchGridPresenceProxy` now reads `_scratchGridByNumber` carrier
  presence instead of asking whether any assigned station still has current
  shindo;
- this makes the active-id clearing path depend on the same carrier table that
  approximates Scratch `grid:検出id` / `@1 grid存在id`;
- existing current-frame evidence gating is retained before applying the
  disappearance check, so missing replay frames do not immediately clear ids;
- diagnostics now expose `grid_presence_count_for_state` beside
  `grid_presence_active_id_count`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

## 2026-07-03 update: new-id metadata, latest ordering, and one-station grace

Expanded the generated `検出id_新規id追加` extraction.

Scratch finding:

```text
検出id_新規id追加(point, 再上昇):
  append 4-3 検出id別情報 entries
    +1 first point / id source
    +2 active flag
    +3 first/latest detection time
    +4 assigned count = 1
    +5/+6/+7 initial distance/score placeholders
    +8 source-key-ish string
    +9 expiry / lifetime value
    ... additional metadata placeholders
  append 10 blank 4-4 検出id震源要素 entries
  if not 再上昇:
    write grid:検出id / grid:検出id時間 for matching grids
```

Implementation update:

- added `_Kotoho7HypState.scratch43Serial` and
  `_nextScratch43Serial` to model Scratch's append-order latest-id semantics;
- latest-id shortcut now chooses the highest active serial within its young-id
  window, with `initializedAt` only as a tie-breaker;
- `_createKotoho7MidFrameNewIdState` now marks:
  - `scratch43CreatedByMidFrameNewId = true`;
  - `scratch43SingleStationGraceUntil = observedAt + 2s`;
- `_updateScratch43ActiveState` allows a one-station mid-frame new id to remain
  active during that grace window, then the normal `<2 station` inactive gate
  applies;
- diagnostics expose:
  - `scratch_4_3_proxy.serial`;
  - `scratch_4_3_proxy.created_by_mid_frame_new_id`;
  - `scratch_4_3_proxy.single_station_grace_until`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

## 2026-07-03 update: `検出id_新規id追加` / cross-state registration

Continued the `検出id3_点にIDを登録` reproduction.

Scratch finding:

```text
if count2 > 0:
  ten:+3 = count2
else if count2 is not negative:
  検出id_新規id追加(point, 再上昇)
  ten:+3 = latest id
else:
  reset point
  stop

grid:検出id[current grid] = ten:+3
grid:検出id時間[current grid] = now
検出id適用数カウント追加(point, distanceSet=true, +1)
```

Important correction:

- When `検出id4` selects another id, the point must be registered into that
  other id. It is not only a "would switch" diagnostic.
- When no candidate id exists but the point reached `検出id3`, Scratch creates a
  new detection id inside the same frame.

Dart implementation:

- added `_assignKotoho7StationToState`, which applies the shared observable
  `ID3` side effects:
  - add station to the target state's `assignedStationCodes`;
  - immediate `scratch43AssignedCount += 1`;
  - initialize station lifecycle;
  - refresh PS cache (`ten:+6/+7/+8`);
  - refresh first-station distance cache (`ten:+4`);
  - write grid carrier.
- selected other-state assignments now actually mutate the selected state,
  while still appearing in current-state diagnostics as a rejected/would-switch
  row.
- added `_createKotoho7MidFrameNewIdState` for `count2 == 0`:
  - seed from the single station's rounded coordinate;
  - create a one-station active detection id;
  - register it in `_states`;
  - rely on later frames / active-id cleanup to either grow or expire it.
- diagnostics now expose:
  - `last_assignment_mid_frame_new_id_count`;
  - `last_assignment_mid_frame_new_id_station_codes`;
  - candidate reason `created_mid_frame_new_id_for_count2_zero`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

## 2026-07-03 update: `検出id3` latest-id shortcut and `+1` count side effect

Continued from the extracted `検出id3_点にIDを登録` / `検出id4_点に適用するべきIDを検索`
ordering.

Scratch finding:

```text
検出id3_点にIDを登録(point, 再上昇):
  if point already has ten:+3:
    検出id適用数カウント追加(point, distanceSet=false, -1)

  if latest id exists and young enough:
    count2 = latest id
  else:
    検出id4_点に適用するべきIDを検索(point, 再上昇)

  if count2 > 0:
    ten:+3 = count2
  else if count2 is not negative:
    検出id_新規id追加(point, 再上昇)
    ten:+3 = latest id
  else:
    reset point
    stop

  grid:検出id[current grid] = ten:+3
  grid:検出id時間[current grid] = now
  検出id適用数カウント追加(point, distanceSet=true, +1)
```

Implementation update:

- added a conservative `_selectKotoho7LatestIdShortcutState` before the current
  grid / 4-2 / around-grid branches;
- it chooses the most recently initialized active source only when:
  - the source id is younger than `10s`;
  - station distance from the source's initial/first-station position is
    `< 400 km`;
- source labels:
  - `scratch_id3_latest_id_shortcut`;
  - `scratch_id3_latest_id_shortcut_other_state`;
- reason counters:
  - `accept_latest_id_shortcut_young_distance_lt_400km`;
  - `latest_id_shortcut_no_young_active_id`;
  - `latest_id_shortcut_first_station_distance_gte_400km`;
- added immediate `scratch43AssignedCount += 1` when a station is assigned,
  matching the visible `検出id適用数カウント追加(..., +1)` side effect before the
  later metadata refresh recomputes the exact count.

Still not implemented:

- the mid-frame `検出id_新規id追加` branch for a single station that cannot be
  assigned to any existing id. Current Dart still creates a new state at the
  event/raw-id level in `_stateFor`, not inside station assignment.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

## 2026-07-03 update: assigned-station `再上昇` refresh side effects

Continued from the extracted `検出id2_各点の許可idと推定用をセット` and
`検出id3_点にIDを登録` flow.

Scratch finding:

```text
if an already-registered point has ten:+1:
  if current state > 3.5 and 変化速度 > 0:
    if state == 6 and nearest/support condition is satisfied:
      点許可状態更新(point, 5, "再び震度加速", ...)
      refresh ten:+1 / ten:+2
      検出id3_点にIDを登録(point, 再上昇=true)
    else if state == 5:
      refresh ten:+2 only
```

Implementation update:

- `_kotoho7AssignedStationResetReason` now requires nearest-7 permission
  support before promoting an assigned station from state `6` back to state `5`.
- When that re-rise promotion happens, `_updateAssignedStationCodes` now applies
  the observable `検出id3` side effects for the already-assigned station:
  - refresh `ten:+6/+7/+8` PS cache;
  - refresh `ten:+4` first-station distance cache;
  - rewrite the grid carrier with source
    `scratch_id2_existing_rerise_refresh`.
- Diagnostics now expose:
  - `last_assignment_rerise_refresh_count`;
  - `last_assignment_rerise_refresh_station_codes`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

## 2026-07-03 update: `d #震度換算30段階[ten:震度 + 60]`

Rechecked the local sb3 Stage list `d #震度換算30段階`
(`a2{*m(q6TnFclX9Ot^rW`). It is a serialized hidden initialization list, not a
runtime-generated list.

The 90 entries are split into three 30-entry ranges:

- entries `1..30`: converted/display shindo values used by shindo history;
- entries `31..60`: color hex values;
- entries `61..90`: grid/status values used by
  `検出許可震度算出` when it evaluates
  `d #震度換算30段階[ten:震度 + 60]`.

The third range is:

```text
[-1, -1, -1, -1, -1, -1,
  0,  0,  0,
  1,  1,  1,
  2,  2,  2,
  3,  3,  3,
  4,  4,  4,
  5,  5,
  6,  6,
  7,  7,
  8,  8,
  9]
```

Important correction:

- The high-shindo grid branch does not write converted shindo like `3.16` or
  `6.5`; it writes this status/grid value range.
- Dart now keeps this as `_kotoho7Shindo30ToGridDetectionMax` and uses it in
  `_kotoho7GridDetectionMaxProxy` for the Scratch high-shindo branch.

## 2026-07-03 update: nearest-7 and highest-shindo state pass

Continued the SB3 replication work for the three missing fields called out
above.

`dc ten:最短7点` finding:

- In the local `リアルタイム地震ビューアー v1.6.3.sb3`, `dc ten:最短7点`
  is not serialized as a full 1748 x 14 static table; the initial list has one
  empty item.
- The table is generated by `最短7点決定 -> 近い観測点TOP7 -> 7回7点追加`.
- Therefore the Dart pass now generates a Scratch-aligned nearest-7 table from
  the full 1748 `d ten:x/y` station order, instead of sorting only the current
  runtime candidate pool.

Implemented:

- fixed Scratch station table count to `1748`, matching local `d ten:x/y`;
- generated a lazy `1748 x 7` nearest table using the Scratch distance formula
  `111.31949 * acos(...)`;
- `_kotoho7Nearest7Records` now prefers this generated table via station index
  and only falls back to runtime geographic sorting if the station is outside
  the Scratch table or the pool lacks all referenced records;
- `_kotoho7ThirdNearestDistanceKm` now uses the generated table distance, so
  the `時間エリア内に点なし` gate is no longer distorted by the current pool;
- added `scratchDetectionPermittedShindo`, equivalent to the first-pass carrier
  for `ten c:検出許可済み震度`;
- added `scratchStationMaxShindoValue` and `scratchStationMaxShindoUpdatedAt`,
  equivalent to `@1 ten:最高震度更新時刻` plus the value needed to update it only
  on new highs;
- `許可震度+` now reads `scratchDetectionPermittedShindo > 7`;
- `震度高+ / 震度中+` now read `scratchStationMaxShindoUpdatedAt` with the
  Scratch 6-second freshness window;
- diagnostics now expose station index, permitted max shindo, station max
  shindo, and station max update time.

Correction after expanding `検出許可震度算出`:

- `ten c:検出許可済み震度` is not a maximum cache.
- Scratch writes it every pass:
  - if `ten:震度 > 0` and `ten c:揺れ検出許可 >= 4`, write current `ten:震度`;
  - otherwise, write current `ten:震度` when it is below `7`, or cap it to `6`
    when it is `>= 7`.
- The Dart cache now follows that current-value/capped-value behavior.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\services\sources\nied_source_estimation_driver.dart lib\core\source_estimation\station_event_tracker.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

## 2026-07-05 correction: `検出id4` rerise current-grid gate and final `count2=-1`

Re-expanded the web `project.json` procedures directly:

- `検出id3_点にIDを登録 %s %b`
- `検出id4_点に適用するべきIDを検索 %s %b`
- `検出id4-1_適用id最短7から候補選択 %s %s %s`
- `検出id4-2_適用id震源から候補選択 %s %s %s %s %s %s`

Two exact `検出id4` control-flow details were still missing from Dart:

```text
current-grid branch:
  if NOT(再上昇) AND count2 == 0:
    if grid:検出id[current grid] > 0
       and 最新クラウド変数[1] - grid:検出id時間[current grid] < 2:
      count2 = grid:検出id[current grid]
      stop

final no-candidate branch:
  if count2 == 0:
    if 20 < LEN(4-3 検出id別情報):
      count2 = -1
```

Implemented:

- `_selectKotoho7StationSourceState` now receives `isRerise`;
- rerise re-registration still enters the same `検出id3/4` selection path, but
  `検出id4` no longer allows the current-grid shortcut when `再上昇 == true`;
- if no id is selected and the Scratch `LEN(4-3) > 20` condition is true, Dart
  now treats the result as `count2=-1` reset instead of creating a mid-frame new
  detection id;
- rerise reset clears the station lifecycle after the prior `-1` membership
  removal, matching the `検出id3 -> count2<0 -> 検出id_点の推定用をリセット`
  shape while preserving the already-correct `ten:+5` lifecycle behavior.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\fukushima_offshore_reference_replay_test.dart test\iwate_east_offshore_reference_replay_test.dart test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
```

Replay result after this stricter Scratch control flow:

| Case | effective-id best | median / p90 | final | final source |
|---|---:|---:|---:|---|
| `20260621_fukushima_offshore_m32_eq6` | `57 km` | `72 / 151 km` | `57 km` | `37.9167, 141.7500, 80 km` |
| `20260622_iwate_east_offshore_m30_hinet` | `13 km` | `102 / 107 km` | `30 km` | `39.6833, 142.1667, 110 km` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `49 km` | `54 / 65 km` | `54 km` | `42.5333, 141.1833, 70 km` |

Important interpretation:

- The stricter `count2=-1` branch can make metrics worse before the upstream
  Scratch state inputs are complete. For Iwate, frames around
  `2026-06-22T11:27:29 JST` now reject stations with
  `scratch_id4_no_candidate_reset_existing_ids` instead of creating a
  mid-frame id.
- This is still the correct direction for reproduction: the remaining problem
  is not to re-enable the old proxy new-id behavior, but to continue upstream
  replication of the exact `ten c:揺れ検出許可`, nearest-7 ordering, and
  grid carrier inputs that decide whether `検出id4` reaches a valid id before
  the final `count2=-1` branch.

## 2026-07-05 correction: `検出id4-1` uses all-station `dc ten:最短7点`

After the stricter `count2=-1` correction, rechecked the `検出id4-1`
nearest-7 inheritance path.

Scratch `検出id4-1_適用id最短7から候補選択` only needs:

- the `dc ten:最短7点` `(distance, stationIndex)` pairs;
- `ten c:揺れ検出許可[neighbor] == 4 or 5`;
- `ten:推定用[neighbor +3] > 0`;
- the `ten:推定用 +1` time difference.

It does **not** require the neighbor point to be present in the current replay
candidate pool. Dart was still using `_kotoho7Nearest7Records(center, pool)` in
`検出id4-1`, which filtered out nearest stations missing from
`allTimingUsable`.

Implemented:

- added `_kotoho7Nearest7StationCodes`, which returns the full Scratch
  nearest-7 station-code table when available;
- `検出id4-1` now iterates that all-station table instead of requiring neighbor
  records in the current pool;
- the ID2 permission-5 nearest support count also uses the all-station table,
  matching the global `ten c:揺れ検出許可` list semantics;
- diagnostics now label this as
  `scratch_dc_ten_shortest7_all_station_table_with_generated_fallback_v1`
  instead of the older geographic proxy label.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\fukushima_offshore_reference_replay_test.dart test\iwate_east_offshore_reference_replay_test.dart test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
```

Effective-id replay metrics after the all-station nearest-7 correction:

| Case | best | median / p90 | final | note |
|---|---:|---:|---:|---|
| `20260621_fukushima_offshore_m32_eq6` | `60 km` | `72.5 / 156.1 km` | `60 km` | mostly unchanged |
| `20260622_iwate_east_offshore_m30_hinet` | `3 km` | `14 / 14.5 km` | `14 km` | `4-1` inheritance now works strongly |
| `20260622_tomakomai_south_offshore_m35_hinet` | `85 km` | `88 / 107 km` | `85 km` | worsened, so remaining gap is upstream permission/phase lifecycle |

Interpretation:

- Iwate proves the previous pool-filtered nearest-7 path was not faithful.
- Tomakomai worsening is acceptable at this reproduction stage: it indicates
  that once `4-1` can inherit ids exactly, the remaining mismatch is earlier in
  `ten c:揺れ検出許可` / `ten:+1/+2/+5/+6/+7/+8` phase lifecycle, not in
  `dc ten:最短7点` ordering.

## 2026-07-05 correction: global shared `ten c:揺れ検出許可`

Rechecked the Scratch data model after the all-station nearest-7 correction.

Important Scratch semantics:

- `ten c:揺れ検出許可`
- `ten c:揺れ検出トリガー時間`
- permission reasons / acceleration scratch work values
- `grid:検出グリッド最大震度`

are global station/grid lists. They are not per `4-3 検出id別情報` row.

Dart previously stored these maps inside each `_Kotoho7HypState`, so a
mid-frame/new detection id could evaluate `検出id2` / `検出id4-1` with a stale or
copied permission cache. That was not Scratch-faithful.

Implemented:

- added estimator-level shared maps for the `ten c:*` permission cache,
  permitted-shindo cache, station max-shindo cache, acceleration diagnostics,
  and grid detection max/keep values;
- new `_Kotoho7HypState` rows now receive references to those shared maps;
- `_invalidateKotoho7SourceState` no longer clears the global permission/grid
  maps when a single detection id becomes inactive;
- diagnostics now label the permission cache as
  `scratch_global_ten_c_yure_detection_permission_cache_from_gif_history_v2`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\fukushima_offshore_reference_replay_test.dart test\iwate_east_offshore_reference_replay_test.dart test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
```

Effective-id replay metrics after the global permission-cache correction:

| Case | best | median / p90 | final | note |
|---|---:|---:|---:|---|
| `20260621_fukushima_offshore_m32_eq6` | `82 km` | `85 / 232.2 km` | `82 km` | worsened; global cache is stricter/more coupled |
| `20260622_iwate_east_offshore_m30_hinet` | `3 km` | `14 / 14.5 km` | `14 km` | unchanged from all-station 4-1 fix |
| `20260622_tomakomai_south_offshore_m35_hinet` | `85 km` | `88 / 107 km` | `85 km` | still poor; final `+7/+8=11`, `+6 true=0` |

Interpretation:

- This is a fidelity correction even though it does not improve all metrics.
- Tomakomai's final cache shows `assigned=17` but only `+7/+8=11`; the missing
  rows appear after assignment while the source cache is unavailable or above
  the Scratch invalid-source threshold, so `推定用tenPS時間計算` clears/does not
  populate `+7/+8`. Since the audited default path has no external
  `検出id_推定PS時間id別再計算` caller, assignment-only behavior does not
  automatically backfill them later.
- The next faithful target remains exact `ten:+1/+2/+5` timing and state `5/6`
  transitions, because those decide when stations re-enter `検出id3` and get a
  valid `距離セット=true` PS-cache recompute.

## 2026-07-05 correction: all-point `検出id2` `+5` pending cloud time

Continued the `ten:+1/+2/+5` lifecycle audit.

Scratch `検出id1_全点へ適用` runs `検出id2_各点の許可idと推定用をセット`
for every point, before `検出id3` assignment. Therefore `ten:推定用 +5` is not
only an already-assigned-station diagnostic:

```text
if current ten:震度 is positive and ten:震度変化速度 > 0:
  if ten:+5 is empty:
    ten:+5 = #r:最新クラウド変数[1]
else if current ten:震度 is positive and ten:+5 is not empty:
  ten:+5 = empty
```

Implemented:

- `_kotoho7Id2GatedAssignmentCandidates` now applies this `+5` set/clear logic
  while scanning the all-point candidate pool;
- `+5` now uses `observedAt` / latest cloud time, not first trigger/rise time;
- `_initializeKotoho7StationLifecycle` now initializes `ten:+1/+2` from an
  existing `+5` value when present, before falling back to first trigger/rise.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\fukushima_offshore_reference_replay_test.dart test\iwate_east_offshore_reference_replay_test.dart test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
```

Metrics did not move, but diagnostics now show the all-point `+5` cache is
active:

| Case | best | median / p90 | final | final `+5` count |
|---|---:|---:|---:|---:|
| `20260621_fukushima_offshore_m32_eq6` | `82 km` | `85 / 232.2 km` | `82 km` | `35` |
| `20260622_iwate_east_offshore_m30_hinet` | `3 km` | `14 / 14.5 km` | `14 km` | `58` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `85 km` | `88 / 107 km` | `85 km` | `31` |

Tomakomai still ends with `assigned=17`, `+7/+8=11`, and `+6 true=0`, so the
remaining PS-cache gap is not simply missing `+5`. The next faithful target is
the exact state `5/6` re-registration path that decides when an assigned station
calls `検出id3` again and receives `距離セット=true` / `推定用tenPS時間計算`.

## 2026-07-04 update: existing `+3` phase proxy with true station timing

Added a lightweight benchmark-only export:

- `sourceTriggerMetadata.station_trigger_observation_times`;
- populated from `StationTriggerSnapshot.firstTriggerInterval` /
  `firstRiseInterval`;
- station observed time is interpreted as `firstTriggerAt ?? firstRiseAt`,
  matching the current source-estimation record preference.

The offline existing-member report now keeps two phase proxies:

- `existingPlus3PhaseProxy*`: older proxy using the first frame where a station
  appeared in `source_trigger_raw_member_ids`;
- `existingPlus3TrueTimingPhaseProxy*`: new proxy using the exported true
  station trigger/rise time.

Regenerated references:

```powershell
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\iwate_offshore_m30_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
dart run tools\build_kotoho7_existing_member_reregister_report.dart --input .dart_tool\source_estimation_benchmark --output .dart_tool\kotoho7_existing_member_reregister_report\report.json
```

Observed shift:

| case | same-id geometry | raw-member P/S | true-time P/S |
| --- | ---: | ---: | ---: |
| `20260622_iwate_offshore_m30_eq10` | `474` | `121/353` | `290/153` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `522` | `372/146` | `403/15` |
| `20260624_fukushima_aizu_m32_jma_eq5` | `833` | `627/206` | `703/130` |

Interpretation:

- The raw-member proxy is late and overstates S-range membership.
- True station timing makes skipped existing `ten:推定用 +3` members more
  P-heavy, especially in the Tomakomai and Iwate M3.0 replays.
- This means the next faithful reproduction target is still the sb3
  existing-member `距離セット=true` path and
  `推定用tenPS時間計算(多目的0,2使用)`, but it must use true trigger/rise time
  instead of first raw-member frame time.
- Do not derive a phase-balance penalty from the old raw-member proxy table.

Added an id2 simulation aggregate to the offline report. This reads the
existing exported diagnostic:

```text
stateful_source_cache.station_assignment_selection.entry_pipeline.scratch_id2_full_loop_simulation
```

Important correction:

- Across the measured id2-enabled replays, `existing_rerise_candidate_count`
  is `0`.
- All `would_call_id3_count` currently comes from `initial_state5_direct`.
- Existing stations mostly fall into `existing_refresh_plus2_only` or
  `existing_no_id3_until_stale_or_rerise`.

Measured totals:

| case | would id3 | initial state5 | existing rerise | +2 only | no-id3 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `20260702_fukushima_aizu_m46_jma_p2p` | `7038` | `7038` | `0` | `171` | `1013` |
| `20260702_shizuoka_west_m36_jma_p2p` | `2424` | `2424` | `0` | `27` | `1216` |
| `20260624_fukushima_aizu_m32_jma_eq5` | `372` | `372` | `0` | `72` | `737` |
| `20260620_iwate_offshore_m34_ref` | `155` | `155` | `0` | `135` | `671` |
| `20260622_iwate_offshore_m30_eq10` | `18` | `18` | `0` | `54` | `490` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `10` | `10` | `0` | `51` | `501` |

So the next branch to inspect is not primarily state6 existing rerise. It is
the `initial_state5_direct -> 検出id3 -> 4-2 source selection` path.

Historical Dart cap mismatch (superseded on 2026-07-04):

- `_usableTimingRecords()` defaults to `maxRecords = 24`.
- The default cap is earliest 16 + strongest 16, then truncate to 24.
- `_updateAssignedStationCodes()` receives the capped
  `currentDetectionCandidates`.
- The id2 simulation uses `uncappedCandidatePool`, and its large
  `initial_state5_direct` totals are therefore a direct sign that the Scratch
  full-point loop is not yet faithfully represented in the assignment path.

Historical next step at that point was a measured uncapped/less-capped
assignment experiment before changing defaults, because earlier hot-path probes
made the Fukushima M4.6 replay hit the five-minute timeout boundary.

Implemented default-off assignment experiments:

- `SOURCE_ESTIMATION_KOTOHO7_UNCAPPED_ASSIGNMENT_EXPERIMENT=true`
  runs `nied_gif_hyp_kotoho7_uncapped_assignment_experiment_v1` with
  `kotoho7_assignment_candidate_mode = uncapped`.
- `SOURCE_ESTIMATION_KOTOHO7_ID2_GATED_ASSIGNMENT_EXPERIMENT=true`
  runs `nied_gif_hyp_kotoho7_id2_gated_assignment_experiment_v1` with
  `kotoho7_assignment_candidate_mode = uncapped_id2_gate`.

Superseded on 2026-07-04: this id2-gated path is no longer only an experiment
for the kotoho7 reference replay. The reference path now uses the decoded
`検出id1_全点へ適用 -> 検出id2 -> 検出id3` full-point gate by default instead
of the old 24-record cap. Historical measurements below still describe the old
comparison runs.

Early measurements:

| replay | reference | experiment | outcome |
| --- | --- | --- | --- |
| Tomakomai | final `53 km`, `31` assigned, `17/3/11` | uncapped final `52 km`, `33` assigned, `17/3/13` | wired correctly, tiny quality change |
| Iwate M3.0 | final `47 km`, max pool `23` | id2-gated final `48 km`, max pool `23` | cap is not the issue for this case |
| Iwate M3.0 | - | naive uncapped timeout at `05:03` | extra estimator overhead can hit test timeout |

So the candidate-cap hypothesis is only for cases whose uncapped pool actually
exceeds 24. For Iwate M3.0, continue with source-selection / PS timing / search
alignment instead.

## 2026-07-04 update: article error-level truth score probe

Added:

- full assigned-station observed-time export in
  `stateful_source_cache.assigned_station_observed_times`;
- full S-flag station export in `station_ps_cache.s_flag_station_codes`;
- `tools/build_kotoho7_truth_score_probe.dart`.

The tool compares the article-style error-level score at the current estimate
against the score at catalog truth, using the same assigned station set and the
same exported `ten:+6` S flags.

For regenerated Iwate M3.0:

| frame | current source error | current score | truth score with same members | score delta |
| --- | ---: | ---: | ---: | ---: |
| best frame | `22 km` | `3727.3` | `4012.7` | truth worse by `285.5` |
| final frame | `47 km` | `97.8` | `318.2` | truth worse by `220.4` |

This is an important correction:

- The Iwate final-frame drift is not just a failed neighbor search.
- With the current station set and S flags, the article error-level formula
  genuinely prefers the wrong source.
- Therefore the next faithful reproduction target is upstream:
  - exact `ten:+6/+7/+8` lifecycle;
  - exact station set that enters `推定震源計算`;
  - Scratch grid/random-thinning behavior for detected vs non-target points.

Do not tune local-search step sizes to fix this case until the above upstream
inputs match the article/sb3 semantics.

## 2026-07-04 update: existing-member `距離セット=true` evidence

The sb3 extraction shows the important call chain:

```text
検出id3_点にIDを登録
  -> 検出id適用数カウント追加(番号, 距離セット, 変更数)
       if 距離セット:
         推定用tenPS時間計算(多目的0,2使用)(番号, id)
```

So the exact reproduction question is no longer "should P/S be refreshed every
frame?". It is:

> When does Scratch send an already-assigned `ten:推定用 +3` station through
> `検出id適用数カウント追加` with `距離セット=true` again?

An offline report now measures candidate evidence without touching the replay
hot path:

```powershell
dart run tools\build_kotoho7_existing_member_reregister_report.dart `
  --input .dart_tool\source_estimation_benchmark `
  --output .dart_tool\kotoho7_existing_member_reregister_report\report.json
```

The report is intentionally offline because the previous hot-path probe made
the Fukushima replay approach the five-minute timeout.

Added explicit offline field names for the skipped existing-`+3` population:

- `existingPlus3CurrentFrameSkipCandidateTotal`;
- `existingPlus3CurrentFrameSkipCandidateFrameCount`;
- `existingPlus3OfflineProbeRequired`.
- `existingPlus3GeometryProxy*`.
- `existingPlus3PhaseProxy*`.

Current findings:

| case | interpretation | raw overlap | effective overlap | note |
| --- | --- | ---: | ---: | --- |
| `20260702_shizuoka_west_m36_jma_p2p` | persistent raw + late effective retention dominance | `1333` | `1426` | final raw/effective `2/95` |
| `20260702_fukushima_aizu_m46_jma_p2p` | persistent raw + late effective retention dominance | `1289` | `3104` | final raw/effective `15/133`; max shadow score delta `~731.73` |
| `20260624_fukushima_aizu_m32_jma_eq5` | persistent raw current overlap | `838` | `838` | raw and effective agree |
| `20260620_iwate_offshore_m34_ref` | persistent raw + late effective retention dominance | `834` | `1022` | final raw/effective `0/47` |
| `20260622_tomakomai_south_offshore_m35_hinet` | persistent raw + late effective retention dominance | `566` | `690` | final raw/effective `0/31` |
| `20260622_iwate_offshore_m30_eq10` | persistent raw current overlap | `549` | `710` | final raw/effective `1/24` |
| `20260622_iwate_east_offshore_m30_hinet` | effective retention only | `0` | `508` | current raw event does not support re-register |

The same report now also summarizes the current Dart assignment actions:

| case | added | rerise refresh | removed | would-switch-other-id |
| --- | ---: | ---: | ---: | ---: |
| `20260702_shizuoka_west_m36_jma_p2p` | `91` | `0` | `1` | `0` |
| `20260702_fukushima_aizu_m46_jma_p2p` | `105` | `0` | `2` | `473` |
| `20260624_fukushima_aizu_m32_jma_eq5` | `30` | `0` | `0` | `141` |
| `20260620_iwate_offshore_m34_ref` | `40` | `0` | `0` | `0` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `26` | `0` | `0` | `0` |
| `20260622_iwate_offshore_m30_eq10` | `20` | `0` | `0` | `15` |
| `20260622_iwate_east_offshore_m30_hinet` | `5` | `0` | `1` | `0` |

Added a first offline geometry-only proxy for skipped existing `+3` stations:

| case | skipped existing `+3` | same-id geometry | first-point fallback | wide reject |
| --- | ---: | ---: | ---: | ---: |
| `20260702_shizuoka_west_m36_jma_p2p` | `1333` | `0` | `1333` | `0` |
| `20260702_fukushima_aizu_m46_jma_p2p` | `1289` | `1166` | `123` | `0` |
| `20260624_fukushima_aizu_m32_jma_eq5` | `838` | `833` | `5` | `0` |
| `20260620_iwate_offshore_m34_ref` | `834` | `794` | `40` | `0` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `566` | `522` | `44` | `0` |
| `20260622_iwate_offshore_m30_eq10` | `549` | `474` | `75` | `0` |

Model boundary:

- station coordinates come from `NiedStationDb`;
- source lat/lon and distance limits come from the exported
  `scratch_4_4_source_cache` / `scratch_4_3_proxy`;
- the proxy only applies the source-cache availability and wide-distance
  geometry gates;
- it does not yet compute P/S residuals because the exported reference JSON
  lacks complete per-station first-trigger / first-rise times.

Then added a first P/S timing proxy using the first frame where a station
appears in `source_trigger_raw_member_ids` as the station observed time:

| case | skipped existing `+3` | same-id geometry | P-window | S-range | before-P | after-S | fallback |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `20260702_shizuoka_west_m36_jma_p2p` | `1333` | `0` | `0` | `0` | `0` | `0` | `1333` |
| `20260702_fukushima_aizu_m46_jma_p2p` | `1289` | `1166` | `963` | `175` | `0` | `28` | `123` |
| `20260624_fukushima_aizu_m32_jma_eq5` | `838` | `833` | `627` | `206` | `0` | `0` | `5` |
| `20260620_iwate_offshore_m34_ref` | `834` | `794` | `305` | `487` | `2` | `0` | `40` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `566` | `522` | `372` | `146` | `4` | `0` | `44` |
| `20260622_iwate_offshore_m30_eq10` | `549` | `474` | `121` | `353` | `0` | `0` | `75` |

This proxy uses the same P/S window shape as the decoded 4-2 branch:

- P accept: `abs(Parrival - stationObserved) <= 5 + distance/120`;
- S accept: otherwise, station time lies between
  `Parrival - (5 + distance/120)` and `Sarrival + (8 + distance/120)`.

Boundary: station observed time is currently approximated by the first raw
member frame, not by the internal `SeismicStationEventRecord.firstTriggerAt` /
`firstRiseAt`.

Interpretation boundary:

- Raw-current overlap is strong enough that existing-member re-register cannot
  be dismissed.
- Current Dart reports `rerise refresh = 0` in every measured replay, so the
  existing-member `距離セット=true` path is not yet faithfully reproduced.
- The geometry-only proxy shows most skipped existing `+3` stations in the
  non-Shizuoka cases pass broad same-id geometry. The next necessary offline
  step is to add P/S timing residuals, not more geometry tuning.
- The first raw-member P/S proxy now shows most skipped existing `+3` stations
  also pass P-window or S-range. This strongly suggests the existing-member
  `距離セット=true` path is not a minor edge case.
- The current Dart assignment loop skips already assigned current detections
  before source selection:
  `if (state.assignedStationCodes.contains(code)) continue;`. This is a
  concrete mismatch with the Scratch point-loop shape, where `検出id2` and
  `検出id3` decide whether the point is same-id, other-id, new-id, or only a
  lifecycle refresh.
- A direct hot-path probe of those already-assigned points is not viable right
  now: enabling 4-2 selection there, and even a lighter count-only version, made
  the Fukushima M4.6 replay hit the five-minute test timeout. The probe was
  removed from `source_estimator.dart`; existing `+3` decision simulation must
  be done offline.
- Effective/continuity overlap is much wider late in several cases, so it must
  not be treated as literal Scratch current membership.
- The diagnostic event-driven shadow cache is still worse than the current
  production full-refresh guardrail. For Fukushima M4.6, the worst shadow frame
  is `2026-07-02T20:49:47 JST`: current score `181.10`, shadow score `912.82`,
  delta `731.73`, with shadow `P/S/O = 44/5/61`.

Next reproduction work:

1. Decode `検出id3_点にIDを登録` and
   `検出id適用数カウント追加` around existing `+3` stations.
2. Separate three cases in diagnostics:
   - new station enters `+3`;
   - existing station re-registers with `距離セット=true`;
   - existing station only updates `+2` / lifecycle metadata.
3. Implement that sb3-shaped decision path first as an offline report, not in
   the replay/estimator hot path.
4. Only after the exact `距離セット=true` path is proven should the event-driven
   `+6/+7/+8` cache be considered for production.

## 2026-07-03 update: `複数トリガ` threshold digit and state-chain correction

Re-expanded the local `リアルタイム地震ビューアー v1.6.3.sb3` with a more
accurate input resolver. The previous decompiler treated Scratch inputs of the
form `[2, blockId]` as unknown `?`, which hid many `if` conditions. After
resolving those block references, the active `揺れ検出許可` path is:

```text
揺れ検出許可
  repeat d ten:x:
    複数トリガ 状態(
      7点スタート = 1 + 14 * (番号 - 1),
      経過時間 = #r:最新クラウド変数[1] - ten c:揺れ検出トリガー時間[番号],
      最低点数 = letter(3, d ten:しきい[番号]),
      震度 = d #震度換算30段階[ten:震度[番号]],
      番号,
      しきい値 = letter(2, d ten:しきい[番号]),
      変化速度 = ten:震度変化速度[番号],
      現在状態 = ten c:揺れ検出許可[番号],
      上昇制限 = letter(1, d ten:しきい[番号]),
    )
  grid:上昇中割合計算&トリガ()
```

Important correction:

- `d ten:しきい` digit 1 is `上昇制限`;
- digit 2 is `しきい値`;
- digit 3 is `最低点数`.

The Dart `@1 c:揺れ検出用` pass previously used digit 2 as the minimum point
count and digit 1 as the acceleration threshold. That was not Scratch-aligned.
It now uses digit 3 for `最低点数` and digit 2 for the acceleration score term
`1.05 - ((しきい値 - 3) / 15)`.

State-chain correction:

- Removed the proxy behavior where a rising station could jump directly from
  low/unknown state into state `5`.
- Unknown state `0` now first becomes state `1` (`initial point seen` /
  `not much higher than neighbors`) instead of immediately becoming a normal
  trigger.
- States `1/2` move to state `3` only through the Scratch-style single-trigger
  threshold or rising path.
- States `3/4` can become state `5` only through the `複数トリガ` gates:
  recent nearby triggers, state-4 nearby permission, or the normal
  `@1 c:揺れ検出用` acceleration/point-count gate.
- The first-trigger timeout now uses the Scratch term
  `20 + 0.25 * dc ten:最短7点[7点スタート + 4]`.
- The previous Dart-only `state5 aged to state6 after 25s` branch was removed;
  state `6` is kept for Scratch's surrounding-permission/grid paths, not as a
  generic timer.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\services\sources\nied_source_estimation_driver.dart lib\core\source_estimation\station_event_tracker.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

## 2026-07-03 update: `gridトリガ` permission-state proxy

Expanded the local sb3 procedures:

```text
grid:上昇中割合計算&トリガ
gridトリガ %s %b %s
周囲9grid最大震度or上昇(多目的0,1)
```

The active permission-state path is narrower than a blanket active-grid
promotion:

```text
grid:上昇中割合計算&トリガ:
  for each populated grid:
    gridトリガ(grid, 上昇割合計算のみ=true, serialGridIndex)
    if grid:検出グリッド最大震度[grid] == -3
       and four cardinal neighbor maxima are below -2:
      gridトリガ(grid, 上昇割合計算のみ=false, serialGridIndex)

gridトリガ(..., 上昇割合計算のみ=true):
  scan points in the grid
  count current points with ten:震度 > 0
  count long-rising points where the history-window delta is positive
  compute grid:長期上昇観測点数 pair:
    [2*gridIndex-1] = rising count
    [2*gridIndex]   = weighted rise score / current point count

gridトリガ(..., 上昇割合計算のみ=false):
  require rising count > 5 and score > 0.3
  scan points in the grid
  require ten c:揺れ検出許可[point] > 0
  require current long-rise delta > 0
  require letter(3, d ten:しきい[point]) < 4
  require own permitted shindo to be lower than nearby permitted shindo support
  then 点許可状態更新(5, グリッド許可, point)
```

Implemented in Dart:

- added `_applyKotoho7GridTriggerPermissionProxy` after the per-point
  `複数トリガ` pass and before station permission state is copied into the
  assigned station lifecycle;
- added `_kotoho7GridLongRiseProxy`, using the same long-rise count and score
  terms from the sb3:
  - `+0.5` for immediate rise;
  - `5 / (上昇制限 + 6)` or `0.56`;
  - `1 / (しきい値 + 3)` or `0.4`;
- only promotes points with existing permission state `> 0`;
- no-ops when the point is already state `5`, matching `点許可状態更新` without
  `強制更新`;
- uses `letter(3, d ten:しきい)` as the `< 4` gate.

Proxy limitation:

- The replay package does not carry Scratch's runtime
  `grid:検出グリッド最大震度` / `grid:長期上昇観測点数` arrays.
- Dart therefore derives the grid maximum from current
  `scratchDetectionPermittedShindo`. The older 0.25-degree grid-number proxy is
  no longer used for this branch after the later `dc ten:点からグリッド番号` /
  populated-grid correction.
- The sb3 `grid:上昇中割合計算&トリガ` cardinal check uses offsets
  `-26/+26/-1/+1`; the Dart proxy preserves those offsets for this branch even
  though the earlier detection-id carrier still uses the known 23-column
  around-grid offsets.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

## 2026-07-03 update: stateful `@1 検出グリッド最大震度キープ`

Completed the missing stateful part of the Scratch grid-max update.

Scratch order in `検出許可震度算出`:

```text
for each populated grid:
  @1 検出グリッド最大震度キープ[grid] = grid:検出グリッド最大震度[grid]
  grid:検出グリッド最大震度[grid] = -3

for each permitted point:
  update grid:検出グリッド最大震度 from current point state
```

Implemented:

- `_Kotoho7HypState.scratchGridDetectionMax` stores the current
  `grid:検出グリッド最大震度` proxy;
- `_Kotoho7HypState.scratchGridDetectionMaxKeep` stores the previous-frame
  `@1 検出グリッド最大震度キープ` proxy;
- `_kotoho7GridDetectionMaxProxy` now mutates these maps in the Scratch order:
  copy current to keep, reset current populated grids to `-3`, then update from
  current records;
- the low-shindo branch now reads keep:
  - `keep == -3` -> write `-1`;
  - `keep == -2` -> write `-2`;
  - otherwise write `-2 + (age < 15)`;
- invalidated source states clear both maps;
- same-source metadata merge carries over the stronger grid max / keep values.

Later correction:

- The populated-grid boundary described here was removed by the 2026-07-04
  `dc grid連番:点がある番号` correction: Dart now derives the same 92 populated
  grid numbers from the Scratch grid formula and station table, and simulates
  the flat 70-slot carrier insertion.
- The high-shindo `d #震度換算30段階[ten:震度 + 60]` range was also resolved by the
  later extracted grid/status range.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

## 2026-07-03 update: `grid:検出グリッド最大震度` update source

The `gridトリガ` pass depends on `grid:検出グリッド最大震度`, but that list is
not produced inside `gridトリガ`. It is updated earlier in
`検出許可震度算出`.

Expanded Scratch flow:

```text
検出許可震度算出:
  for each populated grid:
    @1 検出グリッド最大震度キープ[grid] = grid:検出グリッド最大震度[grid]
    grid:検出グリッド最大震度[grid] = -3

  for each point:
    if ten:震度 > 0 and ten c:揺れ検出許可 >= 4:
      ten c:検出許可済み震度[point] = ten:震度
      age = now - ten c:揺れ検出トリガー時間[point]

      if ten:震度 > 6:
        if (ten:震度 > 9 and age < 400) or age < 30:
          grid max = max(grid max, d #震度換算30段階[ten:震度 + 60])

      else:
        if grid max < (-2 + (age < 15)):
          if keep == -3:
            grid max = -1
          else if keep == -2:
            grid max = -2
          else:
            grid max = -2 + (age < 15)
```

Implemented in Dart:

- replaced the previous `scratchDetectionPermittedShindo`-only grid max proxy
  with `_kotoho7GridDetectionMaxProxy`;
- each frame initializes populated grids to `-3`;
- only stations with `scratchDetectionPermissionState >= 4` can update the grid
  max;
- high 30-step shindo (`> 6`) updates the grid max only under the Scratch
  freshness window:
  - `ten:震度 > 9 && age < 400`, or
  - `age < 30`;
- low shindo writes the Scratch status-style value `-1` or `-2` according to
  the 15-second freshness branch.

Remaining proxy boundary:

- Later 2026-07-03 updates made
  `@1 検出グリッド最大震度キープ[grid]` stateful and replaced the high-shindo
  fallback with the extracted `d #震度換算30段階[ten:震度 + 60]` grid/status
  range.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

## 2026-07-03 update: `点震度の処理` / `震度履歴移動` speed semantics

Expanded the local sb3 procedures:

- `点震度の処理 %s %s %s`
- `震度履歴移動 %s`
- `ten震度更新 %s %s %s`
- `震度履歴時間管理 %s %s`

Important Scratch semantics:

- `ten:震度` stores the 30-step shindo index.
- `ten:震度100` stores the supplied continuous value when available; otherwise
  it falls back to `d #震度換算30段階[震度30]`.
- `ten:震度履歴` stores converted shindo values, not raw 30-step indexes.
- `ten:震度変化速度` is not previous-frame rise. It is:
  `current converted shindo - converted shindo at the history slot selected by
  ten:震度履歴時間2000s[11]`.
- `震度履歴時間管理` maps slot `11` to about `4` seconds.

Implemented in Dart:

- added the first 30 entries of `d #震度換算30段階` as
  `_kotoho7Shindo30ToConverted`;
- `_kotoho7CurrentConvertedShindo` now falls back from continuous GIF value to
  raw/detect 30-step conversion;
- `_kotoho7ChangeSpeedValue` now prefers the observation-history frame about
  4 seconds before the latest frame, instead of the immediately previous frame;
- `_kotoho7ChangeSpeedPositive` now reads that signed 4-second speed.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\services\sources\nied_source_estimation_driver.dart lib\core\source_estimation\station_event_tracker.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

## 2026-07-04 correction: remove non-Scratch grid/raw proxy and make `検出id1/2/3` the default path

User correction: this work must be a reproduction, not a diagnostic proxy.

Removed the previous default-off raw-member grid-presence experiment from code
and docs. It used `source_trigger_raw_member_ids` as a substitute for
Scratch's own `grid:検出id` carrier and is therefore not part of the reproduced
algorithm.

Static SB3 alignment applied to the kotoho7 reference path:

- `検出id1_全点へ適用` is now represented by the default assignment path:
  all timing-usable points are passed through the decoded `検出id2` gate before
  reaching the expensive `検出id3/4` assignment path.
- The old default `capped_24` assignment path is no longer the reference
  default. Historical benchmark-only uncapped/capped modes remain only as old
  diagnostic switches.
- `_kotoho7Id2GatedAssignmentCandidates` no longer falls back to the uncapped or
  capped pool when fewer than three points would call `検出id3`; if SB3 `id2`
  does not call `id3`, the point is not force-fed into HYP.
- New `4-3` state creation now follows `検出id_新規id追加(point)` more closely:
  a new id starts from one point, not the whole source-trigger seed group.
- Removed the Dart-only immediate `assignedCount < 2` inactive gate. Scratch's
  extracted `消えたid` logic clears ids through `grid存在id`, `+9`, old-small-id,
  and weak/bad-score branches, not an unconditional `<2` member rule.
- Unknown station permission no longer falls back to `activeLike/rising -> 5`.
  Unknown `ten c:揺れ検出許可` is now `0`; stations must be promoted by the
  reproduced permission cache before `検出id2` can send them to `検出id3`.

Validation performed in this correction pass:

```powershell
dart format lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart
```

Remaining non-reproduced boundaries visible in code names:

- `_kotoho7DetectionAccelerationProxy`
- `_applyKotoho7GridTriggerPermissionProxy`
- `_kotoho7GridDetectionMaxProxy`
- `_kotoho7GridLongRiseProxy`
- deterministic grid-scan diagnostics and JQ reference-state diagnostics

Next exact-reproduction target should be the permission / grid-trigger group,
because `検出id2` now depends on permission state instead of the old
`activeLike` shortcut.

## 2026-07-04 correction: replace nearest-7/grid-number proxies with SB3 data

Continued the static SB3 comparison before running more replay tests.

Confirmed sources:

- Official Scratch project:
  `.dart_tool/external_refs/scratch-realtime-earthquake-viewer-page/docs/assets/project.json`
- Local SB3 extraction:
  `.dart_tool/external_refs/local_sb3/realtime_viewer_v163/project.json`

`dc ten:最短7点`:

- The official project serializes the complete table: `24472` list items,
  exactly `1748 stations * 7 neighbors * 2 fields`.
- Each station stores seven `(distanceKm, stationIndex)` pairs.
- Dart now uses the serialized Scratch table in
  `lib/core/source_estimation/kotoho7_scratch_reference_tables.dart`.
- The older generated geographic nearest-7 table remains only as a defensive
  fallback if the embedded Scratch table has an unexpected station count.

`dc ten:点からグリッド番号`:

- The list is empty in the serialized project because Scratch builds it in
  `リセット %b`.
- The exact SB3 expression is:

```text
((floor(d ten:y[point]) - 23) * 23) + (floor(d ten:x[point]) - 122)
```

- Dart now computes `_kotoho7GridNumber` with that formula from station
  latitude/longitude.
- The old `0.25° / 23-column` geographic proxy is removed from this path.

Related reset semantics extracted from `リセット %b`:

- populated grids are scanned from `1..530`;
- `dc grid連番:点がある番号` contains only grid numbers present in
  `dc ten:点からグリッド番号`;
- `dc grid:グリッドに含まれる点番号` is allocated as
  `70 * len(dc grid連番:点がある番号)`;
- each station is inserted at:
  `70 * (item number of station grid in dc grid連番:点がある番号 - 1) + first empty slot`.
- Important: this is a flat Scratch list, not an independent fixed array per
  grid. In the official `d ten:x/y` table there are `92` populated grids, and
  pure grid `293` contains `79` stations. Therefore `9` stations spill past the
  nominal 70-slot segment. Dart now simulates this flat-slot insertion for
  `gridトリガ` instead of truncating the grid to 70 stations.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

Test-fixture correction:

- The `kotoho7 replay reuses an existing detection-id source cache` unit test
  no longer uses synthetic station codes (`A..F`), because the reproduced
  Scratch tables require NIED station order/code alignment.
- It now uses real Iwate NIED station codes and coordinates.
- The test is explicitly marked with
  `kotoho7_assignment_candidate_mode = uncapped` because it validates
  source-cache reuse in isolation. A one-frame synthetic fixture does not run
  enough of `揺れ検出許可 -> 検出id2` to prove the default reference assignment
  path.

Remaining exact-reproduction target:

- replace the still-named permission/grid-trigger proxies with the decoded SB3
  `揺れ検出許可 -> 検出許可震度算出 -> grid:上昇中割合計算&トリガ -> gridトリガ`
  state machine.

## 2026-07-04 correction: use Scratch grid serial slots in `gridトリガ`

The previous correction changed the grid-number formula, but `gridトリガ` still
grouped stations by the current request records. That was not faithful enough:
Scratch uses the reset-built serial grid carrier.

Implemented:

- `_kotoho7ScratchStationIndicesByGridNumber` keeps the pure grid membership
  generated from `dc ten:点からグリッド番号`.
- `_kotoho7ScratchPopulatedGridNumbers` mirrors `dc grid連番:点がある番号`
  (`1..530`, only grids present in the station table).
- `_kotoho7ScratchGridStationIndicesBySerialIndex` simulates the flat
  `dc grid:グリッドに含まれる点番号` insertion with `70` nominal slots per
  populated grid, including Scratch's overflow behavior.
- `_applyKotoho7GridTriggerPermissionProxy` now loops populated grid serial
  indices and reads current records through this Scratch carrier.
- `_kotoho7GridDetectionMaxProxy` now resets/carries all Scratch populated
  grids, not only grids currently present in `request.stations`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

## 2026-07-05 correction: `検出id2` nearest-7 initial support is exactly state `5`

Rechecked the extracted web SB3 block for
`検出id2_各点の許可idと推定用をセット`.

The initial positive-rise branch uses `operator_equals` while accumulating
nearest-7 support:

```text
if ten:震度[番号] > 0:
  if 現在状態 != 6 and ten:推定用[番号 + 1] == "":
    if 変化速度 > 0:
      if 現在状態 < 4:
        多目的0 += (ten c:揺れ検出許可[nearest] == 5)
      else if 現在状態 == 5:
        多目的0 = 1
    else:
      if 現在状態 == 5:
        多目的0 = 1
```

Dart correction:

- `_kotoho7Nearest7Permission5SupportCount` now counts only neighbors whose
  `scratchDetectionPermissionState == 5`.
- It no longer counts state `6` as initial nearest-7 support. State `6` remains
  valid in the separate re-rise branch where the SB3 explicitly checks
  `permissionState == 5 || permissionState == 6`.
- `source_trigger_member_gap_audit` now includes the same acceleration /
  time-area fields already available in `full_point_id2_timing_gap_audit`,
  so blocked source-trigger watch stations can be inspected without treating
  that watchlist as Scratch ground truth.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
```

Observed Tomakomai checkpoint after this exact SB3 correction:

- `20260622_tomakomai_south_offshore_m35_hinet`
  - estimate count: `38`
  - median / p90 horizontal error: `20.0 km / 22.6 km`
  - final: `42.0167N, 141.5833E, 30 km`, error `20.0 km`
  - final phase membership: `P=3 / S=7 / O=6`
- The remaining `30 km` vs Hi-net `100 km` depth gap is still upstream of HYP
  scoring: late watch stations are mostly blocked before `ten:+3` by
  permission states `0/1/3`, especially `時間エリア内に点なし` and
  `not_enough_permitted_points`.
- Do not fix this by broadening HYP depth search or changing the error
  surface. Continue by comparing the SB3 `単独トリガ` / `複数トリガ` control flow,
  including the already documented but intentionally unconnected
  `円の中トリガ` branch. That branch requires Scratch-equivalent live EEW circle
  arrays (`0EEW`, `0-1EEW発表中`, `0-2EEW追加情報`, `ten c:震源距離`) and must not be
  approximated from final truth or the current solved source.

## 2026-07-05 live cloud check: `円の中トリガ` EEW input source

Connected read-only to the packaged viewer's TurboWarp cloud channel using the
same fallback path as `docs/index.js`:

```text
csiUrl = https://gist.githubusercontent.com/kotoho7/039aaef1782ef4a7db80f8876c5bef5f/raw/srev-csi.json
hosts  = wss://clouddata-srev.kothn.net,
         wss://clouddata.turbowarp.org,
         wss://clouddata.turbowarp.xyz
ids    = kotoho7.github.io/srev,
         kotoho7.github.io/srev/2
```

The `srev.kothn.net` endpoint returned Cloudflare 403 from this environment,
but the TurboWarp fallback hosts accepted the standard cloud handshake:

```json
{"method":"handshake","project_id":"kotoho7.github.io/srev","user":"player0000"}
```

Important cloud-frame routing:

- `☁ c2h` is the main header/control frame.
- `#r:最新クラウド変数[2] = ☁ c2h[11..50]`.
- `#r:最新クラウド変数[5] = ☁ c2h[51..256]`.
- `☁ c2b0`, `☁ c2b1`, `☁ c2b2`, `☁ c2b4`, `☁ c2b5`, `☁ c2b6`
  are decoded through `雲変化チェック` into `#r` indices `3`, `4`, `6`,
  `8`, `7`, and `9` respectively.
- `EEW(#r:最新クラウド変数[2], 14 * letter(30, #r[2]))` is called only after
  the relevant update flags are present.

Therefore `円の中トリガ` should use the decoded `#r[2]` / `0EEW` state, not a
raw `☁ c2b2` frame. A live sample during this check:

```text
☁ c2h[11..50] = 0000000000000000000099999000000028800000
active bit     = 0
depth 21..23   = 999
M 24..25       = 9.9
slot 30        = 0
```

This means no active shallow EEW circle input was present at the sampled time.
Some `☁ c2b2` frames contained event-like fields such as `active=1`,
`depth=416`, `M=6.6`, but those frames map to `#r[6]`, not `#r[2]`, and a
`416 km` depth would fail the Scratch `円の中トリガ` gate
`0EEW[slot * 14 + 8] < 150` anyway.

Implementation implication:

- To faithfully connect `円の中トリガ`, reproduce the decoded `0EEW`,
  `0-1EEW発表中`, `0-2EEW追加情報`, and `ten c:震源距離` state from our own live
  EEW/JMA/P2P inputs or an explicit captured cloud replay.
- Do not feed raw `☁ c2b2` values directly into `円の中トリガ`.
- Do not synthesize these fields from final catalog truth or the current HYP
  estimate; Scratch's branch is driven by live EEW circle state.
- Added `tools/probe_kotoho7_cloud_eew.py` as a read-only diagnostic helper.
  It connects through the same Packager/TurboWarp cloud fallback route, prints
  `☁ c2h[11..50]` as `#r[2]`, and labels raw `☁ c2b*` packets as inspection-only
  values that must not be fed directly to `円の中トリガ`.
- A second live probe on 2026-07-05 again showed `#r[2]` in the inactive
  placeholder state:

  ```text
  #r[2] = 0000000000000000000099999000000028700000
  active letter 1 = 0
  depth 21..23   = 999
  M 24..25       = 99
  slot 30        = 0
  ```

  Raw `☁ c2b2` packets in the same window still contained event-like envelope
  fields such as `content_depth_21_23=416` and `content_magnitude_24_25=66`,
  but the diagnostic script correctly labels those as raw packets, not direct
  circle input.

## 2026-07-05 correction: `gridトリガ` long-rise uses history slot 12

Rechecked the web SB3 `gridトリガ %s %b %s` procedure against the current Dart
`_applyKotoho7GridTriggerPermissionProxy` implementation.

Important exact Scratch expression:

```text
多目的2 =
  ten:震度履歴[((point - 1) * 10) + 1]
  - ten:震度履歴[((point - 1) * 10) + ten:震度履歴時間2000s[12]]
```

This is separate from the generic `ten:震度変化速度` path documented earlier.
The decoded history-slot setup is:

```text
震度履歴時間管理(4, 11)
震度履歴時間管理(9, 12)
震度履歴時間管理(1, 13)
震度履歴時間管理(7, 14)
```

So `gridトリガ` long-rise is the about-9-second history delta, while the
ordinary permission/rise path still uses the about-4-second slot 11 semantics.

Implemented in Dart:

- added `_kotoho7GridLongRiseChangeValue(...)` as a grid-only history delta;
- `_kotoho7GridLongRiseProxy` now uses about 9 seconds for the rising count and
  weighted score;
- the second `gridトリガ(..., 上昇割合計算のみ=false)` pass also requires the
  same about-9-second delta before promoting a point to state `5`
  (`グリッド許可`);
- the immediate `+0.5` score term remains `_kotoho7ImmediateChangeSpeedValue`,
  matching the SB3 check against history slot `+2`.

## 2026-07-05 correction: `検出id2` initial state-5 positive-rise ID3 path

Re-expanded the web SB3 `検出id2_各点の許可idと推定用をセット`.

Important decoded condition:

```text
if ten:震度[番号] > 0:
  if 現在状態 != 6 and ten:推定用[番号 + 1] == "":
    if 変化速度 > 0:
      if 現在状態 < 4:
        use nearest-7 permission support
      else if 現在状態 == 5:
        多目的0 = 1
    else:
      if 現在状態 == 5:
        多目的0 = 1

    if 多目的0 > 0:
      write ten:+1/+2
      検出id3_点にIDを登録
```

The Dart reproduction previously allowed the direct state-5 initial ID3 path
only when `変化速度 <= 0`. That was too narrow: Scratch also enters ID3 for
`現在状態 == 5` while the point is still rising and `ten:+1` is empty.

Implemented:

- `_kotoho7Id2WouldCallId3` now returns true for
  `!hasPlus1 && currentState == 5` regardless of the positive-rise flag,
  matching the SB3 branch above.
- Entry-pipeline diagnostics now classify both state-5 initial paths as
  `would_id3_initial_state5_direct`.

Related SB3 reset clarification:

- `検出id_点の推定用をリセット` clears `ten:+1`, `+2`, `+3`, `+4`, `+6`,
  `+7`, and `+8`, then calls `検出id適用数カウント追加(..., -1)` without the
  distance/PS recompute boolean.
- It does not clear `ten:+5`; that slot is managed by the surrounding ID2
  positive-change/no-positive-change branch.

Observed Tomakomai effect after the correction:

- `20260622_tomakomai_south_offshore_m35_hinet` kotoho7 replay summary:
  `estimateCount=38`, `medianErrorKm=20.0`, `p90ErrorKm=22.6`.
- Last valid estimate: `42.0167N, 141.5833E, depth=30km`, error `20.0km`,
  phase counts `P=3 / S=7 / O=6`.
- This is a large improvement over the previous state where Tomakomai was
  dominated by missing/late PS-cache membership, but depth is still not
  reproduced against the Hi-net reference depth of `100km`.

Depth-search checkpoint:

- Re-decoded the SB3 hard gates:
  `depth < 10`, `depth > 700`, `depth > @hyp:許可最大深さ`, or
  distance from the first detected point beyond `@hyp:許可最大距離` stop the
  candidate.
- The SB3 formulas match the Dart reproduction:
  `@hyp:許可最大深さ = round(11 + (4-3 +5)^3 * 8e-5)` and
  `@hyp:許可最大距離 = round(50 + 0.3 * ((4-3 +4) * 10 + (4-3 +5)))`.
- Tomakomai's final-stage same-location depth candidates are not capped out:
  `30km score=429`, `40km score=435`, and `80km score=588`.
- Therefore the remaining 30km-vs-100km mismatch should be pursued upstream in
  detection-id membership and `ten:+6` S-flag reproduction, not by changing the
  depth search cap or tuning the HYP score.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_offshore_reference_replay_test.dart test\iwate_east_offshore_reference_replay_test.dart test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
```

## 2026-07-05 correction: `検出id2` rerise and `推定用tenPS` invalid-cache semantics

Rechecked the web project SB3
`.dart_tool/external_refs/scratch-realtime-earthquake-viewer-page/docs/assets/project.json`
instead of the local v1.6.3 SB3. The local v1.6.3 file does not contain the
`検出id*` pipeline; the web project does.

Decoded `検出id2_各点の許可idと推定用をセット` rerise branch:

```text
if 現在状態 > 3.5 and 変化速度 > 0:
  多目的0 = nearest7 recent permission/rise score

  if 多目的0 == Infinity or
     (現在状態 == 6 and 多目的0 mod 10000 > 0.5
      and floor((多目的0 mod 100000) / 10000) > 0):
    if 多目的0 > 10000000:
      点許可状態更新(5, "再び震度加速")
      set ten:+1/+2 from ten:+5 or latest cloud time
      検出id3(再上昇=true)
    else:
      点許可状態更新(6, "再び震度加速用待機")
  else if 現在状態 == 5:
    set ten:+2 = latest cloud time
```

Important consequence:

- State `5` does not normally re-enter `検出id3`; it only re-enters on the
  `Infinity` path, which comes from a nearest-7 neighbor having a newer
  detection-id serial.
- State `6` is the normal rerise-wait state that can promote back to state `5`
  when the nearest-7 score is strong enough.
- The nearest-7 table is Scratch `dc ten:最短7点`, i.e. an all-station table,
  not the current replay candidate pool.

Implemented:

- `_kotoho7Id2ReriseScore` now receives `currentState` and applies the exact
  state `5` vs state `6` split above.
- The rerise nearest-7 scan now uses `_kotoho7Nearest7StationCodes`, reading
  global `ten c:揺れ検出許可` / trigger time by station code, instead of only
  neighbors present in the current replay pool.
- `_kotoho7Id2GatedAssignmentCandidates` now uses this same rerise score for
  existing `+1` candidates instead of the older compressed
  `state == 6 && nearest7Support > 0` approximation.

Decoded `推定用tenPS時間計算(多目的0,2使用)` invalid branch:

```text
if 4-3 検出id別情報[id + 11] > 3000
   or 4-4 検出id震源要素[id + 2] == "":
  ten:+7 = ""
  ten:+8 = ""
else:
  compute P/S travel times from 4-4 source cache
  ten:+7 = origin + P travel time
  ten:+8 = origin + S travel time
  ten:+6 = abs(+1 - +8) < abs(+1 - +7)
```

Implemented:

- The Dart invalid branch now checks the `4-3 +11` score proxy
  (`scratch43BestScore`) plus 4-4 source-cache availability instead of the
  transient candidate score.
- Scratch treats an empty `4-3 +11` item as numeric zero for the `> 3000`
  comparison; Dart now preserves that behavior by invalidating only when the
  score proxy is finite and greater than `3000`.
- The invalid branch clears only P/S arrival caches (`+7/+8`) and no longer
  clears the S flag (`+6`), matching the SB3 procedure.

Decoded `検出id距離計算`:

```text
ten:+4 =
  sqrt(((dtc:Xpix[4-3 +1 first station] - dtc:Xpix[station]) * 11)^2
     + ((dtc:Ypix[4-3 +1 first station] - dtc:Ypix[station]) * 11)^2)

if 4-3 +5 < ten:+4:
  4-3 +5 = ten:+4
```

So `ten:+4` is distance from the first detection point, not distance from the
current source estimate. The Dart first-station-distance cache is the right
direction for this slot.

Decoded HYP source-cache update:

```text
if @hyp:minError < (4-3 +19 bestRaw * 1.7)
   or latestCloudTime - @hyp:firstDetectedAt < 10:
  write 4-3 +8 source summary
  if @hyp:minError < 250 and age < 10:
    4-3 +11 = 250
  else:
    4-3 +11 = @hyp:minError
    if @hyp:minError < 4-3 +19:
      4-3 +19 = @hyp:minError
  4-3 +12 = firstDetectedToEpicenterDistance
  write 4-4 +2/+3/+4/+5 = lon/lat/depth/origin
  4-3 +18 = latestCloudTime
```

This matches the current Dart proxy shape: `scratch43BestScore` represents
`4-3 +11`, and `scratch43BestRawScore` represents `4-3 +19`.

Decoded HYP S-phase usage:

- `HYP:誤差レベル計算` increments `@hyp:Sカウント` from
  `ten:推定用 +6`.
- It does not recompute P/S identity for each candidate during the HYP search.
- Therefore depth recovery depends on whether `推定用tenPS時間計算` previously
  wrote `+6` for the assigned stations.

Current replay result after this fidelity correction:

| case | best error | median error | p90 error | final error | final phase counts |
| --- | ---: | ---: | ---: | ---: | --- |
| `20260621_fukushima_offshore_m32_eq6` | 82 km | 85 km | 237 km | 82 km | P:3 / S:11 / O:40 |
| `20260622_iwate_east_offshore_m30_hinet` | 3 km | 14 km | 15 km | 14 km | P:7 / S:12 / O:2 |
| `20260622_tomakomai_south_offshore_m35_hinet` | 85 km | 88 km | 112 km | 85 km | P:6 / S:1 / O:10 |

Tomakomai remains the key negative case:

- final assigned stations: 17;
- final production P/S cache: 13/17;
- final `+6` S flag count: 0;
- final depth: 10 km, `depth_supported=false`.
- missing final P/S rows are now explicitly diagnosed as
  `not_recomputed_since_source_cache_became_valid`, not as a current
  `4-3 +11`/`4-4` invalid state.

This means the remaining gap is not a simple `+6` clearing bug, not a
`ten:+4` distance-slot mismatch, and not a current `4-3 +11`/`4-4` invalid
state. The next Scratch-fidelity target is narrower: trace why early Tomakomai
members that entered before a useful source cache do not naturally re-enter
`検出id3` after the source cache becomes useful, and verify whether any
non-obvious caller can legitimately run `検出id_推定PS時間id別再計算`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\fukushima_offshore_reference_replay_test.dart test\iwate_east_offshore_reference_replay_test.dart test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
```

## 2026-07-04 full SB3 audit: `4-3 +20` / `+21`

Rechecked the full web `project.json`, not only the HYP extracted subset:

```text
.dart_tool/external_refs/scratch-realtime-earthquake-viewer-page/docs/assets/project.json
```

Finding:

- `4-3 検出id別情報 +20` is not a HYP scoring/depth/magnitude slot.
- It is written by `検出idに対応するEEW %s`.
- It is read by `検出エフェクトなど %b`.
- Inside the source-estimation/id-management path it is only copied during
  `検出id_同一震源統合`.

Decoded producer:

```text
検出idに対応するEEW(おふせ):
  if 7システム設定[62] and 7システム設定[51]:
    for each active 4-3 row:
      distance = km(EEW lon/lat, 4-4 source lon/lat)
      if distance < 300
         and EEW origin/issue time is earlier than 4-3 +3
         and 0-2EEW追加情報[おふせ + 6] first two letters equal 0:
        if 4-3 +11 is still very large
           or normalized source-vs-EEW timing/depth difference < 5:
          4-3 +20 = おふせ
```

Decoded consumer:

```text
検出エフェクトなど:
  when drawing standalone estimated-source effects:
    draw only if 4-3 +20 is empty,
    unless the debug/display override 7システム設定[53] is enabled
```

Therefore the Dart source estimator should not invent a `+20` HYP parameter.
Until an EEW replay package is explicitly wired into the local replay state,
leaving `+20` unmapped is the faithful behavior for the current GIF-only
source-estimation reproduction.

The same audit also corrected the row-shape note:

- `検出id_新規id追加` appends `+1` through `+21` to
  `4-3 検出id別情報`.
- The frequently observed `20` stride still appears in Scratch loops and
  offset math, so existing `id * 20 + slot` expressions are Scratch's own
  indexing convention rather than proof that `+21` is absent.
- The newly identified `+21` add is blank in the current web project audit;
  no producer/consumer has been found in the HYP path.

## 2026-07-04 correction: default PS-cache refresh is assignment-only

Supersedes the earlier 2026-07-03 wording that said Dart refreshes all
assigned stations after each accepted HYP update.

The SB3 execution order is:

```text
検出id1_全点へ適用
  -> 検出id2_各点の許可idと推定用をセット
  -> 検出id3_点にIDを登録
  -> 検出id適用数カウント追加(point, 距離セット=true, +1)
  -> 推定用tenPS時間計算(point, id)

then later:
推定震源計算/HYP
```

The current extracted web project contains `検出id_推定PS時間id別再計算(id)`,
but the audited reachable call path still does not prove a normal
post-HYP member-wide refresh. Therefore the faithful default is now:

- update `ten:+6/+7/+8` when a station is assigned or re-registered through the
  `距離セット=true` path;
- clear those slots when the station's `ten:+3` membership is reset;
- do not refresh every assigned member immediately after each HYP source-cache
  update unless explicitly running the old diagnostic bridge.

Dart correction:

- default `kotoho7_ps_cache_refresh_mode` is now `assignment_only`;
- `member_wide_bridge` remains available only when explicitly requested through
  request metadata, and diagnostics label it as a non-default bridge rather
  than the Scratch path.

Full-project call audit:

```text
推定用tenPS時間計算(...) calls:
  - from 検出id適用数カウント追加(point, 距離セット, 変更数)
  - from 検出id_推定PS時間id別再計算(id)

検出id_推定PS時間id別再計算(id) external calls:
  - none found in the current web project
```

Therefore the earlier `member_wide_bridge` improvement must remain a
diagnostic/non-Scratch bridge. If the assignment-only path worsens a case, the
next faithful target is station re-registration and reset timing
(`検出id2/3/4`, `検出id適用数カウント追加`, `検出id_点の推定用をリセット`), not a
post-HYP all-member PS refresh.

## 2026-07-04 correction: `4-4` source-cache write quantization

Expanded all writes to `4-4 検出id震源要素`.

Normal HYP completion writes the source cache as:

```text
4-4 +2 = round(@hyp:仮の震源 経度X * 60) / 60
4-4 +3 = round(@hyp:仮の震源 緯度Y * 60) / 60
4-4 +4 = round(@hyp:仮の震源 深さ)
4-4 +5 = round(@hyp:仮の震源 発生時刻)
```

Additional writes found in the full project:

- `HYP:誤差レベル計算` has a keypress/debug-only write of candidate values into
  `4-4 +2/+3/+4/+5`; this should not be treated as the production update path.
- `円検出の毎処理` writes `4-4 +6/+7`, which are display/EEW-circle radii used
  by map/effect logic, not HYP hypocenter coordinates.
- `epi最大距離(多目的1)or仮震央` can seed `4-4 +2/+3/+4/+5` from the temporary
  epicenter/first-detection metadata before normal HYP has a stable source.

Dart correction:

- accepted source-cache updates now quantize the stored `_HypCandidate` to the
  Scratch `4-4` precision;
- current `SourceEstimate` output also uses that quantized source-cache value;
- candidate scoring and the `+19` raw-best gate still use the original raw
  error score, matching the Scratch order of "compute best, then write rounded
  cache".

Narrow replay check after assignment-only default and `4-4` quantization:

```text
flutter test test\fukushima_offshore_reference_replay_test.dart `
  test\iwate_east_offshore_reference_replay_test.dart `
  test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
```

All three tests passed.

Current kotoho7 effective-id metrics:

| Case | estimates | best | median / p90 | final | final source | final PS cache |
|---|---:|---:|---:|---:|---|---|
| `20260621_fukushima_offshore_m32_eq6` | `44` | `57 km` | `72 / 151 km` | `57 km` | `37.9167, 141.7500, 80 km` | `+7/+8=62`, `+6 true=36` |
| `20260622_iwate_east_offshore_m30_hinet` | `36` | `13 km` | `19 / 36.5 km` | `19 km` | `39.9667, 142.1333, 70 km` | `+7/+8=43`, `+6 true=27` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `36` | `49 km` | `54 / 65 km` | `54 km` | `42.5333, 141.1833, 70 km` | `+7/+8=15`, `+6 true=2` |

Interpretation:

- The result is more faithful to the visible call graph but worse than the old
  bridge-assisted path on Tomakomai/Iwate.
- Because no external `検出id_推定PS時間id別再計算` call exists in the audited
  web project, this regression should not be fixed by restoring all-member
  refresh.
- The next reproduction target should be exact station lifecycle behavior:
  which points are removed, re-added, or re-registered through
  `距離セット=true`, because only that path recomputes `ten:+6/+7/+8`.

## 2026-07-04 correction: `検出id4-2` fallback uses `4-3 +4`

Rechecked the exact `検出id4-2_適用id震源から候補選択` branch.

The first-point fallback is:

```text
if 4 < 4-3[offset + 4]:
  recurse using:
    x/y = first station coordinates
    depth = 10
    origin = ten:+1(first station) - 3
```

So the gate is the Scratch `4-3 +4` applied-count slot, not a Dart-side set
length guess. Dart now uses `scratch43AssignedCount > 4` for this fallback.

The same pass reconfirmed the `4-4 検出id震源要素` source-cache slots used by
`検出id4-2`:

```text
4-4 +2 = x / longitude
4-4 +3 = y / latitude
4-4 +4 = depth
4-4 +5 = origin time
```

`4-3 +11` is written from `@hyp:最小誤差レベル`, so mapping it to
`sourceCache.score` remains correct.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

## 2026-07-04 correction: `検出id4` latest-id distance guard

Rechecked the `検出id4_点に適用するべきIDを検索` branch that runs after
`検出id4-1` and before the current-grid/source-cache/around-grid paths.

The Scratch guard is offset-based:

```text
if count2 == 0:
  if (
       LEN(4-3) < 40
       or (
         2 < 4-3[LEN(4-3) - 16]
         and (#r:最新クラウド変数[1] - 4-3[LEN(4-3) - 37]) > 40
       )
     )
     and (#r:最新クラウド変数[1] - 4-3[LEN(4-3) - 17]) < 10:
       if distance(current point, latest id first station) < 400:
         count2 = LEN(4-3) / 20
```

Decoded row mapping:

- `LEN(4-3) - 17` is latest row `+3`, so the 10-second test is latest-id
  creation age, not last station update time.
- `LEN(4-3) - 16` is previous row `+4`, the applied count.
- `LEN(4-3) - 37` is previous row `+3`, the previous id creation/base time.

Dart correction:

- `_selectKotoho7Id4LatestIdDistanceState` now orders states by Scratch
  append/serial order;
- the latest row must be active and have `scratch43FirstDetectionAt` age under
  `10 s`;
- if a previous row exists, it must satisfy
  `scratch43AssignedCount > 2` and previous creation age `> 40 s`;
- the 400 km first-station distance check remains unchanged.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

## 2026-07-04 correction: `検出id距離計算` uses Scratch map-pixel distance

Rechecked `検出id距離計算 %s %s`.

Scratch does not update `ten:+4` / `4-3 +5` with geographic haversine distance.
It uses the initialized map pixel tables:

```text
dx = (dtc:Xpix[firstStation] - dtc:Xpix[station]) * 11
dy = (dtc:Ypix[firstStation] - dtc:Ypix[station]) * 11
ten:+4 = sqrt(dx^2 + dy^2)
4-3 +5 = max(4-3 +5, ten:+4)
```

The `dtc:Xpix/Ypix` tables are generated at map initialization from
`d ten:x/y`:

```text
xy3 = (((longitude + 44) mod 360) - 180) * 10
xy4 = ln(tan(45 + latitude / 2)) * 572.9577951308232
      - 374.04780730560344
screenX = 1.8 * (xy3 - 16)
screenY = 1.8 * (xy4 - 41)
dtc:Xpix/Ypix = round(screenX/Y * 100000) / 100000
```

Dart correction:

- `_refreshKotoho7StationDistanceCacheForRecord` now computes the first-station
  distance with the Scratch map-pixel formula;
- `_kotoho7FirstStationRadiusKm` recomputes `4-3 +5` from the same formula;
- true `緯度経度で距離km` branches remain geographic and were not changed.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

## 2026-07-04 correction: `4-3 +10` is not a refreshed source-distance max

Rechecked all reachable HYP / detection-id writes to `4-3 検出id別情報`.

Finding:

- `検出id_新規id追加` initializes `4-3 +10` as empty.
- `検出id4-2_適用id震源から候補選択` only reads `4-3 +10` in the old-wide
  rejection:

```text
if sourceDistance > 900:
  if age > 100 and 1.5 * 4-3 +10 < sourceDistance:
    reject
```

- The only reachable write found after initialization is in
  `検出id_同一震源統合`, where `+10` is copied from another `4-3` row.
- No reachable HYP/source-cache update writes `4-3 +10` as
  "max source-to-station distance".

Dart correction:

- `scratch43MaxSourceDistanceKm` now starts at `0.0`, matching Scratch empty
  numeric behavior for this comparison;
- `_refreshKotoho7StatefulSourceCacheMetadata` no longer refreshes `+10` from
  source-to-station haversine distance;
- the `age > 100` wide-distance gate no longer has the Dart-only
  `sourceDistanceLimitKm > 0` guard, so an empty/zero `+10` behaves like
  Scratch;
- the same metadata refresh now also keeps `4-3 +5` on the Scratch map-pixel
  distance path instead of reintroducing a haversine max.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

## 2026-07-04 correction: `検出id_同一震源統合` metadata copy

Expanded `検出id_同一震源統合 %s %s %b`.

When executing a merge, Scratch first rewrites member station `ten:+3` from
`id1` to `id2`, then conditionally copies selected `4-3` slots:

```text
if 4-3[id2 + 11] > 4-3[id1 + 11]:
  copy +4, +5, +8, +9, +10, +11, +18 from id1 to id2

if 4-3[id2 + 3] > 4-3[id1 + 3]:
  copy +1, +3, +12 from id1 to id2

if 4-3[id2 + 6] > 4-3[id1 + 6]:
  copy +6, +7 from id1 to id2

if 4-3[id2 + 19] < 4-3[id1 + 19]:
  copy +19 from id1 to id2

if 4-3[id2 + 20] < 4-3[id1 + 20]:
  copy +20 from id1 to id2

set id1 +2 inactive
```

Dart correction:

- `_copyScratch43MetadataForSameSourceMerge` no longer uses `max` for mapped
  `+4/+5/+10/+11` fields;
- when the source row has a lower `scratch43BestScore` (`4-3 +11`), Dart now
  copies:
  - `scratch43AssignedCount` (`+4`);
  - `scratch43MaxFirstStationDistanceKm` (`+5`);
  - `scratch43ExpireAt` (`+9`);
  - `scratch43MaxSourceDistanceKm` (`+10`);
  - `scratch43BestScore` and best source cache (`+11` / `4-4`).

Dart correction after the first pass:

- `firstStationCode`, `initialLatitude`, and `initialLongitude` are now mutable
  state fields;
- when the source row has an earlier `scratch43FirstDetectionAt` (`4-3 +3`),
  Dart copies `firstStationCode` / initial coordinates as the mapped `+1`
  equivalent.
- `scratch43LastSourceCacheUpdatedAt` now maps `+18`: it is written when the
  owned source cache is updated and copied together with the better `+11` row.
- `scratch43LastMaxCurrentShindoIndex` / `scratch43PreviousMaxCurrentShindoIndex`
  now map `+6/+7` more faithfully:
  - `+6` is computed from assigned stations'
    `scratchDetectionPermittedShindo` through the Scratch 30-step shindo
    conversion table;
  - `+7 = +6` is still applied in the active-state not-expired branch;
  - merge copies `+6/+7` when the source row has a smaller `+6`, matching
    `if 4-3[id2 + 6] > 4-3[id1 + 6]`.
- `scratch43BestRawScore` now maps `+19`:
  - it initializes as infinity;
  - source-cache updates are accepted only when
    `bestError < 4-3 +19 * 1.7` or the id age is under `10 s`;
  - when accepted, `+19` is updated to the smaller raw best error;
  - `+11` remains separate and is written as the accepted display/selection
    score, including Scratch's early `<250` clamp to `250`;
  - merge copies the larger `+19`, matching the sb3 branch.

Still not mapped:

- `+20` does not yet have an explicit Dart field. In the extracted reachable
  blocks it initializes as empty and is only copied during same-source merge;
  no independent producer/consumer has been found yet.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

## 2026-07-04 correction: `検出id2` `現在状態` uses `ten c:揺れ検出許可`

Rechecked the extracted `検出id1_全点へ適用` call from the web project and the
local v1.6.3 sb3:

```text
検出id2_各点の許可idと推定用をセット(
  番号 = count1,
  変化速度 = ten:震度変化速度[count1],
  現在状態 = ten c:揺れ検出許可[count1],
  7点スタート = 1 + 14 * (count1 - 1)
)
```

Important correction:

- `現在状態` is the Scratch permission cache `ten c:揺れ検出許可`, not the
  `ten:推定用` slot lifecycle cache.
- Unknown / never-promoted stations therefore enter `検出id2` as state `0`.
  They must be promoted by the reproduced `揺れ検出許可` / `単独トリガ` /
  `複数トリガ` / `gridトリガ` pipeline before they can use the state-`5`
  direct registration path.
- The old diagnostic wording that used
  `scratchStationPermissionState` or `_initialKotoho7StationPermissionState`
  as an `id2` fallback is now superseded.
- The `検出id2` branches that set waiting/re-rise states call
  `点許可状態更新`, so Dart now writes those `5/6` changes back into
  `scratchDetectionPermissionState`, matching `ten c:揺れ検出許可`.
- Nearest-7 support for `検出id2` now counts neighbors with
  `scratchDetectionPermissionState >= 5`; it no longer falls back to the
  separate `ten:推定用` diagnostic cache.

Follow-up correction in the same `検出id2` block:

- The initial-registration branch still only needs positive nearest-7
  permission support (`多目的0 > 0`), because Scratch increments `多目的0` for
  neighbors whose `ten c:揺れ検出許可 == 5`.
- The existing-member re-rise branch is stricter. Dart now reproduces the
  Scratch `多目的0` accumulator:
  - neighbor trigger age `< 5s` and permission `5/6`: `+10000000`;
  - the same neighbor in permission `5`: extra `+20000`;
  - neighbor `ten:震度変化速度 > 0` and permission `> 4`:
    `+10000 + changeSpeed`;
  - if the current point's `ten:+3` detection id is lower than the neighbor's
    `ten:+3`, divide the current accumulator by `10`.
- State `6` now only promotes back to `5` and calls `検出id3` when the Scratch
  conditions are satisfied:
  `multi0 % 10000 > 0.5`,
  `floor((multi0 % 100000) / 10000) > 0`, and
  `multi0 > 10000000`.
- If the first two re-rise conditions pass but `multi0 <= 10000000`, Dart keeps
  the point in permission state `6`, matching Scratch's
  `再び震度加速用待機` branch.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

## 2026-07-04 correction: `検出id4-1` nearest-7 existing-id inheritance

Rechecked the `検出id3 -> 検出id4` ordering:

- `検出id3_点にIDを登録` first has the outer latest-id shortcut:
  `timer < 10 && LEN(4-3 検出id別情報) > 0`.
- If that shortcut does not set `count2`, `検出id4_点に適用するべきIDを検索`
  begins with `検出id4-1_適用id最短7から候補選択`.

Decoded `検出id4-1` behavior:

```text
multi1 = 10
for nearest entries in dc ten:最短7点:
  stop if count3 > 12 or nearest distance > 40 km
  neighborOffset = 10 * (nearestStationIndex - 1)
  if ten c:揺れ検出許可[neighbor] is 4 or 5
     and ten:推定用[neighborOffset + 3] > 0:
       delta = abs(current.ten:+1 - neighbor.ten:+1)
       if delta < multi1:
         count2 = neighbor.ten:+3
         multi1 = delta
```

Dart correction:

- Added `_selectKotoho7Nearest7ExistingIdState` after the outer latest-id
  shortcut and before current-grid / source-cache / around-grid selection.
- It uses the extracted nearest-7 table, stops at `40 km`, requires neighbor
  permission `4/5`, requires an active `ten:+3` owner, and selects the owner
  with the smallest `ten:+1` time delta under `10 s`.
- The resulting selection sources are:
  - `scratch_id4_1_nearest7_existing_id`;
  - `scratch_id4_1_nearest7_existing_id_other_state`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

## 2026-07-04 correction: `検出id3` latest-id shortcut uses Scratch `timer`

Rechecked the `検出id3_点にIDを登録` outer shortcut:

```text
if timer < 10 and LEN(4-3 検出id別情報) > 0:
  count2 = LEN(4-3 検出id別情報) / 20   # latest id
else:
  検出id4_点に適用するべきIDを検索(...)
```

Important correction:

- Scratch uses `sensing_timer`. The reference web project and the local v1.6.3
  sb3 contain no `control_resettimer`, so this is the global Scratch/TurboWarp
  runtime timer, not the age of the current earthquake/detection id.
- The earlier Dart shortcut that treated a young active id as equivalent to
  `timer < 10` is now superseded.
- Dart now enables this shortcut only when replay metadata explicitly provides
  `kotoho7_scratch_runtime_timer_s < 10`. Without that metadata, the shortcut is
  disabled and the flow continues into `検出id4`, which is the faithful replay
  behavior for normal long-running production.
- The `first-station distance < 400 km` rule belongs to a later `検出id4`
  branch, not to this `検出id3` outer shortcut.

Follow-up correction:

- The later `検出id4` branch has now been restored in the correct position:
  after `検出id4-1` nearest-7 inheritance and before current-grid/source-cache
  selection.
- Dart implements this as `_selectKotoho7Id4LatestIdDistanceState`:
  latest active `4-3` id, updated within `10 s`, and current point within
  `400 km` of that id's first station.
- Selection sources:
  - `scratch_id4_latest_id_distance`;
  - `scratch_id4_latest_id_distance_other_state`.
- Remaining fidelity note: the decoded Scratch condition also checks detailed
  `4-3 検出id別情報` offsets around the latest id. Dart uses the existing
  `scratch43*` metadata proxy for this branch; the exact offset-level guard is
  still a later replication target.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

## 2026-07-04 correction: `検出id4-2` age gate uses `4-3 +3`

Rechecked `検出id_新規id追加` and `検出id4-2`.

`検出id_新規id追加` writes the third `4-3 検出id別情報` slot as:

```text
4-3 +3 = #r:最新クラウド変数[1]
```

So the `検出id4-2` age checks are detection-id age checks, not earliest station
trigger age:

```text
age = now - 4-3[offset + 3]

source-cache branch:
  age > 5
  and 4-3[offset + 11] < 500
  and 4-4 source cache exists

wide-distance rejection:
  distance > 900
  and (
    age > 100 and 1.5 * 4-3 +10 < distance
    or age > 15 and 1.4 * 4-3 +5 < distance
  )
```

Dart correction:

- new kotoho7 states now set `scratch43FirstDetectionAt = observedAt`, matching
  `4-3 +3 = now` at id creation;
- `検出id4-2` source-cache and wide-distance age gates now use
  `observedAt - scratch43FirstDetectionAt`;
- diagnostics now expose `detection_id_age_s` and
  `scratch43_first_detection_at` for accepted 4-2 stations.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

## 2026-07-04 correction: `単独トリガ` fast-rise energy gate

Rechecked local v1.6.3 SB3 `単独トリガ 状態` and `点震度の処理`.

Important correction:

- `上昇速度早すぎおかしい` is not the 4-second
  `ten:震度変化速度` value.
- It is a direct `ten:震度履歴` slot comparison:

```text
if 上昇制限 == 0:
  limit = 75
else:
  limit = 上昇制限 * 上昇制限

if limit < (3 + ten:震度履歴[(番号 - 1) * 10 + 1])^2
           - (3 + ten:震度履歴[(番号 - 1) * 10 + 3])^2:
  点許可状態更新(番号, 0, "上昇速度早すぎおかしい")
  stop
```

Also separated the `d ten:しきい` digit mapping by caller. The actual
`単独トリガ 状態` call in `点震度の処理` uses:

- digit 1 -> `しきい値`;
- digit 2 -> `点数`;
- digit 3 -> `上昇制限`.

This is different from the already-documented `複数トリガ 状態` /
`揺れ検出許可` path, where the call passes digit 3 as `最低点数`, digit 2 as
`しきい値`, and digit 1 as `上昇制限`.

Dart correction:

- `_kotoho7ScratchFastRiseEnergyExceedsLimit` now maps replay
  `observationHistory` to the recent Scratch history slots and applies the
  slot-1/slot-3 squared-energy gate before the other `単独トリガ` branches.
- `_kotoho7NextDetectionPermissionState` now uses the `単独トリガ` mapping for
  single-trigger branches and the `複数トリガ` mapping for multi-trigger /
  acceleration branches.

Still not claimed complete:

- `最大震度と時間経過` still depends on the reproduced
  `4リアルタイム状況(最大震度など)[1]` path and should not be approximated from
  unrelated max values.
- `円の中トリガ` remains EEW-circle dependent and should be wired only after
  the EEW replay equivalent is explicit.

## 2026-07-04 correction: `単独トリガ` normal-trigger refresh

Decoded the remaining `震度履歴時間管理 %s %s` calls from local v1.6.3 SB3:

```text
震度履歴時間管理(4, 11)
震度履歴時間管理(9, 12)
震度履歴時間管理(1, 13)
震度履歴時間管理(7, 14)
```

Therefore `ten:震度履歴時間2000s[13]` is the about-1-second history slot, not
the 4-second `ten:震度変化速度` slot.

Scratch `通常トリガ更新` branch:

```text
if 現在状態 == 3:
  if しきい値 < 4:
    if (dc ten:最短7点[7点スタート + 5] < 40
        or elapsed > 10)
       and 0.3 < (ten:震度履歴[+1]
                  - ten:震度履歴[+ ten:震度履歴時間2000s[13]]):
      点許可状態更新(番号, 3, "通常トリガ更新", 強制更新=true)
```

`dc ten:最短7点` stores `(distanceKm, stationIndex)` pairs, so `+5` is the
third-nearest distance.

Dart correction:

- `_kotoho7HistoryChangeValue(... targetSeconds: 1)` now represents the slot-13
  rise used by `通常トリガ更新`.
- The previous replay proxy
  `(nearest7CurrentSupport > 0 || elapsed > 10) && rising` was replaced by the
  Scratch condition: `しきい値 < 4`, third-nearest distance `< 40 km` or
  elapsed `> 10 s`, and 1-second history rise `> 0.3`.

## 2026-07-04 audit: `単独トリガ` `円の中トリガ`

Decoded local v1.6.3 SB3 `円の中か判定(多目的0) %s %b %s` and the inline
`円の中トリガ` branch.

Standalone circle helper:

```text
多目的0 = 0
for slot in 0..9:
  if 0EEW[slot * 14 + 1] > 0:
    if ten c:震源距離[(番号 - 1) * 10 + slot + 1]
       < 0EEW[slot * 14 + 12 + s波] + おふせ:
      多目的0 = 1
      stop
```

The `単独トリガ 状態` branch is more restrictive:

```text
if 現在状態 == 3 and しきい値 < 4:
  if (点数 == 1 and 震度 >= -0.5)
     or (elapsed < 10 and 震度 >= 0.5):
    if EEW全体で発表中？ == 1:
      for slot in 0..9:
        if 0EEW[slot * 14 + 8] < 150
           and 0-1EEW発表中[slot + 1] > 0:
          if stationDistance >= 200:
            距離の震度(stationDistance, 0EEW[slot*14+9],
                     0EEW[slot*14+8], 1)
          if 距離の震度 > -0.5 or stationDistance < 200:
            if 0EEW[slot*14+13] - 100 < stationDistance:
              if 0-2EEW追加情報[slot*14+3] * 0EEW[slot*14+13]
                    < stationDistance
                 and stationDistance < 0EEW[slot*14+12] * 0.8:
                点許可状態更新(番号, 5, "円の中トリガ")
                stop
```

Current Dart status:

- This branch is **not connected to production estimation**, because the NIED
  GIF source-estimation request currently carries station GIF/source-trigger
  metadata but not Scratch-equivalent `0EEW`, `0-1EEW発表中`,
  `0-2EEW追加情報`, or `ten c:震源距離` per EEW slot.
- Added an explicit diagnostic block
  `single_trigger_circle_eew_gate` to the kotoho7 reference diagnostics. It
  reports `implemented=false`, `missing_scratch_eew_circle_inputs`, the exact
  Scratch requirements, and any expected metadata keys that are present.
- Do not approximate this branch from final JMA truth, current HYP candidate,
  or P2PQuake text. Scratch uses live EEW circle state, not a solved source
  estimate.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

## 2026-07-04 SB3 check: `点許可状態更新` and `NG加速`

Decoded `点許可状態更新 %s %s %s %b`:

```text
args: 番目, 内容, 理由, 強制更新

if ten c:揺れ検出許可[番目] != 内容 or 強制更新:
  if 強制更新 or (内容 > 1 and 内容 != 6) or ten c:揺れ検出トリガー時間[番目] == 0:
    ten c:揺れ検出トリガー時間[番目] = #r:最新クラウド変数[1]
  ten c:揺れ検出許可[番目] = 内容
  if 理由 == 補助解除 or 内容 == 2:
    stop this script
```

Dart alignment:

- `_setKotoho7DetectionPermissionState` already follows the same trigger-time
  refresh condition: forced, or `nextState > 1 && nextState != 6`, or missing
  trigger time.
- The `stop this script` branch affects the caller's Scratch control flow; the
  Dart state-machine still needs the surrounding `単独トリガ` / `複数トリガ`
  control-flow comparison before claiming full permission reproduction.

Decoded `NG加速 %s`:

```text
多目的0 = baseY + slope * (candidateX - baseX)
if upperSide:
  if candidateY < 多目的0: 多目的0 = 1
else:
  if 多目的0 < candidateY: 多目的0 = 1
```

Important naming correction:

- Although the procedure is named `NG加速`, its caller continues and applies
  acceleration only when `多目的0 == 1`.
- Therefore Dart's `_kotoho7ScratchNgAccelerationAccepted` predicate is not
  inverted; it intentionally returns the same side-of-line condition that
  Scratch uses as the continue/accepted flag.

## 2026-07-04 correction: add `周りの多くが許可or揺れてるから`

Re-expanded `複数トリガ 状態` with corrected variable-reporter rendering.

The missing SB3 branch is inside:

```text
if 現在状態 < 5:
  if 震度 > -1 and (上昇制限 < 4 or 震度 < 1.5):
    scan first 5 nearest points:
      多目的1 = count(ten c:揺れ検出許可[neighbor] > 4)
      多目的0 = count(ten:震度[neighbor] > 5)
      c[1] = sum(converted neighbor shindo)

    if 現在状態 == 4 and 多目的1 > 0:
      点許可状態更新(5, "1点の近くで許可があったから")

    if 震度 < (c[1] / 5) + 1.6:
      if 多目的1 > 2 or (多目的1 > 0 and 多目的0 > 4):
        if 7システム設定[51]:
          点許可状態更新(6, "周りの多くが許可or揺れてるから")
        else:
          点許可状態更新(5, "周りの多くが許可or揺れてるから")
```

Checked both the web project and local v1.6.3 SB3:

- `7システム設定[51] == False`

Implemented in Dart:

- added `_kotoho7Nearest5MultiTriggerSummary`, using the Scratch nearest-7
  table but only the first five neighbors for this branch;
- changed the state-4 nearby permission promotion to use first-five
  `permission > 4`, matching the SB3 branch;
- added the missing first-five surrounding-permission/high-shindo/average
  branch and defaulted it to state `5`, matching the observed
  `7システム設定[51] == False`;
- removed the older all-seven permission-support helper from this path.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

## 2026-07-04 correction: state `3/4` no-time-area cleanup

The decoded `複数トリガ 状態` state `3/4` normal-permission branch does not
merely fail to promote when the time-area gates fail. It actively writes state
`0` in two cases:

```text
if (c[1] < 5 and thirdNearestDistance < 60) or c[1] < 2:
  点許可状態更新(0, "時間エリア内に点なし")
else:
  if 現在状態 == 4 and c[1] < 7:
    点許可状態更新(0, "1点検知の時間切れ")
```

Dart correction:

- `_Kotoho7DetectionAcceleration` now exposes `hasEnoughObservedPoints`, the
  exact `時間エリア内に点なし` gate used by the normal-permission accumulator.
- For state `3/4`, if normal permission does not pass and the time-area gate is
  false, Dart now writes state `0`.
- For state `4`, if normal permission does not pass and `c[1] < 7`, Dart now
  writes state `0` for the one-point timeout branch.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

## 2026-07-04 correction: `単独トリガ` point-missing and time-over branches

Rechecked the decoded `単独トリガ 状態` control flow:

```text
if 震度 == -9:
  点許可状態更新(1, "点なし解除")
  stop

if not 7システム設定[51]:
  if 現在状態 > 4 and elapsed > 400:
    if 震度 > 0.45 and 変化速度 > 0:
      点許可状態更新(5, "時間overから上昇", 強制更新=true)
```

Both the web project and local v1.6.3 SB3 have
`7システム設定[51] == False`, so the `時間overから上昇` branch is active by
default.

Dart correction:

- `currentShindo == null` is now treated as the closest replay equivalent of
  Scratch `震度 == -9`, so the permission cache writes state `1` with reason
  `scratch_permission_point_missing_release` instead of preserving stale state
  or timing out to state `0`.
- For state `> 4`, `triggerAgeSeconds > 400`, `convertedShindo > 0.45`, and
  positive change speed, Dart now writes state `5` with forced trigger-time
  refresh, matching `時間overから上昇`.

Completed after this note:

- `上昇速度早すぎおかしい` is now mapped from Scratch history slot `+1` and
  `+3` squared-energy difference; see the 2026-07-04 fast-rise correction
  above.

Completed after this note:

- `最大震度と時間経過` now uses a reproduced
  `検出許可震度算出` source for `4リアルタイム状況(最大震度など)[1]`: the maximum
  current `ten:震度100`-equivalent value among points whose
  `ten c:揺れ検出許可 >= 4`.
- The timeout is applied as Scratch writes it:
  `120 + 10^(1 + maxShindo / 1.2)`, demoting to state `1` with
  `scratch_permission_max_shindo_elapsed`.

Still not claimed complete:

- `円の中トリガ` remains EEW-circle dependent and should be wired only after
  the EEW replay equivalent is explicit.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```
