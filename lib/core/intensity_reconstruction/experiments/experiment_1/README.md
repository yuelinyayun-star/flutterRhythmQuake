# 算法实验 1：JMA 烈度反演迁移

## 目的

本目录用于从 GSTSL 烈度反演原理向日本 JMA 震度体系迁移的独立实验。

实验首先理解原论文中每个变量的物理含义，再决定哪些数学结构可以保留、哪些内容必须使用日本资料重新建立。这里不直接连接现有 KA/HYP、生产 UI、通知或地图，也不把其他震源算法的参数作为本实验事实。

## 来源层级

1. 原理来源：
   `references/papers/2010_马干等_利用地震烈度数据重构历史地震震级和震中位置的方法.pdf`
2. 原论文的方法补充：
   `references/papers/2009_张杨等_华北地区烈度衰减模型及震中震级定量估算.pdf`
3. 日本场地资料：`lib/core/utils/jma_seis_int_loc.dart`
4. NIED 实时输入定义：
   <https://www.kyoshin.bosai.go.jp/ja/about_kmoni/>
5. 项目内待溯源、待统一的 JMA 风格公式实现：
   `lib/core/intensity_calculator.dart`、
   `lib/core/source_estimation/static_intensity_attenuation.dart` 和
   `lib/core/source_estimation/source_estimator.dart`
6. KA Yahoo/GIF、现有震源推算和其他实验代码只作为数据来源或对照，不决定本实验的算法语义。

## 当前阶段

当前已完成松崎等（2006）原系数前向模型、点震源三维距离、零/一/双根震级反解、
2020-2022 JMA 现代计测震度前向基线、历史近场扩展和固定论文饱和结构的 2017 选择/
2018 冻结评估。固定结构模型避免了自由拟合的饱和项退化，并改善冻结年的事件等权
全距离 RMS，但一个含 98 个近场站的事件明显恶化，因此尚不接入生产。

未知事件候选点震源的经纬度、深度和共同震级联合搜索也已完成代码与合成测试，见
`matsuzaki_2006_joint_inversion.md`。这只完成搜索器闭环，尚未完成真实历史事件端到端
盲测、置信标定或生产接入。

已确认内容记录在 `decision_log.md`，逐变量替换范围记录在
`jma_replacement_audit.md`，现有 2020-2022 JMA 数据分层记录在
`jma_dataset_audit_2020_2022.md`，日本官方业务链、直接震度衰减式、场地项和
适用范围记录在 `japanese_forward_model_sources.md`，首轮现代 JMA 结果记录在
`matsuzaki_2006_jma_baseline_2020_2022.md`。任何尚未取得数据或公式依据的内容必须留在
“待验证”，不能写成默认参数。

## 当前实验代码

- `matsuzaki_2006_attenuation_model.dart`：式（12）前向计算、解析转折点和全根反解。
- `matsuzaki_2006_geometry.dart`：点震源三维震源距，不设置距离下限。
- `matsuzaki_2006_finite_fault_geometry.dart`：地表测站到显式有限矩形断层及多断层并集
  的三维最短距离，不无限延伸断层面。
- `matsuzaki_2006_source_backed_distance_overrides.dart`：统一管理已审计事件几何，复制
  严格基线事件并替换全部接受站距离；保留点源距、真实断层距和论文域状态。
- `matsuzaki_2006_jma_baseline.dart`：现代 JMA 前向残差、排除原因和分层报告。
- `matsuzaki_2006_candidate_scoring.dart`：全根共同簇与前向共同震级两种显式候选评分。
- `matsuzaki_2006_archive_inversion_input.dart`：只从 JMA 事件 ID 和原始逐站震度/坐标
  构建最高震度锚点、搜索边界与固定候选站集，不读取目录震源作为算法输入。
- `matsuzaki_2006_joint_inversion.dart`：未知事件候选点震源的自适应水平边界、深度和
  共同震级联合搜索，保留边界、多解、预算、无解和分辨率诊断状态。
- `matsuzaki_2006_coefficient_calibration.dart`：全局测站加权拟合、事件源项剥离拟合、
  多起点非线性诊断和分层评估。
- `tool/matsuzaki_2006_jma_baseline.dart`：读取年度 JSON 并生成完整报告。
- `tool/matsuzaki_2006_candidate_scoring_diagnostic.dart`：固定目录深度的水平候选诊断。
- `tool/matsuzaki_2006_archive_input_audit.dart`：使用已打开审计年检查来源独立锚点、
  固定站集、硬边界覆盖率和输入状态，不把目录真值喂给输入构建器。
- `tool/matsuzaki_2006_coefficient_calibration.dart`：2020 训练、2021 验证、2022 冻结
  测试及完整报告。
- `tool/matsuzaki_2006_structure_identifiability.dart`：固定/释放 `c,d` 的结构可辨识性
  对照，并明确区分验证集与已打开留出集复用诊断。
- `tools/build_jma_intensity_nearfield_expansion.ps1`：下载和导入历史官方震度归档，保存
  URL、原始文件和 SHA-256，不调用生产训练器。
- `tool/matsuzaki_2006_nearfield_audit.dart`：逐年流式汇总严格松崎域内的近场事件、
  测站和残差，默认拒绝预声明的 2018 冻结年。
- `tool/matsuzaki_2006_nearfield_calibration.dart`：事件等权近场阈值敏感性实验，并同时
  检查近场验证和全距离外推。
- `tool/matsuzaki_2006_near_far_balance.dart`：近远场分组事件目标、固定论文饱和结构、
  2017 预声明门槛和冻结候选选择。
- `tool/matsuzaki_2006_frozen_year_evaluation.dart`：只读取已冻结模型评估 2018，要求
  显式 `--allow-frozen-year`，不包含拟合或模型重选。
- `tool/matsuzaki_2006_finite_fault_distance_catalog.dart`：同时输出既有近场诊断人口与
  六个来源事件的全部接受站距离人口。
- `tool/matsuzaki_2006_finite_fault_migration_diagnostic.dart`：固定目录震源和系数，比较
  点源距与已审计有限断层距的逐站前向迁移误差；不进入未知事件搜索或生产。
- `tool/matsuzaki_2006_source_backed_point_source_inversion_diagnostic.dart`：将六个有来源
  有限断层几何的事件按未知事件处理，运行候选点源联合搜索并只做事后误差比较。
- `tool/matsuzaki_2006_source_backed_depth_profile_diagnostic.dart`：固定上一轮返回的水平
  候选位置，逐 5 km 扫描深度并重新优化共同震级，识别深度边界和不可辨识包络。
- `tool/matsuzaki_2006_finite_fault_semantic_calibration.dart`：按有限断层/点源混合距离
  语义重跑 2010-2016 固定结构校准和 2017 选模，不读取 2018。
- `tool/matsuzaki_2006_finite_fault_frozen_2018_evaluation.dart`：读取已冻结选择后，比较
  2018 点源、大阪单矩形和双矩形联合三个分支，不回写参数或默认模型。
- `tool/matsuzaki_2006_osaka_finite_fault_diagnostic.dart`：对大阪府北部地震保持观测和
  系数不变，比较点震源、单矩形和双矩形并集距离。
- `tool/matsuzaki_2006_kumamoto_m65_finite_fault_diagnostic.dart`：直接使用 NIED 破裂
  起点在有限断层网格内的位置，对熊本 `Mj 6.5` 比较点震源距和断层最短距离。
- `tool/matsuzaki_2006_tottori_m66_finite_fault_diagnostic.dart`：使用 NIED 和同行评审
  论文的 `8 x 8` 子断层网格，对鸟取县中部 `Mj 6.6` 做同配对距离诊断。
- `tool/matsuzaki_2006_ibaraki_m63_finite_fault_diagnostic.dart`：使用 JMA 修订近地强震
  波形反演的 `10 x 8` 子断层网格，对茨城县北部 `Mj 6.3` 做同配对距离诊断。
- `tool/matsuzaki_2006_nagano_2014_m67_finite_fault_diagnostic.dart`：按 JMA 修订反演
  `Mark=1` 的连续 `7 x 4` 有效子断层边界，对 2014 长野县北部 `Mj 6.7` 做诊断。
- `tool/matsuzaki_2006_fukushima_nakadori_m64_finite_fault_diagnostic.dart`：使用 JMA
  修订近地反演全部 `Mark=1` 的 `7 x 6` 子断层网格，对福岛县中通 `Mj 6.4` 做诊断。
- `matsuzaki_2006_kumamoto_m58_finite_fault_audit.md`：核对 JMA/NIED 官方目录和 JMA
  技术报告，记录熊本 `Mj 5.8` 没有可用独立有限断层模型的审计边界。
- `matsuzaki_2006_aso_m58_finite_fault_audit.md`：核对阿苏 DD 重定位、官方目录和正式
  文献元数据，防止把复杂震源簇或其他熊本事件断层面分配给阿苏 `Mj 5.8`。
- `matsuzaki_2006_nagano_m59_finite_fault_audit.md`：核对 JMA 月报图面、JMA 震源过程
  目录和 NIED 余震定位，防止把 03:59 主震模型或整个余震云分配给 04:31 `Mj 5.9`。
- `matsuzaki_2006_nagano_m53_finite_fault_audit.md`：独立核对 05:42 `Mj 5.3` 的 JMA
  震度图和官方目录，防止复用主震或 04:31 余震的几何。
- `matsuzaki_2006_awaji_m63_finite_fault_audit.md`：区分 JMA/EPS 的大反演计算面与
  约 6 km 实际同震破裂区，记录当前缺少唯一三维数值边界的审计结论。
- `matsuzaki_2006_sanriku_m75_finite_fault_audit.md`：核对东日本主震后 `15:25`
  三陆冲 M7.5 的事件身份和官方目录，防止复用主震或相邻 M7 事件模型。
- `matsuzaki_2006_miyagi_oki_m72_finite_fault_audit.md`：区分 JMA 近地/远地反演计算面
  与远地正文报告的约 `30 x 20 km` 实际尺度，记录当前缺少唯一面内边界的结论。
- `matsuzaki_2006_iburi_m67_curved_fault_audit.md`：归档 NIED/Kubo 2020 修订曲面模型
  的 150 个子断层数字几何，并记录当前无点源近场站、不压扁成单矩形的边界。
- `matsuzaki_2006_finite_fault_distance_catalog.md`：从原始年度文件统一生成 6 个事件、
  213 个唯一近场配对和 311 条几何变体距离，并逐站对照单事件报告。

这些代码只由 `experiments/experiment_1/experiment_1.dart` 导出，不从生产算法 barrel
导出。

首轮固定目录深度候选诊断见 `matsuzaki_2006_candidate_scoring_diagnostic.md`。其中原
系数前向误差面普遍在 `+/-0.3°` 网格边界继续下降。后续联合搜索器已经加入水平边界
扩展、深度网格、共同震级搜索和明确的未收敛状态，但尚未在真实历史事件上完成盲测。

来源独立 JMA 输入及 2019 已打开审计年半径敏感性见
`matsuzaki_2006_archive_input_audit_2019.md`。最高震度锚点不读取目录震源，但当前经纬度
矩形硬域在覆盖率和固定站集 500 km 安全约束之间存在冲突；后续已经改为显式公里
圆形域，并在同一 2019 人口中冻结初始 `100 km`、硬半径 `250 km`。尚未打开新的最终
留出年份，网格层级、计算预算和端到端门槛仍需先冻结。

联合反演的 10/30/100 站敏感性见
`matsuzaki_2006_joint_station_count_sensitivity_2019.md`。100 站降低了震中和震级误差，
证明 30 站上限不足；但 100 站仍截断 26/44 个事件，也没有降低深度硬边界总数，因此
最大站数尚未冻结，不能进入最终留出评价。

固定目录水平位置的深度-震级剖面见
`matsuzaki_2006_depth_magnitude_identifiability_2019.md`。100 站下，每层重估 `Mj` 仍有
25/44 和 28/44 个深度边界；固定目录 `Mj` 后仍有 19/44 和 25/44。目录震源残差进一步
确认远场报告站的系统正残差会把论文原系数推向深度上界，因此不再扩大深度或调整搜索器。

2010-2019 原始 DAT 的条件选站诊断见
`matsuzaki_2006_archive_selection_2010_2019.md`。1013 个事件、349641 条原始记录逐事件
匹配官方“震度 1 以上站数”，最低连续计测震度为 `0.5`。该下界已写入独立输入规格；
未归档站不补 0、不加入未经验证的单侧惩罚。下一步转向逐站长期残差。

现代系数拟合和按年份定位复测见
`matsuzaki_2006_coefficient_calibration_2020_2022.md`。两种自由拟合都把饱和指数压到
接近零；该结果只保留为经验退化模型诊断，不作为已采用的日本前向公式。

固定论文 `c,d`、固定 `d` 拟合 `c`、固定 `c` 拟合 `d` 的结构可辨识性实验见
`matsuzaki_2006_structure_identifiability_2020_2022.md`。当前训练集中 `<30 km` 记录
只有 `0.741%`，自由参数分别走向 `d -> 0` 或 `c -> 0`，不能从该归档稳定确定近场
饱和参数。

2010-2019 官方归档扩展、2018 冻结边界、近场样本集中度和近场窄域拟合反例见
`matsuzaki_2006_nearfield_expansion_2010_2019.md`。扩展后校准池有 72 个近场事件和
1,181 条记录，但近场自由拟合严重破坏全距离验证，因此仍未采用新系数。

固定论文饱和结构的 2017 选择见
`matsuzaki_2006_fixed_saturation_selection_2017.md`，2018 一次性冻结评估见
`matsuzaki_2006_frozen_2018_evaluation.md`。冻结模型维持事件等权近场指标并改善
全距离指标，但近场测站加权指标被单个高站数事件显著拉坏；下一步研究有限断层距离、
事件序列和逐站长期偏差，不再用 2018 回调系数。

大阪反例的有限断层对照见 `matsuzaki_2006_osaka_finite_fault_diagnostic.md`。该诊断
确认论文 `X` 对强震会使用断层最短距离，而此前现代校准全部使用点震源距离。跨年份
有限断层目录、统一距离语义重标定、2018 冻结评价和大阪独立双矩形判定均已完成。
下一步是量化混合距离标定系数用于未知事件候选点源搜索时的迁移误差，再研究事件序列
和逐站长期偏差，不能使用 2018 回调系数。

2010-2018 的论文距离条件清单见
`matsuzaki_2006_finite_fault_event_inventory_2010_2018.md`。当前有 14 个可独立评估
候选和 9 个观测不可分配的复合记录候选；大阪、熊本 M6.5、鸟取 M6.6、茨城 M6.3、
2014 长野 M6.7 和福岛县中通 M6.4 已完成诊断，
熊本地方、阿苏地方两场 M5.8 和长野县北部 M5.9、M5.3 已审计但未找到可用模型，
淡路岛 M6.3 已确认约 6 km 实际破裂尺度但缺少唯一数值边界，三陆冲 M7.5 已审计但
未找到目标事件专属模型，宫城县冲 M7.2 已确认约 `30 x 20 km` 实际尺度但缺少唯一
面内边界；胆振东部 M6.7 已归档完整曲面数字模型。14 个候选均已完成来源审计。

熊本 `Mj 6.5` 的 NIED 有限断层对照见
`matsuzaki_2006_kumamoto_m65_finite_fault_diagnostic.md`。该模型以官方破裂起点作为
断层面内部锚点，图面核实其位于第 7 列、第 6 行子断层中心；没有把破裂点猜成矩形
中心或角点。当前大阪和熊本两个诊断均证明全点源校准语义不完整，但也都表明旧系数
已经吸收距离定义误差，仍不能直接接入生产或回调已打开的 2018。

熊本 `Mj 5.8` 的正式来源审计见
`matsuzaki_2006_kumamoto_m58_finite_fault_audit.md`。JMA 专题事件表确认该事件存在，
但 JMA 技术报告的震源过程参数表只覆盖 M6.5、M6.4、M7.3，NIED 完整反演目录也没有
该 M5.8 条目。清单保留“已审计但无可用模型”状态，不复用 M6.5 断层面。

鸟取县中部 `Mj 6.6` 的有限断层对照见
`matsuzaki_2006_tottori_m66_finite_fault_diagnostic.md`。Fig. 2 和 Fig. 4 共同确认破裂
起点在第 6 列、第 6 行中心。24 个同配对有效域测站上，冻结系数 RMS 改善 `36.58%`；
另有 1 站真实断层距低于论文 `1 km` 下限，明确排除而不是钳值。

茨城县北部 `Mj 6.3` 的有限断层对照见
`matsuzaki_2006_ibaraki_m63_finite_fault_diagnostic.md`。JMA 原始数据明确给出单矩形、
`Xorg=8/Worg=5` 破裂起点和完整 `10 x 8` 子断层中心；20 个站的冻结系数 RMS 改善
`10.31%`，但只有 9 站逐站改善。EPS 双平面缺少完整数值边界，未从图面猜测使用。

2014 长野县北部 `Mj 6.7` 的有限断层对照见
`matsuzaki_2006_nagano_2014_m67_finite_fault_diagnostic.md`。JMA `11 x 6` 假定网格中
只有 `X=5..11/W=1..4` 为连续 `Mark=1` 有效单元，诊断使用精确 `21 x 12 km`
边界，不把 `Mark=0` 单元扩进断层。2 个站低于论文 1 km 域，保留后排除残差比较。

福岛县中通 `Mj 6.4` 的有限断层对照见
`matsuzaki_2006_fukushima_nakadori_m64_finite_fault_diagnostic.md`。JMA 修订 ZIP 中
`7 x 6` 子断层全部为 `Mark=1`，`Xorg=3/Worg=5` 明确给出破裂起点槽位。14 个近场
站的论文原系数和冻结系数 RMS 分别改善 `10.19%` 和 `22.44%`，但逐站仍不一致。

淡路岛 `Mj 6.3` 的来源边界审计见
`matsuzaki_2006_awaji_m63_finite_fault_audit.md`。JMA 与 EPS 2020 分别给出约
`6 x 5 km` 和 `6 x 6 km` 的实际同震尺度，但 `14 x 14 km` / `12 x 16.5 km` 是更大
的反演计算面。实际约 6 km 区域没有完整数值边界，因此没有运行最短距离诊断。

三陆冲 `2011-03-11 15:25 Mj 7.5` 的来源审计见
`matsuzaki_2006_sanriku_m75_finite_fault_audit.md`。JMA 月报确认它是独立列出的东日本
主震余震，但 JMA/NIED 震源过程目录没有目标时刻模型；不能复用 14:46 主震或相邻
15:08/15:15 M7 事件。该事件当前没有点源近场站。

宫城县冲 `2011-04-07 Mj 7.2` 的来源审计见
`matsuzaki_2006_miyagi_oki_m72_finite_fault_audit.md`。JMA 近地和远地数字模型分别使用
`50 x 35 km`、`45 x 35 km` 反演计算面，远地正文报告实际断层约 `30 x 20 km`，但
没有给出实际区域相对破裂点的唯一四边。该事件当前没有点源近场站，不运行诊断。

胆振东部 `2018-09-06 Mj 6.7` 的曲面模型审计见
`matsuzaki_2006_iburi_m67_curved_fault_audit.md`。Kubo 等（2020）明确否定单矩形表达，
NIED 修订数字文件逐项给出 `15 x 10` 个曲面子断层，总面积 `476.568725 km2`。该事件
同样没有点源近场站，模型完整归档但没有制造残差改善结果。

6 个有来源几何且存在点源近场站事件的统一距离目录见
`matsuzaki_2006_finite_fault_distance_catalog.md`。目录直接重读 2011/2014/2016/2018
原始年度 JSON，保留 213 个近场诊断配对/311 条变体距离，并扩展到 8221 个全部接受站
配对/9711 条变体距离；其中 3 条低于论文 1 km 下限，原值保留但不代入衰减式。
2010-2016 重标定和 2017 选择见
`matsuzaki_2006_finite_fault_semantic_calibration_2017.md`；参数冻结后的 2018 点源、
大阪单矩形和双矩形分支见 `matsuzaki_2006_finite_fault_frozen_2018_evaluation.md`。
大阪两个变体不参与训练，也未根据 2018 残差选择。独立余震重定位、震源机制、强震
全波形和 GNSS 方法审计见 `matsuzaki_2006_osaka_independent_geometry_selection.md`；
该审计选择双矩形联合作为优选物理几何，单矩形保留为低分辨率简化诊断。

熊本县阿苏地方 `Mj 5.8` 的正式来源审计见
`matsuzaki_2006_aso_m58_finite_fault_audit.md`。JMA DD 图显示的是 5 个区域中的多组
复杂震源簇，没有目标事件专属长度、宽度和边界；清单保留缺失状态，不从震源云或节面
解生成矩形。

长野县北部 `04:31 Mj 5.9` 的正式来源审计见
`matsuzaki_2006_nagano_m59_finite_fault_audit.md`。JMA 月报只给该余震的震源要素、
震度分布和震央，JMA 震源过程目录只收录 03:59 M6.7 主震；NIED 的 17 km 余震域
属于整个序列，不能据此生成目标事件矩形。

长野县北部 `05:42 Mj 5.3` 的独立审计见
`matsuzaki_2006_nagano_m53_finite_fault_audit.md`。JMA 图 4-4 只给本事件的震央和
震度分布，官方震源过程目录无该条目；同一余震序列不意味着可以共享有限边界。

逐站长期中心化残差实验见 `matsuzaki_2006_station_bias_2010_2019.md`。训练固定使用
2010-2016，2017 从预声明的最少 `2/5/10/20` 个训练事件中选择，2018/2019 只做冻结
复用。两套前向模型均选择至少 2 次事件，2018/2019 的事件等权中心化 RMS 分别改善
`21.505%/23.910%` 和 `17.962%/20.426%`。未覆盖站保留原模型预测并明确计数，不补
震度或残差。该站点项尚不能解释为纯 ARV/场地项，也未接生产。

逐站残差的极端项和恶化事件诊断见
`matsuzaki_2006_station_bias_diagnostic_2010_2019.md`。论文原系数在 2017-2019 合计
9 个恶化事件，冻结 2017 系数合计 13 个；总体 RMS 改善仍成立。恶化集中在少站数事件、
2017 的 `trainingEventCount = 2` 小分层、近场 `1-<30 km` 小样本，以及未覆盖站受事件
均值变化影响的中心化副作用。下一步只能做预声明的站点项收缩实验，不能用 2018/2019
回调参数。

预声明站点项收缩实验见 `matsuzaki_2006_station_bias_shrinkage_2010_2019.md`。在
`k in {0,1,2,5,10}` 与最小训练事件数 `2/5/10/20` 的完整 2017 选择中，两套模型都选
`min=2, k=2`。2018/2019 只做冻结复用，整体改善保留，且低样本 `n=2` 分层由此前的
2017 恶化转为改善；有限断层语义模型的 2017 近场分层仍有恶化，故它只是站项稳健化，
不能替代前向模型或距离语义修正。

2019 已打开审计年的站数饱和性结果见
`matsuzaki_2006_joint_station_count_saturation_2019.md`。预声明的
`100/200/300/500/1000` 档显示：300 是两套模型同时达到震中误差平台的最小候选；500 和
全量 1000 不带来稳定总体收益，却提高高站数事件的 P90 时间。该结论只冻结后续盲测的
候选输入上限为 300，不是生产默认，也没有解决深度边界。

冻结站项接入未知候选搜索后的 2019 诊断见
`matsuzaki_2006_joint_station_bias_2019_diagnostic.md`。这次比较使用相同的 44 个事件、
300 个测站和搜索规格；论文原系数下震中误差总体改善，但震级误差变差且有 18 个事件变差，
冻结有限断层语义系数下总体震中中位数、深度、震级和收敛率反而变差。站项路径已验证接入
正确，但 `min=2, k=2` 不能作为未知震源定位的生产参数；最终未参与训练和选择的留出人口
仍未打开。

2022 端点留出协议见
`matsuzaki_2006_joint_station_bias_2022_holdout_protocol.md`。该协议针对当前冻结的
`published` / `finiteFaultSemanticFrozen2017` 与 2010-2016 站项训练链；2022 虽已在另一份
现代系数实验中作为 test 使用，因此不称为整个项目的全新盲测，但没有参与当前站项参数
选择。协议已冻结为 2022、50 个预审计可就绪事件、最多 300 站、250 km 圆形硬域，正式
结果已写入协议报告：`published` 下站项使全部候选震中中位数 `42.749 -> 33.395 km`，
但震级误差 `0.309 -> 0.382`，逐事件震中误差为改善/变差 `33/17`；冻结有限断层语义
系数下震中中位数 `39.224 -> 37.481 km`，但收敛数 `20 -> 17`、硬边界 `30 -> 33`，
逐事件为 `25/25`。两条路径运行时间中位数都约增加 2 倍以上，因此 `k=2` 仍不能进入
生产。

2022 站项对联合定位的事件级影响诊断见
`matsuzaki_2006_joint_station_bias_effect_2022_diagnostic.md`。诊断显示两个模型的站项
覆盖率中位数约为 `0.893`，因此差异不是大范围缺站项造成的；但 `published` 的逐事件
震中误差仍有 `33/17` 改善/变差，冻结有限断层语义模型为 `25/25`，并出现约 `409 km`
的恶化反例。站项会重新塑造共同震级、震中和深度联合搜索的候选目标面，当前不能据此
重新调 `k` 或接入生产。后续只做恶化事件的候选位移、深度边界和共同震级诊断。

候选位移诊断进一步确认，严重反例 `2022051806171907-40.9873-143.1635` 的两个候选
都在 `100 km` 深度上，站项路径只是把最佳候选水平移动了 `478.421 km`，并新增
`radialMaximum` 接触；RMS 仅下降 `0.001017`。当前重点因此转为等价候选、径向边界附近
目标面和共同震级扫描的耦合审计，不能把它归结为深度公式错误或直接调小 `k`。

交叉评分已确认这是站项-共同震级耦合造成的真实目标面重排：近处候选的 RMS 仅由
`0.340868` 降至 `0.340602`，远处候选却由 `0.425208` 降至 `0.339851`，从而以很小优势
取代近处候选。该结论来自同一候选位置的两条路径重评分，不使用目录真值输入；下一步只
检查逐站残差和站项修正的贡献，不能直接添加边界惩罚或调参。

逐站残差显示近处候选在两条路径均卡在模型最低共同震级 `M5.000`；加站项后其平均残差
从约 `-0.0015` 变为 `-0.1782`，但不能继续将 `M` 降至 5 以下，因为会离开当前衰减模型
标定域。远处边界候选则可由 `M5.502` 调至 `M5.297`，并结合站项显著降低 RMS。该反例
应归类为站项、共同震级下界和径向边界候选的耦合，不是单独的深度错误或可立即修复的
搜索半径问题。

局部网格还发现，冻结有限断层语义模型在原始合法搜索域内存在 `RMS 0.297097` 的近场
候选，低于联合报告返回的远处候选 `RMS 0.339851`；该点位于本次 `0.25°` 诊断网格边缘，
因此尚不能称为全局最优，但已确认当前结果没有返回该低 RMS 候选。下一步需要增加只读的
候选访问轨迹，区分“未被评分”和“评分后被阶段筛选”，不能直接改搜索排序。

候选访问轨迹已经完成：该近场点在无站项和冻结站项两条路径中均为 `evaluated=false`，
而远处返回点在冻结站项路径的 `stage=2, expansion=4` 被实际评分。因此已确认是自适应
候选生成路径漏采样，不是评分后排序丢失。下一步统计其他事件的漏采样频率，再做预声明
搜索覆盖实验。

## 与现有代码的边界

- `gstsl_*.dart` 是论文算法还原，不是实验 1 的日本模型成品。
- `ka_intensity_input.dart` 和 `ka_capture_input_extractor.dart` 是输入研究期间的暂存代码，目前不作为实验 1 已确认设计。
- 实验代码继续保持独立；真实输入适配和生产接入只能在输入数值域、场地修正、距离、
  深度、震级类型、端到端评价门槛和标定资料全部明确后开始。

2022 全事件局部覆盖扫描见
`.dart_tool/matsuzaki_2006_joint_station_bias_effect_diagnostic_2022_k2_all_neighborhoods/report.{json,md}`。
该扫描以既有无站项最佳候选为中心，固定其深度，在原始矩形和 250 km 径向合法域内按
`0.025°` 间隔扫描 `+/-0.25°` 邻域，只计算冻结站项路径。`published` 的 50 个事件中有
`0/50` 个局部 RMS 低于已返回站项候选；`finiteFaultSemanticFrozen2017` 有 `1/50`
（2%），即已知的 `2022051806171907-40.9873-143.1635`，局部 RMS 差值为 `-0.042754`，
且局部最低点落在扫描边缘。该比例是局部覆盖风险指标，不等同于漏采样确认；具体候选
是否进入评分仍必须使用 `--trace-event` 单事件复核。

全事件候选访问 trace 见
`.dart_tool/matsuzaki_2006_joint_station_bias_effect_diagnostic_2022_k2_trace_all/report.{json,md}`。
新增 `--trace-all-events` 后，对每个事件监视无站项返回候选、冻结站项返回候选，以及局部
扫描最低点。`published` 的局部最低点实际进入评分 `27/50`，未进入 `23/50`；
`finiteFaultSemanticFrozen2017` 实际进入 `40/50`，未进入 `10/50`。两套模型的冻结站项
返回候选均为 `50/50` 实际进入评分。该统计证明自适应搜索不是局部邻域全覆盖，但只有
“局部 RMS 更低且 trace 未评估”同时成立时，才构成当前已确认的覆盖问题。

硬域粗起点对照见
`.dart_tool/matsuzaki_2006_joint_station_bias_effect_diagnostic_2022_k2_hard_coarse_start_v3/report.{json,md}`。
该只读策略将第一阶段初始窗口替换为原始硬域，后续阶段、评分函数、径向约束和震级搜索
不变。2022 结果中，`published` 冻结站项路径的震中误差改善 `29/50`，中位变化
`-0.075 km`；`finiteFaultSemanticFrozen2017` 改善 `30/50`，中位变化 `-0.121 km`。
有限断层模型的已知反例从原路径 `447.438 km` 降到 `54.564 km`，但仍未超过无站项路径的
`38.155 km`。这只是候选策略证据，不是生产参数或生产搜索已经改变的记录。

2019 交叉验证见
`.dart_tool/matsuzaki_2006_joint_station_bias_effect_diagnostic_2019_k2_hard_coarse_start/report.{json,md}`。
同一硬域粗起点策略在 44 个既有 2019 事件上，`published` 冻结站项路径震中误差改善
`25/44`、中位变化 `-0.046 km`；`finiteFaultSemanticFrozen2017` 改善 `23/44`、中位
变化 `-0.023 km`。2019 曾用于既有审计，因此这里只作为策略交叉验证，不称为新的盲测，
也不据此重新选择搜索或站项参数。

2020/2021 局部覆盖扫描和全事件 trace 见
`matsuzaki_2006_joint_station_bias_2020_2021_coverage_trace_diagnostic.md`。2020 的
`published`、有限断层语义模型分别发现 `0/44`、`1/44` 个低于返回站项 RMS 的局部点；
2021 两个模型均为 `1/51`。三处低点都确认未进入原始评分循环，但只有两处在硬域粗起点
对照中改善震中误差，说明局部 RMS 漏采样是低频覆盖风险，不能直接替换为全域细网格。
当前下一步只允许预声明多起点策略的收益/耗时实验，不从这三处事件调搜索参数。

两路径返回候选 union 对照见
`matsuzaki_2006_joint_station_bias_two_path_union_diagnostic.md`。它将原始路径与硬域粗
起点路径各自返回的冻结站项最佳候选按 RMS 取优，不使用目录真值。2020/2021 四个模型
年度组合的震中误差中位数均未改善，P90 均上升，且额外耗时中位数约 `1.9-2.4 s`；因此
多起点策略暂不进入生产，也不再从当前年度结果调起点或候选排序。

有限断层距离迁移诊断见
`matsuzaki_2006_finite_fault_migration_diagnostic.md`。在 2011/2014/2016/2018 的六个
来源事件、七个几何变体和两套系数上固定目录震源比较点源距与有限断层距：2011 改善、
2014 两套系数均恶化、2016 方向不一致，2018 双矩形仅在冻结系数下略好。因此距离语义
与系数存在事件相关耦合，不能把有限断层距无条件替换进未知事件点源搜索；未知事件仍
使用候选点源三维距，后续若迁移必须建立分层/混合标定和独立留出评价。

有来源有限断层事件的点源联合反演诊断见
`matsuzaki_2006_source_backed_point_source_inversion_diagnostic.md`。六个事件按未知事件
输入运行 12 次：冻结系数改善部分水平误差，但 4/6 个事件触及深度或其他硬边界；原系数
也出现深度边界和明显深度误差。因此这轮只确认距离语义、深度可辨识性和系数存在耦合，
不支持直接替换系数或将有限断层距写入未知事件搜索。下一步做固定候选位置的深度 RMS
剖面诊断，区分真实目标面和边界假收敛。

有来源有限断层事件的深度 RMS 剖面见
`matsuzaki_2006_source_backed_depth_profile_diagnostic.md`。固定上一轮点源候选水平位置
并逐 5 km 重估共同震级后，原系数和冻结系数分别在不同事件触及浅部或深部边界，多个
事件的 `RMS + 0.05` 深度包络很宽。因此深度问题不是统一的固定偏移，不能通过扩大范围
或显示边界值解决；下一步只能用独立深度信息或有物理依据的分层模型验证。

JMA 官方源过程原始包审计见
`.dart_tool/matsuzaki_2006_jma_source_process_audit/report.{json,md}`，原始 ZIP 保存在
`tmp/jma_source_process_raw`，解压文本保存在 `tmp/jma_source_process_audit`。该审计解析
`01event.txt` 的 `M/Mo/Mw/Mxslp`、`02fault.txt` 的有效子断层、`03mom.txt` 的矩量释放
时间序列和 `04slip.txt` 的滑移/刚度，不把这些波形源过程量当成实时烈度输入。福岛、长野、
茨城的 JMA 活跃足迹与当前 JMA 修订矩形在尺寸、走向、倾角和参考深度上相符；熊本、鸟取
分别存在 `24 x 18` 对 `22 x 14 km`、`22 x 16` 对 `16 x 16 km` 的来源差异，因此 JMA
源过程模型与当前 NIED 几何只允许并列诊断，不能拼接或按单事件 RMS 选择。大阪没有本地
JMA 源过程索引条目，继续保持独立资料边界。

JMA 源过程矩形与当前几何的逐站距离诊断见
`.dart_tool/matsuzaki_2006_jma_source_process_distance_diagnostic/report.{json,md}`。
JMA 矩形的下倾方位由原始 `02fault.txt` 有效子断层中心的 `w -> w+1` 坐标推导，并规范化
为与走向严格正交的方向。福岛、长野、茨城与当前同源矩形的逐站距离和 RMS 完全一致；
熊本、鸟取的 JMA/NIED 距离不同，且在原系数和冻结系数下 RMS 改善方向相反。因此这轮
只支持“来源并列、距离与系数联合诊断”，不支持把 JMA 矩形写入未知事件搜索。
