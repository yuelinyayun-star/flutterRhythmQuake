# WHEWS 双站故障切换

## 授权范围与现状核实

用户要求参照 FAN 的主备切换，为 WHEWS 增加两站切换。仅本地修改，未改 FAN、登录 UI、原始报文适配、海啸/情报业务规则或云电脑。

2026-11-01 从当前国内站获取的官方文档确认：中国香港区 `api.beecld.com` 不可用时，两区均提供的端点可以改用中国大陆区 `api.2v8.cn`；仅国内区提供的端点按各自文档处理。文档来源：

- <https://api.2v8.cn/#overview>
- <https://api.2v8.cn/#ws-all>
- 实际下载证据：`tmp/whews_failover_20261101/domestic-index.html`、`index.original.js`、`overview.original.js`、`ws-all.original.js`。

此时主站文档 TLS 连接失败，国内文档可以访问；没有据此推断用户令牌是否被拒绝，也没有向两站发送用户凭据。

本轮原有两个常驻连接分别为 `/ws/all` 与仅国内区的 `/ws/cea_all`，二者承担不同数据，不能互相替代。增加的切换发生于同一路径的两区之间。

## 生产实现

- `WhewsSocketClient` 的 `/ws/all`、`/ws/nied`、`/ws/snet`、`/ws/kma_station` 按主站→国内备用站排列。其他自定义 URL 和仅国内区 `/ws/cea_all` 不增加未经确认的镜像。
- 故障轮换参照 FAN 当前实现：退避3、6、12、24秒；下一退避已达到30秒以上时换站（第一次换站等待48秒），继续指数递增，上限300秒。两站均不可达时继续交替重试。此策略只在单条连接失败时执行，不并发占用双站同一流。
- 原有稳定连接1分钟后退避重置为3秒；稳定的备用连接不被强制抢回。明确停止再启动或更换令牌从主站重新开始。
- 原有20秒首帧活性检查、30秒心跳、90秒停滞检查及4503认证服务暂时失败至少15秒退避保持原样。
- 原有401/403/404/429/4401/4403/4008/1008终止重试约束保持；这类拒绝不会借换站重试。认证停连记录按实际访问的主机+路径写入，换站后不会误记在主站名下。没有清除既有用户认证停连记录。
- 旧连接的订阅和关闭过程继续经过原有 barrier，确认关闭前不会建立替代连接；停止会取消待执行的重连。
- `WhewsService` 的两个逻辑流、状态汇总及去重集合没有被拆掉重建。聚合流切换时 CEA 连接保持，备用站首连补发的重复报文仍被去重。

端点选择和退避决策位于新增 Rust `whews_connection`，Windows `WhewsSocketClient` 通过 `NativeWhewsConnection` FFI 实际调用。仅不支持原生库的平台使用显式兼容实现，Windows 错误不静默回退。

已经在 Rust 运行的 WHEWS KMA 测站 actor 同步接入相同策略，实际 socket host 和诊断日志随站点选择；认证状态读写改为实际 endpoint，保留旧主站记录格式。其余 JIAN、FAN、SeisJS 原生重连规则未修改。

## 验证

- Rust `cargo test ... whews --lib`：3项通过，包括 FAN 轮换时序、4503最短退避、终止码、共享端点白名单与认证记录的主备隔离。Release DLL 编译成功。
- 核心及相关回归68项通过：WHEWS socket、认证生命周期、FAN 生命周期、聚合服务、NIED/KMA 测站、原始 KMA/TREM 原生显示与历史路径等。
- 新增故障切换专项11项，包括原始 CWA 报文跨站去重、CEA 连接不被重建、备站认证拒绝持久化、停止取消重连、关闭未完成时不建立替代连接。
- 真实网络专项：令主站工厂抛出受控网络不可用错误，按实际退避切至备站；只将备站物理地址映射到本机 WebSocket 服务，使用 Release DLL 的 `NativeWebSocketChannel` 完成握手、接收原始 CWA 文件、关闭。报文没有改写，测试凭据没有发往公网。FFI未释放输出为0。
- 原生 KMA actor 的两站公网鉴权切换未实测；不将共享策略单测和旧数据路径回归称为已在公网账户完成切换。
- 静态分析无错误或警告；原 socket 文件保留6条既有花括号格式提示。

日志：`tmp/whews_failover_20261101/rust-tests.log`、`rust-build.log`、`core-final.log`、`failover-final.log`、`analyze-final.log`。

扩大检查时发现独立旧断言：`whews_event_adapter_test.dart` 的 `VXSE51 headline time is not confused with report time` 期待显示23:21，当前设备UTC+8的显示为22:21；原始解析的时刻与UTC+9源时区断言通过。该测试不调用新连接策略，使用上一份安装包对应的旧Release DLL也同样失败，证据为 `old-dll-timezone-baseline.log`。本轮没有修改、删除该断言或改写时间显示规则。

## 交付状态

源码、Rust Release DLL及本地受控运行验证完成。尚未重新编译安装包、安装或启动桌面 APP，也没有修改云电脑。
