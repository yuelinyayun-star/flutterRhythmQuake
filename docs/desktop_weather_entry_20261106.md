# 顶栏天气入口与桌面天气页面（2026-11-06）

## 本轮授权范围

在桌面顶栏左侧终端位置的右边增加当前天气图标、天气文字和温度；点击打开桌面适配的既有天气首页及气象地图。沿用既有天气源、背景资源、预报、气象信息、图层与播放功能。

不修改地震信息、EEW、海啸、测站检测/样式、成图窗口或云电脑程序；不新增气象源、不变更源报文。手机端天气首页布局保持原样。此前已经完成的 MMI 成图修复仍在当前工作树，不属于本轮新增修改。

## 具体文件、位置与前后行为

| 文件 | 具体位置及变化 |
| --- | --- |
| `lib/widgets/ui/top_status_bar.dart` | 构造函数增加可选 `weatherEntry`；位置文字右侧留 18 个基准像素后插入入口，入口最大宽度 210 基准像素；原位置、时间/NTP、模拟注入功能保持 |
| `lib/widgets/ui/weather_status_entry.dart`（新增） | `WeatherStatusEntry` 只读展示当前天气源的天气文字、温度和天气代码图标；复用现有温度合法性与代码图标，识别当前天气代码的日/夜前缀；无数据不编造天气/温度，仍能点击进入天气页；字体现有应用主题 |
| `lib/widgets/ui/desktop_weather_home.dart`（新增） | `DesktopWeatherHome` 宽屏左列展示当地当前天气、实况、附近站，右列展示逐小时预报、每日预报、气象要素、空气质量、日出日落和生活指数；内容宽度小于 900 时改为单列。使用既有天气背景、`WeatherGlassCard`、逐小时预报和详情组件，右上角有定位、设置、气象地图；左上角返回地震 |
| 同上 | `DesktopWeatherWorkspace` 用 `Offstage` / `TickerMode` 保持唯一地图实例。天气首页隐藏地图并暂停绘制时钟，气象地图时恢复；没有额外创建地震/气象地图订阅实例 |
| `lib/screens/main_screen.dart` | `_buildDesktopWeatherEntry()` 接现有 `_hourlyWeatherService.state`，缺少城市温度时沿用已有所在地气象站温度；`_setDesktopWeather()` 打开/关闭桌面页面；`_buildSectionBody()` 挂载桌面工作区；`_buildPhoneWeather(desktop: true)` 复用已有数据和地图控制器；`QuakeMapView.weatherOnly` 在桌面天气模式生效，地震模块在气象地图中隐藏 |
| 同上 | `_syncMobileMapViewport()` 在桌面天气工作区也启用已有天气/地震相机隔离，返回时关闭隔离并恢复地震相机；不改变地图后端的拟合、居中和跟随规则，不把桌面设置成手机 EEW 轮播 |
| 同上 | `_weatherVisible` 桌面条件从“右侧信息栏显示”变为“桌面顶栏可显示天气”，确保右栏关闭后新增入口仍有天气更新；使用原服务实例和原刷新周期。手机号端条件不变 |
| `lib/widgets/ui/mobile_weather_map.dart` | 新增默认关闭的 `desktop` 和可选 `onClose`：桌面地图提供回天气首页/返回地震两条路径，播放栏居中且最多 860 宽；图层/气象信息弹层分别最多 680/720 宽；手机默认布局和按钮不变 |

## 状态与数据隔离

- 同一个 `MapController` / `QuakeMapView`，进入天气首页、地图及返回不销毁或新建地图。
- 桌面工作区沿用既有 `configureMobileViewport` 相机槽位实现；此函数本轮未改。地震和天气中心/缩放分开保留；天气模式拒绝地震自动视角写入，返回保留原手动锁定状态。
- 气象地图复用既有独立图层配置及其源需求并集，不改地震页图层开关，不重启整套连接。桌面和手机使用的是同一套气象页配置键；没有另建第二套桌面气象策略。
- 原雷达/降水/云图目录预加载、帧播放和 NSMC 可见区及外圈预载逻辑未修改。
- 首页设置入口沿用既有 `SettingsPage(weatherOnly: true)` 天气设置，桌面改为应用内宽屏对话框；地图内图层按钮继续使用独立气象图层选择器。
- 原始城市天气/温度、预报与观测数据没有修改；新增内容均为 Flutter 渲染、交互和生命周期接线，没有新增后端计算或复制新的解析策略。

## 实际验证

- 31 项组件与原生调用回归通过：新增 7 项，既有手机天气首页、独立气象地图、地图视角隔离和全部天气产品播放测试继续通过。
- 顶栏用原始义乌报文验证 800×650 和 1600×900 两种窗口，入口紧跟位置、不撑破时间栏，图标与原天气代码一致；按钮回调有效，原始数据不变。
- 桌面首页使用 `test/fixtures/china_weather_hourly/yiwu_current.js` / `yiwu_outlook.js` 原报文渲染，验证 1600×900 双列及 900×700、1.25 倍文字单列，无溢出；按实际原日期检查预报，不改原时间伪装成当前资料。
- 实际 `MainScreen` 入口测试：点击顶栏 → 桌面首页 → 气象地图 → 天气首页 → 地震。地图元素/控制器始终同一个；首页地图时钟停用；地图为 `weatherOnly`；返回严格恢复先前 36°N/140°E、缩放 7、手动锁定与地震图层开关。没有用替代页面绕过真实入口。
- 单地图工作区另重复往返 3 次，验证天气相机和图层独立、地震视角写入无法覆盖天气视角。
- 桌面地图双返回按钮有效，实际图层弹层内容宽度不超过 680；退出清除当前播放源，保留外部控制器所有权。
- 成图检查：`tmp/desktop_weather_20261106/desktop-weather-home.png`，1600×900；`top-weather-entry.png`，1600×50。前者显示的是原始历史天气样本，不声称是当前实况。
- 定向静态分析无 error / warning，保留项目控制流大括号样式 info；差异空白检查通过。
- Windows Release 构建记录见 `tmp/desktop_weather_20261106/windows-build-final.log`；本轮未制作安装包、未安装、未更新云电脑。组件引擎阻断外网的 HTTP 400 与数据库未初始化提示，不当作安装版联网运行验收。

日志：`tmp/desktop_weather_20261106/tests-final.log`、`analyze-final.log`、`windows-build-final.log`。

## 用户追加的安装包编译

- 2026-11-06 按用户后续要求执行 `package_windows.ps1 -Edition personal -SkipProcessCleanup`，Release 与 Inno Setup 均通过。
- 安装包：`build/installer/RhythmQuake_Setup_1.0.5.22_personal_x64.exe`，51,057,048 字节（48.69 MiB），包括本轮桌面天气入口和前轮 ShakeMap MMI 成图接入。
- SHA256：`e4adb06852aeae60ff75363445bf3cfe51e5dcc8d9036d6a93aa167ce2d69468`，重新计算并与 `.sha256` 文件核对一致。
- 清单 149 个文件，包括 8 张原天气背景及 Rust 原生库。本次只编译打包，没有执行安装、启动安装版或更新云电脑。
- 打包日志：`tmp/desktop_weather_20261106/package.log`。
