# API 原始字节入口接入 Rust

本轮在已有 Rust JSON 解析器之上接入网络原始 UTF-8 字节，取消正常 UTF-8 JSON 响应的整包 Dart 字符串解码及再次编码。没有增加新的 Rust 算法或改变 DLL ABI；HTTP／WS 连接管理、重连、过滤、合并和事件发布仍使用现有逻辑。

## 接入范围

32 个服务文件、53 处入口：

- Jian、Jian ICL、Jian 测站、EMSC、SASMEX、NowQuake CENC 烈度及 OBS 的二进制 WS 帧。
- CENC／CWA／JMA／USGS 列表、USGS CMT／ShakeMap／DYFI、ChinaEEW ICL、P-Alert、NIED Yahoo、S-net 目录等 HTTP JSON。
- 台风、GFS／Jian 风场、CMA／JMA 天气、雷达／卫星元数据、NOAA 海啸区域。
- 地理位置、Jian 登录、WAuth、HTTP 时间同步。
- CWA 测站服务的 5 处流式 HTTP JSON，包括登录、刷新令牌、目录和 RTS；保持原超时及关闭连接的顺序。

逐文件变更和迁移前哈希见 `api_byte_ingress_manifest_20261015.json`。`python tools/migrate_api_bytes.py --verify` 将当前代码与迁移前备份及明确记录的表达式替换对照，允许格式化和删除无用导入，不允许更改业务字面量、字段转换或连接策略。该命令同时核验 121 份原始 JSON／GeoJSON 文件的 SHA-256，不重写源代码或原始样本。

此前 `migrate_api_json.py` 的严格验证针对原字符串入口版本，本轮改用上述字节入口核验。

## 编码和所有权

`decodeApiJsonBytes` 直接复制原始字节至复用的原生输入缓冲，Rust 完整校验 UTF-8 后解析；未消费的 JSON 字段中存在坏 UTF-8 也会立即报错。只消耗一个传输层开头的 BOM，与旧 Utf8Decoder 一致；字段名、字段值内的 BOM、原始数字类型和负零均保留。

`decodeApiJsonResponse` 保留当前 package:http 的字符集语义：application/json 未声明 charset 时使用 UTF-8；缺少 Content-Type 或未知 charset 时仍按原 Latin-1 语义处理。其他明确字符集保持原解码路径，不将非 UTF-8 数据当 UTF-8。

JSON 图仍为按需可写视图；冻结后的原始快照独立持有数据。接收缓冲复用、解析器销毁和断线不能影响已发布快照。解析失败销毁共享解析器，下次调用重新创建。

超过 32 MiB 的字节输入仍走原字符串长度限制检查，以保持既有 32 Mi UTF-16 单元限制，普通报文不生成整包字符串。

边界测试发现并修复旧 packed JSON 字段解码吞掉字段开头 U+FEFF 的问题；只恢复被 UTF-8 解码器消费的字段 BOM，不修改原始输入。

## 独立 AOT 对照

同一 DLL：`9bc4f610c56e570ea26b8ddec8e7fe794200cec1fe102225013f438e55187c57`。每个负载独立进程、30 次预热、3 轮交替顺序。比较旧转换流程 `utf8.decode(bytes) → decodeApiJson` 与直接 `decodeApiJsonBytes`；两边均生成同样的冻结快照。最终重测时没有并行运行回归测试。

| 未修改原始样本 | 循环次数 | 字符串流程中位 ms | 字节流程中位 ms | 耗时减少 |
| --- | ---: | ---: | ---: | ---: |
| WHEWS all | 300 | 234.408 | 57.096 | 75.64% |
| Jian all | 300 | 148.247 | 50.459 | 65.96% |
| EMSC WS | 3000 | 41.009 | 25.917 | 36.80% |
| P2P 历史 | 300 | 242.338 | 58.303 | 75.94% |
| USGS DYFI versions | 100，保留快照 | 1496.119 | 763.675 | 48.96% |
| 台风原始响应 | 100，保留快照 | 937.431 | 229.811 | 75.49% |

测量结束时 RSS 中位数：USGS 178.934 → 166.914 MiB，台风 69.656 → 57.621 MiB；小负载基本持平，Jian 增加约 0.531 MiB。这些是组件单点 RSS，包含短时分配，不是完整 APP 的稳态内存或 GC 后保留内存。重复同一份原始输入不代表相同数量的独立实时事件。

工具：`tools/benchmark_api_bytes.dart`、`tools/benchmark_api_bytes.ps1`；完整轮次、哈希及结果：`build/performance/api_bytes_comparison_20261015.json`。

## 回归与备份

- 首轮原生适配器 23 项通过，主要数据源回归 275 项通过、3 项跳过。
- 补充组串行重跑 120 项通过、1 项跳过，包括新增 Jian 二进制目录／观测、重复帧及停止后快照检查。与首轮存在重叠，不累加宣称独立测试总数。
- 非原生字节入口及 API 视图组 14 项通过。
- 新增核心适配器、BOM 修复、测试与基准静态分析无问题。服务文件既有 avoid_print 提示未在本轮扩大修改。
- 正常 `lib/main.dart` 的 Windows 个人版 Profile 构建通过，产物 DLL 哈希与对照 DLL 一致；没有制作新安装包。
- 最终使用 Profile 产物 DLL 的 24 项核心／服务回归通过，再串行复测非原生路径 14 项通过，包含新增 BOM 和空输入／非法字节边界。
- 两个 Flutter 测试进程最初并行写同一测试缓存发生 PathExistsException，停止该轮后串行重跑通过；不把该轮计为有效验收。

日志均保存在 `build/performance/api_bytes_*_20261015.log`。迁移前全部 services、pubspec／lock、相关测试及 packed JSON 文件保存在 `build/performance/backups/api-bytes-20261015`。pubspec 仅将已锁定的 http_parser 声明为直接依赖，未升级 SDK 或依赖版本。

明确保留的路径：有 `allowMalformed: true` 策略的输入、XML／HTML／CSV、SSE 文本分帧、Socket.IO 字符串协议。Web／Android 通过同一字节接口使用 Dart 实现，没有新增 Android 原生目标或制作 Android 安装包。整机 EEW＋测站长时回放、UI 帧耗时和 GPU 收益仍需单独测量，不能用上述组件数据替代。
