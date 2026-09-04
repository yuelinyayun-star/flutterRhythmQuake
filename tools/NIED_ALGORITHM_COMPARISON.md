# NIED 三算法离线对比工具

这个工具只用于算法优化诊断，不接入 UI，不写回生产震源状态，也不会修改或重新编码原始 NIED GIF。

固定比较三套算法：

1. 当前生产算法：`NiedDartHypSourceEstimator`
2. 参考项目算法：`kanameishi-dev/src/classes/NiedHypoInf.js` 原始 JavaScript
3. 新增算法：`t0729/srev-kaizou` Scratch HYP

第二套算法不是 kotoho7。运行器仅把 `@/utils/Utils` 和 `@/utils/TravelTimes` 的导入指向参考项目本地原始依赖，不替换算法函数体，并在报告中记录三个源文件的 SHA-256。

## 一键运行

在项目根目录执行：

```powershell
.\tools\run_nied_algorithm_comparison.ps1 `
  -Capture 'tmp\captures\p2p_20260810_170200_m28_6bf17e'
```

可选参数：

- `-OutputDirectory`：报告输出目录。
- `-KanameishiRoot`：`kanameishi-dev` 本地目录。
- `-SrevProject`：`srev-kaizou` 的 `project.json`。
- `-CompiledBaselineProject`：用于结构核验的 Scratch 基线 `project.json`。
- `-SrevRandomSeed`：srev 固定诊断随机种子，默认 `20260810`。

每次执行会重新导出同一批 GIF 解码观测，并依次运行三个算法。输出目录包含统一 `comparison_report.json`、便于阅读的 `comparison_report.md`、三套算法的完整原始报告，以及 srev 过程结构核验报告。

## 对比口径

- 三个算法使用同一事件、同一批逐秒帧和同一个固定真值。
- 原始 GIF 文件重新计算 SHA-256，报告字节数或哈希不一致。
- 输出首次结果、最终结果、水平/深度/起震时刻误差的中位数和 P90、帧间跳变、P/S/O/L 分配变化、有效测站数、权重、运行耗时、候选搜索和拒绝原因。
- 有限 score 不代表有效结果。生产和参考算法还必须有有效测站支持、正权重和有限误差。
- Scratch 没有暴露的权重或候选评估次数保持 `null`，不推测、不补值。
- srev 使用固定种子，并记录随机算法、种子、抽样次数与排除耗时字段后的 `deterministicTrajectorySha256`。
- 统一报告选择的主震源只用于横向统计，各算法所有原始震源输出仍完整保留。

## 验证

```powershell
node --test tools\nied_algorithm_comparison_test.js
node --check tools\kanameishi_reference_algorithm_runner.js
node --check tools\srev_kaizou_algorithm_runner.js
node --check tools\build_nied_algorithm_comparison.js
```
