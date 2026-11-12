# WHEWS／Jian 测站接收链深度优化与释放核验

本轮继续处理 Windows 高频测站接收链，保留 Flutter 版本和原始输入。先备份上一版，再优化 UTF 编码、原生解析、只读快照表示和数值消费。没有修改云端，也没有将事件聚合入口或 Android 改成原生实现。

## 具体变更

- JSON ABI 升至 2。普通报文通过 UTF-8 批量复制，Rust 直接解析字节，省去逐 UTF-16 单元复制及完整中间转码。含字面代理项的字符串仍通过 UTF-16，保留原始码元，包括未配对代理项。
- 数值节点仅按原始类型和 64 位内容共享。每个数组位置、整数／浮点类型、负零、顺序和未知字段继续保留，没有舍入、抽样或删除数据。重复数值使用显式索引，连续唯一数值使用连续节点。
- 同一帧中的短浮点字面量按完整原文缓存解析结果。高唯一率时自动停用缓存，避免唯一数据承担重复查表成本。缓存不跨帧，不跳过报文解析。
- 原生输出始终复制为 Dart 独立只读存储。原文快照和归一化数值视图共享这一份存储，释放连接不影响已经发布的快照。断线、停止和最终回收释放 owner 与 FFI 缓冲。
- 输入／输出仍限定 64 MiB，深度 512。2M 限制按进入解析器的值计数，数值共享不能绕过输入限制。

首次测站目录仍用 Dart。连接认证、订阅、时间与重复过滤、业务阈值、事件报数、语音和 UI 策略不变。WHEWS／Jian 事件聚合入口仍属于后续工作。

## 原始数据与备份

原始观测：`test/fixtures/whews_nied/observations.json`，1560 站，SHA256：

`ae900469e29ea06beb9dd97c2123cc3abb2cecce0d0f92f2c790303a64a1de67`

原始目录及 Jian 两份抓包与首次迁移前保存的四份哈希全部一致。另对六份未经修改的来源抓包逐字段、类型、键顺序、数组顺序和浮点位核对。压力测试重复解码同一份历史原报文，没有修改时间、数值或补造事件；独立接收器允许该历史时间按原逻辑进入，每轮目录初始化不计入高频接收耗时。

上一版代码、ABI 1 DLL、AOT 程序及测量备份：

`build/performance/backups/station-json-deep-20261015-094441`

当前打包 DLL SHA256：

`908b6531f84febf64d448f0de01f28633126b74b722e6160a57f6d5eb38da286`

## 三轮交替顺序测量

全部表格使用三轮中位数，耗时是固定批次实际墙钟耗时，不是任务管理器 CPU 百分比。旧 Dart 数值循环、快照与完整接收服务使用迁移前冻结版本。

### AOT 解析／快照／数值消费组件

| 同一原始观测解码 3000 次 | 原 Dart | 上一版 Rust | 当前 Rust |
| --- | ---: | ---: | ---: |
| 耗时 ms | 1916.306 | 1331.671 | 1151.927 |
| RSS MiB | 16.523 | 17.414 | 17.102 |

当前耗时较原 Dart 下降 39.89%，较上一版 Rust 下降 13.50%。普通组件 RSS 没有证明低于 Dart。

组件保留 1000 份独立解码快照及三个数值视图时，耗时 875.444 → 423.295 ms，RSS 191.621 → 106.906 MiB。目录共用，不随快照重复保存。这是固定历史报文的保留压力测试，不是 1000 个不同实时事件。

原生一次解码的 packed 输出 112888 → 57352 字节；隔离 owner 的原生存活分配 309936 → 153680 字节，销毁后两版都归零。统计不包含系统分配器保留容量。

### 完整离线接收链 Profile

诊断入口：`tool/station_receiver_benchmark.dart`。每次实际经过解码、生产接收服务、原文快照、异步帧发布及三个数值数组消费；旧版使用冻结接收服务和快照。执行 1000 次，校验原文与输出校验和。它没有连接网络，也没有渲染地图。

| 不保留历史快照 | 冻结 Dart | 当前 Rust |
| --- | ---: | ---: |
| 耗时 ms | 844.250 | 538.544 |
| RSS MiB | 109.648 | 109.445 |

接收链耗时下降 36.21%；该场景 RSS 基本持平。

### 保留与释放诊断

同一 Profile 接收链保留 1000 份独立观测快照及数值视图，通过 VM service 请求 GC。读取保留内容验证引用仍存活，再清空引用、销毁解析器并再次 GC。三轮都成功取得 GC 后内存统计。

| GC 后状态 | 冻结 Dart | 当前 Rust |
| --- | ---: | ---: |
| 保留数据时 heapUsage 字节 | 155549488 | 63665872 |
| 保留数据时 externalUsage 字节 | 80 | 16224 |
| 保留数据时 RSS MiB | 310.375 | 226.762 |
| 释放后 heapUsage 字节 | 4610144 | 4603472 |
| 释放后 externalUsage 字节 | 80 | 80 |
| 释放后 RSS MiB | 166.246 | 164.516 |

存活 Dart 堆与外部内存合计约 148.344 → 60.732 MiB，下降约 59.06%。释放后均回到约 4.4 MiB。RSS 含引擎、VM 与分配器容量，释放后仍约 165 MiB，不能直接当成存活业务数据，也不能据此宣称完整应用没有泄漏。

机器可读记录：

- `build/performance/station_json_deep_comparison_20261015.json`
- `build/performance/station_json_storage_20261015.json`
- `build/performance/station_receiver_comparison_20261015.json`
- `build/performance/station_receiver_retention_20261015.json`
- `build/performance/station_json_phases_before_20261015.json`
- `build/performance/station_json_phases_after_20261015.json`

复测脚本：`tools/benchmark_station_json_deep.ps1`、`tools/benchmark_station_receiver.ps1`。后者的 `-Retain` 执行保留／释放诊断。Profile 诊断文件单独暂存在 `build/performance/station-receiver-profile-20261015`，正式 Profile 目录恢复 `lib/main.dart` 入口。

## 回归与验收边界

26 项 Rust 测试、77 项 Dart 相关回归通过；最终打包 DLL 的解析与真实本地 WS／Jian 生命周期重点 9 项再次通过。禁用原生的 Dart 路径另有 7 项通过、2 项原生专属测试跳过。覆盖稠密唯一数据、重复数值、5000 个差分数值、UTF 编码、原始抓包、不可变缓冲、旧快照存活、重复拦截及释放。重点 Dart 静态检查和本次 Rust 文件格式检查通过。正常 `lib/main.dart` 完整 Windows Profile 构建成功，打包 DLL 与实测 Cargo DLL 哈希一致。

普通接收链吞吐和保留数据内存已有完整链证据；尚未测本轮完整 APP 的 EEW＋测站长时回放、地图帧 P99、GPU 及在线重连长时表现。不能将上述组件数字当成整机 CPU／GPU 降幅，整机长时验收继续保留。没有制作正式安装包。
