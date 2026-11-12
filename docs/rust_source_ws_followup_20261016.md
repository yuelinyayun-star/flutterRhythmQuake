# KMA、SeisJS、P2P 连接与入站迁移（2026-10-16）

三个服务接入已有 `connectSourceSocket`，Windows 默认使用上一轮 Rust/异步 WinHTTP 传输。入站 JSON 使用原始 UTF-8 字节进入已有 Rust 解析器；其他平台及显式 HttpOverrides 保留原传输，字符串入口仍兼容。没有新增 Rust ABI 或依赖。

本轮迁移范围为网络传输与 JSON 字节入口。认证/重连业务、测站对象、KMA 历史/邻接/检出、P2P JMA 要素合并与统一模型构造仍是 Dart，不能称为三个服务全部处理均已原生化。

## 同时修复的生命周期问题

- SeisJS 原来在每次重连时重新创建过期定时器，覆盖引用后旧定时器仍运行。现在每次启用只创建一个过期定时器，每条有效连接只创建一个心跳定时器。
- SeisJS 的 onError 配合 cancelOnError 后不保证还有 onDone，原来错误分支未安排重连；现在错误、关闭、握手失败均进入有序且可取消的重试。
- 三个服务均保存并取消订阅，先切断当前连接身份，再异步关闭 socket；增加连接序号及实例检查，迟到的帧、错误、关闭、ready 完成不能污染替换连接。
- KMA 仅在握手成功后标记连接成功。普通连接失败按原有断线重试路径 10 秒后轮换，连接数超限仍 3 秒后轮换；同步创建失败也走有界重试，避免立即递归轮换。
- P2P 原来先等待 ready 再监听，现在先安装接收/错误监听，保留首批帧；失败会取消心跳和订阅，dispose 会断开传输。
- P2P 不再逐条同步打印完整原文；地震原文仍保存在 sourcePayload。明文 pong 控制帧直接忽略，避免送入 JSON 解析并产生错误日志。

KMA 的测站历史、缺帧补齐、旧时间拦截、保持窗口及检出阈值未改。SeisJS 当前烈度与历史最大烈度的区分未改。P2P 震度/震源信息的合并、海啸入口及原文快照未改。

## 原始数据核验

只读连接三个现有公共 WS 端点，握手后观察 8 秒：

- KMA：收到原始 heartbeat、265 站目录及 initial/update，保留前 8 帧。
- SeisJS：收到原始 heartbeat 和设备观测，保留前 8 帧。
- P2P：握手成功，观察期无新事件；未编造实时数据，回归使用既有原始历史样本。

原文、URL、字节数、SHA-256 见 `test/fixtures/source_ws_followup_20261016/manifest.json`。16 个新原文的哈希均核验一致，之前的 206 个原始 fixture 也未改动。抓包工具拒绝覆盖已有原文目录。

P2P 历史响应数组在隔离本地 WS 测试中整体原文发送，仅证明数组入口兼容，不声称该数组是本轮收到的实时 WS 帧。测试仅实例化隔离服务，没有向运行中的 APP 注入报文，没有修改服务器或触发云端上传。

## 验证

- 原生相关组：53 项通过，含三个服务在实际本地原生 socket 上消费原文，以及关闭后原生工作线程回到基线。
- 非原生组：34 项通过，1 项原生专属测试跳过。两组重叠，不累加。
- 覆盖断线重连、旧回调、晚到握手错误、重复错误/关闭、FAN KMA 端点轮换、停止后无重连、无残留定时器、原始时钟/数值、P2P 文本/字节统一事件及原文一致性；并运行 JMA 取消报回归。
- 静态分析无问题。
- Windows 个人版 Profile 构建成功，157.4 秒；复用原生 DLL，未构建 Android、未制作新安装器、未替换正在运行的安装版。

迁移前的三个文件及哈希保存在 `tmp/source_ws_followup_baseline_20261016/manifest.json`。日志为 `tmp/source_ws_followup_native_final.log`、`tmp/source_ws_followup_fallback.log`、`tmp/source_ws_followup_analyze_final.log`、`tmp/source_ws_followup_windows_profile.log`。

本轮没有新的整机 CPU/GPU/RSS 对照；上一轮组件压测数字不能当作本轮三个服务或完整 APP 的降幅。未迁移的主连接入口仍包括 EMSC 的协议 ping、OBS、GQ TCP、SeedLink/FDSN；HTTP 调度、业务状态及领域处理继续待迁移。
