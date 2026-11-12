# 修复 JMA 区域标签样式计算外溢

## 范围与精确改动

用户授权修复上一轮审查确认的多余样式计算，不修改其他类型的显示或业务规则。

生产代码只改 `lib/widgets/map/intensity_fill_layer.dart` 构建 Polygon 的位置：新增 `hasRegionLabel`，同时用于判断标签文本和标签样式。仅真正带标签的日本普通情报区域主轮廓才执行 `jmaRegionValueTextStyle.copyWith` 和 `jmaRegionValueBadgeForeground`。其他类型、关闭标签的图层、未标数字的岛屿分片使用原构造器默认的 `const TextStyle()`。

原行为：即使 label 为 null，也计算并保留新标签的字体和配色。

新行为：label 为 null 时，完全不求值新标签字体和配色的分支；原填色颜色、透明度、点集、边框、几何回调、相机规则和缓存策略保持原样。

新增的条件判断只涉及 Flutter 渲染，不修改 Dart 或 Rust 后端计算。没有修改数字 1、其他数字、正负号的对齐、圆角、标签颜色或缩放。

## 范围证据

- 修改前记录 727 个 `lib` / 原生 Rust 生产源码文件的 SHA256；修改后仅 `lib/widgets/map/intensity_fill_layer.dart` 不同。
- 将修改处按原代码还原到内存字符串后，整个文件 SHA256 与修改前一致，确认文件内也没有夹带其他修改。
- `tmp/jma_label_scope_fix_20261103/production-change.diff` 保存精确差异；`source-change-check.json` 保存文件范围检查。

## 实际检查

- 先加入回归断言：关闭标签时必须是默认样式，启用标签时未标数字的分片也必须是默认样式。修复前该断言实际失败，修复后通过。没有删去既有几何、颜色、原报文哈希、相机或 40 帧缓存断言。
- 26 项相关回归通过，覆盖 JMA/P2P 标签、几何与缓存、震中居中、EEW 情报切换、CENC 共享视角、USGS 产品等。
- 14 组原始报文绘制检查通过，非目标类型及未标数字分片的多余新标签样式全部变为 0。所有原始报文不改时间、不改数值；历史帧只对齐测试时钟。逐场景使用独立进程。
- 目标标签数保持原样：P2P 震度速报 3、震源情报 26、各地震度 15、WHEWS/JMA 震源·震度 5。EEW、CWA、CENC、KMA、远地情报、BMKG、USGS 和 CENC 仪器烈度速报仍没有这些标签。
- 生产地图重新渲染震动、平静两种测站样式；与修复前同场景图片逐像素比较，两张图各 3029400 像素，变化像素均为 0。这里的测站震动数值是已明确标注的样式模拟，不是实测。
- 针对生产文件和测试文件的 analyze 无问题。

证据目录 `tmp/jma_label_scope_fix_20261103`：`before-fix.log`、`regressions.log`、`after-summary.json`、`image-comparison.json`、`analyze.log`。

## 发布状态

本地 Release 与安装包已成功构建。安装包 `RhythmQuake_Setup_1.0.5.22_personal_x64.exe`，SHA256 `f0b3475b7f01594f8787e90acaf2c368ce7fb64e1d3b03b41155efbf56c78ec3`。

已经通过现有 MCP 更新 `DESKTOP-VUEC9GQ` 的 `E:\RhythmQuake`。本次只替换 `data/app.so` 和发布清单，未替换 Rust DLL、未改配置、未创建备份；暂存文件已清理。部署后 141 个发布文件哈希全部通过，清单 SHA256 `76ae3dc6bbe2711d6af49103a345399cdbec9356719344c8e0af5618c313fde8`，新进程 PID 5056。

部署证据为 `cloud-deployed.json`，实际运行检查保存于 `cloud-running.txt`。更新内容与安装包一致，采用增量部署，没有冒充执行过安装向导。构建后再次核对上述 727 个源码文件，仍只有指定的一个生产文件变化。
