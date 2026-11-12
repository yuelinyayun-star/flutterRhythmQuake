# 手机气象首页改造

## 授权和具体改动

仅改手机气象页面的布局、背景和地图入口。用户要求：地图不再作为天气首页，改为右上角入口；首页采用手机天气 APP 的布局，按天气生成并接入背景图。

| 文件、位置 | 原行为 | 新行为 |
| --- | --- | --- |
| `lib/screens/main_screen.dart`：`_buildPhoneWeather` | 地图上覆盖可拖动天气面板 | 手机气象路径改为 `MobileWeatherHome`；继续使用现有中国天气网、CMA、JMA 状态和气象站组件 |
| 同文件：`_mobileWeatherMapOpen`、`_buildSectionBody` | 进入气象页就显示地图 | 首页默认不显示地图；右上角进入原气象地图，按钮及系统返回键可回首页 |
| `lib/widgets/ui/mobile_weather_home.dart` | 无独立天气首页 | 新增城市、大温度、天气、最高／最低、空气质量摘要、更新时间；保留天气预警及生活建议，重排逐小时、每日预报和实况、气象站；右上角地图、定位和图层设置入口常驻 |
| `lib/widgets/ui/mobile_sections.dart`：手机气象地图可见标记 | 地图始终绘制在天气内容下面 | 新首页中地图 Offstage 并关闭其 UI TickerMode，地图实例及订阅保留；进入地图恢复显示。原有未传该标记的调用保持原行为 |
| `lib/widgets/ui/mobile_weather_home_details.dart`：默认文字样式 | 本地 DefaultTextStyle 未继承应用字体 | 继承主题字体和 CJK 回退，保持应用字形；数据字段和计算不变 |
| `pubspec.yaml`：assets | 无天气背景资源目录 | 仅增加 `assets/images/weather/` 资源注册，没有新增依赖 |

新首页不使用旧的可拖动天气面板；原组件保留供既有引用及测试使用。天气卡片使用圆角、半透明背景和分组毛玻璃，静态背景单独放入 RepaintBoundary，并限制解码宽度；没有新增动画或轮询定时器。

主温度优先展示中国天气网当前城市实况，缺失时才显示已存在的气象站温度并标注“气象站实况”；页面按天气 APP 显示整数度数，原始值没有修改。原始天气服务、预警判断、刷新周期、数据适配、震源及地图视角算法不变。日本页面继续使用已有 JMA 观测及预报入口，不补造国内预报字段。

## 背景资产

通过内置 `image_gen.imagegen` 分别生成，未使用 CLI 回退。全部复制到仓库并由 APP 本地资源加载，无运行时图片网络请求。

- `assets/images/weather/clear_day.png`：晴天。
- `assets/images/weather/clear_night.png`：晴朗夜间。
- `assets/images/weather/cloudy_day.png`：白天多云／阴天。
- `assets/images/weather/cloudy_night.png`：夜间多云／阴天。
- `assets/images/weather/rain.png`：雨。
- `assets/images/weather/storm.png`：雷雨。
- `assets/images/weather/snow.png`：雪。
- `assets/images/weather/fog.png`：雾、霾及沙尘类低能见度。

按当前上游天气代码选择背景，只影响视觉。没有天气或未知代码使用中性背景，不用晴天代替缺测。背景图片不含文字、温度或 UI；所有文字、按钮和天气值由 Flutter 绘制。

完整生成提示词和对应资源见 `docs/weather_background_prompts_20261105.json`。

## 验证和交付边界

- 五个相关测试文件共 **34 项通过**，覆盖原气象组件、逐小时面板和手机切页。
- 固定地图入口及滚动区域最后调整后，新增首页 **6 项测试再次通过**：320×640、390×844、430×932／1.5 倍文字、844×390；地图同实例复用、隐藏时不绘制／不运行 UI ticker、进入／按钮返回／系统返回、设置及定位按钮、滚动位置保留、缺测背景和原始数据不变。
- 新首页使用义乌原始 `yiwu_current.js`、`yiwu_outlook.js` 数据渲染，未修改这两个文件，也未把不同城市数据混用。预览属于固定数据的 Flutter 组件渲染，**不是当前实时天气或手机实机截图**。
- 相关源码与测试静态检查通过。
- 构建工具自动解析资源时带动了七项依赖版本变化，已按解析前版本撤回，并以离线锁定方式恢复；后续验证均使用 `--no-pub`，本任务不升级依赖。
- **尚未编译 APK／安装包，未安装到手机，未更新云电脑。** 没有修改桌面布局或地震页面业务。

测试记录：`tmp/mobile_weather_home_20261105/final-tests.log`、`home-final-tests.log`、`final-analyze.log`。

预览：`docs/previews/mobile-weather-home-20261105.png`。
