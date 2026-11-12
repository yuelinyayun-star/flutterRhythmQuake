# 2026-10-23 回放文件存储更新

正式服务为 `64.90.20.78` 上的 `rhythmquake-collector.service`，
程序仍位于 `/opt/rhythmquake-collector/bundle`，上传定时器与原 Telegram 目标保留。

## 本次变更

- 采集目录按事件命名，每报独立 JSON、每帧独立 gzip JSON；重叠事件共享帧。
- 事件结束流式输出 v3 ZIP 回放包，文件名含北京时间、地名、震级、来源与事件编号。
- 保留旧哈希目录及旧检查点读取，上传器同时接受新事件名称与旧文件名。
- 文件名按 UTF-8 字节限制长度，兼容 Linux 的 255 字节文件名上限。
- 配置 `XDG_STATE_HOME=/var/lib/rhythmquake-collector/runtime`，让鉴权重试记录
  位于 systemd 允许写入的位置。没有清空暂停状态或变更凭据。

## 构建与部署证据

Linux x64 Release 使用 Flutter 3.41.1 / Dart 3.11.0 构建，依赖版本及内容摘要
与工作区 `pubspec.lock` 一致。构建目录与 Windows 工作区隔离。

- 程序包：44,839,116 字节。
- 程序包 SHA-256：`a4dfbd5183eab2e7b45d907d677022e417889f83441c87fb2345490ae14fb7ee`。
- 实际运行 bundle 的 `lib/libapp.so` SHA-256：
  `441f6b33b5d67255d827586599d6e4bd9e7249961e779bec48c65528f7994e50`。
- 上传器 SHA-256：`74b6e0031eb00a888464e5041a8973c504758a4b7e69468146b7085c706c8287`。
- 旧程序、活动目录、待传目录、旧上传器及 unit 备份：
  `/opt/rhythmquake-collector/backup-files-20261023-134719`。
- 部署及运行验收 JSON：
  `/opt/rhythmquake-collector/stage-files-20261023-a4dfbd5183ea/`。

## 验证与边界

- Windows 下相关存储、恢复、命名测试 25 项通过。
- Linux 下采集与命名测试 17 项通过；使用仓库原始报文验证保存、恢复和导出。
- 上传器在服务器执行 9 项测试通过；完整本地 Python 套件 12 项通过、
  2 项因缺少旧性能产物跳过。
- 暂存 bundle 不带凭据启动，按预期返回 64；未建立测试鉴权连接。
- 运行进程的实际路径、加载程序摘要及可写状态目录均已核对。
- Jian 实收连接成功；上传任务退出 0，定时器 active。
- 原 KMA 中继、nginx、FileBrowser 服务保持 active。
- 切换时没有活动事件和待传回放，没有注入改写时间的历史报文到正式采集。
  上线后新事件的端到端整包生成和云盘读回仍需实际有效预警产生。
- P-Alert 站表请求在更新前已报证书错误，更新后仍存在站表请求失败，
  未将其列为已恢复来源；TREM 部分节点有 HTTP 502，存在自动切换。

这次验收是部署、兼容性和短时接收检查，不作为长时间活动录制的内存上限保证。
