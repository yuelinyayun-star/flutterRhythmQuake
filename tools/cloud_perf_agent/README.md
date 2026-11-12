# RhythmQuake 云电脑性能诊断

在云电脑上先启动 APP，再双击 `Start.cmd`。不需要 Python、Rust 或 .NET 运行库。
工具每秒采集目标 APP 的工作集、专用内存、CPU 原始计数、句柄及 IO；磁盘逐行保存 JSONL，内存只留最近 120 条。
默认一小时自动停止，旧采集目录不会被覆盖。代理自身的内存和 CPU 计数单独记录。

APP 打开“本地模拟注入接口”后，新版还会提供原生分配量、EEW/情报队列、震源推算积压帧及计算耗时、历史写入积压。
旧版没有此接口时仍可测 Windows 进程数据，`appDiagnostics.unavailable` 会明确说明内部数据不可用。

## 远程连接

工具仅监听 `127.0.0.1`，随机生成本次诊断的访问令牌。通过 SSH 反向隧道连接可访问的中转机，无需开放云电脑入站端口：

```powershell
.\Start-CloudPerf.ps1 -SshTarget user@relay -RemotePort 18769
```

SSH 使用原有密钥或交互登录，不把密码写入工具。中转机需要允许 SSH TCP 转发。
本次连接资料写入中转账户工作目录 `.rq-perf-connection-18769.json`，权限由 `umask 077` 限制；隧道关闭时清除。
没有修改中转机或 APP 的源代码。中转端口也只绑定回环地址，不对公网暴露。
将中转机连接方式告知负责诊断的人员后，即可通过中转机回环端口读取测试结果。

本机可用 `connection.json` 内的地址和令牌测试，令牌不要公开发送。

## 接口

全部接口要求 `Authorization: Bearer <本次令牌>`。

- `GET /status`：真实进程标识、最近一条数据、采样条数。
- `GET /samples`：最近 120 条，所有更早数据保存在云电脑的 `samples.jsonl`。
- `POST /scenario`：`{"label":"estimate-enabled"}`，仅标记测试阶段，不更改 APP 设置。
- `GET /app/diagnostics`：最近一次 APP 内部指标。
- `GET /app/health`：检查本地模拟接口。
- `POST /app/inject?format=whews`：把请求体的原始字节转发给 APP，最大 8 MiB，不提供改写时间的参数。
- `POST /shutdown`：停止诊断代理；不关闭 APP。

工具没有远程命令执行、任意文件读取、进程终止或系统配置修改接口。
采样覆盖指定的 APP 进程，不把 GPU 驱动或其他进程占用冒充为该 APP 内存。Windows 任务管理器的内存显示口径可能与专用字节不同，因此同时保留两项。

## 对照步骤

记录相同地图视野与数据源，依次测空闲、仅 EEW/情报、震源推算开启、推算停止后的释放。
用 `/scenario` 标记各阶段，每段至少 3–5 分钟；原始报文、GIF、观测时间保持不变。
同时查看 CPU、专用内存趋势、Rust 分配量、推算 pending/maxPending、计算/周转耗时和历史写入积压。
原生分配稳定而进程专用内存增长、或计算耗时高于数据到达间隔，代表不同问题，不能只凭 RSS 宣称“内存泄漏已修好”。
