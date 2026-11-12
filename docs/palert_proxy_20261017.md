# P-Alert 系统代理接入（2026-10-17）

P-Alert 的独立 TLS 客户端之前没有设置 findProxy，未跟随 Windows 用户代理配置。本次只修改 P-Alert HTTP 工厂，保留 TWCA 根证书、既有官方主机证书策略、GraphQL 请求、目录获取频率和观测处理逻辑。

复用既有 FdsnProxyResolver：环境 HTTP_PROXY/HTTPS_PROXY 优先，同时支持 HTTP ALL_PROXY 补充；Windows 使用当前启用的手动代理或 PAC/WPAD，遵守 NO_PROXY 与系统绕过列表，没有代理时直连。解析沿用现有 15 秒配置缓存，运行中改变代理设置后在后续请求重新解析，不写死本机代理地址。

元数据和实时观测共用该工厂，包括 palert-data-processing 中的正式请求。每条路由使用独立连接池，避免并发请求相互改写 findProxy；代理切换时关闭空闲旧池，正在读取的响应完成后再释放。关闭源后不允许尚未完成的代理解析重新创建连接。HTTPS 使用 CONNECT，配置的代理失败时不擅自直连。复用范围为现有 HTTP 代理解析能力，没有修改 FDSN 的实现。

## 验证

- 29 项回归通过，包括原始字节传输、元数据/观测请求、HTTPS CONNECT、并发直连与代理、切换、关闭、P-Alert 数据 worker 和既有 PAC/环境代理规则。
- 静态分析无问题。
- 本机实际解析 `https://palert.earth.sinica.edu.tw/graphql/` 为 `PROXY 127.0.0.1:7897`，未修改系统代理设置。
- 正式 P-Alert 工厂和服务联网核验取得 787 站目录及三个递增观测时刻：2026-10-17T13:59:50Z、13:59:53Z、13:59:56Z；错误证书主机名仍被拒绝。2 项真实联网测试通过。
- 原始响应字节保存在 `tmp/palert_proxy_20261017/live-original`，SHA256 清单位于 `live-original-manifest.json`；日志、路由核验和修改前备份位于同一目录。

本次未重打 Windows 安装包，未构建 Android，未修改云端或 APP 的推算/UI 规则。
