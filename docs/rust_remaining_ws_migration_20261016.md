# OBS、独立 Jian 采集器与 Sidesis 连接迁移

本轮三个入口接入已有 `connectSourceSocket`：Windows 使用 Rust／异步 WinHTTP 的握手、收发、分片和传输缓冲。复用已有原生库，没有新增 Rust 算法、ABI 或依赖。

## 入口与生命周期

- OBS：控制连接接入原生传输，入站 UTF-8 字节继续进入已有原生 JSON 解析器。SHA-256 挑战认证、RPC 请求配对、录制／回放缓存控制、关闭码与重连规则仍由原服务处理。
- 独立 Jian 采集器：接入同一原生传输，原始字节直接解析，移除整包 UTF-8 String 中转。补齐订阅保存与取消、握手期间错误监听、旧连接序号拦截、心跳发送失败处理及有界关闭。每次重连仍换取新的访问令牌，五分钟间隔不变；沿用本轮之前修复的鉴权错误分类。
- Sidesis Socket.IO：接入原生传输，保留文本原文回调及二进制帧忽略契约。先监听再等待握手，失败立即使旧连接序号失效，迟到的 ready 错误不会安排第二次重连。Engine.IO 控制包、Socket.IO 命名空间、事件解包与业务分类仍为 Dart；没有猜测或新增订阅事件。

独立采集器和 Sidesis 客户端不代表 APP 主聚合流增加了两个订阅。主聚合流仍由既有 JianService 与 SourceManager 管理。

三个既有源文件及哈希备份在 `tmp/remaining_ws_baseline_20261016_173337/manifest.json`。OBS 既有测试另行保存在同目录。本轮没有修改服务器、原始报文或正在运行的安装版。

## 验证与边界

原始 Jian `test/fixtures/jian/all.json` 在隔离采集器中逐字段比较，保持原始报文、时钟、报数和原文。实际本地原生 socket 传输同一原文，关闭后工作线程回到基线。受控故障测试覆盖重复错误／关闭、重连换票、停止期间的鉴权与握手、旧回调、停止后无定时器。

OBS 使用既有本地协议服务器验证认证、错误密码、录制、暂停／恢复、字幕、场景、回放缓存保存及断线恢复。Sidesis 本地协议测试验证命名空间、ping/pong、中文／日文、文本回调、二进制忽略和自动重连。它们是明确标注的受控协议输入，不是上游实时报文抓包，也不向运行中的 APP 注入事件。

测试中移除 Flutter 测试绑定的 HTTP override，显式检查原生连接类型／工作线程，避免因 override 而意外只测到兼容路径。

- 原生相关组：103 项通过，包括实际原生 socket、原文一致性、资源释放、OBS 自动化与 Jian 鉴权。
- 非原生组：93 项通过、2 项原生专属测试跳过。组间重叠，不累加。
- 本轮目标文件静态分析无问题。
- Windows 个人版 Profile 构建通过，162.7 秒，正常 `lib/main.dart` 入口；日志为 `tmp/remaining_ws_windows_profile.log`。

没有新的完整 APP CPU／GPU／RSS 对照，也没有把之前的连接组件数据当作本轮或整机收益。未构建 Android，未制作安装器。

## 剩余连接与数据处理

EMSC 的真实协议 ping/pong 截止检测、GlobalQuake TCP、SeedLink/FDSN TCP/TLS、HTTP 请求调度与流式响应传输仍需迁移。Web 分支及显式 HttpOverrides 的兼容分支按平台保留。Socket.IO 状态机、XML／HTML／文本目录、其余领域状态、Android 原生支持与整机固定输入长时对照仍未完成。
