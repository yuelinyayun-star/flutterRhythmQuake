# 非瓦片底图接入记录

## 范围与入口

2026-09-09：在原有设置的地图底图下拉框增加“矢量地图”，键为 `kaVector`。
默认仍为 Petal 浅色，使用原有设置持久化和地图状态通知。地震火山、气象页面均复用现有地图；未改变各业务图层顺序、事件聚焦或视野计算。

底图离线读取内置 TopoJSON，不请求网络图片瓦片。气象、雷达等叠加图层仍按其原有方式联网。
本次不恢复此前删除的海域断层资源，也没有增加新的运行时依赖。

## KA 核对

参考本地 `D:/Users/Rhythm/Downloads/kanameishi-dev` 的 `MainMapComponent.vue`、`Urls.js`、`Utils.js`、设置和 README，并核对官方仓库 README：
https://github.com/Lipomoea/kanameishi

本地目录无 Git 元数据，因此以原始文件 SHA-256 标识数据快照，不声称对应最新提交。

KA 默认路径是 `L.vectorGrid.slicer` 加 `L.canvas.tile`，把本地矢量数据按视口瓦片化，并非联网下载图片瓦片。经典路径使用 `L.geoJson`，也提供 Canvas 渲染选项。
KA 还使用 TopoJSON 缓存、分级注记和图层分离；其设置说明指出两条路径在接缝、拖动加载和世界重复方面有差异。

Flutter 实现没有移植 Leaflet，而是复用现有 flutter_map 的 PolygonLayer / PolylineLayer 投影缓存、按缩放等级简化和可视范围裁剪。

## 数据与地理表示检查

三份 JSON 原样复制，合计 1,302,870 字节，约 1.24 MiB；来源、哈希及许可证见 `assets/maps/ka/NOTICE.md`。

| 数据 | 原始要素 | 展开多边形 | 环 | 拼接后坐标点 |
| --- | ---: | ---: | ---: | ---: |
| 世界 | 237 | 1,561 | 1,573 | 95,629 |
| 日本 | 56 | 400 | 400 | 27,807 |
| 中国 | 35 | 421 | 429 | 26,205 |

绘制顺序保持世界、日本、中国。技术检查包括：

- 世界文件不再叠加中国、台湾和日本的对应要素。
- 中国文件保留台湾省、香港和澳门特别行政区、西藏和新疆等原始要素。
- 保留无名称要素中的 10 个图形，不因名称缺失丢弃南海及台湾东侧的原始线状多边形。
- 钓鱼岛测试点位于中国文件台湾省要素内，不位于日本文件的多边形内。
- 三份文件的全部多边形和孔洞，逐坐标规范化哈希与独立 topojson-client 3.1.0 展开结果一致。
- 对东亚、日本、钓鱼岛、南海、180 度附近太平洋视野进行了两种屏幕尺寸的绘制检查。

KA README 明确提示钓鱼岛和世界争议地区需要处理。以上检查只说明没有在接入和优化中破坏所核对的数据，不是全世界边界逐项审核，也不是获得审图号。
公开发布前仍应针对实际展示范围、边界和注记完成内容审核，并核对上游数据授权；不得将 KA 数据或保留许可证当作审核完成的依据。
参考官方《公开地图内容表示规范》：
https://www.fmprc.gov.cn/web/wjb_673085/zzjg_673183/bjhysws_674671/bhflfg/dtdmxgfl/202303/P020230313585504979937.pdf

## 性能处理

- 首次选择才读取，三份数据共享一次加载 Future；原生平台使用 compute 后台解析，失败可重试，不缓存空成功结果。Web 的 compute 不等同原生后台 isolate。
- 缓存不可变几何，业务 UI 重建不重新生成多边形组件，保留 flutter_map 原生投影和缩放缓存。
- 填充与边线分离，共用弧段在每份数据中只绘制一次，避免相邻区域边线重复生成。
- 启用视口裁剪，渲染简化容差为 0.5 像素；不改写磁盘资源和解析后原始坐标。
- 注记按缩放等级和可视区域筛选，不加载旧 BoundaryService 的整份几何。
- 底图 IgnorePointer，保留地图手势；RepaintBoundary 隔离绘制。
- 底图键只放在 TileLayer，移除以底图键重建整个 FlutterMap 的行为，切换时保留地图实例、视野和业务图层状态。

旧 VectorBoundaryLayer 未作为新底图入口复用：其旧解析和每次构建全量几何的路径不适合这次接入。旧代码不在本次范围内重构。

## 验证与限制

31 条相关测试通过，覆盖全量数据一致性、加载缓存和重试、两种尺寸绘制、平移、切换保持视野、原瓦片配置、视野隔离、瓦片取消以及中日断层回归。

本机 Flutter widget 测试一次记录：430x850 首次加载 209 ms，连续 30 次暖缓存视角移动的 pump 中位数 8.9 ms、P95 12.5 ms；1280x720 分别为 94 ms、14.7 ms、19.1 ms。
这些数值包含测试调度，不是手机或 Windows Release 帧率，不能作为真机性能保证。测试截图使用测试字体，中文注记字形需在安装后的平台字体环境验收。
尚未测量真机持续内存、首次投影掉帧或 Release GPU 耗时；本次没有重新编译安装包。

```powershell
flutter test --no-pub test/vector_basemap_service_test.dart test/vector_basemap_layer_test.dart test/map_config_fan_zxy_test.dart test/map_config_removed_tencent_test.dart test/china_fault_layer_test.dart test/japan_fault_service_test.dart test/map_viewport_isolation_test.dart test/map_tile_cancellation_test.dart
node tools/audit_ka_vector_basemap.cjs tmp/vector_map_reference/node_modules/topojson-client
```
