# 其他 API 的 JSON 数据入口迁移

Windows 的 JSON API 接收与嵌套报文字段统一接入原生解析核，共 56 个文件、86 处调用，不再只接 WHEWS／Jian 测站观测。HTTP／WS 请求、认证、订阅、去重、过期拦截、事件合并、报数、语音和地图业务规则继续沿用现有实现。原始输入没有改写，所有备份样本哈希核验一致。Android／Web 继续使用原 Dart 实现。

## 覆盖范围

| 来源／数据 | 已接入的 JSON 路径 |
| --- | --- |
| Fan、Wolfx、WHEWS、Jian | 聚合事件、初始快照、增量、握手／心跳、独立 ICL、测站目录；高频观测保留已有专用原生路径 |
| EMSC、P2PQuake、USGS | WS／历史目录、地震信息、海啸、CMT、ShakeMap 详情／等值线、DYFI 详情／格子 |
| CENC、CWA、KMA、P-Alert、NIED、S-net、SeisJS、SASMEX | 目录／观测／信息类 JSON；CENC 烈度速报内嵌 JSON、CWA 区域烈度、JMA 观测地区的内嵌 JSON 同样接入 |
| 气象和地图产品 | 中国气象预警／详情／逐小时、CMA 站点与观测、日本天气／雷达／卫星／火山、NSMC／Fan 云图、风场、台风、NOAA 海啸区域 |
| 辅助 API | 定位、HTTP 对时、Jian 认证／采集器、WAuth、OBS WS、J-SHIS 响应 |

逐文件原始哈希、原调用行号及调用数见 `docs/api_json_ingress_manifest_20261015.json`。`tools/migrate_api_json.py --verify` 核验全部 56 个文件、86 处入口已替换。

刻意保留的 Dart JSON 调用包括非原生平台实现、调试／回放导入、本地报数快照、内置 NIED 目录等。XML、HTML、CSV／纯文本及领域字段转换不是本轮 JSON 内核迁移范围，不把这些或完整 APP 渲染宣称为已迁入 Rust。已有 SeedLink／GlobalQuake 二进制内核保留。

## 兼容与生命周期

`decodeApiJson` 使用通用模式，省去测站专用 Float64 副本与 min／max／finite 归集。数值原始类型、浮点位、顺序和未知字段保留；字符串可用原始 UTF-8 存储，转义／代理项继续精确保留 UTF-16。相同字段名共享编码节点，不删除任何键值位置。每层容器的临时序号缓冲复用。

API 原先拿到的是可修改的 Dart Map／List，不能直接替换成测站只读树。兼容层按需返回可修改视图，保留嵌套引用身份、增删、排序、可增长长度、重复键顺序和键迭代的并发修改检查。修改只复制被写入的容器，不修改原生输出或原始报文。

未修改的报文生成原文快照时直接引用独立不可变存储；子节点发生修改会沿父路径标记，只冻结变化路径，快照不受之后修改影响。原生输出在返回前已经复制到独立 Dart 缓冲，没有 native 指针进入历史、事件或跨 isolate 数据。

每个 isolate 最多弱引用缓存一个通用解析器。没有新增业务定时器；缓存不阻止 GC，错误、显式释放及 SourceManager.stopAll 释放资源，NativeFinalizer 处理被回收的解析器与 FFI 缓冲。压力诊断中，仍保留全部快照时 GC 已使原生会话与分配归零，证明快照不依赖解析器存活。

ABI：测站仍为 2，通用接口为 `rq_api_json_decode`／`rq_api_json_decode_utf8`。通用输出头高位标志选择 24 字节布局；tag10 是无副本数值数组，tag11 是 UTF-8 字符串。头文件说明全部布局。限制仍为 64 MiB 输入／输出、2M 输入值、深度 512，错误显式抛出，不在解析失败后暗中换解析器重试。

## 实测结果

三轮交替顺序，使用相同未经修改的原始文件。全部耗时是固定批次墙钟时间，不是任务管理器 CPU 百分比。AOT 组件只包括解析、可选原文快照及形状读取，不包括网络、领域转换、语音和 UI；压力测试重复解码原报文形成独立快照，不是伪造不同事件。

### AOT：解析＋原文快照

| 原始输入与次数 | Dart ms | Rust ms | 说明 |
| --- | ---: | ---: | --- |
| WHEWS 初始目录 300 次 | 180.953 | 185.221 | 约 2.36% 增加，不能称为提速 |
| Jian 初始目录 300 次 | 117.006 | 122.338 | 约 4.56% 增加 |
| EMSC WS 3000 次 | 32.479 | 35.978 | 约 10.77% 增加，单份约增加 1.17 微秒 |
| P2P 历史 300 次 | 231.256 | 174.589 | 约 24.50% 降低 |
| USGS DYFI 版本文档 100 份保留 | 2365.497 | 1315.483 | 约 44.39% 降低，RSS 470.102 → 176.109 MiB |
| 台风文档 100 份保留 | 1096.166 | 623.922 | 约 43.08% 降低，RSS 196.766 → 62.527 MiB |

纯解析小报文也存在回退，因此没有宣称所有 API CPU 都下降。完整原始结果包含纯解析与快照两种负载：`build/performance/api_json_comparison_20261015.json`。

### Profile：保留／释放压力诊断

独立 Flutter Profile 程序执行 100 次 USGS 原始版本文档解析与快照，GC 后保留全部引用，读取引用验证存活，再清空并 GC。三轮中位数：

| 指标 | Dart | Rust |
| --- | ---: | ---: |
| 批次耗时 ms | 2758.760 | 1544.681 |
| 保留状态 RSS MiB | 539.004 | 266.313 |
| 保留状态 heapUsage＋externalUsage MiB | 410.505 | 151.897 |
| 释放后 heapUsage＋externalUsage MiB | 4.617 | 4.618 |
| 释放后原生会话／原生请求分配字节 | 0／0 | 0／0 |

该负载耗时约下降 44%，保留堆约下降 63%，RSS 约下降 51%。这是离线解析／快照压力诊断，不能当成在线完整 APP 的 CPU、GPU 或稳态 RSS 降幅。原文档一直保持原值，释放后堆回到约 4.6 MiB 的程序基线。

诊断入口 `tool/api_json_memory_diagnostic.dart`；脚本 `tools/benchmark_api_json_memory.ps1`。诊断产物隔离在 `build/performance/api-json-memory-profile-20261015`；正常 Profile 目录已经恢复 `lib/main.dart`。完整记录为 `build/performance/api_json_memory_20261015.json`。

## 回归与现存失败

- 27 项 Rust 单元测试通过。
- 最终打包 DLL 的解析、可写视图、快照、实际本地 WS 及测站生命周期重点 16 项再次通过。
- 主要来源 45 个测试文件：540 项通过，1 项跳过，2 项既有断言失败。
- 补充嵌套报文／语音／历史／CENC 地图测试：127 项通过，3 项既有断言失败。与上批有重叠，不相加伪称独立总数。
- 现有 121 份 JSON／GeoJSON 文件逐项对照 SDK 的值、序列化顺序或相同语法拒绝；另覆盖 UTF-16、重复键、数值类型、嵌套修改与独立快照。
- 新解析／快照／内嵌字段和诊断代码的重点静态检查无问题。整个 sources 目录还有 45 项既存 info 级规则提示，没有新增 warning／error。

这 5 项失败均在禁用原生的 Dart 路径中复现：Jian CEA 的已报告烈度／估算边界、历史／取消事件的预估烈度、WHEWS JMA 显示时区，以及两项仍要求“很浅”的旧语音断言。后两项与用户已确认的“EEW 不读深度；其他 0 km 读 0 公里”约定不同。本轮没有修改领域策略或改断言来制造全绿。

日志：`api_json_regression_final_20261015.log`、`api_json_embedded_regression_20261015.log`、`api_json_existing_failures_dart_20261015.log`、`api_json_existing_voice_failures_dart_20261015.log`，均位于 `build/performance`。

## 构建和备份

正常 Windows Profile 已构建，打包 DLL 与测试 Cargo DLL 一致：

`9bc4f610c56e570ea26b8ddec8e7fe794200cec1fe102225013f438e55187c57`

本轮没有制作正式安装包、更新 SDK 或修改云端。新 DLL 需要完全重启应用加载。

迁移前 services／models、补充 core 以及旧 DLL 保存在 `build/performance/backups/api-json-20261015-113352`。原始样本哈希及逐文件替换记录随备份和迁移清单保存。
