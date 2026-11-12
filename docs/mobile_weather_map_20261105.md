# 手机气象地图独立界面（2026-11-05）

## 授权范围

手机天气首页右上角进入的气象地图，使用独立的气象图层开关和信息面板。用户确认独立保存，不影响地震页。继续复用原有地图、气象数据和绘制，不调整 EEW、情报、测站检出、视角算法、桌面地图设置或气象产品解析。

## 具体改动

| 文件 / 位置 | 原行为 → 新行为 |
| --- | --- |
| `lib/widgets/ui/mobile_weather_map.dart`（新增） | 通用图层入口 → 手机气象地图浮动工具栏、七个快捷入口、十二项图层开关、气象站展示要素、所在地实况 / 台风 / 全国预警信息面板。快捷入口单独显示，图层面板可叠加。 |
| `lib/widgets/ui/mobile_weather_home.dart` 的地图分支 | 支持注入专用地图工具界面；不传入时保留原入口。天气首页不变。 |
| `lib/screens/main_screen.dart` 的 `_buildMobileWeather`、地图组件参数和销毁方法 | 接入专用地图工具，复用所在地气象站组件和原定位方法；由独立 ValueNotifier 接收实际图像时次，不因时次刷新整个主界面。 |
| `lib/core/mobile_weather_layers.dart`（新增） | 明确气象图层白名单及独立配置键。首次进入复制现有开关作为初始值，之后单独保存，不写 `map_overlay_*`。 |
| `lib/providers/map_state_provider.dart` 的图层读取和气象站模式 | 仅在手机气象 viewport 读取独立配置；地震 viewport 和桌面读取原配置。非气象键不进入独立配置。相机规则不变。 |
| `lib/widgets/map/quake_map_view.dart` 的气象数据通知 / 托管气象同步 | 输出六类图像产品原始时次；独立配置使用专用气象同步，不执行完整信源重载；切回另一 viewport 后恢复其原有显示和缓存。原图像数据和渲染算法不变。 |
| `lib/services/background_service.dart`、`background_source_manager.dart` | Android 托管连接增加专用气象同步通道和已有帧的快照发送；只同步气象服务，不重启 EEW、地震情报、地震测站连接。 |
| `lib/services/background_source_reload_plan.dart` | 两个新增独立配置键由专用通道处理，避免被未知配置变化触发完整信源重载。原配置键策略不变。 |
| `lib/services/sources/typhoon_service.dart` | 增加只读 `latestSnapshot`，重新显示时复用原台风快照。获取、解析、计时逻辑不变。 |
| `native/station_core/src/weather_map_policy.rs`、`src/lib.rs`、头文件 | 新增标量源请求策略：原配置与手机配置的七位请求掩码取并集，限制到合法位；防止一页关闭另一页需要的气象源。无分配或所有权转移。 |
| `lib/services/native_weather_map_policy*.dart`、`weather_map_source_requests.dart`（新增） | Windows 实际调用 Rust ABI；项目当前未支持 station-core 的平台使用明确的便携实现。读取原配置和手机配置构造请求，不改变产品报文。 |

## 保存格式

- `mobile_weather_map_layers_v1`：JSON 对象，十二项白名单布尔开关。
- `mobile_weather_map_station_mode`：`auto` / `temperature` / `rain` / `wind`。
- 原 `map_overlay_*` 和 `weather_station_mode` 保持独立。
- Rust ABI 七位顺序：全国雷达、全国小时降水、JMA 雷达、葵花卫星、NSMC 红外、西太平洋卫星、台风。
- 图像实际时次来自已有 frame 的 `time`；未收到数据明确显示等待状态，不生成假时次。

## 验证

- Rust 源请求策略测试通过：遍历全部 128 × 128 组掩码并检查非法位。
- 31 项 Flutter 相关测试通过，包含独立配置、原配置不变、非气象键隔离、专用配置不触发完整后台重载、单图层 / 叠加、地图空白区触摸、图层 / 信息面板、定位 / 返回、四种尺寸及放大字体布局，以及原天气首页 / 预警 / viewport 回归。
- 定向静态检查无 error 或 warning；存在控制流大括号等 lint info（含原文件既有项）。
- Windows Release 编译成功（131.9 秒）；打包目录的 Rust DLL 与本次原生编译结果 SHA256 相同。
- 实际启动新编译程序并缩成手机尺寸：天气首页进入地图正常；全国雷达显示实际时次；单独切到全国小时降水，原雷达和台风路径隐藏、降水图正常显示；图层面板开启雷达后与降水叠加；气象信息面板显示所在地义乌 58557 站 16:10 实况。运行日志未发现 overflow、Unhandled、Error 或 Flutter exception。
- 实际保存记录核对：手机独立配置为雷达 / 小时降水，而原 `map_overlay_radarChinaLayer`、`map_overlay_typhoonLayer` 仍为 true；没有因手机操作关闭地震页原图层。
- 本轮完成源码、测试、Windows 编译和运行检查。未制作新的 Windows 安装包、未更新云电脑；Android 真机当前不可用，未声称已经手机实机安装或验证。
