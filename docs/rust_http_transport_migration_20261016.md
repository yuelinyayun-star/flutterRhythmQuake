# HTTP API 传输迁移与核验（2026-10-16）

## 范围

新增普通 API 用的 `createSourceHttpClient` 和 Windows Rust/WinHTTP 实验传输。两轮三轮对照均显示总 CPU/RSS 回退，因此 **默认不启用**，正常版本仍用原 HTTP 客户端；仅显式 `--dart-define=RQ_NATIVE_HTTP=true` 才走实验分支。不能把预接工厂说成这 12 个 API 已在正常版本完成原生切换。实验分支将 HTTP 解析、TLS、连接维护及 gzip 解压移出 UI isolate；JSON 原文字节继续接已有原生 JSON 解码路径。请求生成、数据字段解释、过滤、去重、报数、信息轮播和地图行为仍由原服务处理。

本批为 12 个服务预接共用工厂：JMA 降灰详情、本地天气、长周期地震动、巨大地震关联信息、雷达时刻、卫星云图时刻；CMA 本地天气、中国逐小时天气、GFS 风场；USGS ShakeMap、DYFI；F-net CMT（含表单 POST）。各服务相对本轮备份只增加工厂 import 并替换默认客户端，注入客户端、原请求参数、请求头、业务超时与解析不变。

没有更改图层或统一 UI，没有构建 Android、修改云端或替换正在运行的安装版。

## 传输与所有权

- 全部普通 HTTP 请求共用一个 Rust reactor；WinHTTP 回调只发送完成状态，所有 handle API 由 reactor 调用，没有每请求轮询计时器或每请求 Rust 线程。
- 每个客户端拥有独立 WinHTTP session；关闭请求/客户端会取消未完成请求。接收缓冲及回调上下文保留到 `HANDLE_CLOSING`，不提前释放异步读仍使用的指针。
- 流式 `send` 为 64 KiB 接收队列上限，按可用数据异步读取。消费后通知 reactor 继续；暂停时 Dart 不继续从原生队列取数据。
- 普通 `get` 在 Rust 中合并完整正文，再一次交付 external Uint8List，跳过 Dart BytesBuilder 合并；最多 64 MiB 解压后正文。gzip 每轮最多处理 64 KiB 输出后让出 reactor。完整正文所有权有独立上限，不计入流式队列峰值；报告中的该项为 0 不等于正文零占用。
- 响应块通过独立所有权的 external `Uint8List` 交给 Dart，finalizer 回收；关闭连接不会破坏消费者仍持有的块或子视图。Dart 每轮最多取 8 块，避免大量数据连续占用事件循环。
- Rust 使用已有 flate2/zlib-rs 增量解压 gzip，流式输出块受相同队列预算约束，完整 GET 受完整正文上限约束。校验 CRC、截断和连续 gzip member；保留原始 Content-Encoding/Content-Length，不使用会移除它们的 WinHTTP 自动解压。
- 维持普通 Dart 客户端的直连路由。禁用 Windows 自动凭据、Cookie jar 和自动重定向；显式请求头仍按原值发送。没有原生失败后自动改走另一条网络的重试。
- 重定向在 Dart 中逐跳处理：GET/HEAD 的 301/302/303/307/308、POST 的 303；POST 303 改成无正文 GET。遵守 followRedirects/maxRedirects、循环检测及跨来源敏感头清除。
- 可选完整请求 deadline 覆盖等待头和正文并取消原生请求；各业务现有 `.timeout` 保留。本批没有将所有现有 Future.timeout 改为可取消请求。

## 明确保留的分支

P-Alert 独立证书配置、CWA 特殊证书客户端、NIED/LPGM 专用 `HttpClient`、FDSN HTTP 代理/PAC 路由、Jian 鉴权暂未改用这套默认工厂。EMSC 仍需要 Dart WebSocket 的协议 ping，SeedLink/FDSN TLS 也仍在原路径。

共享工厂在非 Windows、测试无 DLL、Web 或自定义 HttpOverrides 时保留原客户端。原生客户端遇到流式上传、Abortable 请求、URI 内凭据或非 gzip 压缩协商时，在发送前使用原 IOClient；不会发送一半后重试。这些契约尚未声称全部原生化。

## 核验

- `test/native_http_transport_test.dart`：19 项原生传输测试。覆盖原始 XML、原始二进制、编码 URL/请求头、状态与 charset、gzip 元数据及原文、CRC/截断/连续 member、POST 原字节、重定向与凭据、HEAD、暂停/恢复、取消、超时、16 并发和关闭归零。
- 原生相关组 116 项通过；兼容组 97 项通过。两组包含相同的业务测试，不相加当作独立覆盖；业务测试主要用注入客户端核对原解析/过滤，实际 native 网络由上述传输组和 HTTPS 探针验证。
- Rust 34 项现有回归通过。新 HTTP 的 WinHTTP/FFI 路径由 Dart 侧实际网络测试覆盖，不将这 34 项称为新增 HTTP 单测。
- 新增 Dart 文件、测试和 benchmark 静态分析无问题；12 个服务一起分析时，仅 F-net 原有 4 处 print 提示仍在，已对照本轮备份确认。
- 第一版 Windows 个人版 Profile 构建通过（150.3 秒）；批量交付与默认关闭开关后的最终构建另见末尾。入口均为生产 `lib/main.dart`，没有安装或替换用户窗口。
- 真实 HTTPS GET：JMA 区域目录 262108 bytes、JMA eqvol feed 25913 bytes、USGS version 5 bytes，均 HTTP 200。记录为 `tmp/http_https_probe.json`，只读取原文和哈希，不注入事件。
- 压测 XML `test/fixtures/jma_ashfall/20260923145625_0_VFVO55_010000.xml` 与 Git HEAD 完全一致，25909 bytes，SHA-256 `7497642638fa4e61abd343f05f724176de290848c81460a733972e4cc514a915`。

首次传输验证发现 WinHTTP 自动解压会移除压缩响应头，已改成上述 Rust 解压。中间尝试的 WIRE_ENCODING 返回字节而非 UTF-16，未进入最终代码。小块读取取消测试的初始服务端缓冲在旧 Dart 也导致首块等待；将测试服务器 bufferOutput 关闭后，两边同条件核验通过。失败过程日志保留在 tmp，不能当成功结果。

## 组件性能

使用 `tools/benchmark_http_ingress.ps1` 交替启动独立 AOT Dart/原生进程，三轮中位数；单并发 1024 请求、16 并发 2048 请求，每次返回上述完整 XML，逐次校验 SHA-256。分别测普通正文和 gzip，未变更任何震情字段。两模式先加载相同 DLL、完成预热；CPU 为整个组件进程累计时间，包含本地 Dart HTTP 服务与 SHA-256，不是 APP 整机百分比。

第一版流式交付报告：`build/performance/http_ingress_streaming_initial_20261016.json`。CPU 回退 21.69%～56.79%，峰值 RSS 多 10.31%～20.88%；虽有并发耗时缩短，未达到降低 CPU/RSS 的目标。

减少分块回传与 Dart 正文合并后的三轮中位数如下；报告：`build/performance/http_ingress_buffered_20261016.json`。

| 正文 / 并发 | CPU ms：Dart → 原生 | CPU 变化 | 峰值 RSS MiB：Dart → 原生 | 耗时变化 |
| --- | ---: | ---: | ---: | ---: |
| 普通 / 1 | 1250.000 → 1765.625 | +41.25% | 19.785 → 24.219 | +48.89% |
| 普通 / 16 | 2531.250 → 3390.625 | +33.95% | 28.695 → 36.828 | -18.24% |
| gzip / 1 | 1453.125 → 1578.125 | +8.60% | 20.254 → 24.242 | +8.10% |
| gzip / 16 | 2453.125 → 2718.750 | +10.83% | 30.500 → 37.457 | -39.99% |

全部原文 SHA-256 一致、请求与客户端 handle 归零。WinHTTP/系统线程池内部缓存不在这些 handle 计数中，不能用归零宣称整个进程所有缓存已回收。两轮 DLL 不同，只能在各自轮次内比较 Dart/原生；没有控制轮次之间的所有系统负载，不能把两轮绝对数的差额当作单一改动的严格因果量。

第二版测量 DLL SHA-256：`F1091B86D24A29C54B535011FE5F0A79C46B3F896739FA9C7E0B4576D81BE9D2`。

**结论：性能门槛未通过，默认开关关闭。** 保留可复核的实验和工厂接线，不用语言迁移完成度代替占用改善。本批没有新的正常 APP CPU/RSS 降幅结论。

不含 Flutter 引擎、地图 GPU、事件推算或实际网络延迟，不能推导整机内存、CPU、GPU或帧率降幅。

## 备份与复核入口

本批原文件备份：`tmp/http_transport_baseline_20261016_194300/manifest.json`（15 文件，逐文件 SHA-256）。保留先前迁移备份及实验。核心文件为 `native/station_core/src/http_transport.rs`、`lib/services/sources/native_http_client.dart`；新增 Rust 文件已加入 CMake 依赖列表。

WinHTTP 异步缓冲生命周期与禁用自动功能依据 [WinHttpReadData](https://learn.microsoft.com/en-us/windows/win32/api/winhttp/nf-winhttp-winhttpreaddata)、[WinHttpCloseHandle](https://learn.microsoft.com/en-us/windows/win32/api/winhttp/nf-winhttp-winhttpclosehandle)、[Option flags](https://learn.microsoft.com/en-us/windows/win32/winhttp/option-flags) 核对。最终实现和核验以上述代码、测试与原始日志为准。

新的原生 DLL 需要完全退出 APP 后重新启动，热重启不能替换已加载 DLL。

最终默认关闭实验开关的 Windows 个人版 Profile 构建通过（141.2 秒）。打包 DLL 与第二版三轮测量 DLL 哈希相同。显式打开实验开关的原生相关组仍为 116 项通过，默认关闭开关的 19 项传输/工厂检查通过，Rust 34 项通过；最终新增文件静态分析无问题。
