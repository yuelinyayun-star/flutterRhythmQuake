# SASMEX TG 归档与云盘目录修复（2026-10-12）

## 结果

本地备份、修改和检查后部署。TG 对照归档仅在收到真实地震报文或 Firestore 事件内容变化时上传。
心跳、握手、连接／断开、错误／恢复、每分钟状态、启动备份、未变化的旧文档不会触发上传。
上传 timer 保留每分钟检查；空队列直接退出，不上传状态包。原始报文仍按接收字节保存，上传回读校验 SHA-256 和长度后才释放本地临时包。

Firestore 正常轮询改为 5 秒。HTTP 429 从 60 秒指数退避到最多 900 秒，其他失败从 5 秒退避到最多 300 秒；遵守更长的 Retry-After。成功后恢复 5 秒。
实测 14:58:09、14:59:10（UTC+8）失败后分别退避 60、120 秒；15:01:11 恢复 HTTP 200，回到 5 秒周期，旧文档未重报。

TGFS 修复消息查询队列：新查询不再取消正在执行的查询；所有等待者都有明确的结果、错误或取消结果。
每批最多 100 个消息 ID，批间间隔 0.25 秒；消息 ID 缓存仍有上限，容量从 1024 调至 16384，搜索缓存保持原上限。
原查询队列复现并发到达时的超时，新代码通过 8 项检查。

挂载曾短暂恢复：以 filebrowser 用户列目录并逐个读取属性，父目录 5 项约 0.0045 秒，2026-10-11 的 934 项约 0.1342 秒，2026-10-12 的 321 项约 0.0429 秒。
随后再次验证时直接 WebDAV 与挂载目录均超时，TG 后端连续出现约 30 秒 FloodWait，因此尚不能认定目录阻塞已经彻底修复。继续核对实际缓存命中与查询数量，不将短暂缓存命中或未登录网页外壳 HTTP 200 当作完成证据。

## 为什么之前一直上传

- 比较观察器把每 25 秒收到的 Engine.IO `2` 心跳送入 outbox。
- 每 60 秒连接状态快照也送入 outbox。
- connecting、connected、disconnected、connection-error、invalid-response、recovered、implementation-backup、stopped 等运维状态同样会生成包。
- 每分钟上传检查因此始终有内容；最近 24 小时有 937 次成功的对照包上传，最近每包 4–5 条记录、约 5–7 KB。
- 实际回读的一包是 3 条原始 `2` 心跳和 1 条 connection-status，没有地震报文。
- 原始 `2` 的 SHA-256 为 d4735e3a265e16eee03f59718b9b5d03019c07d8b6c51f90da3a666eec13ab35。

修复后连接状态继续保存在服务器 connection-status.json 和 journal。Firestore 初始快照、最近变化快照、最近错误响应保留本地原始字节；历史 TG 归档后来按用户要求清理非报文，清理前完整备份另存，见下文。
截至 15:18:56（UTC+8）的观测：两路 healthy=true；Firestore 203 次成功、变化 0；新归档 0，TG 上传 0，空队列检查 18 次。

## 目录阻塞的证据

早期页面 HTML 可返回 200，但已登录目录 API 没有结果，nginx 记录客户端取消 499。
父目录直接 WebDAV 能列出五个日期，只证明父目录可读，不能排除日期目录的后端问题。
进一步读取昨天目录，直接 WebDAV 同样超时；Go 栈显示 rclone 等待 WebDAV HTTP 响应。
TGFS 日志有 GetMessagesRequest FloodWait。代码中消息 broker 会在新请求到达时取消旧 worker，已取走的请求 future 没有被完成，导致永久等待。

原代码复现：6 项调度检查中有 2 个失败和 1 个超时错误，其中并发新查询导致先来请求超时。
修复后 8 项调度／缓存检查通过。检查只使用离线调度标识和 mock bot，不连接 Telegram，不伪造或推送地震事件。
SASMEX 本地相关检查 17 项通过，服务器候选观察器 10 项通过；其中 Firestore 正常与 429 样本均来自实际原始响应。

挂载恢复还发现断开的旧 FUSE 挂载点会阻止 ExecStartPre mkdir，造成重启循环。
核对 in use=0、to upload=0、uploading=0 后结束旧进程并分离残留挂载；为 TG 实例安装 ExecStopPost 清理配置，不删除缓存或远程文件。

## 部署和备份

- 本地原始观察器备份：tmp/sasmex_tg_audit_20261012/local-before-fix.zip。
- 服务器观察器备份：/opt/rhythmquake/backups/sasmex-event-only-20261012T065658Z。
- TGFS 全部源代码原始备份：tmp/sasmex_tg_audit_20261012/tgfs-source-before.tar.gz。
- 本地 TGFS 可编辑源：D:/Users/Rhythm/Documents/YuelinCloud/TGFS。
- 服务器 TGFS 初始修复备份：/opt/rhythmquake/backups/tgfs-broker-20261012t071612z。
- 服务器 TGFS 缓存／节流修复备份：/opt/rhythmquake/backups/tgfs-broker-20261012t072322z。
- 旧镜像保留为 tgfs-tgfs:before-broker-20261012t071612z；当前镜像候选为 tgfs-tgfs:broker-fixed-20261012t072322z。
- 挂载清理配置备份：/opt/rhythmquake/backups/tgfs-cleanup-20261012T070117Z。

APP 主中继没有改动或重启，PID 始终为 158330；SASMEX 实时 WS 健康检查正常。
观察器 sasno_realtime.py 仅部署 Retry-After 响应头保留的最小差异，保留服务器既有旧映射实现；APP 的实时解析不受影响。
所有修改在本地完成后部署，不在服务器编辑项目源文件。历史 TG 归档仅按下文已核验清单清理，保留原文和清理前完整备份，没有使用 git checkout。

详细原始日志、部署哈希、查询耗时和检查输出保存在 tmp/sasmex_tg_audit_20261012/。

## 用户要求的非报文清理与报文日期目录

2026-10-12 追加核验：逐包读取 3862 个对照归档，校验外层 ZIP、内层记录 ZIP 及原始附件 SHA-256 和长度。共 19968 条记录，19966 条非报文，2 份 Firestore 初始快照含真实 2026-10-06 04:09:46 UTC 的地震原文，无无法分类的记录。

已部署观察器的报文日期改动，服务器 10 项检查通过。Firestore 用原文 unix、Socket.IO 用现有解析器 sent／updated 对应时间生成 eventTimeUtc；uploader 原有同日期分包规则继续使用，不按收到或上传日期归档已知事件。

2026-10-12 11:02:56 UTC 提交清理，并回读整个 TGFS 元数据树一致。删除 3862 个已审计的旧文件引用（其中 3860 个纯非报文包、2 个混合包），移除 2026-10-08 至 2026-10-12 五个空日期目录。共 19966 条非报文从云盘可见目录移除；2 份有效快照的内层 ZIP 和原始响应字节保持不变，统一保存到源事件日期目录 2026-10-06，合成一个仅含有效快照的外层上传包。

保留包为 SASMEX_20261006T040946Z_20261006T040946Z_24b220b656548e116cc75b0cd75698dbeeda61991d026414b78198507089c087.zip，4230 字节。目录重新挂载后，以 filebrowser 用户列目录并读取全部属性：父目录约 0.0211 秒，仅 2026-10-06；日期目录约 1.9508 秒，仅该包。再经直接 rclone 回读约 0.4702 秒，外层包、两份内层 ZIP 及原始 Firestore 响应长度与 SHA-256 全部通过。文件页面和挂载服务均恢复 active，APP 中继 PID 158330 未改变。这里验证的是页面所用挂载目录和服务状态，不将未登录网页外壳当作已登录目录验证。

清理前全部原始 ZIP、元数据、审计清单已备份到服务器 /opt/tgfs/data/sasmex-cleanup-20261012t104335z/，并下载本地 tmp/sasmex_tg_audit_20261012/original-cloud-archives-before-cleanup.tar.gz；大小 13986811 字节，SHA-256 为 82c4f5159fd2b7bdbd3ceb5f66cc451802cb3e4461fdf76ae8c9650324e4351b。此备份不在云盘可见目录。删除采用 TGFS 文件引用删除语义，不直接清空 Telegram 频道消息历史。

清理工具首次因脚本目录未带 /app 的 Python 模块路径而在载入前退出，未改元数据；补充 PYTHONPATH 后遇到 FileBrowser 的 FUSE 读取线程阻塞。确认 VFS in use=0、to upload=0、uploading=0 后停止挂载释放读取，保留所有 VFS 缓存，再提交清单。服务和原来启用的上传 timer 已恢复。

新写的 TGFS SQLite 元数据缓存仍只在本地／候选区，未部署；用户要求先清理，已暂停该迁移。当前运行镜像仍是 tgfs-tgfs:read-rate-20261012t102331z。
