# 独立回放采集服务

本服务不依赖浏览器打开，不修改普通网页、桌面端的配置或历史记录。
它用独立 Flutter 原生入口复用现有解析器和回放编码器，不加载地图、音频、
OBS、GQ、ICL 或 SeedLink 服务。当前录制对象与应用历史回放一致：Jian 推送的 EEW 事件，
不是普通地震目录、气象资料或所有 `/all` 字段。

## 保存到哪里

最终目标固定为 **Telegram 云盘 / RhythmQuake回放文件夹**。

1. `active/`：事件进行中的本地检查点，测站使用无损 JSON 字典压缩，每 5 秒落盘。
2. `outbox/`：事件结束后生成的标准 `.rqreplay`，等待上传，不是最终网盘。
3. `upload_telegram.py`：验证实际 TGFS 别名及本机 WebDAV 地址，读取独立私有配置。
4. 直接 `rclone copyto tgfs:RhythmQuake回放文件夹/...`，绕过 FUSE 异步写缓存。
5. 经该远端网关重新读回并核对 SHA-256 后，写入回执、删除本地待传包。

别名不匹配 Telegram、网关失联、上传失败、校验失败都会保留待传文件。
不会退回本机文件夹，不调用 Telegram `sendDocument` 绕过网盘索引，不替换已有不同内容。
网关读回校验不能代替首次上线时对 TG 频道/存储索引实际持久化的验收。

2026-10-04 已通过 SSH 核对实际部署：FileBrowser 的 `Telegram 云盘` 对应
`/mnt/yuelincloud/tgfs`，`/etc/rclone/yuelincloud.conf` 的 `tgfs` 是
`tgfs-webdav:telegram` 的别名；网关为 `http://127.0.0.1:1900/webdav`。
实际实现是 `/opt/tgfs`，文件和描述消息写入 Telegram，上传接口等待元数据推送。
不是旧本地 YuelinCloud 副本的 WIP 托管连接；该服务器没有 `connections.json`。
已只读列出目标目录，目录存在。实际传输验收与代码测试应分别记录。

## 测站与结束时间

- 默认启用 NIED、S-net、KMA、TREM/CWA、SeisJS、P-Alert、LPGM。
- 不连接或保存 GQ、两个 ICL 源、SeedLink 测站；采集和检查点恢复均拒绝 GQ/ICL 事件。
- `RQ_COLLECTOR_STATIONS` 只控制这个独立进程，不修改用户设置。
- S-net 当前使用现有 MSIL 适配器；NIED 使用 Lmoni；其他源复用各自原生服务。
- S-net 保存坐标、站号、震度、活动状态和观测时间等 JSON 字段，不保存图片。
- LPGM 保存现有回放模型的读数、最大 SVA、最大阶级和测站摘要；不宣称保存原始波形。
- 有原始 JSON 的来源随帧保留；图像来源只保存现有解码器产出的显示快照，不伪造原始 JSON。
- 未开启的源不启动、不保存。没有活动事件时只保留各源最近一帧，不持续写历史文件。
- 不以“最终报”直接结束：按现有 `eewDisplayDuration`、收到时间和 30 秒尾段确定结束时间。
  后续报文可以延长窗口，不会缩短；同时发生的事件分别保存各自的测站时间段。
- 重启恢复已有检查点，不补造停机期间的数据。异常断电可能丢失最后约 5 秒未落盘数据。
- 待传队列或采集中数据达到默认 8 GiB 时停止并报错，不自动丢弃未上传文件。
- 超过现有回放格式 128 MiB 限制的单个事件会保留检查点并报错，不能声称已经上传。

## 构建与运行

运行时仍使用 Flutter 引擎，但独立采集入口启用 CPU 图片解码，
S-net、LPGM 和 NIED 的回退解码均不再创建 `dart:ui` 图片资源。
这是独立原生采集进程，不是纯 Dart CLI，也不是无头浏览器。
Linux 无桌面服务器使用 Xvfb。空白 Flutter 根节点下的原生图片解码可持续累积
原生内存；使用已有 `image` 库只解码首帧，通过原始 GIF 的像素逐字节对比验收。
服务设置 640 MiB 软限制、896 MiB 硬限制和一个 CPU 核心的配额，避免采集故障
耗尽整台服务器。硬限制不是正常内存目标；每分钟记录 RSS 和活动事件数。

在 Linux/WSL 的独立构建目录，使用项目已有 Linux 依赖（参考
`.github/workflows/linux-build.yml`）；Ubuntu 24.04 的最小化安装还需
`lld`、`llvm-18`，提供原生资产构建使用的 `ld.lld` 和 `llvm-ar`。执行：

```sh
flutter pub get
flutter build linux --release --target lib/main_collector.dart --dart-define=RQ_EDITION=personal
```

将专用 bundle 部署到 `/opt/rhythmquake-collector/bundle`，不要覆盖普通客户端 bundle。
额外运行依赖为 `xvfb`、`xauth`、Python 3、现有 rclone 及 Linux bundle 依赖库。
无桌面的 Ubuntu 24.04 还需 `libegl1`、`libegl-mesa0`、`libgles2`、
`libgl1-mesa-dri` 和 `gsettings-desktop-schemas`；EGL/GLES 是运行时动态加载，
仅检查 `ldd` 不足以完成验收。
配置目录 `/etc/rhythmquake-collector` 只允许服务用户读取，使用
`collector.env.example` 中的独立路径。`jian-token` 仅包含 Jian 长期 `rt_` 凭据；
不要提交到 Git，不要打包进 Flutter，也不要放到公开 Web。

先只读核对 TG 连接，不会上传：

```sh
sudo -u filebrowser python3 /opt/rhythmquake-collector/upload_telegram.py --inspect
```

程序只输出远端名、配置路径和目标文件夹，不输出 token。
`install_server.py` 在服务器上提取现有配置的两个 Telegram 段，写入
`/etc/rhythmquake-collector/telegram.conf`，权限 root:filebrowser 0640。
不复制 R2 凭据，不修改现有配置、挂载或网盘服务。TGFS 凭据变更后需重新安装配置副本。
安装脚本只安装独立服务文件，不启用采集或定时上传；不会创建或覆盖 Jian 密钥。

`rhythmquake-collector.service` 管理采集进程；`rhythmquake-replay-upload.timer`
每分钟重试待传队列。安装不会自动启动；采集服务另有 Jian 密钥文件存在性检查。
首次上线需：确认 TG 目录与网关、配置 Jian 凭据、上传一份已知真实回放、核对 TG
持久化记录、重新下载并在客户端导入，再验收重启和断网重传。

## 本地验证

```sh
flutter test --no-pub test/replay_collector_test.dart test/station_history_replay_test.dart
python -m unittest discover -s server/replay_collector -p 'test_*.py' -v
```

测试使用仓库原始 CWA/Jian 回放或抓包，不改写其报文。非空 S-net 序列化用例明确标注为
模型测试数据，不能当作在线观测或 TG 上传成功的证据。

## 2026-10-04 上传验收

- 使用用户原有 `RhythmQuake_1790619619000(3).rqreplay`，4450 字节；只对上传副本改文件名，内容未改动。
- 上传服务返回成功，网关重新下载及 FileBrowser 挂载读取均得到相同 SHA-256：
  `f955f8260f4e2fbee4da12265ab35d2d8e91dee9cb0a9bfe0ae442b9d436a969`。
- 独立只读 Telegram 会话读取置顶目录元数据，找到目标文件夹与描述消息 35；
  文件内容消息 36 直接从 Telegram 下载后，字节数及 SHA-256 再次一致。
- 服务已保留上传回执、移除本地待传副本；该真实回放留在用户指定 TG 文件夹供核对。
- 上传定时器已启用；网盘和 nginx 保持运行，没有重启它们。
- Jian 密钥尚未配置，采集服务未启用；以上不代表已完成 Jian 实时采集或长期性能测试。
- 独立 Linux x64 Release 已在 WSL 编译并部署到 `/opt/rhythmquake-collector/bundle`。
  包大小 36728895 字节，SHA-256：
  `f63be3d1203af18a15982cf4e2799458c26d8d27bfc3d21fd1ae418ceaada2ee`。
- 服务器 Xvfb 下的缺少配置、空密钥启动检查均返回预期退出码 64；
  `systemd-analyze verify` 通过。未使用伪造密钥进行在线采集测试。

## 2026-10-04 内存修复上线验收

- 旧采集进程两次因匿名内存约 2.7 GiB 被内核 OOM 杀死；重启后没有活动事件，
  内存仍持续增长。待传目录没有回放积压，问题不是上传或写文件积压。
- 在 Linux/Xvfb 下重复解码同一份仓库原始 NIED GIF 1000 次，原生路径最终 RSS
  为 985006080 字节；生产 CPU 解码路径为 198172672 字节。原始 GIF 与 S-net
  PNG 的解码像素逐字节一致，没有修改源报文或图片，也没有改变普通客户端默认路径。
- 用户重启服务器后，先停止旧采集服务，再部署私有采集 bundle；启动时间为
  2026-10-04 14:36:45 UTC。旧 bundle 与旧 unit 均保留备份，未删除历史或上传队列。
- 本次 bundle 大小 36742302 字节，SHA-256：
  `7fac99a4901fab71c536394d65d243b085cb2ace7dd429b0f6b89e835e690c57`。
- 启动确认 `imageDecoder=CPU`、`excluded=GQ,ICL,SeedLink`。七个测站源均收到 JSON：
  NIED 1634、S-net 150、KMA 265、TREM/CWA 104、SeisJS 1、P-Alert 787；
  LPGM 本次收到 5 条 topStations 摘要。数量仅描述当次接收，不代表固定站数。
- 14:38:30 至 14:48:30 UTC 按分钟采样：主进程 RSS 240.8-254.9 MiB，
  cgroup memory.current 157.5-171.6 MiB，进程组内存峰值 193.3 MiB。
  两种内存口径不同，不将 cgroup 数值当作 RSS 或承诺严格保持 200 MiB。
- 采集进程组 CPU 为一个核心的 28.48%-33.35%，折算四核整机为 7.12%-8.34%；
  整机 CPU 同期为 8.20%-9.29%。没有服务重启、OOM 或内存限额触发。
- KMA 健康接口持续正常，265 站，采样时最新帧年龄 0.056-0.697 秒、连续失败 0；
  公网 WebSocket 实收连续 update。网盘首页与公网健康接口返回 HTTP 200。
- TG 上传定时器保持运行，目标仍为 `tgfs:RhythmQuake回放文件夹`。无活动事件时
  active/outbox/runtime 分别约 4/8/4 KiB，未持续落盘测站历史。
- P-Alert 期间出现上游连接提前关闭及暂时断开，已有逻辑自动恢复；不宣称所有上游
  全程无网络异常。本次没有新活动预警，尚未验证修复版新生成的完整在线回放上传。
- 修复相关 42 项 Flutter 测试、7 项上传测试通过，8 个相关 Dart 文件分析无问题。
  本次结论是短期空闲接收与解码压力测试通过，不是长期或最大回放负载的性能保证。

## 活动录制补测

随后已在同一服务器运行独立探针，实测一分钟单回放与五分钟双回放。
短回放导出和逐帧校验通过，但导出 RSS 峰值约 634 MiB；双回放导出因内存软限流
停滞，未生成最终文件，测试不通过。正式采集未停止，测试文件不进入 TG 上传队列。
详细口径、原始报告位置和实测数据见 [PERFORMANCE_20261004.md](PERFORMANCE_20261004.md)。
