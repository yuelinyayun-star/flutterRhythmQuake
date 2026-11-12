# 数据连接的 JSON 外层解析迁移

本轮把已有网络入口的外层识别和 JSON 解析合成一次 Rust 调用，复用现有 API JSON owner／独立快照。没有执行远端 JavaScript，没有改变报文字段或对原始样本进行重写。

## 实际接入

- CMA 雷达／降水：原始 UTF-8 JSONP 字节直接识别 `readRadarList`／`getPreObs1h` 并解析。
- 中国天气：地理位置 JSONP 的 `getData`，以及 JS 赋值中的 `fc1h_24`、`fc40`、`index3d`、`dataSK`。HTTP 保留原始字节至 Rust；公开解析函数同时接受原有 String 和 UTF-8 字节。日期、字段转换和加载状态仍在 Dart。
- TREM RTS：`data:` 行的内容识别、左空白处理和 JSON 解析接入 Rust。Dart 保留元数据／空行的廉价拦截，UTF-8 流解码及 LineSplitter 仍在 Dart。这不是完整 SSE 分帧迁移，也没有改为多行 data 合并。
- CWA 目录列表：正常响应直接使用原始字节；错误形状的诊断摘录才解码文本。
- WHEWS：补齐二进制 WS 帧入口。原来非 String 帧会原样传给下游，测站处理器不接纳该字节列表。现在二进制目录走通用 API JSON，二进制观测走已有测站数值解析器；String 路径、认证、心跳和重连规则保持原逻辑。

核心文件：`native/station_core/src/json_envelope.rs`、`station_json.rs`、`lib/services/sources/json_wire_envelope.dart`、`station_json_decoder_io.dart`、`api_json_decoder.dart`。新增 wrapper ABI 1；原 station core ABI 1、station JSON ABI 2 未变。CMake 已声明新源文件依赖。

## 兼容性

外层模式分别保留 JSONP 允许／不允许回调名后空白的区别、JS 首次匹配和括号／引号／转义计数、SSE 原先逐行解析的规则。ECMAScript 正则空白与 Dart trimLeft 的 NEL 差异有独立测试。UTF-16 路径保留孤立代理项，UTF-8 校验整份传输，即使坏字节位于选中 JSON 之外也拒绝。

传输开头只按原 UTF-8 解码语义消费一个 BOM；字段内 BOM 保留。超过 32 MiB 的传输进入 UTF-16 兼容路径，JSON 长度限制仍针对选中的原始 JSON，不把巨大的外层空白错误算作 JSON 大小。普通字节入口不构造整份 Dart String。

Web／Android 保留同一文件中的原 Dart 算法。它同时用于对照测试，不另存整份项目备份；已有迁移前完整备份和实验数据保持原状。本轮没有升级 SDK、改变依赖或修改云端。

## 最终产物 DLL 的独立 AOT 对照

DLL SHA-256：`b9fd8961845bc366713b98ebd41a47b99698a2e1cee9bad5fc2f09288539546d`。

双方均使用这个 DLL 中的同一 Rust JSON 内核。参考路径是原来的 Dart UTF-8 解码、正则／括号扫描、substring 后调用 decodeApiJson；新路径为原始字节直接识别外层并解析。双方均冻结快照。每个模式独立进程，30 次预热，3 轮交替顺序；测试／构建结束后单独测量。

| 原始响应与字段 | 次数 | 旧流程中位 ms | 新字节流程中位 ms | 耗时减少 |
| --- | ---: | ---: | ---: | ---: |
| 雷达 JSONP | 2000 | 52.911 | 33.387 | 36.90% |
| 降水 JSONP | 2000 | 53.948 | 31.889 | 40.89% |
| 地理位置 JSONP | 2000 | 36.960 | 19.282 | 47.83% |
| 北京逐小时 fc1h_24 | 400 | 206.000 | 130.724 | 36.54% |
| 义乌日预报 fc40 | 400 | 276.306 | 61.564 | 77.72% |
| 义乌指数 index3d | 400 | 738.965 | 106.239 | 85.62% |

该表取代使用独立构建 DLL 的较早初测。String 兼容输入也单独记录：fc1h_24 为 211.032 ms，比参考路径慢约 2.44%；实际 HTTP 已使用字节输入。没有宣称所有输入路径均提速，也没有用这些小进程的结束 RSS 代表完整 APP 稳态内存。没有原始 SSE 传输样本的性能对照，SSE 只完成协议边界和功能验证；没有据此宣称 SSE CPU 收益。

脚本：`tools/benchmark_json_envelope.ps1 -LibraryPath build/windows/x64/runner/Profile/rq_station_core.dll`。原始轮次、校验值及输入哈希：`build/performance/json_envelope_comparison_20261015.json`。

## 验证

- 28 项 Rust 测试通过。
- 最终代码的原生主组 84 项通过，覆盖原始 JSONP／JS 字段、真实 WHEWS 原始文本／二进制 WS 发布、重复拦截、断线清理、归档和快照、CWA 列表／详情与县市震度、Unicode／坏 UTF-8／长度边界。
- 非原生路径 66 项通过、2 项原生专用测试跳过；组间存在重复，不累加为独立测试总数。新增代码静态分析无问题。
- 正常 `lib/main.dart` 的 Windows 个人版 Profile 最终重建通过；产物 DLL 与最终性能对照使用的 DLL 一致。
- 原始样本对照与受控协议边界分开；受控数据未注入实时 APP，未作为性能样本。
- 从清理前已保存的哈希清单核验 203 份原始样本未变；记录在 `build/performance/json_envelope_fixture_hashes_20261015.json`。

日志保存在 `build/performance/json_envelope_*_20261015.log`。原始文件保持不变；HTTP／WS／TCP 连接管理、完整 SSE 分帧、Socket.IO 包处理、XML／HTML／文本、事件分发及整机长时验收仍待继续。未制作新安装包或 Android 构建。
