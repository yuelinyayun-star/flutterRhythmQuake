# JIAN 主备与配对鉴权（2026-11-01）

## 文档与修改边界

本轮按用户要求接入 JIAN 新备用服务，同时复核上一轮 WHEWS 备用连接的鉴权。本地源码修改，没有云端部署、安装或桌面操作。

当前官方文档 <https://api.sismotide.top/api/#overview> 和 <https://api.sismotide.top/api/#auth> 已列明：

| 业务站 | 换访问令牌 |
| --- | --- |
| `wss://api.sismotide.top` | `https://auth.sismotide.top/api/access` |
| `wss://api.jianproject.cloud` | `https://auth.jianproject.cloud/api/access` |

两站共用已保存的 RT，但换 AT 的服务必须与当前业务主机对应。公开业务和 `/all` 需要 AT；`/kmoni`、`/s-net`、`/kma-station` 按文档免鉴权。原始文档保存于 `tmp/jian_failover_20261101/api.original.html`。

覆盖本地前台/后台共用 `JianService`、本地采集器代码 `JianCollectorFeed`、三个 `JianStationService` 测站入口以及原生 Rust KMA actor。原有 ICL 私有专用凭据入口未套用公开业务 AT/RT，也没有为未列入本轮文档确认范围的 ICL、GET 天气/IP 等路径猜测镜像。

## 实现和既有规则

- Rust `jian_connection` 选择主备业务主机、配对鉴权主机、测站豁免和重连目标。Windows 实际通过 FFI 使用新策略，原生 KMA actor 直接使用同一主机定义；没有静默退回 Dart。其他不支持原生库的平台有明确兼容实现。
- 普通聚合网络失败切到下一站，保留原有45/90/180/300秒重连间隔和稳定2分钟后重置规则。认证网络/服务器故障允许在原5分钟退避后换站；账号封禁、限流、连接数拒绝、凭据错误不触发换站规避。
- 采集器仍保留原有5分钟退避，单逻辑连接；测站仍保留15秒重连。停止后取消未执行的换站和换票。
- 切站之前按原 barrier 等待旧连接关闭，之后向对应鉴权站用 RT 换新 AT。换票为无 Body 的 POST，关闭自动重定向，RT 只进入 Authorization；原生业务握手仅带新 AT 的 Bearer header，不把 RT/AT 塞进业务帧或 URL。
- 新增对握手 HTTP 401/403/429 和已知 JIAN 关闭码的分类，认证拒绝不会被笼统当成网络失败后换站。403只标记握手被拒绝，不猜测具体是账号还是IP封禁。
- 原有凭据安全存储、RT/AT到期检查、跨 owner 的拒绝次数与冷却记录不变，切站不会清空重试预算。仍然无凭据不连、不匿名降级、不在已认证连接上反复发票据。
- 令牌申请/登录密钥换 RT 仍按原有主站流程。Web 主站原有同源换票代理不变，备站使用官方配对鉴权地址；浏览器备站 CORS 环境未作实机验收。本轮运行验证针对 Windows 原生路径。
- 原始报文、历史/海啸分发、地图、声音和业务阈值未修改。

## WHEWS 鉴权复核

当前国内站官方鉴权文档 <https://api.2v8.cn/#auth> 仍指向 WAuth `auth.beecld.com`，两区 WS 采用同一类 `wat_` API Token，没有要求按 JIAN 的方式切换换票发行方。当前文档原件为 `tmp/jian_failover_20261101/whews-auth.original.js`。

WHEWS 主备同一路径都由 `buildConnectionUri` 附上 Token，原生 KMA 也保留原 URL 编码 Token。切站不会变成匿名连接，认证停连记录按实际主机+路径保存。WHEWS 4401/4403/4008及HTTP拒绝停连、4503退避等检查本轮与 JIAN 一起通过。

## 验证结果

- Rust新模块2项通过，Release DLL 编译成功。
- JIAN专项14项通过：主备业务与换票主机配对、每次Bearer握手、新AT不混用、主鉴权服务网络故障切备、认证拒绝不换站、采集器、三个免鉴权测站、停止取消切换、未知主机拒绝与FFI输出归零。
- 本机真实网络专项：通过原生 Rust WebSocket 对隔离本机服务器进行备用握手，服务器实际收到 `Authorization: Bearer at_backup_controlled`；URL无票据，随后收到的业务/心跳帧不含 AT/RT。用于故障模拟的凭据不出本机，没有用用户账号制造公网无效鉴权。
- 另一专项验证原始 `test/fixtures/jian/all.json` 经备用连接分发后各事件 `sourcePayload` 与原数据一致，没有改时间或字段。
- 最终248项回归通过，包含 JIAN 鉴权、拒绝预算、凭据到期、前后台适配、海啸分发、原生测站及 WHEWS 主备鉴权、FAN 生命周期。日志 `tmp/jian_failover_20261101/regression-final.log`。
- 新桥接和专项测试静态分析无问题；完整涉及文件分析无错误或警告，保留10条原有花括号格式提示。
- 未实测个人账号在公网两站的断线切换；未把本机受控传输验证称为已部署或已在云电脑验收。

测试维护保留原约束：旧 `FakeChannel`/`Peer` 补齐实际 WebSocket 接口的 `closeCode`（普通关闭为null），没有删除原断言。旧海啸分发测试原来只 pump 一次，未等待已存在的异步 Rust 解析；现在有界等待原生投递后仍检查原有快照/实时数量、原始载荷和报次断言。生产海啸解析未改。

交付为源码、Rust Release 和本地运行验证；尚未重新打包或安装。
