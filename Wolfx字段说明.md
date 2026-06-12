# Wolfx 字段说明文档

## 1. 公共/通用说明

| 项目 | 说明 |
|------|------|
| Wolfx | API地址：wss://ws-api.wolfx.jp/all_eew（接收所有 JSON API 推送） |

---

## 2. JMA 緊急地震速報 (type: jma_eew)

| 字段 | 类型 | 备注 |
|------|------|------|
| type | 字符串型 | jma_eew，通过这个来识别发报机构 |
| Title | 字符串型 | EEW发报报头 |
| CodeType | 字符串型 | EEW发报说明 |
| Issue.Source | 字符串型 | EEW发报机构位置 |
| Issue.Status | 字符串型 | EEW发报状态 |
| EventID | 字符串型 | EEW发报ID |
| Serial | 数值型 | EEW发报数 |
| AnnouncedTime | 字符串型 | EEW发报时间(UTC+9) |
| OriginTime | 字符串型 | 发震时间(UTC+9) |
| Hypocenter | 字符串型 | 震源地 |
| Latitude | 数值型 | 震源地纬度 |
| Longitude | 数值型 | 震源地经度 |
| Magunitude | 数值型 | 震级 |
| Depth | 数值型 | 震源深度 |
| MaxIntensity | 字符串型 | 最大震度(弱/強) |
| Accuracy.Epicenter | 字符串型 | 震中精度说明 |
| Accuracy.Depth | 字符串型 | 深度精度说明 |
| Accuracy.Magnitude | 字符串型 | 震级精度说明 |
| MaxIntChange.String | 字符串型 | 最大震度变更说明 |
| MaxIntChange.Reason | 字符串型 | 最大震度变更原因 |
| WarnArea.Chiiki | 字符串型 | 警报区域 |
| WarnArea.Shindo1 | 字符串型 | 区域最大震度(弱/強) |
| WarnArea.Shindo2 | 字符串型 | 区域最小震度(弱/強) |
| WarnArea.Time | 字符串型 | 区域警报时间 |
| WarnArea.Type | 字符串型 | 区域发报类型，分为 "予報" 和 "警報" |
| WarnArea.Arrive | 布尔型 | 区域地震波是否已到达 |
| isSea | 布尔型 | 是否为海域地震 |
| isTraining | 布尔型 | 是否为训练报 |
| isAssumption | 布尔型 | 是否为推定震源(PLUM法) |
| isWarn | 布尔型 | 是否为警报 |
| isFinal | 布尔型 | 是否为最终报 |
| isCancel | 布尔型 | 是否为取消报 |
| OriginalText | 字符串型 | JMA气象厅原电文 |

---

## 3. 中国地震台网 地震预警 (type: cenc_eew)

| 字段 | 类型 | 备注 |
|------|------|------|
| type | 字符串型 | cenc_eew，通过这个来识别发报机构 |
| ID | 字符串型 | EEW发报ID |
| EventID | 字符串型 | EEW发报事件ID |
| ReportTime | 字符串型 | EEW发报时间(UTC+8) |
| ReportNum | 数值型 | EEW发报数 |
| OriginTime | 字符串型 | 发震时间(UTC+8) |
| HypoCenter | 字符串型 | 震源地 |
| Latitude | 数值型 | 震源地纬度 |
| Longitude | 数值型 | 震源地经度 |
| Magnitude | 数值型 | 震级 |
| Depth | 数值型 | 震源深度（可能为null） |
| MaxIntensity | 数值型 | 最大烈度 |

---

## 4. 福建省地震局 地震预警 (type: fj_eew)

| 字段 | 类型 | 备注 |
|------|------|------|
| type | 字符串型 | fj_eew，通过这个来识别发报机构 |
| ID | 数值型 | EEW发报ID |
| EventID | 字符串型 | EEW发报事件ID |
| ReportTime | 字符串型 | EEW发报时间(UTC+8) |
| ReportNum | 数值型 | EEW发报数 |
| OriginTime | 字符串型 | 发震时间(UTC+8) |
| HypoCenter | 字符串型 | 震源地 |
| Latitude | 数值型 | 震源地纬度 |
| Longitude | 数值型 | 震源地经度 |
| Magunitude | 数值型 | 震级 |
| isFinal | 布尔型 | 是否为最终报 |

---

## 5. 重庆市地震局 地震预警 (type: cq_eew)

| 字段 | 类型 | 备注 |
|------|------|------|
| type | 字符串型 | cq_eew，通过这个来识别发报机构 |
| ID | 字符串型 | EEW发报ID |
| EventID | 字符串型 | EEW发报事件ID |
| ReportTime | 字符串型 | EEW发报时间(UTC+8) |
| ReportNum | 数值型 | EEW发报数 |
| OriginTime | 字符串型 | 发震时间(UTC+8) |
| HypoCenter | 字符串型 | 震源地 |
| Latitude | 数值型 | 震源地纬度 |
| Longitude | 数值型 | 震源地经度 |
| Magnitude | 数值型 | 震级 |
| Depth | 数值型 | 震源深度（可能为null） |
| MaxIntensity | 数值型 | 最大烈度 |

---

## 6. 中国地震台网 地震信息 (type: cenc_eqlist)

| 字段 | 类型 | 备注 |
|------|------|------|
| type | 字符串型 | cenc_eqlist，通过这个来识别发报机构 |
| No(1~50) | 字符串型 | 地震信息条目数，发布时间顺序 |
| type | 字符串型 | 信息类型，分为"automatic"和"reviewed" |
| time | 字符串型 | 发震时间(UTC+8) |
| location | 字符串型 | 震源地（对原数据进行了处理以保证国内地区格式一致性） |
| placeName | 字符串型 | 震源地（未对原数据进行修改以保证数据的原始性） |
| magnitude | 字符串型 | 震级 |
| depth | 字符串型 | 震源深度 |
| latitude | 字符串型 | 震源地纬度 |
| longitude | 字符串型 | 震源地经度 |
| intensity | 字符串型 | 最大烈度 |
| md5 | 字符串型 | 地震信息更新校验码 |

---

## 7. CWA 地震预警 (无 type 字段)

| 字段 | 类型 | 备注 |
|------|------|------|
| ID | 数值型 | EEW发报ID |
| ReportTime | 字符串型 | EEW发报时间(UTC+8) |
| ReportNum | 数值型 | EEW发报数 |
| OriginTime | 字符串型 | 发震时间(UTC+8) |
| HypoCenter | 字符串型 | 震源地 |
| Latitude | 数值型 | 震源地纬度 |
| Longitude | 数值型 | 震源地经度 |
| Magunitude | 数值型 | 震级 |
| Depth | 数值型 | 震源深度 |
| MaxIntensity | 字符串型 | 最大震度(弱/強) |

> ⚠️ 注：CWA预警没有type字段，所以当Wolfx源抓不到type时显示此机构名称

---

## 8. JMA 地震情報 (type: jma_eqlist)

| 字段 | 类型 | 备注 |
|------|------|------|
| type | 字符串型 | jma_eqlist，通过这个来识别发报机构 |
| Title | 字符串型 | 发报报头 |
| No(1~50) | 字符串型 | 地震情报条目数，发布时间顺序 |
| time | 字符串型 | 发震时间(UTC+9) |
| location | 字符串型 | 震源地 |
| magnitude | 字符串型 | 震级 |
| shindo | 字符串型 | 最大震度(-/+) |
| depth | 字符串型 | 震源深度 |
| latitude | 字符串型 | 震源地纬度 |
| longitude | 字符串型 | 震源地经度 |
| info | 字符串型 | 津波情报（仅第一条提供） |
| md5 | 字符串型 | 地震情报更新校验码 |

---

## 9. WebSocket 通用/控制包字段

### 9.1 心跳包 (heartbeat)

| 字段 | 类型 | 备注 |
|------|------|------|
| type | 字符串型 | heartbeat |
| ver | 数值型 | 服务端版本号 |
| id | 字符串型 | 客户端连接UUID |
| timestamp | 字符串型 | 心跳包发送毫秒级时间戳 |

### 9.2 Pong包 (pong)

| 字段 | 类型 | 备注 |
|------|------|------|
| type | 字符串型 | pong |
| timestamp | 字符串型 | Pong包发送毫秒级时间戳 |

---

## 10. type 字段对应的预警机构说明

| type 字段 | 机构名称 | 说明 |
|-----------|----------|------|
| jma_eew | JMA 緊急地震速報 | |
| cenc_eew | 中国地震台网 地震预警 | |
| fj_eew | 福建省地震局 地震预警 | |
| cq_eew | 重庆市地震局 地震预警 | |
| cenc_eqlist | 中国地震台网 地震信息 | |
| (无type字段) | CWA 地震预警 | CWA预警没有type字段，所以当Wolfx源抓不到type时显示此机构名称 |
| jma_eqlist | JMA 地震情報 | |

---

## 11. 重要使用说明

> **字段获取说明：**
> 
> 请严格按照本说明来获取并注册字段。建议先获取 `type` 中的字段来判断发报机构，再获取对应的内容字段。关于 `type` 字段的说明请参见上表"type对应的预警机构说明"。
> 
> **Wolfx字段注册说明：**
>
> 通过对字段的抓取，将字段内容识别或转换之后注册成可以为 APP 利用的内容。**不同 API 的注册不得混在一起**。