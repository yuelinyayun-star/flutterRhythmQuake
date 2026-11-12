# Debug 内置网络记录与导出

本工具用于本机诊断，不自动上传文件，不修改 Token、代理、源开关、重试策略或冷却时间。原文和 TLS 密钥包含凭证，保留在本机，不应公开发布。

1. 将完整的 `RhythmQuake_NetworkDebug_x64.zip` 解压到云电脑。
2. 退出旧 APP；在准备好解封后，右键 `NetworkDiagnosticExport.exe` 以管理员身份运行。
3. 点击“抓包并启动 Debug”。工具先启动系统抓包，再启动 `APP` 中的 Debug。不是覆盖原安装目录。
4. 复现问题，点击“停止抓包并导出”，或等待 180 秒自动导出。桌面生成 ZIP。导出完成不会退出 APP，停止全部连接时手动退出 APP。

Debug 单独启动也会自动记录到 `%LOCALAPPDATA%/RhythmQuake/network_diagnostics/`，但系统抓包应由导出器先行启动。导出器不再替旧版本 APP 注入临时 DLL；仅接受带文件校验标记的配套 Debug。

## 文件

- `app_capture/network_raw.jsonl`：原始字节以可逆 Base64 保存，UTF-8 元数据记录时间、PID、连接编号、请求参数、调用方请求头、响应、收发、错误及关闭。包含凭证。
- `network_raw.jsonl.status.json`：已写条数、队列字节、丢失条数、写入错误和文件大小。原文上限 1 GiB，队列上限 32 MiB；超出时明确计为丢失，不能当作完整记录。
- `app_capture/tls_keys.log`：NSS 格式的 Dart TLS 会话密钥，可配合 Wireshark 解密；Rust/WinHTTP 已在应用传输层保存明文。
- `network*.etl`：PktMon 全包与 TCPIP/WinHTTP 事件；转换成功时另有 `network*.pcapng`。系统抓包可能同时含其他程序流量，需按 PID/五元组关联，不是只抓 APP。
- `sample_*.json`：实际进程、加载的 DLL 路径和哈希、TCP 端点、Jian 的冷却和真实测站源配置。DNS 地址可能共用，不能单凭地址判断域名。
- `report.json`：记录器、抓包、转换、落盘确认结果。`flushStatus=confirmed` 时原文快照严格复制到确认落盘的完整记录边界，不重编原文。

## 覆盖与边界

覆盖 Rust HTTP/WS/TCP、Dart HttpClient 的请求及消费到的响应、通用 Dart WS 和 SourceTcpSocket、专用 FDSN TLS。日志是旁路观察，不把原本的 Rust 连接切换到 Dart，不重试接口或主动发业务探测。

`send_queued` 不是服务端已收到的证明。调用方请求头不代表 WinHTTP/SDK 自动追加的全部线上头部。自动 HTTP 重定向、中途取消而未被应用消费的响应、原生插件、子进程、UDP 和其他分离 Socket 要结合系统抓包；TLS 解密只覆盖实际导出的密钥。不能仅凭明文日志宣称所有流量均已解密。

PktMon 原有过滤器不会被清空，状态另存 `packet_filters.txt`；已有过滤器可能影响包覆盖。系统不允许启动抓包时不会启动 APP，也不会抢停其他人的抓包。

普通 `lib/main.dart` 不启用记录器。专用入口为 `lib/main_network_diagnostic.dart`，仅 Debug 可启用。此包用于诊断，不用于比较正常版本的 CPU/内存。

编译后自检参数 `APP/flutterrhythmquake.exe --network-diagnostic-self-test` 仅访问回环 HTTP，不启动业务源；导出器 `--self-test` / `--ui-self-test` 不启动 APP、不访问上游。
