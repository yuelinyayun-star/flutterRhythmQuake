# Rust 定位修复与验证状态（2026-10-30）

## 根本错误及指令范围

根本错误是未确认授权范围、擅自改变用户已确认的固定行为；不仅是视角规则或性能优化的问题。另一个错误是把静态分析、组件测试或当前代码现象当成完整运行验证。

全局主提示词已改为“修改范围与既有行为约束（全局）”，补充全局、项目、本轮要求与历史记忆的适用范围。Rust 迁移要求只写入本仓库 `AGENTS.md`，不推广到其他项目。用户明确要求导入回放故障“只记录，不改回放”，本轮未修改回放生产逻辑。

## 本轮实现

- 恢复 CENC 桌面、手机、EEW 临时情报、历史、共享视角五个入口的固定中心约束。
- `native/station_core/src/camera_focus.rs` 承担定位策略和固定锚点的范围缩放计算；Windows 生产经 FFI 调用 Rust，支持平台发生 Rust 错误时不静默退回 Dart。
- Flutter 保留投影适配、交互和动画执行。非 Windows 平台有明确的兼容实现，本次不宣称已迁移这些平台。
- 普通 P2P JMA 的已知震中固定居中；`ScalePrompt` 和 `Destination` 保持原始两阶段范围规则。未把这两个特殊类型统一改成普通情报规则。
- 添加显式诊断计数：`GET /diagnostics/performance` 的 `native.cameraFocus`，只在诊断请求时读取，没有新采样定时器。

## 已完成验证

- Rust 单元 3 项通过。
- 加载真实 Release DLL 的相关回归 78 项通过，包括截图事件原始报文、CENC 三份原始观测、完整填色轮廓及站点可见性、共享视角、特殊电文、其他信源视角。
- 原始截图记录 `6ae45a03e88ee598246bf44c` 的实际地图组件中心误差小于 1 像素，未修改原始字段。
- 原生成功/错误路径连续 1000 次调用后，未释放输出数为 0。
- 本地 Release 实例 PID 37084 启动成功；141 个发布文件校验通过。
- 本地接口已实际发送截图对应原始 P2P 报文，返回 `{"ok":true,"injected":1,"apiName":"Mock"}`。实际进程随后报告 Rust camera calls=12，outstandingOutputs=0。旧报文进入显示后很快过期；当时未捕捉到稳定的最终定位截图，不能宣称完整实机定位验证已结束。

证据：`tmp/jma_info_center_20261030/release-camera-regression.log`、`runtime-injected-original.json`、`runtime-after-injection.json`。

## 本地后台发报与渲染验证（18:54–18:57 补充）

前面反复占用桌面却没有取得稳定截图，属于验证流程错误。接口的 `injected:1` 只证明解析、发布成功，不能代表 Provider 接纳后的显示寿命或最终相机正确。不能将这些阶段混为一谈。

已通过无窗口 Flutter 引擎重现：原始旧 P2P 电文在默认配置下返回 `injected:1`，先进入真实 Rust Provider 的活动列表，随后在两秒内从活动列表移除。Rust 的 `schedule` 将剩余寿命下限限制为一秒；旧电文未启用现有“显示旧事件”设置时，剩余寿命不足。此前没有检查这条完整链路，截图等待又超过了该窗口，重复发同一旧报文并不能解决。此结论来自真实 HTTP→Mock 服务→生产 Provider→Release Rust DLL 的跟踪，不是从接口成功码推测。

随后只在测试内启用原有 `setShowStaleInfoEvent(true)`，没有修改电文原始时间、字段、生产寿命规则，也没有修改回放：

- 相同原始字节通过本地真实 HTTP 接口返回 `injected:1`。
- 生产 `QuakeProvider(nativeUnifiedEvents: true)` 接收，原始 `sourcePayload` 完全相等。
- 实际 `QuakeMapView` 进行自动定位；经过 20 秒测试时钟后，事件仍在显示，相机仍保持震中居中。
- 震中像素 `(854.3136764705778, 434.11058823529675)`；可用视口中心 `(854.3136764705882, 434.11058823529413)`；误差约 `1.08e-11` 像素。
- 实际 Release Rust 相机调用增加 4 次，未释放输出为 0。
- 已保存实际地图 RenderRepaintBoundary 的 PNG，并检查震中及原始震度填色位置。Flutter 测试的外部瓦片请求被隔离，因此该图不包含在线底图；不能将此图称为安装版完整桌面截图。

新增测试：`test/jma_local_http_camera_validation_test.dart`。复现旧事件移除时传 `--dart-define=VERIFY_DEFAULT_EXPIRY=true`，常规模式验证稳定显示及截图；两种模式均使用真实 Release DLL，通过 `RQ_STATION_CORE_LIBRARY` 指定。

证据目录：`tmp/jma_info_center_20261030/headless-http/`，含 `default-expiry-evidence.json`、`evidence.json`、`jma-centered.png`。日志：`headless-expiry.log`、`headless-http-final.log`。后台链路与地图渲染验证已经完成；这不等于安装、安装版整窗验证或云端部署完成。

补充回归结果：`final-headless-regression.log` 中其余 77 项完成通过；新增用例当时有测试代码中局部变量声明顺序的编译错误，已修正并单独重跑通过，结果见 `headless-http-final.log`，静态分析无问题。不能把含该编译错误的整份日志写为一次全绿。验证覆盖 EEW 临时情报聚焦与返回、CENC 各入口/完整填色/测站可见性、桌面与手机、JMA 特殊类型、共享视角、USGS DYFI/ShakeMap 及火山视角。此阶段只增补测试和验证记录，没有继续修改生产行为。

## 实机发现但未修复的问题

其他填色/范围缩放情报的追加后台验证，见 `docs/filled_information_camera_validation_20261030.md`，分别覆盖 JMA 特殊阶段、USGS ShakeMap/DYFI、火山原始降灰窗口、CWA 观测填色及 CENC 共享范围，不把各自规则混为一项。

导入回放文件后，播放报 `Bad state: Missing saved replay selection`。导入文件已经带有可读报告引用，却进入了要求已保存历史锚点的加载分支。用户明确选择只记录，不修改，本轮未更改相关生产代码。

## 桌面与云端操作状态

- 用户要求释放本地屏幕后，Computer Use 收到物理 Esc 停止信号，后续未再调用桌面输入。
- 已关闭本轮自行启动的本地验证实例，恢复临时注入开关为关闭、时间轴联动为原先开启状态。
- 先前未获授权时未上传、替换或重启云端程序；当时新建的本地 reader 隧道已停止。
- 用户随后明确授权改用云电脑，重新建立 reader 隧道，但日志为 `open failed: connect failed: Connection refused`，MCP 为 `MCP_TRANSPORT_REJECTED`。当前没有完成云端上传、程序替换或发报。
- 云端验证需云电脑 MCP 重新连接后继续，不能把网络连接拒绝写成验证通过。
- 用户最终要求停止占用桌面后，本次仅运行无窗口测试；关闭本轮验证 Release 进程 PID 16540，核对本地注入设置仍为 false、时间轴联动仍为 true。没有操作用户的其他窗口。

## 构建产物

`build/installer/RhythmQuake_Setup_1.0.5.22_personal_x64.exe`，39.61 MiB。

SHA256：`9a53eca130daf24ecafa866245ec49b70b55a03d8056b4c58c89996677bebdfc`。

源码、Release 构建及上述后台链路与地图渲染验证已完成；没有安装该安装包，安装版整窗及云端未验证，云端未更新。此文件取代早期审计中的临时验证状态，仍未完成的事项明确保留。
