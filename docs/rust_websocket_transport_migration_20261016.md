# Windows WebSocket 传输迁移与核验（2026-10-16）

本轮迁移的是实际网络传输，不是只把计数器或 JSON 函数改名。Windows 的 HTTP Upgrade/TLS、WebSocket 帧接收、分片组合、发送队列及关闭交给 Rust 驱动的异步 WinHTTP；各服务原有的认证、订阅、重试、历史标志、字段适配、去重及取消报规则继续保留。因此连接相关业务状态还没有全部迁入 Rust。

## 接入范围

| 服务入口 | 本轮处理 |
| --- | --- |
| Wolfx | 原生握手、收发；保留原有证书策略及原文字符串日志 |
| FAN | 原生收发、UTF-8 字节直接进入 Rust JSON；移除 WebView2 分支和 `webview_windows` 依赖 |
| WHEWS | 聚合与复用该客户端的测站连接使用原生传输；查询参数认证、4401 首帧认证回退、4503 退避不改 |
| Jian 聚合 | 原生传输；Authorization 请求头、持久化重试间隔和历史查询不改 |
| SASMEX | 原生连接现有中继；报告序列、快照/更新、心跳及源原文不改 |
| Jian 测站 | NIED / S-net / KMA 连接接入原生传输，原始 UTF-8 直接进入已有测站解析器 |
| Jian ICL | 原生传输；Token 查询参数及无效凭据停止重试不改 |
| NowQuake 烈度速报 | 原生 WS；HTTP 列表/详情、缓存及事件绑定不改 |
| EMSC | 保留 IOWebSocket 的真实 ping/pong 截止检测，不将 WinHTTP 保活误作等价替换 |

平台入口在 `source_socket.dart`，原生适配在 `native_websocket_channel.dart`，Rust 实现在 `native/station_core/src/websocket.rs`。非 Windows 沿用 Dart 传输；显式 `HttpOverrides` 也沿用其原连接，避免绕过自定义代理或测试 HTTP 行为。

FAN 当前数据服务仍可启用；仅删除用户明确要求移除的 WebView 分支，没有关闭 FAN 数据源，也没有改变其他页面的 WebView 依赖。

## EMSC 协议差异：以实际帧核验

`tools/verify_websocket_keepalive.dart` 使用单独的本地控制协议对端：完成 Upgrade、响应 close，但故意不回应 ping。这不是地震事件或性能数据。

- Dart `pingInterval=15s`：约 15.24 秒发 opcode 9（ping），约 30.26 秒判定断开。
- WinHTTP `keepalive=15s`：约 15.15 / 30.17 / 45.18 秒发 opcode 10（pong）；观察 48 秒仍未因缺少 pong 断开。

因此 `connectSourceSocket` 对需要 `pingInterval` 的来源保留 IOWebSocket；EMSC 仍为官方 WS 实时接入，HTTP 仍仅用于连接后的目录同步。原生适配的可选参数明确命名为 `keepaliveInterval`，避免把两者混用。[WinHTTP 选项说明](https://learn.microsoft.com/en-us/windows/win32/winhttp/option-flags)只约定保活间隔；以上 opcode 和断线时间来自本轮实际控制帧测量。

## 生命周期与资源

- 每条连接持有独立、单调增加的 ID，原生会话不会复用旧连接身份。
- 由原生端通过 `NativeApi.postCObject` 向 Dart 原生端口推送通知；空闲时没有 Dart 轮询定时器。
- WinHTTP 回调只复制完成元数据；原生工作线程串行调用句柄 API，避免回调与关闭交错调用句柄。
- 接收、发送及异步 Shutdown 的缓冲保留到相应完成通知；关闭后等待句柄的最终关闭通知再释放回调上下文。
- 消息和输入/输出缓冲各受 64 MiB 限制，溢出报错并终止连接，不静默丢报。该限制不用于完整历史归档文件。
- Dart 单次分发至多 32 条，后续通过事件循环继续处理；JSON 源传原始 UTF-8 字节，不先构造整包 Dart 字符串。
- 原生端口在连接存活时保持所属 isolate 存活。加入了只有原生连接、没有其他 Dart 定时器的 isolate 回归，防止 CLI 或后台 isolate 提前退出。
- 终止、握手超时和 GC 均有 owner 释放路径；NativeFinalizer 与弱引用端口处理避免遗忘连接被端口永久强引用。

并发规则依据 [WinHTTP 官方文档](https://learn.microsoft.com/en-us/windows/win32/winhttp/concurrency-in-winhttp)，跨线程通知使用 [Dart NativeApi.postCObject](https://api.dart.dev/dart-ffi/NativeApi/postCObject.html)。没有引入新的 Rust 第三方依赖；新增 Dart 直接依赖 `stream_channel` 原本已存在于依赖树中。

## 测试与原文

主组 200 项通过、3 项跳过；非原生组 178 项通过、3 项跳过，两组重叠不累加。Rust 32 项通过。新核心及工具静态分析无问题。

覆盖文本/二进制/空帧、约 2 MB 原文跨分片、六条并发连接、4401 关闭码、请求头和编码后的查询参数、未完成握手时取消、HTTP 拒绝、超时、默认 ws/wss 端口、原生工作线程释放，以及各源原有认证/历史/去重/报数/JMA 取消报。上述传输边界测试包括明确标注的控制协议输入，不能当作上游真实事件。

测试保留并直接读取既有抓包。2 MB 中国天气原始响应仅用于跨分片传输测试，不声称该 HTTP 响应是线上 WS 报文。迁移前文件备份与哈希见 `tmp/ws_transport_baseline_20261016/manifest.json`；之前的完整迁移前备份及实验资料保留。

实际公共端点核验：Wolfx、EMSC、SASMEX 均成功完成原生 WSS 握手；Wolfx / SASMEX 收到首帧，EMSC 在 5 秒观察期无事件帧，不能声称收到了新地震。最终关闭均无错误且原生工作线程归零。没有读取或试用用户保存的 WHEWS/Jian 凭据；这些认证入口依靠原有协议回归核验，尚未进行带实际账号的长时在线验收。

核验日志：

- `tmp/ws_transport_native_tests_final.log`
- `tmp/ws_transport_fallback_tests.log`
- `tmp/ws_transport_rust_tests_final.log`
- `tmp/ws_transport_keepalive.json`
- `tmp/ws_transport_live_native_final.json`
- `tmp/ws_transport_analyze_final.log`

## 固定原文 AOT 对照

`tools/benchmark_websocket_ingress.dart` 在两个路径中都使用独立 Dart isolate 的本地服务器，关闭压缩，以 16 条一批重放未经修改的原文字节。输入包含三份真实 WS 快照/帧与一份 Wolfx HTTP 原文；后者仅作为固定字节负载，未冒充实际 Wolfx WS 抓包。

两路径都使用现有 Rust JSON 核心；比较旧 Dart WS + String 入口与原生 WS + UTF-8 入口。每个独立 AOT 进程先热身 64 帧，再处理 4096 帧、57,961,472 字节，包含接收、通知及完整 JSON 解析，包含同进程中本地服务器的 CPU 时间。原文重复只表示压力负载，不表示 4096 个不同实时事件。

三轮交错进程的中位数：

| 指标 | 原 Dart WS | 原生 WS/字节 | 说明 |
| --- | ---: | ---: | --- |
| 接收＋解析耗时 | 2151.193 ms | 1322.028 ms | 减少约 38.54% |
| 进程 CPU 时间 | 3406.250 ms | 2500.000 ms | 减少约 26.61% |
| 8 ms 定时器间隔 P99 | 10.893 ms | 8.454 ms | 主事件循环计时，不是 Flutter 渲染帧 P99 |
| 峰值 RSS | 27.328 MiB | 29.500 MiB | 本轮未证明内存下降；Dart 三轮有 52.926 MiB 波动 |
| 结束 RSS | 26.828 MiB | 29.496 MiB | 没有强制 GC，不能作为长期留存或泄漏结论 |

六轮输入哈希、帧数、字节数及消费校验一致。关闭后原生工作线程每轮均为 0。原始轮次见 `build/performance/websocket_ingress_comparison_20261016.json`。

以上是组件压力测试，不能换算为完整 APP 的 CPU、GPU 或内存降幅。地图、统一 UI、字段对象构造和业务合并仍可能占用主 isolate，仍需完整 APP 的固定输入长时验收。其余 HTTP、TCP/TLS、Socket.IO 应用协议和未接入共用入口的其他 WS 服务，也没有在本轮宣称全部迁完。

本轮仅构建 Windows 个人版 Profile 用于验证；未构建 Android，未制作新安装器，未修改云端，未替换用户正在运行的安装版。
