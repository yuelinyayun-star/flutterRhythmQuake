# SASMEX 实时网页地图核对（2026-10-08）

本次继续会话 `019eff06-bad3-79b3-aaea-618b840c67dd`，按最后的要求重新核对实时地图。
用户已明确 APP 的规则：有发警报就显示警报效果；不能用单个测站是否进入范围限制全局警报。

## 核对依据

- 原网页：https://asmx1-8.bolt.host/
- 当前加载脚本：https://asmx1-8.bolt.host/assets/index-D2MjXyog.js
- 原始下载保存：`tmp/sasmex_map_audit_20261008/index-D2MjXyog.original.js`
- SHA-256：`9D71B687B961C68DFC3CB60BFA20337E162D5A687AD59A24F28523E243EFC035`
- 当前脚本与此前的 `tmp_asmx_page.js` 仅末尾空白不同。

以下为当前网页源码中真实消息的处理和渲染分支。没有修改原始脚本、发送模拟事件，
也没有以历史报文改时间的方式制造实时警报；本次没有观察到真实新事件触发的画面。

## 全局警报与测站弹窗是两套判断

全局事件组件 `t$`（封装为 `r$`）直接判断 `alert.severity === "Severe"`：

- Severe：页面顶端红色渐变警报条、脉冲与文字闪烁，文字为地震警报；播放 `/alerta.mp3`。
- 其他活动消息：黄色到橙色的检出提示；检出声音受设置控制。

它没有附加“用户位置进入范围”或“某测站进入范围”的条件。

此前引用的 `zH(isOnline, isInAlert, severity)` 是测站弹窗 `HH` 的状态判断，
不是整个页面顶部警报条的判断。不能将其当成 APP 全局标题的额外门槛。

## 真实消息如何进入地图

`Bh` 收到 Socket.IO `new_message` 后，心跳进入 `heartbeat_station`；事件进入
`sidesis_message`。严重性优先读 `info[0].severity`，否则读顶层；事件坐标来自
顶层 `circle` 的第一个经纬度对。

地图组件 `$9` 监听 `sidesis_message`。它将 Severe 保留为 Severe，其余值归为
内部 Unknown 检出态，并建立活动事件及当前事件。这说明原始三档与地图内部的
红/黄分支并不是三档一对一映射。

该网页另有按州名提供坐标、缺失时提供默认坐标的逻辑。这是网页自行补值，
不能作为上游真实震中写入 APP。

## 活动事件的地图层

| 地图层 | 源码入口 | 当前实现 |
| --- | --- | --- |
| 当前震中 X | `qT` | 白色外描边，48px；每秒切换透明度。红/黄/绿来自内部 severe/moderate/light 分类。 |
| 扩散波圈 | `SH` → `EH` | 黄色 P 波边线；红色 S 波边线、光晕和半透明填充。两类活动事件都绘制。 |
| 事件所在州高亮 | `_H` → `yH` | 取州 GeoJSON 边界；Severe 为红，Unknown 为黄；透明度在 0.6 与 0.3 间每 500ms 切换。另有震中处 100 米小圆。 |
| 测站 | `nT` → `qH` | 圆点，激活后带扩散脉冲；预计烈度非零时显示带数字的烈度色圆，边框继续表达测站状态。 |
| 预计烈度区域 | `fH` → `dH` | 在州边界内取网页预计测站烈度最高档填色，填充透明度 0.55，并绘制边界。 |
| 用户位置 | `kH` | 与实时事件层同时保留用户位置标记。 |

震中 X 的分类来自测站检出计数：severe 比例大于 30% 或数量大于 15 时为 severe；
否则 moderate 比例大于 40% 或数量大于 20 时为 moderate；否则为 light。
没有检出计数时为 light。因此不能说收到 Severe 就必定直接得到红色 X。

## 波圈和测站状态的计算

网页波圈使用固定速度 P=8km/s、S=5km/s，并给 P 波增加 7 秒偏移；通常每 50ms
更新一次。这些是网页动画模型参数，不是报文提供的实测波速。

普通测站的状态阈值（排除网页特殊站点覆盖规则）：

| 活动事件 | 距震中距离 | 状态颜色 |
| --- | --- | --- |
| Severe | ≤220km | 红色 |
| Severe | 220–280km | 橙色 |
| Severe | 280–350km | 黄色 |
| Unknown 检出态 | ≤60km | 橙色 |
| Unknown 检出态 | 60–150km | 黄色 |

状态切换延迟由距离计算；红/橙/黄分别设置 5/3/2 分钟后的复位。
网页还会随机安排固定测站的连接与闪烁展示，不能把这部分当成真实测站观测数据。

预计烈度由网页模型计算；缺失震级时用 Severe 的 M6、其他的 M5，缺失深度时用
10km，并附加本地地质分类。州烈度层没有算出区域时，还会给震中所在州提供
Severe 的 5-、其他的 2。上述默认值和估算不能标为上游实测结果，也不能直接
补进 APP 的原始事件。

## 结束与历史标记

Severe 活动事件保留 5 分钟，其他活动事件 3 分钟；结束后清除活动层并保存历史 X。
历史 X 为灰色、32px，不闪烁。它与当前活动地图不同，也与 CAP 归档 polygon 不同。

## 当前本地 APP 状态

- 客户端 `SasmexService` 连接自己的 `wss://ws.yuelinrhythm.top/sasmex-eew`。
- 右下角 API 显示名为 Rhythm，内部来源仍为 SASMEX。
- SASMEX 已通过 `UnifiedQuakeData` 接入统一 EEW 事件流；Minor、Moderate、Severe
  均为 `isEew: true`。前台和 Android 后台均订阅该事件流。
- 地图复用现有 `QuakeWaveLayer` 红色震中交叉标记与统一闪烁、定位策略；坐标
  来自中转 JSON 的 lat/lng，不补默认位置。缺失或非法坐标时不绘制标记。
- 波圈和震中完全复用现有 `QuakeWaveLayer` / `WavePainter`；P 波沿用默认白色，
  S 波沿用统一事件 `className` 的现有颜色。线宽、渐变填充、透明度与震中样式
  沿用现有绘制方法；不复制网页 P 黄/S 红、粗线、光晕、多边形圈或 100 米震中圆。
  仅将网页 P=8km/s、S=5km/s、P 增加 7 秒、最小半径 500 米接入半径计算。
  传播动画从原始源时间算龄，不补震级、深度或烈度，不使用 JMA 走时表。
- 网页 2000km 停止更新，APP 将传播半径停在该上限；
  波圈更新复用 APP 的 4fps 共用时钟，州闪烁为 2fps。
  Severe 的活动层保留 5 分钟，其他消息 3 分钟；旧 snapshot 不会因接收重新启动。
- 州高亮使用网页同一份 `angelnmara/geojson/mexicoHigh.json`，原始字节随 APP 打包。
  优先匹配源地点，随后按真实坐标落州；支持 Polygon/MultiPolygon 与孔洞。
  Severe 红色、其他检出态黄色，透明度在 0.6/0.3 间切换。
  该独立层仅画州，不重复绘制波圈或震中。
- 2026-10-08 按用户后续要求撤下固定测站目录、真实测站显示和测站订阅。
  旧站点目录及功能代码保存在 `tmp/sasmex_compare_20261008/local-before/`，
  此前真实心跳核验依据仍保留在本文后面的历史记录中。
- 用户定位沿用现有 `UserLocationLayer`。历史选择沿用 APP 统一历史入口，
  没有另建网页历史库。预计烈度填色仍未接：源消息不提供所需的震级、深度和
  观测烈度，不能将网页 M6/M5、10km 和州烈度默认值变成真实事件数据。
- 自动缩放使用与该图层相同的网页 P 圈半径；不调用 JMA 走时或默认深度。
  统一震中绘制层沿用现有指针处理。
- 本地中继 `parse_sidesis_message` 已对齐真实 new_message，保留 circle 原文并提取
  中心至 lat/lng；明确模拟/回放被排除。测站心跳未作为地震事件转发。
- 本地 snapshot / query_response 均使用真实 IO 缓存；查询不会混入 CAP 归档。
- `SasmexService` 的标题已对齐全局规则：Severe 显示警报，无测站范围前置条件。
- 统一卡片保留已确定的检出 / 警报标题，按 SA 的统一 UI 约定在缺少报数时显示
  “第1報”；这是客户端展示值，不写入上游原文，不自动累加。严重性保留在徽章
  和中间行，不占用 reportNumText。地点接入现有 catalogDisplayLocation
  中文地名转换，使用真实震中坐标查询离线 FE 区域，原始地点保留在 sourcePayload
  和详情提示中。没有可转换的地点时保留原文，没有地点与坐标时显示“地点未知”。
- 中间原震级 / 深度位置显示“类型：msgType 原值 · 严重性：severity 原值”；
  缺失字段明确显示“未知”。原始 description 留在详情提示中，
  下方按现有 formatSourceClockInSystem 转换为电脑本地时间及其时区并标注“发布”，
  源时间、源时区及原始报文保持原值；API 标签 Rhythm 沿用统一地震卡片的
  时间下方独立小字行及原有字号、颜色，不拼在时间后面。
- 徽章显示严重性文字：Minor → 轻微、Moderate → 中等、Severe → 严重；
  小字为“严重性”，不显示成数字烈度。原始 severity 与 maxIntensity 不被改写。
- 鼠标悬停或长按卡片正文可查看上游标题、描述、强度文字、grado / severidad
  原值、消息类型、发送 / 更新时间与 circle 原文；只显示实际提供的字段。
- snapshot / query_response 保留源时间，旧缓存按统一 EEW 过期规则过滤；
  无编号的实时更新允许同事件坐标修订，不自动递增报次。

首次核对只保存依据；后续已按用户要求修改本地中继解析。
2026-10-08 用户指定服务器 WS 并提供登录后，部署了独立测站服务，
没有覆盖或重启原 KMA/EEW 服务。
真实 IO 观察窗口内只有握手与传输心跳，没有收到业务事件。协议与绘图测试不能
代替真实警报的端到端验收，不能用历史 CAP 或修改时间后的数据充当实时警报。

## 本次地图资源与验证

- 州边界：`assets/maps/mexico_states.geojson`，下载来源
  https://raw.githubusercontent.com/angelnmara/geojson/master/mexicoHigh.json ，
  SHA-256 `7de22266d11293117321ea0aba07b610900e06626e1fffc74ffef96b751e33dc`。
- 旧目录（已撤下并备份）：从已核验原网页 JS 的 U1 数组
  直接解码，保留全部字段和数值，不生成站点或改变坐标。
- 测试使用 2026-10-06 04:09:46 UTC 的真实 Firestore 历史事件，原数据单独保存于
  `test/fixtures/sasmex_firestore_20261006.original.json`。这是 Firestore 数据，
  不是 CAP 或本次新捕获的 IO。独立历史展示时钟只作用于绘图，不修改事件时间。
- 原坐标 `16.29569,-97.90988` 落在 Oaxaca；发布后 20 秒的网页动画为 P=216km、
  S=100km。检查了旧缓存/未来时间不会启动、州和波圈绘图、无测站圆点、
  活动结束与共用动画时钟释放。

## 已撤下的测站 WS：历史核验记录（2026-10-08）

- 上游与网页一致：Socket.IO 根命名空间 `new_message` 中 `type: heartbeat`；
  启动和每 60 秒 GET 网页公开 `heartbeat_stations` 表，select 与网页完全一致。
- 公共表源：https://lridvfywjpugfskukqif.supabase.co/rest/v1/heartbeat_stations 。
  仅 GET，不写入或删除上游。保留每条 `sourcePayload` 原始字段与类型。
- 初次实读只有 amozoc 一条记录，坐标 `19.0480497,-98.0336564`，
  ID `830111bb-f909-4a31-a486-2f277f3897de`，
  源最后心跳 `2026-10-08T04:16:30.842+00:00`。
  UUID 没有匹配到 U1 目录 ID，不按地点猜测关联，当时共显示 126 个位置。
- 服务器 `sasmex-station-relay.service` 监听本机 8766，Nginx 暴露
  `wss://ws.yuelinrhythm.top/sasmex-station`，独立于 KMA/EEW 的 8765 服务。
- 上游真实业务心跳按网页实际接收时刻算在线龄，原始 payload timestamp 不改写；
  缓存按 last_heartbeat 算龄。小于 2 小时在线，达到 2 小时离线。
  源或客户端连接失去健康时显示未知，传输心跳不能刷新测站最后心跳。
- APP `SasmexStationService` 单独接收测站，不发布地震事件或触发预警声音。
  沿用 Rhythm（SASMEX）开关，无 EEW 也显示测站；地图后台/销毁暂停 WS。
  无活动 EEW 时测站层不持有传播动画时钟。
- 点击详情显示原始名称/ID、坐标、在线状态、最后心跳（电脑时区）及未知观测烈度。
- 公网初始快照/query/ping/15 秒传输心跳已核验，缓存和 Socket.IO 均健康，
  KMA PID 前后相同。观察期间业务心跳计数为 0，尚未验收新业务心跳到地图的
  实时变化，不能将传输心跳或缓存轮询说成已经收到业务更新。

## 截图中的多站在线显示核验（2026-10-08 13:04，电脑时区 UTC+8）

用户截图显示大量绿色在线圆点。不能用心跳表的一条记录推导网页只有一个在线点。
实际打开同一网页，先观察到 101 个绿色圆点；刷新后测站组件内也已出现
53 个绿色点，而网页自己收到的 heartbeat_stations GET 原文仍然只有 amozoc 一条。

重新下载网页实际加载的 `index-D2MjXyog.js`，SHA-256 与前述相同。
固定目录状态的明确调用链如下：

1. `$9` 的 `O` 是全局 `isSidesisConnected`。全局连接建立后，等待 2 秒启动目录流程。
2. `U1` 125 站用 `Math.random()` 随机排序。每站定时器延迟
   `dt*800+Math.random()*400` 毫秒，将该目录 ID 加入 `Pi` 已连接集合。
   这一段没有逐站网络请求或等待逐站心跳。
3. 固定目录 `U1.map` 给 `nT/qH` 传入 `isConnected: Pi.has(Ie.id)`。
4. `qH` 在全局连接与该值为真时设置 `#00FF41`，并在浏览器本地生成
   `${t.name} conectado al sistema` 的 `[CONN]` 日志。特殊站点固定颜色另行覆盖。
5. 真实动态心跳站 `Pe` 是另一个列表，由 `m9` 读取公开表并监听
   `heartbeat_station`，传入的是 `isConnected: Ie.isOnline`。

浏览器 CDP 从刷新起记录了网页实际请求的两个 WS：Sidesis 与 SeismicPortal。
在固定点变绿、出现连接日志的观察窗口内，Sidesis 仅收到 `0`、`40` 握手及 `2`
传输心跳，没有测站 `new_message`。SeismicPortal 收到的是 Flores Sea 地震事件，
并非墨西哥目录站心跳。网页自己的公开表 HTTP 200 响应就是前述一条 amozoc 原文。

因此需明确区分“网页呈现多站在线”和“逐站实际收到心跳”。当前 APP 接入的是
真实心跳记录；不会将目录启动定时器产生的绿点/连接日志标记为实测数据。
没有修改原始网页、发送模拟消息或修改 APP/服务器的站点数据。

本次原始脚本与精确摘录：
`tmp/sasmex_station_audit_20261008/green-audit-20261008T050403Z/`。
`directory-online.original-excerpt.js` 是目录状态定时器，
`directory-marker-props.original-excerpt.js` 是两种列表的传值，
`green-and-connection-log.original-excerpt.js` 是绿色和连接日志的生成代码，
`real-heartbeat.original-excerpt.js` 是独立真实心跳入口。


## 双连接对照

APP 保持原有 Sidesis `/sasmex-eew` 实时通道；独立服务器观察器只读连接 Socket.IO
与 Firestore `sasno-d79e1` 的 `app/events`，每秒轮询后者。两个来源的真实原文、
连接状态及原始轮询实现备份到 TG `SASMEX原始归档/双连接对照/YYYY-MM-DD/`。
Firestore 不进入 APP，10 月 6 日旧文档只建立基线。连接可达、实际收包和内容变化
分开统计，不能以连接成功代替新事件证据。实现和部署说明见服务器 README。
