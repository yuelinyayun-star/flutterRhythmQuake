# SASMEX 的 OBS 与历史接入核验

本轮仅检查和隔离测试，未修改 APP 业务、UI 或服务器代码。

## 结论

| 路径 | 当前状态 |
| --- | --- |
| SASMEX 接收到统一事件处理 | 已接入 |
| OBS 统一事件输入 added / updated / removed | 通用路径已接入，added 已用原报文验证 |
| OBS 发布机构条件 | 缺少 `sasmex`，当前返回 null |
| OBS 发布机构选择项 | 缺少 SASMEX |
| 内置“EEW 分机构自动录制” | 缺少 SASMEX 分支；启用现有内置方案仍不会因 SASMEX 启动录制 |
| EEW 历史入组、原文保存 | 已接入，原报文实测通过 |
| Windows 独立文件保存、摘要恢复、按需加载 | 已接入，隔离临时目录实测通过 |
| 导出回放包、重新导入、回放交付 | 已接入，原始内容与事件时间保持不变 |
| 历史卡显示 | 尚未按 SASMEX 类型和严重性适配 |

OBS 的缺口位于机构判定和内置模板。使用不限定机构的统一 EEW 输入或按来源条件配置的
自定义程序，与该内置模板不是同一种情况，不能据此认定所有自定义程序都无法触发。

历史卡仍使用普通地震的震级、深度和烈度显示。原报文实测显示：

- 烈度徽章：`-`，名称仍为“烈度”。
- 要素行：`規模 調査中  深度 --`。
- 没有显示统一 UI 中的 `类型：Alert · 严重性：Minor` 和“轻微”徽章。
- 时间显示 `2026-10-17 09:36 (UTC+0)`，采用来源时区；统一 UI 为电脑时区的 `17:36:43 (UTC+8)`。

## 实测

输入为 2026-10-17 原始 SASNO 文档对应的已转换 JSON，事件 ID `1792229803000`，
原始 `unix: 1792229803`、地点 `Zihuatanejo, Gro.`、强度 `Leve` 均未改。
事件入场测试使用该事件时刻的测试时钟，不修改源时间，也不向线上推送。

隔离测试 3 项通过：

1. 原报文经现有 SasmexService 与 QuakeProvider 进入历史组和 OBS 输入；
   现有 OBS 机构读取为 null，内置模板没有开始录制动作。
2. 在独立临时目录经真实 WindowsPreferencesWorker 写文件，恢复摘要、加载原文、
   导出和重新导入回放包，随后由现有 HistoryReplayController 交付回放事件。
   原始 body 和 originTime 不变，回放事件 ID 带独立 session 前缀。
3. 使用原 HistoryPanel 组件验证仍出现通用震级和深度占位，确认显示缺口。

未连接或操作用户的 OBS，没有触发真实录制；未向用户历史库写入测试事件。

测试脚本及记录：

- `tmp/sasmex_obs_history_audit_20261017/audit_test.dart`
- `tmp/sasmex_obs_history_audit_20261017/test.log`
- `tmp/sasmex_obs_history_audit_20261017/history-ui-text.json`
- `tmp/sasmex_obs_history_audit_20261017/replay-package.json`
