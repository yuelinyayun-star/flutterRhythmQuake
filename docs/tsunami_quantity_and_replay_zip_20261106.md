# 海啸波高字段与回放 ZIP 导出核对（2026-11-06）

## 授权范围

处理用户截图中 JMA 海啸波高把 `map[type:津波の高さ unit:m value:0.2]` 当成文本显示的问题；核对回放是否仍为单一 JSON。用户随后确认刚才打开的是旧回放文件。

## 本次具体改动

- `native/station_core/src/jma_tsunami.rs`：新增显式海啸高度量的解码，只接受类型 `津波の高さ`、单位 `m`、有限非负值的 JSON 对象或 Go `map[...]` 字符串。原来这些结构无法获得数值或被原样展示，现在数值进入现有高度字段，并由列表投影显示为 `0.2m`。投影同时兼容已有记录中的这种字符串。定性描述（巨大、超、未满等）、到达时间、预警等级、测站观测、分页及原始 sourcePayload 的规则不变。
- `lib/widgets/ui/history_replay_controls.dart`：原生平台目录格式回放的保存文件名后缀从 `.rqreplay` 改为 `.zip`，桌面保存对话框同步说明 ZIP；浏览器仍走现有旧格式编码并保留 `.rqreplay`，不把 JSON 标成 ZIP。导入入口仍接受 `.rqreplay`、`.zip`、`.json`。
- `lib/widgets/ui/history_replay_file_io.dart`：移动端 ZIP 导出的临时文件名同步为 `capture.zip`。本次不改打包算法、逐文件存储、帧内容和读取策略。
- `test/jma_tsunami_quantity_height_test.dart`：通过生产 Rust 解析、投影及实际左右列表组件验证截图中的字段显示。截图字段构成的最小协议样例明确标注为样例，不冒充完整抓取报文。
- `test/replay_zip_export_entry_test.dart`：使用原始旧回放样本经过实际导出入口，核查 ZIP 内独立报告文件、manifest、再导入后的原始报告一致性，以及取消保存行为。

## 回放实际核对

只读检查用户本次导出的福島県中通り回放：文件为 ZIP 魔数，内部 `manifest.version=3`、`layout=files-v1`，含独立的 5 报、2048 帧，共 2054 个成员。文件大小 65,655,187 字节；主要占用来自实际测站帧，尤其 NIED 帧。本次更改后缀不会压小内容，不删除、降采样或改变原始数据。

## 验证与交付边界

- Rust JMA 海啸模块及其既有子模块测试：56 项通过。
- Flutter 海啸高度、左列表、右侧栏、观测及 JIAN 接入测试：48 项通过。
- 回放实际导出入口、目录存储、新旧导入播放兼容、事件命名测试：33 项通过。
- 已检查实际组件渲染图 `tmp/jma_tsunami_height_20261106/left-and-right-height.png`，两处均为 `0.2m`，未出现 `map[...]` 或长列溢出。
- Rust 原生 release DLL 已编译；本次尚未重新打包 Windows 安装包、安装或部署云电脑。上述组件验证不等同于完整安装版运行验证。
- 未改前面暂停处理的 JMA/P2PQ 地震情报、PLUM/EEW 分类、地图标记或历史事件逻辑。
