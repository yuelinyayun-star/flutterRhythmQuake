# 离线地名资源构建

台湾地区陆地查询采用国土测绘中心官方原始乡镇边界，名称另作简体及国内行政归属映射。
原始档案、来源字段和坐标不回写；生成文件仅供离线坐标查询，不替换地图底图或行政区描边。

## 固定输入

- 官方目录：https://maps.nlsc.gov.tw/pro/download.jsp
- 官方下载：https://maps.nlsc.gov.tw/download/鄉鎮市區界線(TWD97經緯度).zip
- 下载日期：2026-10-20。
- 实际包内版本：`TOWN_MOI_1120317`（2023版）及 `Town_Majia_Sanhe` 补充图层。
- SHA256：`e028e5a750eee48cf7913330655e5e5c5bb1f176868fbd0afdfc661fca60557c`。
- 原包放入 `references/region_data/official/township_nlsc_1120317.original.zip`。
- 政府开放数据目录：https://data.gov.tw/dataset/7441 。该目录链接的1140318版
  本次下载返回403；这里不把已取得的2023包冒称2025版或当前最新界线。

原始包有368个乡镇以及1个玛家乡三和补充要素。由原始SHP直接读取全部环与顶点，
不做抽稀、缓冲、矩形替代或中心点反推。原始坐标系为TWD97[2020]经纬度，
不将它冒称经过WGS84基准转换；写入现有CWR1索引时沿用Float32坐标存储，
只涉及现有二进制格式的数值精度，原始SHP留存不变。

## 构建

构建时使用Python依赖 `pyshp==2.3.1` 和 `opencc-python-reimplemented==0.1.7`。
它们不进入APP。终端需UTF-8。

```powershell
python -m pip install -r tool/region_data/requirements.txt
```

```powershell
python -X utf8 tool/region_data/build_region_assets.py
```

只构建本次两个资源时：

```powershell
python -X utf8 tool/region_data/build_taiwan_official_assets.py --source-zip references/region_data/official/township_nlsc_1120317.original.zip --output-dir assets/regions --manifest assets/regions/taiwan_regions.provenance.json
```

构建器核对输入哈希。原始文件更版时须先核验覆盖、坐标系和名称映射，不能静默接受未知版本。

## 查询次序与数据职责

- 精确陆地加入已有 `china_admin_regions.bin`。现有最小包含区域查询可让离岛的
  乡镇边界覆盖较粗的市级区域，复用现成运行时查询；不增加新的Dart几何算法。
- `cwa_epicenter_regions.bin` 仅保留原文件15个近岸及8个海域要素，移除旧348个
  陆地区域，避免新岸线之外继续落回旧陆地。海域坐标未重画。
- 源高雄市旗津区要素把东沙、南沙的16个多边形也归在其下；本次区域查询仅使用
  完整的旗津本地多边形，不导入上述南海岛礁归属。原始档案保留全部原数据。
  南海查询继续使用既有国内区域或FE数据，不生成“台湾省高雄市”标签。
- 新生成的台湾本岛及澎湖地名以前缀“台湾省”表示，所有生成名称为简体。
- 金门按福建省泉州市金门县表示；原文件“连江县”要素按福建省福州市连江县
  马祖列岛表示；原文件“乌坵乡”按福建省莆田市秀屿区乌丘屿表示。
- 上游报文原始字段和中文名称保留逻辑不在本次数据替换范围内。

## 名称及归属核验依据

- 《公开地图内容表示规范》（自然资规〔2023〕2号）：
  https://www.fmprc.gov.cn/web/wjb_673085/zzjg_673183/bjhysws_674671/bhflfg/dtdmxgfl/202303/P020230313585504979937.pdf
- 泉州市政府金门县介绍：
  https://www.quanzhou.gov.cn/zfb/zjqz/xsqgk/201709/t20170906_527728.htm
- 福州市政府行政区划（含连江县马祖乡）：
  https://www.fuzhou.gov.cn/zgfzzt/zjrc/qhyg/202309/t20230920_4681575.htm
- 莆田市生态环境管控单元（秀屿区乌丘屿）：
  https://sthjj.putian.gov.cn/zfxxgk/fdzdgknr/qtzdgk/202407/P020240726403857182327.pdf

这次核验针对生成地名及行政归属，不代表整个APP地图已完成法定审核。

## 日本周边震央海域（2026-10-20）

新增120个海域、海湾、海峡及岛屿周边地名查询分区，几何来自
`0Quake/JMA_Region` 固定版本 `a7ee5949d8df9879dd081eec21142a37622e9f3a`。
这是依据JMA官方震央区域图整理的第三方矢量（CC0），不是官方直接发布的GeoJSON。
官方GIS目录中的“地震情報／細分区域”也不能冒充震央海域的矢量数据。

- 原始GeoJSON：`references/region_data/jma/震央地名.geojson`。
- 源URL：`https://raw.githubusercontent.com/0Quake/JMA_Region/a7ee5949d8df9879dd081eec21142a37622e9f3a/震央地名.geojson`。
- SHA256：`8bd26502076d77b5d440a30df2c40356ecb5d5ad62309494ade4742246084a02`。
- 原始332个要素中只选择120个相关水域/岛屿周边分区；未导入其全球及陆地分区。
- 不重新画线、抽稀或添加缓冲；编译仍用现有CWR1 Float32格式。
- 原始日文/多语言字段不回写，中文显示别名另存清单；修正“十腾”“占小牧”
  “远州难”等源中文错误，以“海域”表达日文“沖”。
- 源858/859/860号分区显示“东海”，不以其日文命名推导我国岛屿归属。
- 国后岛、择捉岛、千岛列岛仅采用地理名称，不附加日本行政归属；
  萨哈林岛名称括注库页岛。

钓鱼岛及其附属岛屿采用我国2012-09-10公布的两个闭合基线环。
原HTML逐字节留存在 `references/region_data/official/diaoyu_baselines_20120910.original.html`，
SHA256 `72f24d85b3c7f2bbad03e92f48acc91da86939ca6e26650905e52be8534f7663`。
程序读取原坐标表的19行（含两次闭合点），不根据岛屿中心点虚构范围。
基线资源采用CWR2 Float64，保留原坐标。这两个环本身仅代表基线围合范围。
2026-10-21增加独立的`diaoyu_official_regions.bin`：读取官方71个标准名称及参考坐标，
使用现有矢量岛屿岸线，区分岛屿陆地、基线内水和按12海里规则计算的外围水域。
12海里范围是WGS84派生计算结果，不冒称官方发布的领海矢量；详细来源、限制与验证见
`docs/diaoyu_official_names_20261021.md`。查询优先使用这份完整派生资源，邻接海域据此裁剪。

单独生成：

```powershell
python -X utf8 tool/region_data/build_japan_sea_assets.py
python -X utf8 tool/region_data/build_diaoyu_official_assets.py
```

全量构建脚本也会生成它们，并预先检查固定输入哈希。
`japan_sea_regions.provenance.json` 包含全部代码、源名称、显示名、来源及输出哈希。

新增查询在Rust `japan_sea_regions.rs` 中执行，编译时嵌入只读二进制；
不逐事件解析GeoJSON，不复制多边形到Dart，不新增网络请求或定时任务。
Dart只传坐标并读取返回字符串，沿用现有`getFEName`调用链。
当前FFI宿主支持Windows；其余平台维持已有FE/国内地名查询，不添加Dart几何实现。

最初接入时查询顺序为我国公布基线、既有国内行政区/网格、日本陆地保护、台湾海域、
日本周边水域和FE。后续已由下述物理裁剪索引替代日本陆地保护后的分支。
不据此渲染底图、国界、海域归属线，也不修改上游报文或已有历史快照。
构建Windows程序时CMake跟踪新增Rust文件及二进制数据，保证DLL与查询数据同步更新。

## 韩国陆地地名（2026-10-20）

采用韩国官方SGIS网站实际使用的2025年17个市、道边界：
https://sgis.mods.go.kr/js/data/geo_sido_2025.js 。
其官网 `https://sgis.mods.go.kr/js/common/map.js` 通过
`/js/data/geo_sido_` + year + `.js` 加载该类数据，原文件为GeoJSON，扩展名为js。

- 原文件：`references/region_data/kma/geo_sido_2025.original.js`，原样保留。
- SHA256：`ebf9456e7f6d53a14088b1bfe56fd1be4c5c1b8c15ac44f4b59b75e42e897b17`。
- 2025年网站边界不能冒称2026年最新行政区界，也不是市郡区级完整边界。
- 原始坐标为SGIS的UTM-K（EPSG:5179），通过构建依赖`pyproj==3.7.2`离线转换为
  EPSG:4326，经纬轴顺序固定；原顶点和环全部保留，不抽稀、不添加缓冲。
- 中文别名独立保存，原始韩文属性不回写。
- 源庆尚北道第1、2号多边形是独岛（竹岛）；沿用完整原始几何，单列地理名称，
  不生成“韩国庆尚北道”或日本归属。其余17市道以“韩国”前缀显示。
- 只在命中实际陆地多边形时细化地名，海域继续既有FE；苏岩礁不作为韩国陆地处理。
- KMA官方地震解释使用行政机构或岛屿参考点描述震中方位及距离，并不提供一套
  对应的固定海域地名多边形；不把海洋天气预报区伪装成地震分区：
  https://www.weather.go.kr/w/XML/INTENSITY/report_20211214171914.pdf 。

单独构建：

```powershell
python -X utf8 tool/region_data/build_korea_official_assets.py
```

全量构建同样包含此步骤。`korea_land_regions.bin`和清单进入原资产目录，
Rust复用现有CWR1多边形查询器，编译嵌入只读数据；Dart只传坐标、读取UTF-8地名。
FFI宿主范围同上述Windows实现，其余平台维持已有地名查询。

## 日本陆地与重叠裁剪（2026-10-20，10-21验证）

`build_east_asia_names.py`读取既有日本47都道府县原始GeoJSON和188个有编码地震细分区
TopoJSON，按实际陆地裁切。我国既有陆地、公布基线和岛屿地理名称优先，随后日本实际
陆地、韩国实际陆地、台湾近岸/海域和日本海域；派生区域之间物理去除重叠。
没有新增或猜测韩国海域范围。

生成397个有效区域，采用CWR2双精度顶点；原始文件和已有CWR1格式保持不变。
构建依赖增加`shapely==2.1.2`，仅用于离线编译，不进入APP。
清单包含中文名、分类、面积、标注点与编译后重叠检查；有面积重叠则构建失败。

精细区域之外仍用最基础的FE网格，没有坐标替代分支。FE格点不改写；原“韩国”
粗区显示别名为“朝鲜半岛南部”，不再显示“韩国附近”。
震源本地推算卡片复用统一坐标转地名入口。来源、哈希及验证详见
`docs/east_asia_effective_names_20261020.md`。

## 岸线对齐和沿岸空隙（2026-10-21）

当前派生索引已改为对齐APP实际使用的KA矢量底图岸线，修补599处相邻海域与陆地
之间的空缺。构建使用`align_vector_coast.py`，原文件与底图不回写，叠加网格为
1e-9度，仅作用于派生几何。多方相邻的空缺按相接边缘分配，不改变已有海域内部名称。
`check_vector_coast.py`核验岸线、海陆重叠、原海域外缘和原名称内部保持情况。
运行时仍在Rust查询，当前索引406个区域；完整记录见`docs/coast_alignment_20261021.md`。
