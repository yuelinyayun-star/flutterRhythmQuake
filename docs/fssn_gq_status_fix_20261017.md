# FSSN 状态面板与 GlobalQuake 连接修复

## FSSN

FSSN 服务已经通过 SourceManager 上报 connecting、connected、error 和 disconnected，QuakeProvider 也已接收这些状态。缺失的是 SourceDashboard 右下角状态名称列表。

补入 FSSN，沿用统一状态颜色和数据源启用开关。服务连接、解析和事件数据均未改动。

## GlobalQuake

本机原生 TCP 对主、备服务器均立即返回 Windows 10022。相同地址使用 Dart TCP 能连接并获得 HandshakeSuccessfulPacket。

独立 Mio 实测定位到：非阻塞 connect 尚未完成时，set_nodelay(true) 返回 10022；继续注册并等待可写后，take_error 为 None，peer_addr 成功。旧实现因提前设置 TCP_NODELAY 而直接放弃连接。

将设置移入 Connection::connected，在 peer_addr 确认连接成功后执行，保留原生 reactor、主备轮换、重连和解码方式。

修复前 DLL SHA256（与本次检查时运行目录中的 DLL 一致）：
`509baad42b9c997f93d04a216501a66da94ec3cec3d02680a76e6b535a726e2d`

修复后验证 DLL SHA256：
`49af1cfdf6f5580bca349fdc30b3079b6c4b110d3ceda2efb2c7e64e367dccba`

## 验证

- FSSN 服务、面板状态颜色、禁用隐藏、窄屏和多 API 换行、Jian 独立状态行：31 通过，1 项既有跳过。
- 原生 TCP、GQ 原始二进制解码和连接清理回归：16 通过。
- Rust TCP 模块：2 通过。
- 面板与相关测试静态分析无问题。
- 实际服务器连接日志保存在 `tmp/status_panel_20261017/gq_fixed_live.log`；测试直接使用修复后的原生 DLL，不注入地震事件。
- 主、备服务器各持续观察 22 秒，均获得上游握手确认，最终状态 connected，lastError 为空，2 项通过。

修改前源码和 DLL 保存于 `tmp/status_panel_20261017/before`。本次未替换正在运行的 APP 的 DLL，未生成安装包；原生修复需要重新构建并完整重启生效，热重载不能替换已加载 DLL。
