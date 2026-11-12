# 2026-10-11 地图投影内存实验（未保留）

本轮延续完整 APP 中地图 Offset 持有链的调查，使用当前 Flutter 3.41.1、锁定的 flutter_map 8.3.0，以及三份原始 KA TopoJSON。**候选修改已撤回，工作区底图源码逐字节恢复到本轮开始时的备份；前几轮已验证的优化保持原样。**

备份和证据根目录：`D:/flutterApp/flutter-map-projection/20261011-143132`。原 `lib/widgets/map/vector_basemap_layer.dart` SHA-256：`0eb761f8c707f9139333baa705aebe0ba4e0f025421cc4341ba419836a18c339`。

## 验证过的候选方案

flutter_map 为完整坐标保留投影 Offset 列表，再为当前缩放保存简化后的列表。实验仅在非交互底图子树中适配 Projection.projectList，将完整投影列表存为 Float64 双精度数组；绘制仍交给原 PolygonLayer / PolylineLayer，保留原简化容差、投影公式、绘制顺序、洞、日期变更线规则和全部地图源坐标。动态覆盖图层使用原相机。

第一版读取数组时创建 Offset，第二版保留原投影对象供简化阶段读取，帧结束后清掉临时引用；不简化的四点及以下图形直接使用原列表。两版均通过原始坐标、跨世界和洞参考点对照，以及手机/桌面共 22 个视角的逐像素比较。第二版四个测试文件共 13 项通过，静态分析无问题。

## 固定场景实测

同一 Windows Profile 二进制包含本轮开始前的冻结组件和候选组件，通过环境变量选择。每个模式独立进程运行 40 秒，先以相同顺序经历全球、日期变更线、东亚、欧洲等视角，再停在指定场景；正常采样完成后才请求 VM GC。全球按原版→候选顺序，东亚按候选→原版顺序，避免全部候选均排在后面。所有原始地图文件测量后重新核验 SHA-256，无修改。

第二版结果：

| 场景 / 指标 | 原版 | 候选 |
| --- | ---: | ---: |
| 全球 3 级：平均 RSS MiB | 202.19 | 213.94 |
| 全球 3 级：GC 后 Dart 堆 MiB | 24.76 | 20.12 |
| 全球 3 级：Offset 个数 | 266,112 | 42,244 |
| 全球 3 级：构建最大耗时 ms | 99.26 | 116.93 |
| 全球 3 级：构建 P95 ms | 83.20 | 115.81 |
| 东亚 7 级：平均 RSS MiB | 214.32 | 218.89 |
| 东亚 7 级：GC 后 Dart 堆 MiB | 14.58 | 14.51 |
| 东亚 7 级：构建最大耗时 ms | 98.01 | 117.03 |
| 东亚 7 级：构建 P95 ms | 79.81 | 113.31 |

外部内存各次约 0.00064 MiB。构建统计每次只有 15–18 帧，包含初次渲染及离散视角切换，不能当作常态 FPS 或大样本性能统计。

第一版全球 Dart 堆由 24.76 降至 20.10 MiB，RSS 202.61→200.08 MiB，但构建 P95 87.83→118.34 ms；东亚 Dart 堆只有约 0.08 MiB 差异。两版均有全球常驻堆减少，但 RSS 未稳定改善，且构建耗时增加。因此不将此方案留在产品中，也不把 Offset 数量减少直接写成完整 APP 内存收益。

本轮没有改 SDK、地图精度、上游数据、服务器或安装包。所有实验进程已关闭。隔离验证项目中的底图组件也恢复为工作区原版，防止后续完整 APP 构建误带实验。

## 证据

- `backup/`：本轮开始前源码与像素对照测试备份。
- `candidate1-source/`、`comparison.json`、`verified-binary/`：第一版源码、测量和实际运行二进制。
- `phase2/candidate-source/`、`phase2/comparison.json`、`phase2/verified-binary/`：第二版源码、测量和二进制。
- 各版本的 `original-map-manifest.json`、`source-manifest.json`、`binary-manifest.json`，以及各场景的 `os.json`、`heap.json`、`snapshots.jsonl`、`process.json` 和运行日志。
- `phase2/map-projection-tests-final.log`、`phase2/map-projection-analyze-phase2.log`：第二版测试与静态检查。
- 初次验证构建因准备脚本使用错误工作目录而没有找到目标文件；修正路径后构建成功，失败日志单独保留，未作为测试成功或性能证据。
