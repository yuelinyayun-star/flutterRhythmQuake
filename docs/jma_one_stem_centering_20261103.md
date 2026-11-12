# 区域数值 1 的主竖笔画校正

用户范围：只校正圆角方格中的数字 `1`，按主竖笔画左右两边的中线定位。其他数字、正负号、颜色、透明度、圆角、缩放、相机、测站保持原样。

## 修改

- `lib/widgets/map/jma_region_value_badge_layer.dart`，`jmaRegionValueOpticalCenter` 的 `value == '1'` 分支。
- 原先按字体向量轮廓的主竖笔画中点 `(.300 + .443) / 2 * fontSize` 定位。实际导出的方格图中，字体栅格化后的主竖笔画仍有半个图片像素的左偏。
- 现在显式计算竖笔画两侧中点，再加设计字号 20 下向右 0.1 的绘制校正（实际跟随方格一起缩放）。不纳入左上斜挑，也不按整个字符宽度居中。
- 这只是 Flutter 字形绘制校正，不修改后端、震度阈值、原始数据或其他类型规则。

此前对“漏算实际排版偏移”的归因不准确：生产文字画笔实测 lineLeft / boxLeft 均为 0。此次依据的是实际方格导出图的栅格笔画边缘，没有继续用那个归因扩大修改。

## 直接渲染与像素核对

使用真正的 `JmaRegionValueBadgeLayer` 和 `JmaRegionValueBadgePainter`，不是单独排版一个 TextPainter 来代替生产路径。

- 旧图：方格中线 519.5 px，主竖笔画左右为 515..522，笔画中线 519.0 px。
- 新图：方格中线 519.5 px，主竖笔画左右为 515..523，笔画中线 519.5 px。
- 图像对比共变化 139 像素，全部位于 `1` 的字形内；其余数字、符号、方格底色和边框像素一致。
- 测量记录：`tmp/jma_region_values_20261102/one-stem-centered-measurement.json`。
- 完整地图分别导出为唯一新文件名：`detail-one-centered-active-20261103.png`、`detail-one-centered-idle-20261103.png`，避免重复图片地址掩盖本次更新。
- 完整地图仍使用原始 P2P 情报及生产 Provider / Rust 相机入口；测站坐标真实，震动和平静数值仅用于样式模拟。没有向云电脑注入假报文。

## 打包及云电脑结果

- 本地 Release 与 Inno 安装包编译通过，保留其他 Dart 工作进程。
- `RhythmQuake_Setup_1.0.5.22_personal_x64.exe`，41630386 字节，SHA256 `f861e7f5d36ed793e65031e44d6e386ede91c511ee47da40be6c931dd10c0ef8`。
- 经现有 MCP 更新 `DESKTOP-VUEC9GQ` 的 `E:\RhythmQuake`，本次仅 `data/app.so` 变化；Rust DLL 未再次替换。安装内容全部 141 文件哈希通过，清单 SHA256 `ab89094194f421efa78e398dfaa1d92e18652f4925b71dc903921d7f1625a56f`。
- 中途 MCP 返回一次 CONTROL_PREEMPTED，未在该错误上盲目重发追加。恢复控制后核对远端 Base64 文件长度和 SHA256 与本地前缀完全一致，再续传剩余部分。
- 已重新启动 APP，PID 9184；不创建备份、不改配置，暂存传输文件及展开目录已清理。
- 证据：`tmp/jma_one_center_20261103/package.log`、`cloud-deployed.json`。这是与安装包相同内容的增量更新，不表示执行过安装向导。
