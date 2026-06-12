# FAN Studio API 字段和调用说明

## 1. API 文档

### API 地址

| 类型    | 地址                             |
| ----- | ------------------------------ |
| 正式服务器 | wss\://ws.fanstudio.tech/\[路径] |
| 备用服务器 | wss\://ws.fanstudio.hk/\[路径]   |

### 新补充内容

WS API可通过向服务端发送cenclist、fssnlist、cwalist指令获取对应数据源信息列表

### 可用路径

| 路径            | 说明                |
| ------------- | ----------------- |
| /all          | 接收全部源推送           |
| /weatheralarm | 中国气象局气象预警         |
| /tsunami      | 自然资源部海啸预警中心海啸预警信息 |
| /cenc         | 中国地震台网地震信息        |
| /cenc-ir      | 中国地震台网烈度速报        |
| /cea          | 中国地震预警网地震预警       |
| /cea-pr       | 中国地震预警网各省级网地震预警   |
| /ningxia      | 宁夏自治区地震局地震信息      |
| /guangxi      | 广西壮族自治区地震局地震信息    |
| /shanxi       | 山西省地震局地震信息        |
| /beijing      | 北京市地震局地震信息        |
| /yunnan       | 云南省地震局地震信息        |
| /cwa          | 台湾省气象署地震报告        |
| /cwa-eew      | 台湾省气象署地震预警        |
| /jma          | 日本气象厅地震预警         |
| /hko          | 香港天文台地震信息         |
| /usgs         | 美国地质调查局地震信息       |
| /sa           | 美国ShakeAlert地震预警  |
| /emsc         | 欧洲地中海地震中心地震信息     |
| /bcsf         | 法国中央地震研究所地震信息     |
| /gfz          | 德国地学研究中心地震信息      |
| /usp          | 巴西圣保罗大学地震信息       |
| /kma          | 韩国气象厅地震信息         |
| /kma-eew      | 韩国气象厅地震预警         |
| /kma-station  | 韩国气象厅PEWS测站实时数据   |
| /fssn         | FSSN 地震信息         |
| /fssn-cmt     | FSSN 地震矩心矩张量解     |

***

## 2. 消息协议

### 服务器推送消息

| 消息类型            | 格式示例                                                                              | 说明      |
| --------------- | --------------------------------------------------------------------------------- | ------- |
| 初始数据 (initial)  | `{"type": "initial", "data": {...}}`                                              | 连接后首次推送 |
| 数据更新 (update)   | `{"type": "update", "data": {...}}`                                               | 数据更新推送  |
| 心跳包 (heartbeat) | `{"type": "heartbeat", "ver": "1.1.0", "id": "uuid", "timestamp": 1630000000000}` | 心跳检测    |

### 客户端请求

| 请求类型         | 格式示例                            | 服务器响应                                          |
| ------------ | ------------------------------- | ---------------------------------------------- |
| 查询数据 (query) | `"query"` 或 `{"type": "query"}` | `{"type": "query_response", "data": {...}}`    |
| 心跳检测 (ping)  | `"ping"` 或 `{"type": "ping"}`   | `{"type": "pong", "timestamp": 1630000000000}` |

***

## 3. 注意事项

- 无效路径会立即关闭连接
- 客户端需自行实现断线重连逻辑
- 数据格式与对应业务接口一致
- 长时间无操作建议主动发送心跳

***

## 4. FAN调用API列表1（与Wolfx共同调用）

### 中国地震台网地震信息 (/cenc)

| 字段           | 类型      | 说明                                   |
| ------------ | ------- | ------------------------------------ |
| eventId      | string  | 地震事件国际标准编码                           |
| shockTime    | string  | 地震发生时间（UTC+8，格式：YYYY-MM-DD HH:mm:ss） |
| createTime   | string  | 数据记录生成时间（UTC+8）                      |
| longitude    | number  | 震中经度                                 |
| latitude     | number  | 震中纬度                                 |
| placeName    | string  | 地震震级（注：原文档此处可能有误，实际应为地名）             |
| magnitude    | number  | 地震震级                                 |
| depth        | integer | 震源深度（单位：千米）                          |
| infoTypeName | string  | 测定标识符，例如：\[自动测定]/\[正式测定]             |

### 中国地震台网地震烈度速报 (/cenc-ir)

| 字段                          | 类型     | 说明                             |
| --------------------------- | ------ | ------------------------------ |
| uniEventId                  | string | 地震事件唯一标识符                      |
| oriTime                     | string | 地震发生时间（UTC+8）                  |
| gmtCreate                   | string | 烈度报告生成时间（UTC+8）                |
| locName                     | string | 震中位置名称                         |
| epiLon                      | string | 震中经度                           |
| epiLat                      | string | 震中纬度                           |
| focDepth                    | string | 震源深度（单位：千米）                    |
| subjectCodes                | string | 报告包含的主题编码                      |
| intensity\_info\_text       | string | 烈度分布的文字描述                      |
| contour\_geojson            | object | 烈度等震线地理数据，符合 GeoJSON 标准，用于地图绘制 |
| instrument\_intensity\_json | array  | 各台站实测的仪器烈度详细数据                 |

### 中国地震预警网 (/cea)

| 字段           | 类型      | 说明                  |
| ------------ | ------- | ------------------- |
| id           | string  | 预警事件唯一标识符           |
| eventId      | string  | 事件编码（格式：年月日时分.序号）   |
| shockTime    | string  | 地震发生时间              |
| longitude    | number  | 震中经度                |
| latitude     | number  | 震中纬度                |
| placeName    | string  | 地震发生地地名             |
| magnitude    | number  | 地震震级                |
| epiIntensity | number  | 预估地震烈度（可能为null）     |
| depth        | integer | 震源深度（单位：千米，可能为null） |
| updates      | integer | 该事件的更新报数            |

### 中国地震预警网省级网地震预警 (/cea-pr)

> ⚠️ 注意事项：此接口推送的是由各省级地震预警分中心发布的数据。province 字段指明了发布来源。同一地震事件可能会有多次更新推送，客户端应自行识别并更新数据。

| 字段           | 类型      | 说明                                      |
| ------------ | ------- | --------------------------------------- |
| id           | string  | 预警事件的唯一标识符                              |
| eventId      | string  | 事件编码，格式通常为 年月日时分.序号                     |
| shockTime    | string  | 地震发生时间 (UTC+8, 格式: YYYY-MM-DD HH:mm:ss) |
| longitude    | float   | 震中经度                                    |
| latitude     | float   | 震中纬度                                    |
| placeName    | string  | 地震发生地点的详细名称                             |
| magnitude    | float   | 地震震级                                    |
| epiIntensity | float   | 预估的震中最大烈度                               |
| depth        | integer | 震源深度 (单位: 千米)                           |
| updates      | integer | 该地震事件的更新报数，从 1 开始                       |
| province     | string  | 发布该预警的省级分中心所在省份                         |
| md5          | string  | 数据校验码                                   |

### 宁夏自治区地震局地震信息 (/ningxia)

| 字段        | 类型     | 说明                                   |
| --------- | ------ | ------------------------------------ |
| id        | string | 地震事件唯一标识符                            |
| title     | string | 完整事件描述（含时间、地点、震级）                    |
| latitude  | number | 震中纬度                                 |
| longitude | number | 震中经度                                 |
| depth     | number | 震源深度（单位：千米）                          |
| placeName | string | 地震发生地地名                              |
| shockTime | string | 地震发生时间（UTC+8，格式：YYYY-MM-DD HH:mm:ss） |
| magnitude | number | 地震震级                                 |

### 广西壮族自治区地震局地震信息 (/guangxi)

| 字段        | 类型      | 说明                 |
| --------- | ------- | ------------------ |
| shockTime | string  | 地震发生时间（UTC+8，精确到秒） |
| longitude | number  | 震中经度               |
| latitude  | number  | 震中纬度               |
| placeName | string  | 地震发生地地名            |
| magnitude | number  | 地震震级               |
| depth     | integer | 震源深度（单位：千米）        |

### 山西省地震局地震信息 (/shanxi)

| 字段        | 类型      | 说明                 |
| --------- | ------- | ------------------ |
| shockTime | string  | 地震发生时间（UTC+8，精确到秒） |
| longitude | number  | 震中经度               |
| latitude  | number  | 震中纬度               |
| placeName | string  | 地震发生地地名            |
| magnitude | number  | 地震震级               |
| depth     | integer | 震源深度（单位：千米）        |

### 北京市地震局地震信息 (/beijing)

| 字段        | 类型      | 说明                                   |
| --------- | ------- | ------------------------------------ |
| eventId   | string  | 事件编码（格式：CC+年月日时分秒）                   |
| shockTime | string  | 地震发生时间（UTC+8，格式：YYYY-MM-DD HH:mm:ss） |
| longitude | number  | 震中经度                                 |
| latitude  | number  | 震中纬度                                 |
| placeName | string  | 地震发生地地名                              |
| magnitude | number  | 地震震级                                 |
| depth     | integer | 震源深度（单位：千米）                          |

### 云南省地震局地震信息 (/yunnan)

> ⚠️ 注意事项：该接口提供震级包含 magnitude (M) 和 magnitudel (ML)。若原始数据中某项数值缺失，该字段将返回 null。

| 字段         | 类型     | 说明                  |
| ---------- | ------ | ------------------- |
| id         | string | 地震事件唯一标识符           |
| shockTime  | string | 地震发生时间（北京时间 UTC+8）  |
| latitude   | number | 震中纬度（可能为null）       |
| longitude  | number | 震中经度（可能为null）       |
| depth      | number | 震源深度（单位：千米，可能为null） |
| magnitude  | number | 地震震级 M（可能为null）     |
| magnitudel | number | 地震震级 ML（可能为null）    |
| placeName  | string | 发震参考地点名称（可能为null）   |

### 台湾省气象署地震报告 (/cwa)

> ⚠️ 注意事项：地名 placeName 为中文繁体。

| 字段           | 类型     | 说明                                      |
| ------------ | ------ | --------------------------------------- |
| id           | string | 地震事件唯一ID                                |
| shockTime    | string | 地震发生时间 (UTC+8, 格式: YYYY-MM-DD HH:mm:ss) |
| latitude     | number | 震中纬度                                    |
| longitude    | number | 震中经度                                    |
| depth        | number | 震源深度 (单位: 千米)                           |
| magnitude    | number | 地震震级                                    |
| placeName    | string | 震中参考地名 / 位置描述                           |
| maxIntensity | string | 最大震度                                    |
| imageURI     | string | 等震度图 (Shakemap) 图片链接                    |
| md5          | string | 数据校验码                                   |

### 香港天文台地震信息 (/hko)

> ⚠️ 注意事项：verify=Y 表示香港天文台已完成人工复核，数据可信度高；verify=N 为初步速报，可能后续更新。citystring 与 placeName 均为中文繁体，若需简体请客户端自行转换。

| 字段         | 类型      | 说明                                            |
| ---------- | ------- | --------------------------------------------- |
| id         | string  | 内部事件ID                                        |
| eventId    | string  | 香港天文台地震事件唯一标识（格式：时间戳\_序号）                     |
| shockTime  | string  | 地震发生时间（香港时间 HKT，UTC+8，格式：YYYY-MM-DD HH:mm:ss） |
| longitude  | number  | 震中经度（东经为正，西经为负）                               |
| latitude   | number  | 震中纬度（北纬为正，南纬为负）                               |
| depth      | integer | 震源深度（单位：千米）                                   |
| magnitude  | number  | 地震震级（里氏规模）                                    |
| placeName  | string  | 最近城市或地区名称                                     |
| citystring | string  | 震中相对最近城市的方位、距离及深度描述                           |
| region     | string  | 地震所在宏观区域（如"斐濟群島區"）                            |
| verify     | string  | 数据核验标记：Y = 已核实，N = 待核实                        |

### 美国地质调查局地震信息 (/usgs)

> ⚠️ 注意事项：所有时间均为 UTC+8 (北京时间)

| 字段           | 类型     | 说明                                        |
| ------------ | ------ | ----------------------------------------- |
| id           | string | USGS 地震事件唯一标识                             |
| title        | string | 地震的完整标题描述                                 |
| infoTypeName | string | 测定标识符，例如：automatic/reviewed               |
| magnitude    | number | 地震震级                                      |
| placeName    | string | 震中位置的文字描述                                 |
| shockTime    | string | 地震发生时间（UTC+8，格式：YYYY-MM-DD HH:mm:ss）      |
| updateTime   | string | 此条数据的最后更新时间（UTC+8，格式：YYYY-MM-DD HH:mm:ss） |
| longitude    | number | 震中经度                                      |
| latitude     | number | 震中纬度                                      |
| depth        | number | 震源深度（单位：千米）                               |
| url          | string | 指向 USGS 官方地震事件页面的链接                       |

### 美国ShakeAlert地震预警 (/sa)

> ⚠️ 注意事项：所有时间（shockTime）均为 UTC+8 (北京时间)。

| 字段        | 类型      | 说明                                   |
| --------- | ------- | ------------------------------------ |
| id        | string  | 地震事件唯一标识                             |
| shockTime | string  | 地震发生时间（UTC+8，格式：YYYY-MM-DD HH:mm:ss） |
| latitude  | number  | 震中纬度                                 |
| longitude | number  | 震中经度                                 |
| depth     | integer | 震源深度（单位：千米，可能为null）                  |
| magnitude | number  | 地震震级（可能为null）                        |
| placeName | string  | 震中位置的文字描述                            |

### 欧洲地中海地震中心地震信息 (/emsc)

> ⚠️ 注意事项：所有时间（shockTime）均为 UTC+8 (北京时间)。

| 字段        | 类型      | 说明                                   |
| --------- | ------- | ------------------------------------ |
| id        | string  | 地震事件唯一标识                             |
| shockTime | string  | 地震发生时间（UTC+8，格式：YYYY-MM-DD HH:mm:ss） |
| latitude  | number  | 震中纬度                                 |
| longitude | number  | 震中经度                                 |
| depth     | integer | 震源深度（单位：千米，可能为null）                  |
| magnitude | number  | 地震震级（可能为null）                        |
| placeName | string  | 震中位置的文字描述                            |

### 法国中央地震研究所地震信息 (/bcsf)

> ⚠️ 注意事项：所有时间（shockTime）均为 UTC+8 (北京时间)。

| 字段        | 类型      | 说明                                   |
| --------- | ------- | ------------------------------------ |
| id        | string  | 地震事件唯一标识                             |
| shockTime | string  | 地震发生时间（UTC+8，格式：YYYY-MM-DD HH:mm:ss） |
| latitude  | number  | 震中纬度                                 |
| longitude | number  | 震中经度                                 |
| depth     | integer | 震源深度（单位：千米，可能为null）                  |
| magnitude | number  | 地震震级（可能为null）                        |
| placeName | string  | 震中位置的文字描述                            |

### 德国地学研究中心地震信息 (/gfz)

> ⚠️ 注意事项：所有时间（shockTime）均为 UTC+8 (北京时间)。

| 字段        | 类型      | 说明                                   |
| --------- | ------- | ------------------------------------ |
| id        | string  | 地震事件唯一标识                             |
| shockTime | string  | 地震发生时间（UTC+8，格式：YYYY-MM-DD HH:mm:ss） |
| latitude  | number  | 震中纬度                                 |
| longitude | number  | 震中经度                                 |
| depth     | integer | 震源深度（单位：千米，可能为null）                  |
| magnitude | number  | 地震震级（可能为null）                        |
| placeName | string  | 震中位置的文字描述                            |

### 巴西圣保罗大学地震信息 (/usp)

> ⚠️ 注意事项：所有时间（shockTime）均为 UTC+8 (北京时间)。

| 字段        | 类型      | 说明                                   |
| --------- | ------- | ------------------------------------ |
| id        | string  | 地震事件唯一标识                             |
| shockTime | string  | 地震发生时间（UTC+8，格式：YYYY-MM-DD HH:mm:ss） |
| latitude  | number  | 震中纬度                                 |
| longitude | number  | 震中经度                                 |
| depth     | integer | 震源深度（单位：千米，可能为null）                  |
| magnitude | number  | 地震震级（可能为null）                        |
| placeName | string  | 震中位置的文字描述                            |

### 韩国气象厅地震信息 (/kma)

> ⚠️ 注意事项：该接口仅提供韩国国内的地震数据。placeName 字段的内容为韩文原文，未进行翻译。

| 字段           | 类型      | 说明                                     |
| ------------ | ------- | -------------------------------------- |
| id           | string  | KMA发布的地震事件ID                           |
| shockTime    | string  | 地震发生时间（UTC+9，格式：YYYY-MM-DD HH:mm:ss）   |
| createTime   | string  | 数据记录生成时间（UTC+9，格式：YYYY-MM-DD HH:mm:ss） |
| latitude     | number  | 震中纬度                                   |
| longitude    | number  | 震中经度                                   |
| depth        | integer | 震源深度（单位：千米）                            |
| magnitude    | number  | 地震震级                                   |
| epiIntensity | number  | 地震烈度（可能为null）                          |
| placeName    | string  | 地震发生地地名（韩语原文）                          |

### 韩国气象厅地震预警 (/kma-eew)

> ⚠️ 注意事项：地区编码 affectedAreas 包含韩国 17 个行政区的韩文名称，名称为：서울、부산、대구、인천、광주、대전、울산、세종、경기、강원、충북、충남、전북、전남、경북、경남、제주。

| 字段            | 类型      | 说明                                       |
| ------------- | ------- | ---------------------------------------- |
| id            | string  | 地震事件唯一标识符                                |
| updates       | integer | 该地震事件的更新报数，从 1 开始                        |
| shockTime     | string  | 地震发生时间（KST/UTC+9，格式：YYYY-MM-DD HH:mm:ss） |
| createTime    | string  | 报文生成时间（KST/UTC+9，格式：YYYY-MM-DD HH:mm:ss） |
| latitude      | number  | 震中纬度                                     |
| longitude     | number  | 震中经度                                     |
| magnitude     | number  | 地震震级                                     |
| depth         | integer | 震源深度（单位：千米）                              |
| epiIntensity  | integer | 最大预测烈度（MMI）                              |
| placeName     | string  | 震中位置描述（韩语）                               |
| affectedAreas | array   | 预测受影响/最大震度地区列表（韩语数组）                     |

### FSSN 地震信息 (/fssn)

> ⚠️ 注意事项：该数据源由FSSN测报部报告，仅供学术研究。该数据源包含全球范围内的地震信息。

| 字段           | 类型      | 说明                                     |
| ------------ | ------- | -------------------------------------- |
| id           | string  | 地震事件唯一标识符                              |
| shockTime    | string  | 地震发生时间（UTC+8, 格式: YYYY-MM-DD HH:mm:ss） |
| latitude     | number  | 震中纬度                                   |
| longitude    | number  | 震中经度                                   |
| depth        | integer | 震源深度（单位：千米）                            |
| magnitude    | number  | 地震震级                                   |
| placeName    | string  | 地震发生地地名                                |
| infoTypeName | string  | 速报类型，例如："已确认、正式(已核实)"                  |

### FSSN 地震矩心矩张量解 (CMT) (/fssn-cmt)

> ⚠️ 注意事项：CMT 数据通常在地震发生后，由 FSSN 地震学部完成反演后报告，具有一定的滞后性，仅供学术研究。eventId 可用于将此 CMT 解与常规速报接口 /fssn 的数据进行关联。矩张量分量采用科学计数法字符串表示，方便物理机制分析与震源球绘制。depth 字段包含误差估算值，解析时请注意其字符串格式。

| 字段            | 类型     | 说明                                       |
| ------------- | ------ | ---------------------------------------- |
| id            | string | CMT 记录内部唯一标识符                            |
| eventId       | string | 关联的 FSSN 地震事件 ID（对应 /fssn 中的 id）         |
| shockTime     | string | 地震发生时间（UTC+8, 格式: YYYY-MM-DD HH:mm:ss）   |
| latitude      | number | 震中纬度                                     |
| longitude     | number | 震中经度                                     |
| depth         | string | 震源深度（单位：千米，包含误差范围）                       |
| allMagnitudes | object | 震级集合，包含不同类型的震级计算结果 (M, mb, Mw 等)         |
| placeName     | string | 地震发生地地名                                  |
| centroidDepth | string | 矩心深度（单位：千米）                              |
| nodalPlane1   | string | 断层节面 1 参数（走向 Strike / 倾角 Dip / 滑动角 Rake） |
| nodalPlane2   | string | 断层节面 2 参数（走向 Strike / 倾角 Dip / 滑动角 Rake） |
| mnn, mee, mdd | string | 矩张量对角线分量（单位：N·m），分别对应北-北、东-东、垂直-垂直方向     |
| mne, mnd, med | string | 矩张量非对角线分量（单位：N·m），分别对应北-东、北-垂直、东-垂直方向    |

***

## 5. FAN调用API列表2（与Wolfx互为备份）

### 台湾省气象署地震预警 (/cwa-eew)

> ⚠️ 注意事项：地名 placeName 及 locationDesc 为中文繁体。

| 字段           | 类型      | 说明                                      |
| ------------ | ------- | --------------------------------------- |
| id           | string  | 地震事件唯一ID                                |
| updates      | integer | 该事件的更新报数                                |
| shockTime    | string  | 地震发生时间 (UTC+8, 格式: YYYY-MM-DD HH:mm:ss) |
| latitude     | number  | 震中纬度                                    |
| longitude    | number  | 震中经度                                    |
| depth        | number  | 震源深度 (单位: 千米)                           |
| magnitude    | number  | 地震震级                                    |
| placeName    | string  | 震中参考地名                                  |
| locationDesc | array   | 影响区域或位置描述列表                             |
| md5          | string  | 数据校验码                                   |

### 日本气象厅地震预警 (/jma)

> ⚠️ 注意事项：placeName 和 infoTypeName 字段为日语原文，客户端可能需要自行翻译或处理。重要标志位：final 和 cancel。当收到 final: true 的报文时，可以认为该地震事件的参数已最终确定。当收到 cancel: true 时，应撤销该事件的预警。

| 字段           | 类型      | 说明                                         |
| ------------ | ------- | ------------------------------------------ |
| id           | string  | 事件唯一ID                                     |
| updates      | integer | 该事件的更新报数                                   |
| shockTime    | string  | 地震发生时间 (UTC+9, 格式: YYYY-MM-DD HH:mm:ss)    |
| createTime   | string  | 本条信息的创建时间 (UTC+9, 格式: YYYY-MM-DD HH:mm:ss) |
| latitude     | float   | 震中纬度                                       |
| longitude    | float   | 震中经度                                       |
| depth        | integer | 震源深度 (单位: 千米)                              |
| magnitude    | float   | 地震震级                                       |
| placeName    | string  | 震源地名 (日语原文)                                |
| epiIntensity | string  | 最大震度                                       |
| infoTypeName | string  | 信息类型 (日语原文)                                |
| final        | boolean | 是否为最终报文。true 表示这是此事件的最终确定信息                |
| cancel       | boolean | 是否为取消报文。true 表示此前的预警被取消                    |
| md5          | string  | 数据校验码                                      |

***

## 6. FAN调用API列表3（其他用途）（先获取并注册后期再调用）

### 中国气象局气象预警 (/weatheralarm)

> ⚠️ 注意事项：经纬度为预警区域的中心点，实际影响范围需结合业务逻辑处理。

| 字段          | 类型     | 说明                  |
| ----------- | ------ | ------------------- |
| id          | string | 预警唯一标识符             |
| headline    | string | 预警标题                |
| effective   | string | 生效时间（UTC+8）         |
| description | string | 预警详细描述              |
| longitude   | number | 预警区域中心经度，可能为空       |
| latitude    | number | 预警区域中心纬度，可能为空       |
| type        | string | 预警类型编码，可根据此编码查询预警图标 |

***

## 7. 路径与机构名称对照表

> 请将以上所有的字段都获取并注册，对应的机构名根据路径来获取，如 /jma 路径则转换注册成当前发报机构的名称：日本气象厅地震预警。

| 路径            | 机构名称              |
| ------------- | ----------------- |
| /cenc         | 中国地震台网地震信息        |
| /cenc-ir      | 中国地震台网烈度速报        |
| /cea          | 中国地震预警网地震预警       |
| /cea-pr       | 中国地震预警网省级网地震预警    |
| /ningxia      | 宁夏自治区地震局地震信息      |
| /guangxi      | 广西壮族自治区地震局地震信息    |
| /shanxi       | 山西省地震局地震信息        |
| /beijing      | 北京市地震局地震信息        |
| /yunnan       | 云南省地震局地震信息        |
| /cwa          | 台湾省气象署地震报告        |
| /cwa-eew      | 台湾省气象署地震预警        |
| /jma          | 日本气象厅地震预警         |
| /hko          | 香港天文台地震信息         |
| /usgs         | 美国地质调查局地震信息       |
| /sa           | 美国ShakeAlert地震预警  |
| /emsc         | 欧洲地中海地震中心地震信息     |
| /bcsf         | 法国中央地震研究所地震信息     |
| /gfz          | 德国地学研究中心地震信息      |
| /usp          | 巴西圣保罗大学地震信息       |
| /kma          | 韩国气象厅地震信息         |
| /kma-eew      | 韩国气象厅地震预警         |
| /kma-station  | 韩国气象厅PEWS测站实时数据   |
| /fssn         | FSSN 地震信息         |
| /fssn-cmt     | FSSN 地震矩心矩张量解     |
| /weatheralarm | 中国气象局气象预警         |
| /tsunami      | 自然资源部海啸预警中心海啸预警信息 |
| /all          | 全部源推送             |

