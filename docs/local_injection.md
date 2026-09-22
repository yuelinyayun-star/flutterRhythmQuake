# 本地报文注入

## 入口和来源

顶部“模拟注入”和 Debug 调试工具中均可设置“本地注入 API”的开关和监听端口。
桌面正式安装包也支持监听，默认关闭。端口范围 1–65535，设置会保存。
端口冲突会显示错误；切换端口失败时保留原监听和原端口，不接管其他程序的端口。
手机可以使用面板内的手动注入，但目前不启动 HTTP 监听。

HTTP 地址为 `http://127.0.0.1:<端口>/inject`。这是程序自身的注入入口，
不是上游服务的注入功能，也不需要上游 API 的鉴权凭证。
注入事件只发到统一事件链路一次，机构身份、报次、过滤、过期、语音和视角仍由原链路处理。
卡片、历史记录中的 API 名称为“本地注入”，监听时数据源面板也显示此名称。
保留原始报文及时间，不把旧事件自动改成当前事件。因此已过期报文不保证出现活动卡片。

## 格式

通过 `?format=...&source=...` 指定，或在面板选择格式、填写机构/适配器。
也支持单独的注入信封：`{"format":"whews","payload":原始报文}`。
`source` 只是解析提示，不是显示的 API 名称。

| format | 接受的事件数据 |
| --- | --- |
| auto | 可识别的原始业务包；FAN/WHEWS 等外形相同的包请明确选择格式 |
| wolfx | EEW；JMA/CENC 的 No1/No2 列表；单项列表指定 source |
| fan | update、initial、initial_all、query_response、列表和单源事件 |
| p2p | 551 地震信息、552 海啸信息 |
| whews / wauth | source + Data 业务包，包括地震、火山、气象预警和已适配海啸类型 |
| jian | type + Data、all（支持全角冒号）、list_response |
| nowquake | 包含 eq_id、stations 的 CENC 烈度速报原始数据 |
| nied | NIED EEW JSON（不等于测站 GIF） |
| adapter | source 指定现有适配器，例如 fnetCmt、hinetAquaCmt、usgsCmt，payload 为该适配器接收的数据 |
| unified | 程序统一事件的 toMap 数据，用于已解析事件回放，包括 GlobalQuake |

支持 JSON 数组及已有工具使用的 meta/reports 文件；整批解析成功才发布。
`GET /help` 列出格式和适配器名称。心跳和鉴权回包不是事件。
Jian 全量包仅接纳正式客户端已接入的业务类型，不把尚未接入的气象或灾害类型伪装成地震。
这不是通用二进制解码器：GlobalQuake Java 序列化流、SeedLink 波形、HTML/XML
原始响应不能直接粘贴为 JSON；这些需先由原服务解析，再以 adapter/unified 形式回放。
气象图像、瓦片和台风路径不属于本事件入口。

## PowerShell

使用保存好的原始 JSON 文件，不修改文件内容：

```powershell
.\tools\local_inject.ps1 -Action health -Port 18765
.\tools\local_inject.ps1 -Action inject -Port 18765 -Format p2p -JsonFile .\test\fixtures\jma_voice\p2p_scale_prompt.json
```

脚本先验证服务标识，再提交原始 UTF-8 字节，防止向占用同端口的其他服务误发。
旧的 `/inject/eew`、NIED GIF、K-NET 和 replay 路由保留。
脚本的 eew/scenario 默认也不修改时间；原有改时功能须显式传入 `-FreshOrigin`，仅用于模拟样例。

## 历史报文回放包

历史卡片底部的播放和下载按钮分别用于回放、导出该事件已保存的报文。
没有原始报文的旧记录不可回放；部分报次缺失时显示数量，只导出已有的报次。
单报、多报卡片仍保持统一尺寸。

模拟注入面板可导入 `.rqreplay` 文件，也接受相同结构的 `.json` 文件。
导入只加载，点击播放后开始；支持重新播放和停止，不要求开启 HTTP 监听或 SSH。
回放包采用 UTF-8 JSON，格式标识 `rhythmquake-replay`，版本 `1`，包含每报的
统一事件快照和当时保存的完整 `sourcePayload`，不额外读取或导出账号设置。
这里的原始报文是保存时的解码对象，不是逐字节网络抓包。

回放优先依据已保存的发布时间，其次读取原报文中的发布时间，最后使用接收时间。
均没有时间时转为逐报播放，由“下一报”推进，不编造间隔。
原报文和卡片时间不改写；地图波圈使用独立的回放时间偏移。
回放标为“本地注入 · 回放”，静音，不写入历史、目录列表或实时去重缓存，
不发送系统通知，也不触发 OBS 自动化。真实预警继续接收和处理。
最后一报展示 30 秒后自动清理，停止或重播仅移除当前回放会话。
回放包上限 16 MiB、1000 报，自动回放的时间跨度上限 24 小时。

## SSH 转发

“注入的 SSH”是 SSH 隧道加上上述 HTTP 接口，而不是程序内置 SSH 登录服务器。
如果运行程序的电脑已配置可用的 SSH 服务，在另一台设备执行：

```text
ssh -L 18765:127.0.0.1:18765 用户@运行RhythmQuake的电脑
```

然后向发起隧道设备的 `http://127.0.0.1:18765/inject` 提交报文。
左右端口可不同，右侧须对应程序设置。系统 SSH 连接端口由 ssh 的 `-p` 参数决定，
与程序监听端口独立。本次不会安装、启动或更改系统 SSH，也不更改防火墙。
接口只绑定回环地址，拒绝带 Origin 的浏览器请求及非本地主机名，报文上限 8 MiB。
