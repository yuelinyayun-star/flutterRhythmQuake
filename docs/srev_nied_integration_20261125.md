# NIED SREV 接入记录（2026-11-25）

主工程：D:\flutterApp\flutterrhythmquake，main e52a8ac（保留原有未提交改动）。本轮只修改 NIED 的原生检出路径和推算测站输入，不改现有 HYP/震级计算，不改其他信源检出或测站渲染规则。

## 实现

- vendored crate: native/station_core/vendor/srev-detector（原已验证 Rust 移植，CC BY-SA 2.0 及来源说明见 crate README）。
- native/station_core/src/srev_nied.rs：SREV 原始1748站目录，以名称+五位小数经纬度匹配；当前已扩展目录适配，全部1725站纳入（详见末尾更新）；原始连续震度按0.1刻度映射到原版1..30档，缺测0；仅KA档位时采用上次验证的区间中间刻度。用原始源时间推进 SREV 状态，重复源时间不重复推算。活动站=原版 permission>=4 且本帧有效；到时优先原版关联站记录，否则原版触发时间。未接入 SREV HYP 反馈（保留 RQ 推算）；当前对照对象为独立 SREV 检出、不运行 HYP。
- native/station_core/src/nied_detection_state.rs：新增 SREV owner 模式，原版许可替代 KA 关联。既有地图网格、通知、生命周期投影兼容；无新数据时仍有10.5秒失效保护，但每次新观测直接根据 SREV 许可更新，不额外延续 KA 活动保持。旧5字段 FFI 目录留作历史 KA 对照，生产目录带站名为6字段。
- Cargo.toml/Cargo.lock/CMakeLists.txt/src/lib.rs 接入依赖及构建跟踪。
- lib/services/sources/native_nied_detection_owner_io.dart（及 stub）：传入站名、原始观测档位与可用细震度；按SREV更新许可、到时。旧 `level` / `kaLevel` 保留为现有 UI、历史回放、其他算法的兼容投影，未将其重解释为 SREV 编号；不改变既有地图颜色、点和数字切换阈值。
- shake_detection_service.dart：NIED native owner 默认 SREV；旧 KA 模式显式留作历史回归。P-Alert 等非 NIED 入口不切换。
- nied_realtime_pipeline.dart、nied_source_estimation_worker.dart、nied_source_estimation_driver.dart 和 quake_map_view.dart：native live NIED 使用 SREV 已选活动站及到时，不重复执行 KA 链式活动站选择。保留 RQ 现有 HYP、震级、KA兼容输入及独立诊断检测。旧历史回放入口仍用既有模式。未原生移植的 iOS/Web 仍是旧路径。
- test/native_nied_detection_owner_test.dart 历史KA等价测试显式选择旧owner，原断言未删除；test/srev_nied_migration_test.dart 新增独立SREV许可对比及地图实际渲染对比。

## 已完成验证

- cargo check --offline：通过。
- cargo build --release --offline --locked：通过，构建产物 native/station_core/target/release/rq_station_core.dll；未替换当前运行 APP 的 DLL 或重启 APP。
- Dart 针对6个改动源文件 analyze：0 errors，1个 info（if 大括号提示）。
- Rust KA档位中点映射单测：通过；原始目录合成对照初次因1748中2个同名同坐标歧义站断言失败，调整参考输入为1746唯一站后重跑尚未得到完成结果。
- Flutter Test 真实原生 owner 对照：独立 SREV 保存的中间档位、无 HYP 反馈参考；三场535帧、1725站目录，1710唯一匹配；真实源数据转换成测试输入，非完整实时原始采样器。所有帧许可集合完全一致。
| 样本 | 帧 | 首次许可帧(0基) | 峰值许可站 | 少检 | 多检 | 显示level改变 | 活动站无到时 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 小笠原 |373|36|825|0|0|0|0|
| 奈良 |71|11|230|0|0|0|0|
| 大隅 |91|36|25|0|0|0|0|

原生owner（Flutter测试中，包括桥接及投影）平均耗时10.736/5.345/8.194ms，非隔离性能基准。
输出：tmp/srev_nied_migration_20261125/comparison_input.json、native_owner_comparison.json。参考来自独立工程 validation/rq_srev_ab/*_frames.ndjson 的 mid 方案，而非将现有 KA 结果当作 SREV。

## 未完成/注意

- 地图像素回归已完成：真实NIED第80帧加全部显示档位、缺测样本，现有 FlutterMap/NiedIntensityLayer 实际渲染，1000×700每幅，屏蔽检测网格仅比较测站；4组前后共280万像素，全部零差异。3.9默认 0/0 图标；4.0默认 18/18；6.0显示震度0 222/222；6.0信息聚焦 0/0。8张PNG和 map_comparison.json 均存在于 tmp/srev_nied_migration_20261125。
- 后续核查当前设备资源阻塞，继续运行原生合成测试、旧KA历史对照、其他共享图标、实际采样器及生产链路、SREV检出+RQ HYP 的混合回放。
- 旧版未匹配测站被排除的限制已解除；各数据源实际目录和观测仍需分别核查 lmoni/kmoni/Yahoo/WHEWS/JIAN 的真实目录。原始0.1量化边界、实际连续值来源时效、重复帧、断连恢复、时间跳跃、非日本站、平台覆盖、长期误报/弱震需追加验证。
- SREV 使用原始阈值配置，未将旧 KA sensitivity=1..3 强行映射到SREV；目前设置仍传入但 SREV 不消费该值。
- 当前运行 APP 未切换新的 DLL；不得声称已完成运行验收、全平台切换或新版本发布。

## 更新：完整目录与侧栏修复（2026-11-25）

APP 已终止 PID 37664，保持关闭，未替换运行程序。
- SREV 目录适配：1710唯一精确匹配以外，12个同名近邻旧站（唯一未占用、距离<=15km）采用当前坐标；两条白川同名同坐标且阈值相同的记录按输入顺序分别分配独立槽；大田原2作为新增站，使用320默认阈值、最近旧站区域。该迁移策略不是已核实的原站身份，旧站阈值继承与新站默认阈值仍需长期误检校验。重算受移动/新增站影响的最近7站、网格及相关历史数组；原始1748站目录保持原版行为，动态网格容量保证终止空项。无额外KA检出。
- Rust 原始目录24帧等价对照和档位映射2项通过，完整目录 Release 构建通过。Flutter test/srev_nied_full_catalog_test.dart 通过（535真实帧+24合成帧），输出 tmp/srev_nied_migration_20261125/full_catalog_report.json。
| 样本 | 帧 | 首次帧 | 旧峰值 | 新峰值 | 共同站相对旧参考少/多许可站次 | 新15站许可站次 |
|---|---:|---:|---:|---:|---:|---:|
| 小笠原 |373|36|825|836|217/937|1351|
| 奈良 |71|11|230|235|3/71|56|
| 大隅 |91|36|25|25|0/0|0|
- 小笠原和奈良的共同站差异包含目录几何变化，以及小笠原完整快照有效时间过滤等输入变化；不可等同误检/漏检，不再宣称1710站参考零差异。新增站真实14站有有效观测并在小笠原获得许可；ISK008羽咋三场无有效观测，合成网络整体上升时15站全部取得许可，峰值1725。不是15场独立真实地震验证。559帧活动站集合、触发到时、显示level不变、检出快照分类数量和网格档位断言通过。
- 侧栏缺陷：此前 native station_summary.rs 的区域使用0..7合并分类，而 MainScreen 使用0..9完整JMA标签表。现改 native区域、Dart map fallback区域、MainScreen fallback、summary worker签名为完整0..9；DetectedStationEntry.jmaIndex 从兼容显示level派生，既有 jmaShindo / maxShindo 0..7、通知、强震分组、地图渲染均保持。新增 Rust 全等级映射测试与 Flutter 原生侧栏5-/5+/6-/6+/7投影测试；Rust station_summary::tests 4项已通过。Dart analyze改动文件无error（有原有风格info）。
- 修正 native SREV EventDetection.detectorId（实际SREV才使用新标识，reset捕获旧模式）；目录签名补站名。JIAN坐标不变但代码/非空站名/地区/网络改变时重新建立目录。新增 test/srev_nied_source_metadata_test.dart，estimate:false。
- 源码审计：Lmoni/Kmoni GIF、Yahoo、WHEWS/JIAN数组统一在 nied_realtime_pipeline.accept -> detector.processUpdate -> native owner。WHEWS保留API序号、JIAN保留原始站号，连续震度通过gifObservation，Yahoo通过量化档位；iOS/Web未移植路径、原有灵敏度选项、全源真实回放、长期误检及HYP另列待验证。此次不更改HYP/震级。
- 最终验证：18:55:40生成的新 Release DLL（22125568 bytes）已实际加载；Flutter test/native_station_summary_test.dart + test/srev_nied_full_catalog_test.dart + test/srev_nied_source_metadata_test.dart 共10项通过（exit 0），含独立5弱至7级侧栏区域投影、CWA/P-Alert/S-net共享统计回归、559帧完整目录复测和JIAN同坐标元数据替换。此前Yahoo/WHEWS连接、数组原始输入及档位等专项16项通过，JIAN三个在线测试跳过，未声称完成全源实况验收。git diff --check通过（仅换行提示）。APP保持关闭，未替换APP构建目录DLL。当前修复未进行完整MainScreen实机截图验证，也未再次渲染1725站地图像素对照，前次280万像素报告仅属于1710站版本。


## 更新：SREV HYP + 震级正式接入、P-Alert 推算暂时断开（2026-11-25）

本次用户要求在替换前先备份当前自研定位与震级，并暂时断开未切换档位的 P-Alert 推算。主线仍为 D:\flutterApp\flutterrhythmquake，main e52a8ac，未覆盖其他本地改动。

### 原算法备份
- tmp/srev_nied_migration_20261125/pre_srev_hyp_magnitude_20261125.zip：241个实际工作树文件，1555724字节，SHA256 2815cc4f01a9feb073694c6ba220afa0d4216c78967afe732b9bdd0c2b33ffc4。
- 包含原RQ Dart HYP/震级、Rust station_core、NIED/P-Alert相关接口、源码、研究测试与文档，内部 BACKUP_MANIFEST.json 为逐文件SHA256；已验证ZIP testzip和所有文件哈希。非整个APP备份，不应整包覆盖当前主线；恢复时按manifest选择需要的文件，与后续修改逐文件核对。
- 自研旧HYP和震级源码仍保留。NiedSourceEstimationWorker 默认研究/兼容构造保留旧driver，正式原生入口显式选SREV。

### 实现与边界
- native/station_core/src/srev_nied.rs：在同一个已有 SREV detector 中执行原版 HYP round-robin、圆/到时重算和 magnitude.rs。原版配置51/52/57/62启用，固定种子12345（可复现，不是原JS随机流）；每个新的源观测时间一次轮询求解，重复时间不重新执行。保留原版120秒HYP搜索截止和多槽状态，不改原版公式。关闭推算时不调用HYP，配置恢复52/57=false、62=true。
- native/station_core/src/nied_detection_state.rs 与 Dart native_nied_detection_owner：原FFI行flags增加bit4显式启用HYP，返回可选第5项SREV事件数组，原四项检出协议及无HYP测试仍兼容。源槽含编号、起始时间、原版支持数、关联站索引、经纬度、深度、原点时间、残差、原版M和P/S半径。
- nied_realtime_pipeline.dart：正式原生数据owner直接消费同一检出状态中的 SREV 源槽，不再将其送入旧RQ HYP worker。仍在非UI isolate；现在检测和推算按观测帧同步，重计算可能暂时阻塞数据owner而非UI，需要长时实况性能检查。
- nied_source_estimation_worker.dart：SrevSourceProjection 对接既有 SeismicActiveEvent / SourceEstimate / history / logger / 多源地图transport；method=nied_srev_hyp_rust_v1。原版残差不是概率，confidence_available=false，confidence字段仅以0兼容接口；卡片显示SREV HYP及残差。站记录为当前关联站的轻量投影，非旧自研完整观测历史；保留原时间和峰值摘要。主事件选择优先沿用当前有效槽，其他槽随多源metadata传输。P/S半径作为诊断输出，现有地图波圈显示仍用RQ原来的显示逻辑。
- 原生平台的回放及Android hosted备用路径使用独立 SREV native session；归档数据没有原始采样历史时使用有效KA档位/已有连续震度重建，而非声称无损还原。iOS/Web无station_core，仍用旧兼容路径。未构建Android或完整APP。
- P-Alert 的 PAlertSourceProfile / native_palert_levels / palert_inference 仍是KA/PGA/PGV体系；PAlertService.sourceEstimationAvailable=false，服务端强制不启用native inference，地图不调用Dart worker、不显示旧推算，回放不启动PAlert worker。原检测、颜色、测站网格、通知与档位不动。研究用独立算法仍留在原文件；正式切回需先明确P-Alert档位/地理目录/推算适配和测试。

### 验证
- cargo check通过，最终cargo build --release --offline --locked成功；Dart改动文件analyze无error，仅样式info。
- test/srev_nied_hyp_integration_test.dart：同输入、原始1748站目录、种子12345与此前独立SREV Rust输出进行535帧逐值对照，共4669项（3472/611/586）零差异。不是重新执行原TurboWarp实时调度的独立对比；此前原版积木/HYP/震级移植等价验证见交接文档。
- 新1725站目录真实回放535帧全部通过并产生如下主震源估计；使用旧回放已量化档位或Yahoo原始档位转换，实际原GIF另测。水平误差以之前核实的JMA最终震源目录为参考，不是EEW最终报。

| 样本 | 首次估计JST | 估计帧 | 最小误差km | 最后误差km | 最后深度km | 最后M | owner平均/P95/最大ms |
|---|---|---:|---:|---:|---:|---:|---|
| 小笠原M6.8 |11:11:13|337|24.24|63.26|440|5.888|15.58/54.22/89.80|
| 奈良M3.6 |18:01:31|60|0.36|2.48|30|3.011|9.93/16.62/19.59|
| 大隅M3.3 |14:41:36|55|2.82|31.11|10|1.539|5.99/12.43/14.15|

- 现有原生接口合并检出+推算、桥接及重绑的耗时；非独立同条件benchmark，未包括实际采样/完整应用或所有UI开销。与以前独立原版目录相比，新增站使小笠原最小误差20.78->24.24km，最后位置和M未改变，奈良、大隅结果相同。未将此解释为全样本定位优越性；大隅深度和M明显低估。
- test/srev_nied_live_hyp_test.dart：原始Nara Lmoni GIF51帧、1634站，实际NiedRealtimePipeline接入（非量化回放直接注入owner），40帧输出SREV源；第一次18:01:31JST、34.15/135.8167/20km/M1.111；最后18:02:10JST、34.15/135.7833/40km/M2.911，最后支持225站；Kmoni源切换且estimate=false不输出推算。此处Kmoni测试是使用同一保存GIF注入，不是实况连接。
- 联合Flutter测试：test/srev_nied_hyp_integration_test.dart、test/srev_nied_live_hyp_test.dart、test/srev_nied_full_catalog_test.dart、test/native_station_summary_test.dart 共13项通过（exit0）。无HYP的原1725站检测559帧与侧栏回归仍通过。另有P-Alert正式推算功能门测试。
- 独立归档推算worker回归额外通过（71帧奈良输入，60帧SREV估计，method和M断言通过，exit0）。本次合计14项Flutter专项测试通过。
- 输出目录：tmp/srev_nied_migration_20261125/original_hyp_reference.json、srev_hyp_original_parity.json、srev_hyp_full_catalog.json、full_catalog_report.json。报告含逐帧主估计、独立参考比较差异、时耗。
- APP仍关闭，未替换已构建APP的DLL，未完成实机地图/卡片截图、五源全实况、P-Alert实况禁推算、原生Android/iOS/Web测试。旧Nara pipeline回归用例此前固定比较旧RQ推算，不能直接当作SREV等价参考；新专门用例已替代该比较范围，但整个历史测试集尚未重新执行。现有震源推算不是官方地震信息。


## 更新：原 RQ 震级并行对照（2026-11-25）

- 用户要求将旧 RQ 震级接回 SREV 震源，评估是否需重新校准。旧公式文件 lib/core/source_estimation/srev_kaizou_magnitude.dart 与先前ZIP备份逐字节相同。此次仅修改 Dart SrevSourceProjection 和诊断显示/测试，不改 SREV Rust、正式M、检出、定位、P-Alert禁用或现有公式系数。
- 旧生产公式 srev_kaizou_scratch_magnitude_v3_dcond_20_over_d：M0=max(0,I-0.94+1.73log10(D))，校准在截断前进行：M=max(0,I-0.94+1.73log10(D)+min(1,20/D)*(-0.2984*I+1.0303))。D=0.1度四舍五入后震央到旧1748站目录最近站水平距离，下限20km，不含深度；I为原算法处理后震度，多个活动槽使用原分支转换。保留旧公式旧目录以隔离公式迁移，不自动换成新目录。
- 影子输入使用已有 SREV 活动站的 GIF连续震度（可用时）或KA兼容档位的物理震度中点，然后调用原 SrevKaizouMagnitudeIntensityState 进行原版10秒保持/30档代表值转换。单活动槽使用全活动站，多槽按当前关联站。每事件保留输入峰值，随当前SREV坐标重新计算，不套用旧HYP报号锁定（SREV无等价报号）。这不是逐帧重现旧整个HYP生产链。多事件分裂/合并时峰值归属仍需独立验证；不同源时序/量化亦需验证。诊断字段 rq_magnitude_shadow / rq_magnitude_shadow_current / rq_magnitude_shadow_input / rq_magnitude_shadow_peak / rq_magnitude_shadow_distance_km / rq_magnitude_uncalibrated_current；正式 estimate.magnitude 仍为原SREV。debug_page 增加这些对照值。
- 原1748站535帧原版 HYP 对照4669项零差异；新1725站535帧中452个主估计帧与前一报告逐值核对（frame/lat/lon/depth/origin/magnitude/count/residual）全部相同。51张奈良GIF实际实时链、归档worker和P-Alert功能门联合测试5项通过；新增事件峰值保持及槽复用清理专项测试1项通过（合计6项）。Dart analyze无error，debug_page 单独分析无问题。
| 样本/JMA | SREV最终M | 旧公式未校准/当前10s保持 | 旧校准/当前10s保持 | 旧校准/事件峰值 | 最终误差SREV/RQ峰值 |
|---|---:|---:|---:|---:|---:|
| 小笠原6.8 |5.888|3.388|3.426|6.060| -0.912/-0.740 |
| 奈良3.6 |3.011|2.811|3.393|3.393| -0.589/-0.207 |
| 大隅3.3 |1.539|1.499|2.445|2.445| -1.761/-0.855 |

- 三事件等权最终MAE 1.087->0.601（约44.7%下降），RMSE 1.194->0.664，事件等权全帧MAE 1.268->0.867。小笠原峰值I=2.16，最后10s保持I=-0.5；峰值保持至关重要。奈良RQ峰值首次进入官方M±0.5为帧17（SREV原M从未进入），另外两场两方案均未进入。实际奈良51张原GIF最后M2.911->3.393，40帧估计（同一事件，不能算第四独立样本）。
- 固定JMA最终经纬度、保持同一旧RQ峰值I的反事实测试：小笠原D617.45->591.61km、M6.060->6.029；奈良D20->20、M3.393不变；大隅D20.76->48.59、M2.445->2.542。表明仅修正水平定位不足以消除低估。用官方深度做简单震源距替代的灵敏度试算为6.232/3.771/2.644，但校准建立于水平距离，不能直接将距离换为震源距并上线。先研究按实际有测值站逐站距离和深度衰减的候选，而非按三事件强行调系数。之前tmp/mag_scoreboard/DCOND.md 73例旧链语料可供参考，其中部分桌面距离由app M反解，不是新链独立验证；旧校准可能在强震/多震源不同分布下失效，需要重新验证。
- 报告：tmp/srev_nied_migration_20261125/srev_hyp_original_parity_mag_shadow.json、srev_hyp_full_catalog_mag_shadow.json、nara_gif_mag_shadow.json、magnitude_shadow_summary.json（逐帧及固定震源灵敏度）。原报告未覆盖。APP保持关闭；无完整APP实机渲染；原生owner耗时不含Dart shadow投影，尚未进行单独开销benchmark。暂不替换正式M，建议扩展独立事件语料后决定公式及峰值策略。



## 最新状态：RQ 震级正式启用（2026-11-25）

- 用户确认先接入已验证的 RQ 震级，暂停新公式研究，继续其他模块打通。主线 main e52a8ac。SrevSourceProjection 正式 SourceEstimate.magnitude 采用旧校准模型及已验证的事件峰值保持；不修改公式系数、SREV Rust 检出、HYP、事件关联或P-Alert禁用。native原版M保留在 srev_original_magnitude；诊断 magnitude_model 标识来源。若RQ没有可用峰值，明确回退SREV原版M（srev_original_fallback），两者均无则为空；回退是本次兼容决策，单测覆盖。Debug区分别展示Published M、SREV original M、Magnitude model、RQ peak/current M。保留原rq_magnitude_shadow字段以兼容既有分析工具，其值现在是正式优先震级。多源地图仍使用投影后SourceEstimate.magnitude。
- 最终联合测试15项全部通过（exit0）：原1748站535帧独立SREV底层4669项零差异；新1725站535帧、24帧合成检出、侧栏统计、真实51张Lmoni GIF、归档worker、峰值/槽复用/回退、P-Alert禁用门。两份目录各452个主估计帧及40个GIF主估计帧，与上一轮影子报告逐值比对：定位、深度、发震时间、站数、残差和原版M未改变；正式M逐帧完全等于此前RQ影子M。三场最终正式M=6.060/3.393/2.445（JMA6.8/3.6/3.3），实际奈良GIF最终M3.393。Dart analyze无error（5个样式info）；git diff --check通过。APP_COUNT=0，未构建完整APP或实机渲染。
- 新报告 tmp/srev_nied_migration_20261125/srev_hyp_original_parity_rq_magnitude.json、srev_hyp_full_catalog_rq_magnitude.json、nara_gif_rq_magnitude.json。旧基准、影子报告及备份仍保留。

### 后续震级研究待办（暂缓，优先其他链路打通）
1. 扩大独立事件样本，按震级、深度、陆地/近海/远海、测站密度和信源分层，按事件留出验证，避免同一事件不同帧泄漏；统一JMA最终目录参考，统计首报、收敛后及末报MAE/bias/RMSE。
2. 优先研究实际关联测站的逐站震级稳健融合：每站匹配自己的震度峰值、震源距、深度与衰减项，异常/缺测/未成熟样本剔除或降权；与现有最近目录站+全局最大震度基线对照。不能直接把现有水平距离公式改成震源距后上线，需重新校准并独立验证。
3. 峰值必须按事件归属，验证多事件分裂/合并、噪声站峰值污染、站源切换及时间跳跃；目前原旧报号冻结策略没有直接套用，保留峰值并随SREV坐标重算。
4. 核对实际SREV 30档和旧RQ物理震度→代表值转换差异、真实连续震度质量、不同源采样、远震深度与强震饱和；避免仅根据当前三场低估直接加常数。
5. 保留原SREV M作长期对照，增加正式RQ震级和Dart投影耗时观测；评估完后再决定是否调整系数、移植Rust或替换模型。此轮不继续试验。


## 更新：SREV 生命周期与地图/UI 审计（2026-11-25；仅检查，未修改生产代码）

原始修改版 project.json 的受信と検出与地図积木、vendor generated.rs 逐段核对：
- HYP p39 (1625起)：活动槽且最新源观测时间减去该槽检测起始时间严格小于120秒才执行搜索；不是从JMA/估计发震时刻计时。120秒内结果也可能被接受门槛拒绝。满120秒停止搜索，保持最后有效经纬度、深度、发震时刻，并不自动关闭事件或冻结震级。
- p17 的关联清理（945-948）：有效支持数不足2可关闭槽。p36 (1541起) 对消失网格ID及事件时限处理：无活动网格ID清空事件及震源表；有网格的槽以起始时间加2*(3+支持数)秒（支持数>=200时400秒）延长期限，过期关闭；事件年龄>150且支持数<50关闭；支持<5、范围<80、残差>3000、最大震度分类<3且年龄>10可关闭；ID不再存在且年龄>2关闭。另有原版同源合并与测站许可解除，后者使用120+10^(1+全局最大震度/1.2)秒（不是HYP截止），因此不应硬编码所有事件120秒结束。以上是源码规则，未为每次实际清除判定唯一原因。
- p45 (1879起)：原版HYP波圈还要求支持数>2，并按估计发震时刻计算传播；发震后300秒及以上设999999隐藏哨兵，支持数不足时为空（配置21还可限制半径）；这是另一条独立时间轴。原地図绘制还依赖活动槽、坐标可用、配置53/57、残差/范围门槛等；未把这些原版视觉规则强行替换RQ现有地图风格。原项目没有发现明确“更新終了”文本字段；本轮核对的是原积木控制逻辑，非运行原Scratch界面截图。

实测 test/srev_nied_lifecycle_audit_test.dart：三场真实535帧+静默尾段19/91/23帧（人工追加所有站KA0=-3，无新事件，不能当成真实自然结束时间）；通过正式native owner、Dart SrevSourceProjection，断言同一槽几何在120秒后不变、活动槽消失时current event为空、历史归档。主槽：
| 样本 | 最后位置变化（检出后s） | HYP截止 | 槽消失（检出后s） | 后续波圈 |
|---|---:|---|---:|---|
| 小笠原 |119|120|383（静默尾段）|120秒S半径1005.33km，最后999999隐藏|
| 奈良 |101（静默尾段）|120|150（静默尾段）|120秒S半径536.71km，最后665.96km|
| 大隅 |43|尚未到120|77（静默尾段）|事件先结束|
小笠原另2个无有效震源估计槽各在11秒关闭，未判断真伪。原历史归档分别3/1/1个槽。输出 tmp/srev_nied_migration_20261125/srev_lifecycle_audit.json。

发现的RQ显示/状态问题：
1. source_rows 只返回活动槽+估计，没有独立 HYP更新状态、最后接受时间或最后实际改变时间；SrevSourceProjection 每帧 updatedAt=observedAt。alert_module.dart 的 reportTime 仍使用这个时间，isFinal仅sourceEvent.isClosed；一旦关闭又不在当前列表，无法显示“更新结束但事件仍活动”。建议由Rust权威导出每槽HYP生命周期（尚无估计/搜索中/截止/已结束或合并），与波圈、M、检测生命周期独立；侧栏时间区分观测时间和最后有效HYP更新时间，保留RQ M后续更新。
2. 确认地图波圈适配缺陷：quake_map_view.dart:niedWaveRadiiFromEstimate 只读 best_source_p_radius_km/best_source_s_radius_km/best_source，SREV诊断是 srev_p_radius_km/srev_s_radius_km，因此非零原生半径被转换成0（两圈不显示）。旧NiedWaveElapsedClock还依赖wave_elapsed_s，而SREV未提供；不要沿用旧HYP300秒与半径策略直接推断原版。先正确消费原生半径（含999999/空/0），若要帧间平滑需输出权威波龄、原版配置/半径上限与支持条件并做同值验证。
3. 地图正常事件消失走_syncNiedSourceEstimateState清理震源、波圈时钟，当前源列表驱动渲染。卡片测试实际渲染119/120秒仍显示SREV HYP/M3.4、无更新结束字样，清空event后卡片消失。旧 _estimateSignature 包含每帧updatedAt，地图仍刷新；SREV残差字段 srev_error 未被普通地图marker的best_source_error读取。需检查冻结时静态震源标记、波圈动画、单槽清理、多槽独立状态，以及不会因旧聚合检测stage而提前清除全部槽。源码中onShakeExpired可在非processing时投影空列表（断连保护），不能把它当自然HYP截止。
- 测试：原波圈半径/时钟、卡片、曲线overlay lifecycle与新回放联合执行exit0；新增卡片119/120/清空fixture和原生半径800/500被旧适配器转换0的专项复现各通过。后者是缺陷复现，绝非正确波圈验收；修复时反转断言为800/500。卡片测试有原先数据库factory未初始化警告，未测试历史数据库持久化。未启动APP、未渲染完整地图实际截图；原原版地图具体视觉样式尚未运行对照。
- 建议下一轮优先修状态/波圈桥接与实际Flutter地图及卡片渲染验证，再继续其他模块。没有改业务代码、没有修改检出/HYP/震级公式；新增/调整测试和本记录。APP_COUNT=0。


## 更新：SREV 更新结束、报号和地图/UI 接入（2026-11-25）

- 原始 p39 / generated.rs 1663-1679：检出年龄<120秒方可进入搜索；接受门为新残差<历史最佳残差×1.7，或年龄<10秒。接受后写经纬度、深度、发震时刻，并写4-3每槽第18项为最新源观测时间；原始工程未发现独立报号计数器。RQ 自定义本地报号基于该权威字段：首次有效接受=1，同一事件槽+起始时间下新观测时间的接受提交递增；相同坐标也可能被接受，普通采样/拒绝/波圈/M/截止不计报。合并复制旧时间不计新提交，槽复用按起始时间新建。未专门验证所有真实合并类型，不将本地报号称为SREV原版报号或官方EEW报号。
- native/station_core/src/srev_nied.rs 输出每槽 hyp_state=pending/updating/finished、hyp_accepted_at、observed_at，读取现有列表而不改原算法；120秒结束搜索不结束事件。Dart SrevSourceProjection 输出 srev_hyp_report_num/report_time/state/accepted_at、wave_elapsed_s等诊断，保留 event.updatedAt 为源观测时刻。alert_module V2用最后接受时刻作报时，报号加更新中/更新结束；isFinal仍表示事件关闭，不滥用EEW最终报。震级继续使用已接入RQ模型。
- quake_map_view.dart：读取 srev_p_radius_km/srev_s_radius_km，保持原生999999/0/null隐藏规则，不套旧HYP估算/限幅；按原生帧更新，未作帧间外推。地图标记显示SREV残差和每槽更新中/结束，原本颜色、图标样式及其他方法保留；地图签名纳入每槽状态/报号/波圈。共享生产函数 buildNiedEstimateMapLayers，实际FlutterMap双震源测试验证半径、状态、单槽清除和隐藏波圈而仍保留标记。侧栏保持既有主源卡片设计，地图仍显示多槽；无完整APP实机验收，断连导致聚合检出过期的旧保护仍保留，长时断连/恢复及合并需专项测试。
- 测试：Rust Release 新DLL构建成功（2026/11/25 19:34:56，22284800 bytes）；Dart analyze无error（原风格info）；git diff --check通过。原波圈/时钟/卡片回归联合exit0，SREV卡片119/120秒保留并显示第17报/更新结束，清空事件消失；test/srev_nied_map_lifecycle_test.dart 单项通过（实际FlutterMap图层，不是整机地图截图）；新DLL下生命周期/原版HYP等价/1725站/归档worker/真实GIF/震级峰值与回退/P-Alert门共7项通过。底层535帧4669项数值仍零差异，真实GIF40估计帧及正式M保持原结果。
- test/srev_nied_lifecycle_audit_test.dart 新增每槽报号、权威时间、120秒状态、几何冻结逐帧断言。结果文件 tmp/srev_nied_migration_20261125/srev_lifecycle_ui_report.json。小笠原111报，最后接受/位置变化年龄119/119秒，结束383秒；奈良94报，103/101秒，结束150秒；大隅31报，43/43秒，结束77秒。三场原录制数据535帧后追加19/91/23静默帧，共668帧；奈良部分报号及全部实际关闭时刻来自人工静默尾段，不能解释为真实事件自然报数/结束时刻。APP_COUNT=0，未重启或打包完整应用。


## 更新：其他实时测站源震度转换及检出迁移评估（2026-11-25）

- APP_COUNT=0；未更改NIED正式检出、HYP、RQ震级、其他源检出/推算、P-Alert禁用状态。未启动完整APP。
- JpShindoScale新增srevCodeFromShindo及srevCodeFromKanameishiLevel：0缺测、1..30有效；同native SREV 0.1量化公式；有限值低于-3缺测，高值饱和；KA旧档使用原Rust适配中点q，不可把新编号传给旧显示/通知。旧Scratch/KA映射非有限值返回缺测，CWA gridLevelFromInstShindo复用公共KA转换。
- CWA/TREM CwaStation.srevObservationCode使用当前i，srevDisplayCode使用currentIntensity（有alert取I），时间缺失返回0；S-net（官方GIF、WHEWS及回放模型）srevObservationCode使用有效活动观测shindo，旧显示档位保留；PAlertStation.srevObservationCode/srevDisplayCode分别当前/保持的PGA/PGV档位映射到等效震度区间中点，不冒充计测震度，保留高PGA的PGV分支；SeisJsStation.srevCalculatedCode仅转换CalcShindo诊断（现有解析缺失默认-3故该值保守视为未知），CSIS Intensity 0..12不改。KMA MMI 0..11及FSSN PGA/状态保持独立，不能直接套日本震度；官方情报JMA/CWA/MMI/长周期等级等不转换。新getter为候选输入/诊断接口，尚未切换这些源的生产档位、检出或native数据路径；未来消费必须另做时间新鲜度、有效性、原始采样对齐。
- test/srev_other_station_scale_test.dart：99个原始q值、21个KA档、缺测/非有限/饱和与当前/保持语义通过；18个CWA控制震度的原preparedLevel与新公共物理转换路径实际FlutterMap渲染，3.9默认0/0图标、4.0默认12/12、6.0显示震度0为15/15，800x600每组、144万像素零差异（不含网格，6张PNG）；S-net及SeisJS图标标签专项通过；联合9个Flutter测试文件exit0（含P-Alert桌面/手机图标、KMA MMI高档和缩放、S-net侧栏、native共享统计、CWA解析、P-Alert既有检出/震级换算、NIED旧档兼容）。首次测试失败是地图相机复用，修正独立地图后全部通过。Dart analyze无error、3个风格info，git diff --check通过。
- P-Alert真实保存档案test/fixtures/palert_cwa_1150077_20261017，28条归档中17个独立PGA帧、12071个有效数据样本（仅实际出现在报文的样本，不包含未上报站）、11790个低于0.8Gal现有噪声门槛、无>=80Gal样本，无法验证高强度PGV分支实况。新候选档位转换全部有效；现有native P-Alert与Dart参考真实回放对照17帧、787站、7个活动帧，通过原档位、活动站、网格和原始JSON断言。没有运行SREV P-Alert检出A/B，不得称其等价或优于现有检出。
- 地理阻塞：现有SREV适配grid(lat,lon)按123E/23N原点、23列/23行并clamp。保存的TREM station.original.csv 155站全部在该网格范围外；真实1度网格8格被压成3格，最大格42站变73站。台湾P-Alert/TREM直接使用该实现会扭曲关联，必须先支持独立地区目录和网格。原日本参数、阈值、邻站、海底/陆地观测差异及HYP范围均需分开验证。
- 建议：优先S-net独立shadow（真实计测震度、对远海事件有意义；isActive现在仅观测有效，不等于地震检出，海底噪声/观测深度、目录/网格、数据同步须校验，禁止直接混入NIED正式推算）；P-Alert第二（保留0.8Gal门槛、三站联合和重复采样/失效策略作为基线，台湾网格先改，扩样本含静默/强震/PGV；推算继续断开）；CWA/TREM保留上游alert为正式规则，可shadow当前i而非保持I，之后对照漏误检/时效；KMA保留其MMI检出，SeisJS手机/社区CSIS不直接迁移，FSSN无同类计测震度。现阶段不批准任何其他源的正式SREV检出替换。
- 输出：tmp/srev_nied_migration_20261125/palert_srev_scale_audit.json、other_source_render/cwa_*_before/after.png。完整APP地图、其他源原始在线/长时噪声及SREV A/B尚未验证。

## 更新：台湾 P-Alert / TREM 网格对齐与 SREV 检出初测（2026-11-25）

- 用户明确 S-net 分钟级更新，仅观测显示，不做检出；取消此前 S-net 优先迁移建议。
- P-Alert/TREM 原来分别以最强站小数坐标作动态网格偏移，现固定为 floor(lat/lon)+0.5 的1度网格中心，0.99度框边长保留，颜色保留。已修改 native palert_state.rs、station_runtime.rs 的CWA/TREM分支、Dart shake_detection_service.dart 的P-Alert分支、cwa_station_layer.dart fallback。NIED/KMA网格规则不改。不同源重叠框颜色覆盖尚未进行完整APP视觉验收。
- Rust Release 19:58:30构建成功，22284288 bytes。原始日本目录24帧等价回归及档位测试通过。P-Alert原始档案17帧/787站/7活动帧，实际新DLL回放与旧Dart参考的原检出站、held档、网格、通知和原报文对照通过；所有网格中心小数为0.5。test/palert_detection_grid_test.dart 7项通过，含真实FlutterMap中TREM和P-Alert重叠框四顶点完全一致，桌面/手机闪烁及清理。未重新构建完整APP，APP关闭。
- native/station_core/src/srev_nied.rs 的 taiwan_layout 为仅测试编译的候选实现，独立台湾目录、经纬度网格原点112E/16N，仍用23列，超边界拒绝不clamp；不混入日本目录、不继承日本沿岸外推；所有台湾站暂用320阈值及实际7邻站。候选不开HYP，不用于生产。未校准台湾阈值，也未完成非规则采样时间及源切换处理。
- 真实候选输入 tmp/srev_nied_migration_20261125/taiwan_candidate_input.json、输出 taiwan_candidate_report.json。P-Alert 17个原始采样帧（间隔1-5秒），787站、8地理格，旧检出7活动帧、峰值100；未加PGA噪声门槛的SREV候选16活动帧、峰值427，第2帧出现213许可站而旧算法为空。不能将许可差异直接判定为实际误检或提前预警；目前差异过大，不替换正式算法。需先按PGA<0.8Gal基线噪声门槛、采样间隔及台湾适配阈值做分项A/B、补充静默/强震样本。TREM现有原始保存155站目录、121站观测、8格、仅1个真实静默帧，两方案均未检出；无法评估真实地震检出能力，需连续地震及静默样本。现有上游alert保留。TREM网格native生产路径已编译，尚未单独做真实活动帧端到端验证。P-Alert推算仍断开，其他源转换getter尚非正式生产档位替换。


## 更新：台湾五事件检出研究与噪声门控（2026-11-25）

- 云盘原地址页面可访问（普通HTTP请求403，浏览器UA返回FileBrowser Quantum页面），未取得认证目录列表；无云盘下载。本机 replay_history/v3/events/ 与 frames/ 文件真实存在，按 stationFrameKeys SHA256 对应gzip文件读取，排除 TEST2-EEW-JP-C 人工事件。5场CWA归档：1150076花莲万荣M4.5、1150077宜兰大同M4.5、1150080宜兰头城M4.7、1150085台东北外海M4.7、1150086台东南外海M5.6。震级及发震时刻来自本地最后保存报文，非独立最终目录核验。
- 归档原CWA2232、P-Alert1239帧。CWA每源时间1秒桶取最后真实观测，单站work及lastUpdate距接收时刻<=3秒，保留当前I不用held alertIntensity；早期无时区字符串按UTC+8，UTC显式保留。1150086源时间与接收时间偏移使第一版过滤错误，已用接收时间修正并替换全部CWA实验输入；最终1293独立帧。P-Alert首个相同dataTime快照去重，站dataTime必须与帧一致，PGA/PGV按原阈值计算，不用历史heldLevel，1017独立帧。过期站不作0值；归档快照可能非完整原始报文，旧基线为归档detectedStationIds/hasAlert，不是重新运行旧检出。不同源采样间隔未插值，SREV仍按每个采样推进历史；时序适配待研究。
- test-only 原台湾SREV adapter，787/786站P-A及94-129站CWA，使用独立实际地理目录和7邻站，320默认阈值，不开HYP、不切换生产。五场×P-A 5策略（无门槛、0.44、0.59、0.8 Gal、adaptive）及CWA原I共30组6378帧，实际Rust测试二进制独立运行，全部exit0。P-A门槛下有效低振动站输入KA0，非缺测；adaptive用仅过去90秒有效样本的25%分位×3，限制0.25..1.4Gal，前10样本默认0.59；未冻结地震时基线更新，待长时静默及强震验证。
- 离线事件门：当前超过各自门槛且SREV已许可站中，存在30km内至少3站；连续两个真实观测帧、间隔<=6秒且簇有共享站。输出事件确认诊断，不覆盖站级许可或地图网格，未写入生产。相对本地归档发震时刻（秒）结果：
| 事件 | 旧P-A首次活动 | SREV+0.44+空间门 | SREV+0.59+空间门 | SREV+0.8+空间门 | SREV+adaptive+空间门 |
|---|---:|---:|---:|---:|---:|
|1150076|7|7|7|7|7|
|1150077|20|9|9|20|9|
|1150080|28|28|28|28|28|
|1150085|12|13|13|13|13|
|1150086|13|8|9|15|9|
- P-A adaptive+空间门5场均有确认，较旧2场提前11/4秒、2场相同、1场晚1秒；未出现发震前或最后60秒空间确认。1150080与1150085回放已在发震后开始，旧/新可能冷启动时已有震动，非完整预警延迟；1150086未经过空间门的候选在发震前2秒有单/双站活动，空间门避免把它当事件。未经门控原SREV五场峰值584-666，尾段活动严重。
- 后续30组3598帧：CWA 0.3/0.5震度下限将低值有效观测映射-3，不更改显示；P-A 5事件各尾段60秒重新冷启动四策略，adaptive重新从尾段建立噪声历史。253实际尾段帧，无门槛248帧许可、最大658站；0.59Gal 7帧（1150085、最大2站）；adaptive和0.8均0帧。不是独立长期静默数据，不能得出真实误报率。合计60组9976帧。此前单场17帧及12方案为另一批测试，不混计。
- CWA原版直接迁移仅3/5场许可：1150076/1150077当前I最大仅1.1/1.6，同时>=0.5最多2/1站，旧上游alert仍保持负I站（max 5/8）。旧两场早期归档版本和新11月CWA背景值存在差异，不能仅凭held告警判定SREV漏检原因；当前档案不能补回发震前历史。其余1150080/85/86原SREV峰值127/15/129，旧78/6/19；0.3门槛97/6/45，0.5门槛90/3/38，仍未恢复两场缺失。保留CWA上游alert作为正式检出；新候选后续优先查TREM数据语义和真实连续采样，不将低背景震度直接归零后上线。
- 推荐P-A下一轮优先adaptive+空间门影子接入（0.59作为固定对照、0.8保守对照），独立站噪声/突升/不规则采样、强震PGV、长时静默/多事件检验后再决定生产；空间确认与后续保持/释放需单独设计，不能直接用瞬时空间门替换整个生命周期。此次未修改任何生产检出/推算代码，P-A推算仍断开，S-net不检出，APP保持关闭。
- 可复现文件：tmp/srev_nied_migration_20261125/prepare_taiwan_five_events.py、prepare_taiwan_cwa_corrected.py、run_taiwan_five_events.py、summarize_taiwan_five_events.py、run_taiwan_followup.py；输入与清单 taiwan_five_event_input.json、taiwan_five_event_manifest.json、taiwan_five_event_cwa_corrected.json、taiwan_five_event_cwa_manifest.json；逐帧输出 taiwan_five_event_report.json、taiwan_five_event_summary.json、taiwan_followup_report.json，five_event_runs/单组输入与输出。第一版CWA输入保留审计，最终报告只用corrected。


## 更新：TREM上游检出确认 / P-Alert SREV正式原生入口（2026-11-25）

- 用户确认TREM使用上游检测、S-net不检测；ExpTech原始接口文档 https://exptech.dev/docs/api/stream/rts/ 与 https://exptech.dev/docs/api/stream/rts-replay/ ：rts.v1每0.5秒快照、当前连续i、alert=1表示测站参与正在进行的事件，未参与省略字段；历史接口每秒一次。上游实际后端检测器源码未找到，不能据此推断其阈值。当前Rust/Dart已按上游alert，原有固定台湾网格保留。新增 TREM v1 测试：高震度无alert不触发，两格逐个移除、结束清空，实际旧DLL（本轮TREM生产路径未修改）与Dart通过。TREM非官方观测，非官方预警。
- 用户给出有效公共共享 https://file.yuelinrhythm.top/public/share/2me6CJMrNsVOv_-aFfNePQ ：GET public/api/resources 返回86项，保存cloud_share_listing.json；其中1150078/1150079两场花莲M4.7（34,951,168 / 28,020,736 bytes）。公开download请求180秒超时，Range重试读超时；未取得完整ZIP，不纳入测试样本，不尝试绕过授权。原下载脚本download_cwa_share.py保留，.part非完整档案。
- 新 native/station_core/src/palert_srev.rs：使用独立台湾SREV检测实例（不启用HYP），每站过去90s有效PGA的25%分位×3，限0.25..1.4Gal，未满10样本使用0.59。低于门槛有效观测映射安静KA0，缺测仍缺测，当前原始PGA/PGV对应KA档输入原SREV。30km内3站（低灵敏度4站）当前许可且过门槛，连续两个真实采样、间隔<=6秒且同局部簇有共同站后确认；高灵敏度噪声门槛乘0.85且不低于0.25。灵敏度1/2/3为本轮设计映射，非SREV原版参数。原生沿用已有10.5秒站保持、6秒失效、通知/显示、原始归档、PGV换算；不修改震级及推算，不改变NIED。重复时间不推进算法，>120秒间隔/连接失效重置独立台湾状态。SREV站目录至少8站且位于台湾带有余量的独立网格，否则回退旧KA并标明原因。PAlertService原生正式入口选择palertDetection=srev，nativeSettings可显式选择legacy；裸NativeStationRuntime默认仍旧，非原生Dart fallback仍旧。prepared ABI detection数组增加末尾算法名，旧DLL缺字段时仍可兼容。检出原因srev-palert-spatial。不将SREV许可站直接等同事件确认站。
- Release模块测试3项通过，五场每档1017独立帧，尾段每档253帧重启，重复时间断言；三档5/5确认、发震前零确认、尾段零确认。相对档案发震时刻，按1150076/77/80/85/86顺序旧7/20/28/12/13秒；低7/9/28/13/11；默认7/9/28/13/9；高7/9/28/13/8。默认Release模块均值1.159ms P95 1.908 max2.263ms；低1.226/1.933/9.059，高1.168/1.924/3.174。原日本目录等价及档位测试通过。测试报告palert_srev_actual_module_report.json、palert_srev_actual_module_sensitivity_report.json。回放非独立预警真值，部分左截断，旧基线保存的检出站集合。动态门槛仍在地震期间更新，长期强震、PGV强震实况、真实断连恢复和多震源仍需验证。
- 另外从本机四个远离台湾的JMA事件选择背景观测（20261123141411/20261124210714/20261118183714/20261121190909），170/129/213/154个源时间去重帧，旧算法零活动。保存palert_background_windows.json；不是官方确认无地震样本。后续端到端测试结果追加于下。

- 正式DLL cargo build --release --offline --locked 成功，非预先存在DLL。新DLL Flutter test/native_palert_runtime_test.dart 指定3项联合 exit0：旧KA原始报文回归17帧/787站/7活动帧；PAlertService默认新入口17帧/12活动显示帧，断言检出原因、固定格中心、原报文、直接归档与显示列、侧栏投影、超时后格及活动站清除；独立4个背景窗口666真实去重帧，以源时刻作受控接收时刻重建PGA/PGV报文，实际NativeStationRuntime新模式，旧新均零活动（palert_background_runtime_report.json）。背景验证不是官方无震目录，不能宣称长期零误报。原生SREV与KA显示档位分离；无APP完整构建或现场渲染，Windows测试通过不等于Android实测；iOS/Web/Dart兼容路径仍KA。P-Alert推算未重新启用。TREM上游检出逻辑未变。


## UI/台湾检出框安装后反馈修复（2026-11-25）
用户要求保持SREV接受更新条件且必须显示报数，不要擅自更改地图文案，TREM/P-A框仍未对齐。SREV复用原Dart HYP橙色叉形标记（当前/震源编号、深度、误差），关闭通用绿色点文字，去除地图“SREV残差/更新中/更新结束”后缀，侧栏沿用“震源本地推算 第N报”，截止后“第N报（更新结束）”。未改报号计算、Rust定位/检出/震级或波圈。旧HYP及其他源原文字逻辑保留。
检查四场历史事件1150076/77/80/86的267个P-A活动保存帧全部含旧偏移坐标；1150085没有找到此类活动框。实际原因之一是旧回放仍透传保存的坐标，而TREM重新按固定格计算；另有prepared native几何直接消费的旁路。现CWA/P-A地图统一taiwanDetectionGridCenter与Vertices，固定半整数中心、0.99度边长、同格去重；P-A旧历史/hosted payload优先按已检出station IDs与held gridLevel重分格，缺少成员记录时才按旧中心归格。保留原颜色、闪烁、源独立清理，修P-A仅有preparedGrids而fallback为空时不绘制的问题。未改生产检出阈值。四份真实样本grid_legacy_*.json验证重分格；全267帧已查坐标，未逐帧实机渲染。
55项Flutter联合测试通过（地图标记、报17→18、截止保留报18、波圈、多源、旧prepared坐标、真实archive、P-A旧链回归）；旧回归最初要求动态网格与参考源完全相同，修断言为独立固定格且检测ID/state仍一致。打包目录DLL实际668帧生命周期测试通过，报111/94/31、120秒截止、事件清理均未改变；含人工静默尾段。记录ui_grid_fix_final_tests.log和ui_report_real_replay.log。git diff --check通过。用户已运行安装版（PID30960），没有关闭它、没有安装或重打包。需后续完整应用实际显示验收；本轮修复仅源码。


## P-Alert HYP接入前审计：与那国岛近海及六场对照（2026-11-25）
- PAlertService.sourceEstimationAvailable=false，未开启P-A正式推算。新增的Rust比较入口仅cfg(test)，不影响生产检测/推算/地图。用户截图为Jian Project M4.6/40km/19:18 JST；本机20261125191853的6份JMA EEW前两报24.3N123.0E M4.6/40，最后24.4N122.9E M4.2/10，发震时间19:18:51。以最后本地EEW位置比较，不是独立官方最终目录；GlobalQuake同事件另一档案末次24.27375N122.96468E M4.2486/43.41仅作旁证。
- 本机240保存P-A帧→209独立时间帧、786站、最高PGA5.566665Gal；时间匹配当前站值，未上报/过期视为缺测。旧检出采用原归档detectedStationIds，旧推算为现有Rust Inference重新跑，不宣称逐帧复现原应用所有状态。新检出用默认灵敏度PAlertSrev、10.5s保持（源时间近似接收时间），原SREV HYP仅测试期开启；保留原日本HYP速度模型/范围/接受逻辑与台湾独立站目录。5场旧样本共1017帧的确认站集合与此前HYP关闭版逐帧一致。
- 与那国岛最佳/最大/末次水平偏差km：旧检出+旧HYP 69.4/905.7/602.5；新检出+旧HYP 78.1/246.2/187.9；新检出+SREV HYP 27.6/162.5/158.6。旧HYP第50秒23.8N131.8E、M7.2917、发震时刻相对首帧-201.959秒、8有效站、D级，说明绝不能仅凭低残差发布。新SREV第44秒24.58333N123.08333E深10/M4.8655、10当前确认关联站；第70秒偏回台湾，8当前确认关联站，故只加最低站数门槛不足；第86秒无当前关联站仍更新，M0；末次第165秒23.76667N121.5E深10/M0。第31秒初解无确认关联站，不能直接发布。
- 六场共1226帧同一测试运行exit0，57.18s Debug总耗时（非实时性能）；输出旧/新检出+旧HYP选中主源、原SREV所有有效槽估计（不同统计口径，需注意多槽）。末次水平偏差km：
  1150076 3.3/17.4/19.3；1150077 10.1/1.5/16.3；1150080 304.5/34.7/125.4；1150085旧未输出/60.7/27.5；1150086 85.6/18.1/12.6；与那国岛602.5/187.9/158.6。SREV 599个估计槽帧中364个与P-A保持确认站无交集。新检出改善部分旧推算，但并不普遍；新HYP也非总优。
- 固定SREV几何的P-A旧PGA震级公式离线候选：按当前同槽确认关联站保存事件内真实PGA峰值，至少5站，旧taiwan_pga_attenuation_inverse_median_v1按各站震源距反算M取中位数；不是原生产峰值归属的逐值等价移植。与那国岛第44秒M4.542/21站（原SREV4.866）；第86秒M4.575/58站（原SREV0）；末次M4.127（位置已错误，不代表正确震级）。不能以震级接近参考掩盖定位偏差。峰值归属须与关联一致，PGV/强震/站点修正待验证。
- 下一步优先：检测许可与HYP有效到时分离，按真实PGA变化与实际不规则采样间隔回溯起跳，保留测站时间不确定度；以当前确认关联及地理覆盖、独立有效到时/残差/时间可行性作发布门，冻结缺乏新证据的结果，禁止旧事件吸收不相干后续簇；研究离岸/单侧台网的深度和距离退化、多解与合理走时边界，不将震源硬限制台湾陆地。台湾专用走时/衰减需独立校准，现有SREV JMA2001未直接验证台湾。新候选必须在六场及独立静默/新回放上验证，不能只按与那国单场调参。继续沿用普通UI隐藏算法名。P-A保持推算禁用，不打包。
- 输出目录tmp/srev_nied_migration_20261125/：palert_yonaguni_input.json、palert_yonaguni_event_reference.json、palert_yonaguni_hyp_audit.json/summary.json、palert_yonaguni_fixed_geometry_magnitude.json、palert_hyp_six_event_input.json/audit.json/summary.json。新增测试station_runtime::palert_hyp_audit::compare_taiwan_hyp_on_archived_event，环境RQ_PALERT_HYP_AUDIT_INPUT/OUTPUT。


## P-Alert低成本发布门控与固定几何震级研究
- 仅离线后处理现有六场1226帧，13策略×6=78组、15938帧次，不重跑HYP，不修改生产代码。脚本audit_palert_hyp_fast_gates.py、audit_palert_hyp_gate_sensitivity.py，输出palert_hyp_fast_gate_audit.json、palert_hyp_fast_gate_sensitivity.json，均在tmp/srev_nied_migration_20261125/。门控不使用事件参考真值；以下参考仍为保存报文，而非独立官方最终目录。候选选择使用同一批6场，无独立验证。
- 原始599个有效槽估计帧，其中374个与保持确认站无交集（更正上一节364的笔误）；未全部是实际接受的新报。门控只发布hyp_state=updating且accepted_at不同于已发布值的结果，不以帧数当报数。
- 低成本候选：当前帧同槽关联且空间确认站>=5；后续报相较上一发布累计至少3个新确认关联站（累计集合，不等于新独立有效到时）；如果该槽超过10秒不满足5站则冻结，拒绝同槽后续发布；不更改检出及SREV内部接受规则。事件内PGA峰值仅取当前同槽确认站，至少5站按原台湾PGA衰减反算各站震级中位数；用门控最后一次发布时的几何与峰值计算，不继续在冻结后改变显示。事件开始/结束及槽消失仍需生产投影单测；新事件不能继承峰值。
- 六场末次水平偏差km（原SREV→候选）：1150076 19.3→17.8；1150077 16.3→11.3；1150080 125.4→44.6；1150085 27.5→23.8；1150086 12.6→12.6；与那国岛158.6→44.9。六场平均末次59.96→25.86km，候选90次发布、无零保持支持发布，全部有结果。但最大偏差仍197.18km（1150086），未解决初解/单侧台网。
- 分项平均末次km：held5 42.62、fresh5 41.85、fresh5_new3 42.13、fresh5_gap10 28.89、fresh5_new3_gap10 25.86。6秒冻结会过早停止与那国岛（仅1次报、83.4km），15秒允许错误后续簇重入（136.7km）；10秒并非确定最终参数。发震时刻变化限制8秒会锁死1150086错误初解（末次167.4km），不采用。累计新3站规则也可能阻止同站新到时驱动的正常修正。
- 候选末次固定几何PGA M（按76/77/80/85/86/与那国）4.23/3.84/4.84/3.84/4.99/4.77，原SREV同帧2.51/2.01/3.01/5.01/2.56/3.46；PGA不再随当前震动衰减至0，但不能保证更准确，特别台东北外海偏低、与那国偏高；峰值归属和场地修正待验证。下一步优先独立有效到时及关联，10秒门控仅作为shadow候选，不上线或打包。P-A sourceEstimationAvailable仍false。


## P-Alert 已验证低成本候选 Rust 接入
- 新增 native/station_core/src/palert_hyp_gate.rs（HypGate）：独立槽ID+start身份、当前确认且有效关联站>=5、相较上一报累计>=3个新成员、支持不足>10s冻结；仅新SREV接受时刻发布，报号每次有效发布递增。事件PGA峰值限同槽当前确认站、至少5个有效峰值采用既有台湾PGA反演中位数；冻结后固定最后发布几何/震级/报号，槽消失清除显示并保留冻结身份，reset清空。有限数值、时间重复及目录索引保护。没有改动原HYP、检出或NIED。
- lib.rs注册模块，palert_srev.rs 增加可选HypGate并在真实观测处理后执行；palert_state.rs 配置及测试JSON投影，station_runtime.rs 显式 testing=true + palertHypShadow=true + palertDetection=srev 进入候选链路。普通运行不启用HYP，不额外计算；候选只出现在测试JSON字段palertHypShadow，不接入正式推算UI。PAlertService.sourceEstimationAvailable仍false。未改变旧推算开关或已验证正式检出。
- Rust Debug两项测试exit0：lifecycle_and_peaks 验证报数、重复帧、冻结、槽复用、清理；saved_six_event_gate_matches_reference 对已有1226帧逐帧输出90报（按1150076/77/80/85/86/与那国岛为26/9/31/7/12/5），经纬度深度、发震时刻、接受时间、PGA震级误差<1e-8，支持站及峰值站数完全一致。各场gate P95 43~971us（仅候选模块Debug，非整链实时性能）。输出palert_hyp_gate_rust_parity.json。此前选择同一批样本，非独立验证。
- 实际原生输入路径 station_runtime::palert_hyp_audit::palert_shadow_raw_runtime_parity exit0：用与那国岛209帧PGA、786站重建报文，普通与shadow双运行，逐帧确认站和检测网格完全相同；候选5报全部与参考JSON一致，reset清除，非testing参数不激活。运行87.45s（Debug双实例+完整JSON序列化测试，非实时性能）。未重新编译Release/打包/安装，未关闭当前APP。
- 仍需到时提取与测站关联实验，尤其M5.6错误初解和海域退化。门控冻结时间及新增站数为候选策略；不是SREV原版接受规则。测试期保留冻结身份，长期内存管理、强震、多事件及实时性能未验证，不能上线。下一轮优先研究真实PGA起跳时间和不规则采样。


## P-Alert 有效到时初步研究（低成本离线）
- 用户要求继续下一步。读现有palert_inference.rs Pick::update：8个历史采样、排除最近一帧后的历史最大PGA作为背景，两帧>=1.5倍或单次>=2倍（并含KA>=6条件），单站采样间隔>6秒重置。原真实档案1226帧，间隔1~15秒，不应等同秒级连续波形。
- 新脚本tmp/srev_nied_migration_20261125/audit_palert_arrivals.py，保留六场原始观测、原SREV槽成员、P-A空间确认以及此前90次候选发布时刻不变；仅因果回看12秒内真实观测，起跳区间为相邻低值及升高值的真实时间，最大区间6秒，不凭空补帧。候选至少4个历史有效观测、90秒背景25%或50%分位×2/3及0.25/0.44/0.59 Gal绝对下限；连续升高或单次显著跳升（>=max(0.59,1.8*threshold)），须同槽当前空间确认才纳入，按槽保存首次提取。无前置安静观测/长缺测不当成精确到时。old_like仅为离线八样本最大背景阈值对照，不等价旧Rust Pick的完整状态、过期与触发保持。
- 6策略×6事件，原1226帧、90报时刻；输出palert_arrival_audit.json。最后一报累计区间数按old_like/q25_3x/q25_2x_059：1150076 160/173/126，1150077 136/166/116，1150080 216/262/259，1150085 1/18/20，1150086 201/250/218，与那国岛21/31/18。合计735/900/757；末报>=5到时的事件5/6/6。区间中值宽1~3秒，非到时精度保证。q25_3x首个已验证发布时刻中>=5区间相对回放首帧为9/15/5/6/13/33秒；old_like为9/23/10/无/13/43秒；严格0.59为9/20/5/6/17/43秒。原门控首报为9/12/1/1/13/33秒。上述均只在既有报时刻检查，不等同独立实时首报延迟；部分样本左截断。
- 使用已有Rust hyp_travel_tables.rs JMA2001 P/S表，离线粗网格21..26N、119..124E、0.1度，深度10/20/40/60/100km，自由发震时刻（中位数），区间外Huber残差诊断拟合；分别假定全P或全S，不表示已识别相位，也不改变SREV HYP。参考保存EEW最终坐标（非独立官方最终目录），不参与拟合。末报六场均值q25_3x P32.82/S35.95km、q25_2x_059 P31.67/S26.63km；旧式仅5场P41.77/S51.06km，分母不同不能直接当改进百分比。配对同站残差检查未普遍改善，尤其低门槛更易混入噪声。台东M5.6末报严格候选P/S相对时差MAD4.47/2.04s，旧式5.27/2.76s（不同站集）；同站182站P7.18→4.61、S2.92→1.98。与那国岛旧式末报P32.3/S112.0km，q25_3x P37.6/S111.4，严格P42/S42；不要用事后挑选相位声称提升。
- 追加audit_palert_arrival_first_fit.py与palert_arrival_first_fit.json，17个首个>=5区间的既有报时刻×P/S诊断。q25_3x台东M5.6第13秒既有90.1km，诊断P35.2/S40.1；与那国第33秒83.4→P64.7/S61.7；台东北外海M4.7第6秒既有19.3→P273.7/S274.4（退化/边界）。严格0.59在M5.6第17秒既有97.7→P294.3/S280.0。初解可能明显恶化，不采用到时数单门控或直接替换现有HYP。诊断域有限，不是生产定位性能。
- 建议下一轮：按相邻站差分时间、允许P/S不确定和起跳区间宽度给证据权重，验证几何覆盖和多解，先对候选关联及早期异常点作剔除；再考虑Rust独立到时提取器/实际SREV输入对照。前一轮HypGate/PGA峰值候选保持不动，正式P-A推算关闭。此次只新增离线研究脚本和JSON、本文档，无生产代码改动、无编译打包/APP操作。同批6场筛选，无独立验证。


## P-Alert 走时模型独立审计
- 用户要求先研究走时。SREV vendor/generated.rs p24 使用 state.json lists[21] 的1704系数（4组×71深度×6阶：P/S时间→震源距、P/S震源距→时间）；p42输入sqrt(震中距²+深度²)，深度四舍五入至10km，正反独立拟合。RQ native/hyp_geometry.rs 的travel_pair为JMA2001双线性表插值；native/hyp_travel_tables.rs 的106深度、236距离、各25016个P/S值与assets/travel_times.json jma2001逐值相同。APP资源只有jma2001（0..700km深度、0..2000km震中距）及jb远距离表，未发现台湾表。不同实现不等于不同地质模型。
- 台湾候选的公开来源：Kim et al. (2005), Table 1, historical CWB model modified from Chen (1995), https://doi.org/10.1186/BF03351860 ，表数字核对 https://www.academia.edu/127305794/Earthquake_relocations_fault_zone_geometry_and_constraints_on_lateral_velocity_variations_using_the_joint_hypocenter_determination_method_in_the_Taiwan_area ；0/2/4/9/13/17/25/30/35/50/70/90km层顶，Vp=3.48/4.48/5.25/5.83/6.21/6.41/6.83/7.29/7.77/8.05/8.16/8.34，Vp/Vs=1.73。Wu et al. (2007) Table 1 https://doi.org/10.1029/2007JB004983 为VELEST一维初始参考模型，18个深度及Vp/Vs见脚本；不是现行CWA生产模型。CWA近年研究使用台湾3D速度模型，但不能据此判断现行业务定位实现。3D模型平台 https://tecdc.earth.sinica.edu.tw/TWtomo/ ，观测相位/波形目录入口 https://gdms.cwa.gov.tw/eqDownload.php 及 https://tecdc.earth.sinica.edu.tw/waveform.php ，未获取独立人工相位真值。
- 新增离线脚本tmp/srev_nied_migration_20261125/audit_palert_travel_models.py，台湾模型按层顶常速、平面层状、地表接收、直接上行射线水平慢度二分与更深高速界面临界折射首波最小值。Kim最后90km层延伸（非论文另有更深速度数据），不做3D、地形、地球曲率、场地修正。生成13个深度0/5/10/20/30/40/50/60/70/90/100/150/200km、801个整数震中距0..800km的P/S表，各模型20826值。均匀介质解析解、两层垂直走时解析解校验通过；有限、非负、距离单调通过。palert_taiwan_travel_candidate.json及palert_travel_model_samples.json。不是官方表，不接入生产。
- 10km深度、100km震中距，SREV P16.90/S28.93s，RQ JMA表17.04/29.05s，Kim CWB17.77/30.74s，Wu18.05/31.33s；50km处台湾S波比SREV慢约1.6~1.8s。SREV正反近似数值往返测试，10/20/40/60/100/200/400/700km深度，0..500km每1km×P/S；palert_srev_travel_roundtrip.json（近距离反解小于深度时以0半径表示，仅诊断，不修改原代码）。各组P95<1.54km，最坏6.33km以内，10..100km深度最坏6km；未见该距离范围正向时间非单调。不能解释百公里级定位失常。
- 仅改变走时的A/B：复用上轮q25_3x同槽确认起跳区间，六场每场首个>=5区间的已有报及末报共12个快照，四走时×两种全P/全S假设共96组；同一0.1度网格21..26N、119..124E，深度10/20/40/60/100km，发震时刻取中位数、区间外Huber损失。无使用参考坐标作为拟合先验，参考仍为本地末次EEW。结果palert_travel_model_ab.json。首快照水平误差均值P/S km：SREV78.90/80.23，RQ77.19/78.57，Kim77.19/78.57，Wu76.82/76.92；末快照SREV30.33/36.59，RQ32.82/35.95，Kim36.01/36.92，Wu33.26/37.67。末报固定参考几何相对起跳时间MAD跨事件中位数P/S秒SREV1.506/1.945、RQ1.565/1.780、Kim1.627/1.552、Wu1.592/1.642；S波参考残差改善不等价定位改善。与那国末快照P/S SREV37.6/111.4km，Kim37.6/111.4，Wu46.2/111.4；首快照Wu61.7/51.8 vs SREV74.2/71.7。台东北外海首快照所有模型约274km误差，换走时不能解决。此为独立粗网格诊断，不是原SREV HYP替换后的真实回放性能；PGA起跳区间并非人工P/S相位，样本少且同批筛选，局部模型差异未充分验证。
- 建议暂保留现有JMA候选，下一步取得CWA/TECDC实际P/S相位或波形，固定已知震源检验台湾模型真正走时残差；有独立优势后考虑只对P-A接入可选走时，正向和反向应来自同一表并复核关联、波圈及估计。此次只新增实验文件/文档，未改生产、未启用推算、未编译打包或操作APP。

## 追加：CWA Benchmark 实际人工相位独立走时初测（2026-11-25）

- 已核对上节走时结果已存在；本轮仅追加离线研究，不更改生产代码、NIED、P-A推算开关、UI或打包。
- 数据来源 Tang et al. (2024), The CWA Benchmark: A Seismic Dataset from Taiwan for Seismic Research, DOI 10.1785/0220230393；公开元数据 https://huggingface.co/datasets/NLPLabNTUST/Merged-CWA/resolve/main/sample.csv 。CWA GDMS官方目录 https://gdms.cwa.gov.tw/catalogDownload.php 与事件数据 https://gdms.cwa.gov.tw/eqDownload.php 另作后续来源。另找到台湾3D P波模型及实测本地P到时 https://doi.org/10.5281/zenodo.21194749 （尚未下载或测试）。
- 实际HTTP下载20秒超时，仅收到81920/2236219 bytes，保留原始前缀，SHA256 da321a755fed9940aa874c766166dbc7df337ab9ce8151b790ac55bf030a9402；镜像TLS证书吊销检查失败，未关闭验证。仅解析完整换行记录214条，非随机样本、仅2011年。筛选人工标记manual/maunal、采样点与波形起始时间相符（<=0.05秒）、坐标计算震中距与目录差<=3km、深度0..200km、震中距0..500km、有效正到时及事件/站/相位去重后198到时（P99/S99，11事件、77站）。权重0/1子集P80/S57；其中深度<=30km且震中距<=100km P52/S44。未将weight 0/1 或 completeness=4 当无误差真值；同一目录可能使用相同相位定位，非独立真实震源。
- 用原SREV p24系数、RQ JMA2001表、前轮Kim/Wu候选表在固定目录震源计算；距离由经纬度重算，地表接收不修正测站高程。实际到时减source_origin_time与path_*_travel_s存在事件相关常数偏移：11事件中位差0.08..0.655秒，事件内极差<=0.015秒；其由来未查清。两口径分别统计，禁止选择更有利的口径作为最终结论。
- 权重0/1子集MAE（秒，顺序SREV/RQ/Kim/Wu）：直接时间戳P 0.918/0.927/0.982/0.980，S 1.141/1.165/1.387/1.419；path字段P 1.154/1.176/0.909/0.902，S 1.374/1.424/1.182/1.199。浅源近距直接时间戳P 0.514/0.521/0.643/0.641，S 0.581/0.607/0.914/0.949；path P 0.783/0.807/0.486/0.494，S 0.841/0.896/0.642/0.671。
- 去除发震时刻基准影响：同站P/S均权重0/1共57对、10事件，S-P到时差MAE 0.382/0.387/0.445/0.481秒（path口径0.381/0.387/0.445/0.480）；每事件每相位>=3站，减各自残差中位数后P73条MAE 0.888/0.887/0.877/0.875秒，S50条1.059/1.058/1.070/1.077秒。台湾一维模型未显示稳定相对走时优势，暂保留SREV；本轮仅小规模初筛，不能排除完整样本或3D模型有优势，也不能当P-Alert定位回放结果。
- 文件均位于tmp/srev_nied_migration_20261125/：cwa_benchmark_sample.csv（部分下载，不作为完整数据）、audit_palert_cwa_phase.py、audit_palert_cwa_phase_differential.py、palert_cwa_phase_audit.json、palert_cwa_phase_picks.json。两脚本实际运行exit0。下一步补全样本（校验大小及哈希、检查时间基准定义）、按事件及区域分层，另测试3D模型及其P波到时，才讨论生产替换。


## 追加：CWA Benchmark 完整公开 sample.csv 扩样及分层验证（2026-11-25）

- 完整下载 https://huggingface.co/datasets/NLPLabNTUST/Merged-CWA/resolve/main/sample.csv?download=true ，HTTP成功，2236219 bytes，5882条数据记录，与 datasets-server test split 总行数一致；本地SHA256 5b774aaeeec9a0e8ca826700dfe7ba76de22407d5b3fc0832a57d2d73b878551（计算留档，并非与发布者独立哈希核验）。另取14页分页接口记录并校验row_idx，完整CSV成功后未将分页数据重复计入。公开sample.csv完整不等于整个CWA Benchmark；实际本次筛选数据全部为2011年，并未覆盖2012—2021。先前80KB前缀实验保留。
- 延用上轮原始人工相位、波形采样时间一致性、震中距核对、深度及距离范围、事件/测站/相位去重过滤条件；实际有效6890条P/S到时，720事件，467站。权重0/1子集5474到时（P2965/S2509），701事件；同站同事件P/S配对2490组，665事件。固定目录震源，仍未修正测站高程，不宣称独立真实震源。
- 四模型固定震源直接时间戳MAE（秒，顺序SREV/RQ/Kim/Wu）：P 0.863/0.868/0.935/0.935，S 1.134/1.154/1.223/1.250；path字段P 1.095/1.116/0.882/0.887，S 1.361/1.405/1.116/1.134。两口径排名反转依旧；中位path减timestamp偏移P0.355/S0.365s。
- 消除发震时刻偏移：同站S-P MAE 0.4462/0.4621/0.4350/0.4560秒；每事件等权MAE 0.3934/0.4083/0.4016/0.4192秒；中位绝对误差0.3168/0.3242/0.3899/0.4106秒。按事件为聚类单元固定seed20261125、2000次bootstrap，事件等权MAE差（候选减SREV）及95%分位区间：RQ +0.01482 [0.01166,0.01801]，Kim +0.00816 [-0.01756,0.03292]，Wu +0.02577 [-0.00152,0.05375]。不能以逐站加权的Kim小幅改善宣布整体优胜。
- S-P分层表（秒，按SREV/RQ/Kim/Wu）：
| 分组 | 配对 | SREV | RQ | Kim CWB | Wu2007 |
|---|---:|---:|---:|---:|---:|
| 全部 |2490|0.4462|0.4621|0.4350|0.4560|
| 深度<=30km |2107|0.4325|0.4480|0.4405|0.4635|
| 深度>30km |383|0.5215|0.5394|0.4048|0.4148|
| 距离<=50km |2295|0.4429|0.4597|0.4329|0.4504|
| 50<距离<=100km |193|0.4821|0.4882|0.4591|0.5235|
| 距离>100km |2|0.7590|0.7439|0.4530|0.4365|
| 震源经度>=122E |46|0.3290|0.3404|0.4869|0.5344|
| 震源经度<122E |2444|0.4484|0.4644|0.4340|0.4546|
- 深度>30km有41个配对事件，等事件权MAE 0.4717/0.4918/0.3436/0.3413；台湾候选在该子集值得进一步独立验证，但不能在推算过程中按不稳定估计深度直接切换。浅源624个配对事件的等事件权MAE 0.3883/0.4028/0.4054/0.4243。经度>=122E仅13个配对事件，且经度阈值不是海陆掩膜，不作为真实海域分组。>100km仅2对；现有公开样本以近距为主，不足以判断与那国岛/远海。尚未验证深度选择规则及生产定位。
- 同事件同相位>=3站，扣除残差中位数的相对走时MAE：P 0.7982/0.7975/0.7955/0.7961，S 0.8993/0.8983/0.9075/0.9152。各模型相对P波走时几乎相同，S波仍未见台湾一维整体优势；结合6场P-A回放实验不支持直接替换。
- 三维候选：TECDC模型列表 https://tecdc.earth.sinica.edu.tw/TWtomo/php/getModelOption.php 已核验，包括针对台湾东北外海的Wu2009 Vp/Vs（DOI 10.1111/j.1365-246X.2009.04180.x）、Huang2014及Lee2025 Vp/Vs。尝试列表相对路径拼成 /TWtomo/download/WU2009.txt 实际返回404 HTML（196 bytes，不是模型，未参与实验）；需查真实下载入口。另核实 Su et al. 2026 Zenodo 21194749 数据清单包含evt.lis、sta.lis、18.5MB本地P到时与2.5MB 3D Vp模型，可作下一轮研究，但模型训练数据不能称独立验证；本轮未计算3D走时。
- 新增实验目录文件：cwa_benchmark_full_download.csv、cwa_benchmark_expanded.csv、fetch_cwa_sample_pages.py、cwa_hf_rows_*.json、audit_palert_cwa_expanded.py、palert_cwa_expanded_audit.json、palert_cwa_expanded_picks.json。扩样脚本实际执行exit0，完整输入哈希另用Get-FileHash复核一致。本轮只新增离线实验和追加本文档，未修改生产、未开启P-A推算、未改NIED、未编译打包。后续优先取得海域/远距足量真实相位及三维Vp/Vs模型，固定路径与独立事件检验。


## 追加：P-Alert 校园单站冲击与无固定 PGA 门槛检出研究（2026-11-25）

- 用户指出P-A测站多在学校，局部人为踹碰可能造成很强的单站振动，不能把所有低于0.8Gal的观测认作噪声；要求测试且不使用固定PGA振幅门槛。本轮仅离线研究，未修改生产Rust、未启用正式推算、未编译打包。
- 复查正式原生路径 palert_native_runtime.dart 选择srev；palert_srev.rs 自适应噪声背景为过去90秒PGA的25%分位×3，限制0.25..1.4Gal，不满10样本0.59Gal；输入SREV许可后要求30km内3站（低灵敏度4站）同帧过门槛并连续2个真实帧、间隔<=6秒及局部簇重合。P-A推算发布另有5站门，不能混同检出。前一轮分解脚本audit_palert_detection_bottleneck.py、结果palert_detection_bottleneck_audit.json：与那国回放第19秒首次至少3站过自适应门槛形成空间簇，第33秒才出现连续帧确认；不能把14秒全归因于SREV许可。六场当前确认时间按1150080/85/77/86/76/与那国分别1/1/12/13/9/33秒（相对回放首帧；非发震时刻）。
- 实验输入沿用palert_hyp_six_event_input.json（六场1226帧）及palert_background_windows.json（四段真实背景666帧，非独立官方静默真值）。对背景副本注入26次模拟单站冲击：每隔24个采样选择当时有效且30km邻站最多的一站，幅值乘10/100/1000，持续1..3个报文帧，保留缺测，不修改原始档案。模拟并非实录踹碰，不代表所有校园干扰；重复选择密集站，不保证26个不同测站。
- 第一轮audit_palert_adaptive_onsets.py共32策略；因果过去90秒中位数或75%分位、相对倍率2/3/4/5、最少3/5历史、4/6秒起跳窗口；30km内三站两两相邻，至少一站新起跳。无固定Gal阈值，零/未知背景不计算倍率；缺测不补帧。取中位数/最少3历史/4秒窗口，倍率2/3/5分别六场全部触发，背景触发108/3/0帧、冲击背景触发127/7/0帧，与那国首触发9/19/43秒。单靠降低倍率导致背景触发。第一次运行末尾JSON序列化numpy int64失败，修正后完整重跑exit0，输出palert_adaptive_onset_audit.json。
- 第二轮audit_palert_adaptive_corroboration.py共36策略，背景中位数、最少3历史，弱起跳倍率2.5/3、强起跳4/5、4/6秒、三站中两站强证据/两站连续观测/强+连续证据/局部四站替代；排除<=0.05km的近同址配对。候选3.0/4.0/4/2persist_or4：4秒内至少三站起跳且三站两两距离<=30km，其中至少两站有连续异常观测证据，或中心邻域有至少四站且包含三站三角形（第四站不要求与全部三站两两<=30km）。强倍率4仅用于触发重新评估，不是固定Gal或必要发布门槛。六场首触发按1150080/85/77/86/76/与那国为3/4/10/10/8/32秒；4场更早、2场延后（这2场回放左截断且已有震动，冷启动缺背景）。四段背景及26次模拟冲击的背景副本均零触发帧，六场末60秒零触发帧；不是独立误报率。低倍率2.5的同规则可使与那国提前至19秒但背景3帧/冲击背景4帧/尾段1帧，暂不采用。输出palert_adaptive_onset_corroboration.json，脚本exit0。
- 第三轮audit_palert_adaptive_scale.py，选定候选在六场各整体幅值乘0.01/0.1/10，逐帧触发时刻与输出成员完全一致，共18组等价验证通过，输出palert_adaptive_scale_parity.json；这是数值尺度不变性测试，不是现实地震振幅衰减模拟。实际与那国第32秒输出6个参与成员，当前PGA 0.483198/0.606931/0.229563/0.599135/0.541824/0.892331Gal，其中5站低于0.8Gal；台东南M5.6首触发4成员0.29551/0.657836/0.889363/0.537902Gal。输出成员是确认三角形并集，不一定完整列出第四站证据。证明候选允许低于旧门槛的真实观测参与，不能因此称为已识别P相位。
- 仍有不足：当前候选只产生诊断触发帧，未实现稳定事件生命周期、冻结已确认震动背景、明确起跳区间、持续高噪站降权及P/S传播一致性；3样本冷启动、背景窗口混入震动、固定相对倍率与30km邻域都仍需校准。四段背景和六事件用于策略选择，非独立验证；模拟冲击不等于真实校园冲击数据。下一步优先提取单站起跳证据及持续噪声的动态可靠性、保留先后到时，针对与那国第19..32秒的3站簇逐站查证，并在独立背景及弱震样本上验证后再考虑Rust候选链路。所有新增脚本和JSON在tmp/srev_nied_migration_20261125/，原始输入不变。


## 追加：2026-11-26 早间 P-Alert 真实背景采集（UTC+8）

- 用户观察：P-A白天常有震度0图标，偶尔1～2个测站因校园局部干扰突然升高；要求不以固定Gal区分地震/噪声。显示规则复查：KA level6/7对应0.44<=PGA<0.8Gal的震度0数字（需开启displayShindo0、zoom>=4），level8起对应震度1；显示保持3秒，不能把瞬时PGA分布直接等同于UI实际图标分布。
- 直接复用正式公开GraphQL接口 https://palert.earth.sinica.edu.tw/graphql/ ，stationList(onlineAll) 与 realtimePGA(recordTime=0, token='', type0/1)，约1秒轮询，保存原始PGA/PGV、源时间及本地接收时间、目录，按源PGA时间去重，无插值。独立离线采集，不启动/修改APP、不改变生产检测。样本只能称背景候选，尚未逐时与官方地震目录核验。
- 第一批源时间UTC+8 08:19:54–08:20:29，35独立帧、786目录站、713实际观测站、24859有效PGA值，0请求错误/0重复响应；瞬时PGA<0.44有24836，0.44<=PGA<0.8有21，>=0.8有2，中位0.171131Gal；3秒保持诊断（只统计当帧有效站）震度0图标站数中位2/最大6，>=1档最大1。未观察到大量震度0，不能代表整个白天。
- S01C 在08:20:27/29分别为1.797113/0.827763Gal，35帧中位0.360339；08:20:27时最近S019约0.136km、PGA0.171，附近12站未同步明显上升且全网其余站无>=0.8，作为真实孤立干扰候选，具体原因不明（不可标为已证实踹碰）。候选3.0/4.0/4/2persist_or4、2.5/4.0/4/2persist_or4、3.0/4.0/4/2persist均0触发帧；短窗口不构成长期误报验证。
- 第一批文件 tmp/srev_nied_migration_20261125/palert_morning_20261126_0819/{metadata.json,raw_frames.jsonl,manifest.json,summary.json,diagnostic.json}，原始报文SHA256 499968387ad70e6e6e83b2df49916e09e20004ad834147c5f8c651420f4805af。脚本 collect_palert_morning.py、summarize_palert_morning.py、check_palert_morning.py 实际运行；数据保持在实验目录。


- 第二批源时间UTC+8 08:20:52–08:22:31，跨99秒、96独立帧，786目录站/712观测站/68200有效PGA值，0请求错误/1重复响应已去重；瞬时PGA<0.44有68140、0.44<=PGA<0.8有52、>=0.8有8，中位0.170081Gal。3秒保持诊断震度0站数中位2/最大4，>=1最大2。S018/W102/S01C/W177/W164峰值分别1.961425/1.731892/1.723219/1.071461/1.036826Gal。三种自适应候选仍均0触发帧。第二批目录 palert_morning_20261126_0821/，原始报文SHA256 7ec4caef8195c3b95ae9d69f019671581fe74909d188faec6e756dee6dbc25fe。
- 两批共131独立帧、93059有效PGA观测（不连续，中间23秒源时刻差，不能拼接为连续背景历史），原始数据分别保存。export_palert_morning_windows.py 导出兼容既有背景回放的 palert_morning_noise_windows_20261126.json（1769480 bytes，SHA256 42d34cecf2bd204fed0f046480620b9a3f54a2baee38fb289c5c61d24a252ab0），保留两个独立窗口，不插值。第二批采集、统计、候选回放、导出均exit0。当前样本仍短、并非全天或大量震度0的高背景情形；未验证具体校园干扰成因，未修改生产代码。


## 追加：以2026-11-26早间真实背景为基准的P-A快速起跳关联优化

- 用户确认早间背景记忆有误，要求先以真实采集为基准，午间再采。继续保持无固定Gal振幅门槛。使用六场1226帧回放、原四段666帧背景加早间两段131帧，共797背景帧。早间数据此前未用于原候选参数选择，但本轮已纳入筛选，不能再当作独立验证集。
- 与那国事件第19秒：W032/W03E/W048当前PGA分别0.421/0.420/0.543Gal，各站过去背景中位约0.122/0.123/0.126Gal；三站间距2.41/15.08/14.17km，起跳接近，W048先一帧。原候选要求连续震动确认，直到32秒才触发；现行SREV回放33秒。原始PGA与诊断背景保留；未将起跳当作已识别P波。脚本inspect_palert_early_20261126.py。
- audit_palert_early_coherence.py扫描36种策略：背景中位数、相对倍率2.5/3/3.5、最少3历史样本、1/2/4秒起跳窗口、2或3站最近1秒内起跳、三站当前均过相对门槛或允许一站衰减，三站间距0.05..30km。六段背景分别模拟39组单站冲击和39组双站冲击（选密集站及其最近有效邻站，倍率10/100/1000，1..3帧，同步或间隔一帧，原始数据不改）。3.0/2/2/same 六场首触发3/4/10/10/8/19秒；真实背景0、单站冲击0、双站冲击6触发帧、尾段1帧，不能直接作为正式确认。输出palert_early_coherence_20261126.json，exit0。
- audit_palert_balanced_coherence.py增加三站相对各自背景的增幅均衡条件（只约束比值最大/最小，不使用固定Gal），八组扫描。建议早期候选3.0/2/2/2.0：每站当前PGA>=自身过去90秒中位数3倍，三站均在当前有效帧且起跳年龄<=2秒，其中至少2站最近1秒起跳，三站两两0.05..30km，三站相对增幅最大值不超过最小值2倍。六场首触发3/4/10/10/8/19秒；较现行1/1/12/13/9/33秒，四场提前2/3/1/14秒，两场冷启动延后2/3秒。六段真实背景0触发、39组单站及39组双站模拟冲击均0触发帧，地震末60秒仍有1触发帧。相对倍率2.5及均衡上限1.5/3在本数据上也有近似表现，不表示最优参数。第一次脚本因复用源码截断SyntaxError，修正rsplit后完整重跑exit0，输出palert_balanced_coherence_20261126.json。
- 建议仅作为内部早期候选，需独立事件/午间背景、更多随机位置和弱幅双站冲击、强震振幅不均情况、事件去重/结束生命周期、连续观测缺测及P/S一致性验证。均衡分支可能不适用近源振幅梯度强的事件，保留其他证据分支，不用作否定地震的硬规则。本次未将其接入Rust/HYP、未验证新首报实际定位精度或运行耗时、未编译、未修改生产及NIED。测试统计为触发帧，不等同实际误报率；模拟冲击不代表真实学校噪声。所有脚本及JSON留在tmp/srev_nied_migration_20261125/。


## 追加：P-A早期三站检出接入离线定位及误差原因审计（2026-11-26）

- 用户同意验证提前检出后的实际定位。只做离线诊断，不改正式Rust检出、HYP、NIED或UI。新脚本 audit_palert_early_locator.py 复用已验证的相对增幅均衡检测3.0/2/2/2.0；六场原始历史回放不修改；参考位置沿用palert_hyp_six_event_summary.json，不作为独立官方最终震源真值。原对照为palert_hyp_gate_rust_parity.json保存的SREV影子首报，并非正式P-A生产推算。
- 新候选首帧只接收有真实前一帧、间隔<=6s的起跳区间，后续追加30km内与已有站到时差满足d/2+2s及区间宽度容差的相对起跳，冻结已加入的首次到时。未识别P/S相位。诊断定位沿用RQ JMA2001表、21..26N/119..124E、0.1度网格、深度10/20/40/60/100km，分别全P/全S，自由发震时刻、区间损失与Huber稳健损失。近似等价水平网格点定义为最优代价+0.125以内（诊断容差，非置信区域或概率）；网格存在平局时取第一个最小值，不是可信震中。真实回放执行exit0，输出palert_early_locator_20261126.json，脚本内部计时12.28秒（六场多次离线网格求解合计，非单帧生产耗时）。
- 六场新候选首触发时刻/有效到时数/全P水平误差km/全S水平误差km/既有影子首报时刻与误差km（均相对回放开始）：
  - 1150080：3s/5/91.1/100.8；既有1s/56.8。
  - 1150085：4s/3/304.2/284.3；既有1s/47.9。
  - 1150077：10s/20/15.0/11.2；既有12s/8.7。
  - 1150086：10s/3/66.6/59.5；既有13s/90.1。
  - 1150076：8s/7/10.5/10.5；既有9s/9.9。
  - 20261125191853（与那国）：19s/3/268.6/316.3；既有33s/83.4。
- 与那国第19秒P/S分别694/702个近似等价水平网格点，距任意最优解的最大近似等价半径441.7/486.6km，不能发布单一震中。第29秒首次有5个到时，P/S误差71.8/59.2km、近似等价半径37.7/75.4km；第33秒10个到时却恶化至138.9/159.2km，第39秒13站152.5/218.1km、第59秒15站139.1/187.7km。不能用第29秒的单次改善宣称后续定位稳定。其余事件也有追加站后恶化（1150080 P误差14秒15.2km→43秒100.2km、1150076 P误差9秒3.3km→28秒67.6km）。
- 进一步固定参考震源复查palert_early_locator_geometry_20261126.json（30组诊断）。与那国第19秒三站到时区间W032/W03E=[17,19]秒、W048=[16,17]秒；在参考震源处假定全P/全S的反演发震时刻跨度0.680/0.652秒，区间外平均残差均0，说明早期到时与参考震源相容，但方位缺口353.0度（站方位覆盖约7度），三站几何无法唯一定位。第29秒加入W02D=[26,27]、W040=[27,29]，参考位置P/S发震时刻跨度8.593/7.026秒，区间外残差MAE2.116/1.101秒；第33秒10站方位缺口348.5度，P/S跨度14.592/14.865秒，区间外残差4.458/5.101秒。只能确认后续相对起跳不适合直接当作同一相位到时，原因可能是P/S混杂、重复起跳、阈值延迟、错误关联或参考/走时误差，未独立确定具体波相。
- 结论：提前检出有效，但以所有相对PGA起跳直接求解会造成不可接受的初期不确定性及后续漂移，不能接入生产。下一步应分离早期检出证据与定位用到时证据，保留多解及候选事件，重点验证后续站的首动/相位一致性和几何约束，避免强制全P或全S、站数增加即更新。午间新增噪声作为独立背景验证，正式P-A推算继续关闭。未编译、未打包、未修改生产文件。所有新增诊断文件均位于tmp/srev_nied_migration_20261125/。


## 追加：宜蘭縣近海 M3.7 事件官方 P-A 历史观测补录（2026-11-26）

- 用户截图：2026-11-26 08:43:47 UTC+8，宜蘭縣近海，M3.7、深46km、最大震度1，CWA。此次参考信息来自截图，公开搜索结果尚未找到对应独立官方最终报告坐标，不用于定位精度评价。本机已检查57个回放事件，未找到该次事件记录。
- 官方帮助 https://palert.earth.sinica.edu.tw/help 明确提供过去24小时PGA动态回播。实际验证GraphQL realtimePGA(recordTime=Unix秒, token="", type=0/1)可直接返回指定秒PGA/PGV，非毫秒；2026-11-26 08:44:10测试返回时间完全一致且711站。后续按约1请求/秒补录发震前30秒至后60秒（08:43:17..08:44:47 UTC+8），91/91秒均成功、逐条验证源PGA时间，无失败。目录786站（采集时目录，不保证历史时刻目录完全一致），有效PGA 64754、PGV 64739，未知站ID 0；PGV仅在同源时间时加入标准输入。
- 原始数据目录 tmp/srev_nied_migration_20261125/palert_replay_20261126_084347_M37/ 下metadata.json、raw_frames.jsonl、manifest.json、diagnostic.json；raw_frames.jsonl SHA256 72512d4c1b7b87270ef05e7ec6591ebddf39eab78af53f4ad6b9384103e2a32d。导出与既有六场输入格式兼容的 palert_20261126_m37_input.json（原观测不插值，缺测保留null，baseline为空表示无原APP历史标签）。未生成可直接导入APP的.rqreplay文件。collect_palert_historical_m37.py、diagnose_palert_historical_m37.py实际exit0。
- 不改参数直接验证上一轮均衡候选3.0/2/2/2.0：发震前30秒无触发，首次关联为发震后9秒（08:43:56），成员W02B/W03D/W04A/W473，PGA分别0.774316/0.478796/0.595863/0.482420Gal，全部低于0.8Gal。后续+13/14/15/16/17/18/20/25秒亦有触发帧；并非9个独立事件，尚无事件生命周期验证。先前连续观测候选3.0/4.0/4/2persist_or4在发震前-6/-2秒有2个背景触发帧，发震后同为+9秒首次响应；背景触发性质尚无独立目录确认。S01C发震前多次高振幅（例如-1秒2.84828Gal），+53秒2.973915Gal，均未参与均衡候选；+14/+15秒多站真实响应，W02B/W040分别2.62815/2.635026Gal。新样本支持均衡分支弱震检出且抑制孤立振动；此次仅独立单事件离线候选测试，不能推算长期误检率，未测试正式Rust生产检出及震源推算、未修改生产。


## 追加：P-A检出噪声过滤机制定型候选与随机冲击验证（2026-11-26）

- 用户要求尽量确定噪声过滤机制，不使用固定Gal门槛。现有Rust基线复查：用2026-11-25 22:47构建的本地debug测试二进制rq_station_core-0aaa3b208fc6f998.exe实际执行station_runtime::palert_hyp_audit::compare_taiwan_hyp_on_archived_event，RQ_PALERT_HYP_AUDIT_INPUT指定新M3.7输入，exit0，1项测试通过。现有SREV灵敏度2在发震后14秒7站首次确认，至25秒仍有确认站，发震前30秒0确认；前一轮均衡快速候选+9秒4站（全部低于0.8Gal），快5秒。输出palert_20261126_m37_current_srev_audit.json。该二进制是已有离线审计构建，非重新编译/实装验证；其old=0因输入baseline为空，无旧KA正式标签，不能解释为旧KA漏检。
- 真实噪声例S01C：M3.7发震前30秒PGA中位0.716Gal、90%分位1.285Gal、峰值2.848Gal，发震后9秒1.016Gal，仅为前30秒中位1.42倍。W02B/W03D/W04A/W473在+9秒分别0.774/0.479/0.596/0.482Gal，相对各自前30秒中位6.27/3.74/4.86/3.81倍。此统计使用固定前30秒窗口的普通中位数用于解释，不等同检测实现每帧过去90秒lower中位数。证明绝对振幅并非可靠区分手段。
- audit_palert_noise_mechanism.py：复用六场历史+新M3.7共七场，原四段背景666帧+早间两段131帧+M3.7发震前30帧，共827帧背景候选。七种策略含增幅均衡消融、过去90秒q90动态抑制1.3/1.5/2倍、历史>=3倍中位数的频率降权及组合。各站使用当前帧之前的真实有效观测，无固定Gal。随机seed20261126，在七段背景每段20组单站、20组近邻双站冲击，随机时刻/测站、幅度设为历史中位数3..8倍（中等）或10..1000倍（强），持续1..3个原始帧、双站同步或错开一帧；保留原始缺测，仅重算被注入站历史特征。280组中原均衡规则触发2组（中等单站1、中等双站1），去掉均衡约束触发7组（中等单站1、中等双站2、强双站4）。q90及噪声频率降权没有进一步减少两组，七场首检时刻均不变，故不作为当前必要硬门槛。原均衡两例：20261118183714背景W13B/W424（5.02/5.47倍）及M3.7发震前W29E（4.11倍），随机冲击与其他自然起跳偶合。脚本首次因Windows默认GBK读取UTF8失败，指定UTF8后重跑exit0，输出palert_noise_mechanism_20261126.json，内部15.23秒。
- audit_palert_noise_confirmation.py：保留原三站均衡快速候选：过去90秒中位数（>=3实际历史样本，零/未知背景不计算比值）、当前>=3倍自身背景，三站两两距离>0.05且<=30km，均为当前真实有效观测、2秒内起跳、至少2站最近1秒内起跳且至少1站在当前帧起跳，三站相对增幅最大/最小<=2。只用于内部候选，不等同已确认事件或P/S波相。
- 推荐确认层four：候选当帧至4秒内，要求至少一个额外独立站当前达到相对起跳条件且与原三站中至少两站相距0.05..30km；若当帧确认，额外站起跳在此前2秒内；若后续确认，额外站起跳在候选帧及之后。原三站在确认帧均有真实观测，至少2站仍满足3倍自身背景；额外站无额外绝对PGA阈值、不强制纳入三站增幅均衡比例。若候选到期无证据仅内部取消，不作正式确认。此处实现为逐种子帧确认诊断，尚未实现完整候选去重/持有/超时状态机；不宣称已接入生产。测试four_or_steady允许三站连续两帧仍均衡的替代规则，七场首次确认与four完全相同，未证明收益；仅允许后续新增站的new_four_or_steady延迟明显，暂不采用。
- 复现seed20261126的280组并新增seed20261127的280组，共560组不同随机注入（280单站/280双站、两类强度各半）；这包含前述280组，不重复累计为840。原三站候选触发5组（单站1/280、双站4/280），four、four_or_steady及new_four_or_steady均0/560组触发；7段827真实背景帧均0。四站确认候选七场首时刻3/4/10/12/8/32/39秒（最后M3.7为回放首帧+39秒即发震后9秒）；三站候选3/4/10/10/8/19/39秒；现行基线1/1/12/13/9/33/44秒。与那国内部候选提前14秒，四站确认仅提前1秒；小震四站确认仍提前5秒。前两场旧档案左截断造成冷启动延迟。四站候选对发震后9秒M3.7输出5站（W02B/W03D/W040/W04A/W473），不同于三站均衡候选输出4站。输出palert_noise_confirmation_20261126.json，exit0，内部51.8秒为Python多事件多组合压力测试总耗时，非Rust实时开销。
- 暂定机制：动态单站背景标准化+近邻独立三站时空/增幅均衡作为快速候选+独立第四站确认；不采用固定Gal、静态黑名单或高分位/噪声频率硬否决。仍需午间独立背景、实际多站校园干扰与更弱/稀疏台网事件验证；目前仅七场且参数选择使用这些数据、背景非独立官方静默真值，随机注入非真实人为波形，0/560不能解释为长期零误报；完整状态机、背景冻结、真实站点共址识别、运行时性能、Rust实现和UI端到端均未验证。三站不满足均衡不能作为否定真实地震硬规则，生产替换前需强近震/不均衡分支测试。未修改生产/NIED、未启用正式P-A推算、未编译打包。保留脚本/输出至tmp/srev_nied_migration_20261125/。


## 追加：P-A检出V1暂定冻结及台湾初期定位文献研究（2026-11-26）

- 用户确认暂定检出阈值，冻结上节 audit_palert_noise_confirmation.py 的 seed+four 规则为 P-A 检出研究基线 V1：90秒因果历史lower中位数（至少3个真实有效历史样本）、3倍相对背景、三独立站两两距离>0.05且<=30km、起跳窗口2秒且至少2站在最近1秒/至少1站在当前帧起跳、三站当帧相对增幅最大/最小<=2；确认窗口4秒内额外独立站与三站中至少2站相邻、符合当帧或后续起跳窗口，原三站均有实际观测且至少两站仍过相对条件。不使用固定Gal。严格实现细节以上节及脚本为准。七场/827背景帧/560随机冲击验证已有记录；午间背景独立测试前不重新调参。不等于生产启用，强近震不均衡、冷启动、状态机及性能仍需验证。

### 外部文献与适用性
1. CWA官方强震即时警报说明 https://scweb.cwa.gov.tw/zh-tw/pws/info_d/2 ：采用近震央少数站最初几秒P波，承认外海及测站稀疏地区测报延迟与误差，增加海底站改善覆盖。官方20周年专刊 https://scweb.cwa.gov.tw/zh-tw/page/twenty/83 亦指出板块边缘事件存在东南外海向西北陆地的系统偏移。该统计为自动定位总体，不是当前P-A首报精度。
2. Hsu et al. 2018, Improving Location of Offshore Earthquakes in Earthquake Early Warning System, doi:10.1785/0220170212，https://nckur.lib.ncku.edu.tw/handle/987654321/280481 ：CWB团队利用多个预设外海初始震中并行Geiger迭代，针对陆站初值导致局部最优；60场M3.3..6.0事件平均误差减少约4.9km。核验出版摘要及大学仓储摘要，出版全文入口403，未复现细节。RQ已有全域网格实验，必须区分搜索局部极值与观测欠约束，不预设多初值必然改善。
3. Integration of Machine learning and equal differential time method for enhanced hypocenter localization in earthquake early warning systems: application to dense seismic arrays in Taiwan (2024), https://doi.org/10.1186/s40623-024-02037-0 ：RED-PAN波相+EDT+三维走时预计算；5个P到时，方位缺口>220°时至少10个，研究RMS阈值0.3秒，30秒无新增P到时删除事件。EDT比较测站间到时差，不依赖绝对发震时刻；保留多个可能网格。CWA研究报告 https://scweb.cwa.gov.tw/webdata/PDF/Reports/MOTC-CWB-112-E-06.pdf 后段也介绍该方法，PDF文本可读、截图请求因文件太大失败，以同行评审HTML全文为主。原研究用100Hz原始波形和真实P到时，不得直接照搬0.3秒、5/10站或220°作为PGA生产门槛；与那国19秒参考方位缺口353°仍提示几何欠约束。
4. Automatic hypocenter determination with the IPFx method for the 2018 Hualien earthquake sequence (2022), https://doi.org/10.1007/s44195-022-00018-y ：以贝叶斯粒子滤波结合波相到时与振幅；暂定事件->三站触发开始推算->新增站按距离、邻接Voronoi、起跳顺序及理论到时残差归属。台湾数据噪声较高，将触发邻域30km缩至20km、估计站组50缩至30；第4..6站及第7站以后按不同邻接与残差条件处理。使用连续波形，不能原样移植；对RQ最有价值的是分离检出证据与定位到时证据，按候选源集合评估新站而不是单一最优点硬拒绝。
5. Satriano, Lomax & Zollo (2008), Real-Time Evolutionary Earthquake Location for Seismic Early Warning, https://doi.org/10.1785/0120060159 ，RTLoc https://github.com/claudiodsf/rtloc ：EDT结合已触发/未触发站，逐步缩小源区。Zollo et al. 2021 https://doi.org/10.1029/2020JB020359 加入相对振幅及反方位角。RQ无三分量实时波形，不能使用偏振反方位角，也不能把未达到3倍背景当成未到P波；仅对在线、正常采样、预期信号可观测的站建立弱概率约束，先消融检验防止把海域解错误推回陆地。
6. P-Alert团队 Progress on the earthquake early warning and shakemaps system using low-cost sensors in Taiwan (2022), https://doi.org/10.1186/s40562-022-00251-w ：原系统用Earthworm及原始波形P到时，研究采用12触发站以改善方位覆盖。2012..2022共36场ML>5.5且深度<40km，震中差12.1±9.2km、深度差-3.6±15.9km、报告时间15.5±4.3s（8..23s）；不是PGA/PGV-only初期精度，不与RQ七场直接横比。该文说明设备在学校墙面安装与楼层差异，振幅定位需场址/建筑修正。2024花莲P-Alert研究 https://doi.org/10.1038/s41598-025-97748-z 使用100Hz三分量、Allen P拾取及Pd，初期仍有明显定位不确定性。
7. 数据：P-Alert官方 https://palert.earth.sinica.edu.tw/help 与 TECDC https://tecdc.earth.sinica.edu.tw/waveform.php 提供事件波形资料；历史强震波形用于标定PGA/PGV起跳相对于实际P/S初动的偏差，不等同开放实时原始波形流。CWA GDMS https://gdms.cwa.gov.tw/catalogDownload.php 及产品说明 https://www.cwa.gov.tw/Data/data_catalog/5-1-1.pdf 提供目录/相位初达等。此次未下载新波形或独立目录，未实测资料权限及特定事件可用性。

### 下一轮实验优先级（研究建议，未实施）
A. 保持检出V1、同一走时及回放，先做区间EDT A/B。测站真实观测起跳区间[a,b]，两站差区间[a_i-b_j,b_i-a_j]；预测T_i-T_j落入区间时零区间外残差，超出则稳健罚；按站而非独立站对估计有效样本量，防止一异常站产生大量关联对。全P/全S只作对照，探索P/S/延迟/离群混合假设但防止自由度过多。用已知参考坐标仅评分，不用于实时选解。
B. 新增站先做与多个可行候选的传播一致性及起跳区间残差，保留未归属证据；验证与那国29->33秒恶化，区分相位混杂、重复起跳及关联错误。以同一时刻匹配原方案，报告首报/连续轨迹、深度、候选范围覆盖、误差恶化及运行耗时。
C. 用有效安静站的弱概率证据、地理/历史震源先验（严格训练/验证分离）及振幅比作为独立消融，禁止将未触发硬判为未到P波；初期方位缺口大时保留外海多解，不因网格代价平局任意发布单点。需要真实原始波形标定阈值延迟/漏触发；优先核验官方目录及P-Alert波形下载。
D. 三维走时候选作为后续单独变量，现有一维走时测试不支持直接替换。所有结果必须实测，不以论文性能宣称RQ性能。本轮仅完成文献核验与研究基线冻结记录，未实施新定位实验、未修改生产代码、未启用P-A正式推算、未改变NIED。


## 追加：国际EDT应用补充与P-A区间EDT首轮同条件A/B（2026-11-26）

- 用户确认继续EDT研究，检出V1冻结。补查韩国气象厅多算法系统论文 https://pmc.ncbi.nlm.nih.gov/articles/PMC12902117/ ：RTLoc与MAXEL均使用EDT，MAXEL以Student-t分布减轻异常P到时影响；意大利PRESTo的RTLoc、NonLinLoc亦使用EDT（https://doi.org/10.1785/0120060159、https://academic.oup.com/gji/article/208/2/589/2417317）。本文实验不是原版MAXEL/RTLoc完整复现。
- audit_palert_edt_ab.py实际运行exit0，输出palert_edt_ab_20261126.json（30组快照、6场既有事件、全P/全S分别评估，每组3个新EDT评价和1个已有基线），内部76.29秒为Python全部试验总耗时，非单帧生产耗时。保留上次早期定位相同起跳区间、坐标、JMA2001表、21..26N/119..124E、0.1度网格、10/20/40/60/100km深度，不使用参考震源选择解；基线为发震时刻自由的中位数+区间Huber残差。对照为站对残差高斯核sigma=1s（区间中点）、区间高斯核（扣除两站半宽之和）、区间Student-t形核（df=3、尺度1s）。取平均核值最大网格；平局仍取首格。21组快照使用全部站对，9组大样本按固定seed20261126均匀抽取2048站对，未做全站对/抽样稳定性或独立站权重检验，不能视作校准概率。近似区域定义为最高平均核值-0.02以上，和原基线近似区域容差不同，不能直接比较区域大小。
- 水平误差均值km，顺序基线/高斯中点EDT/区间高斯EDT/区间Student-t EDT：
  - 全P首个候选：125.98/61.17/169.90/169.90；30组快照：73.60/61.20/82.21/82.21；每事件最后快照：67.11/38.95/56.85/56.85。
  - 全S首个候选：130.43/54.94/147.93/147.93；30组快照：76.72/51.60/71.21/71.09；每事件最后快照：57.31/45.07/45.93/45.93。
  - 全P首候选中位误差78.86/34.50/170.49/170.49km；全S首候选80.15/47.90/111.59/111.59km。全P/S为假定波相的独立诊断，不可按参考误差选P/S，不是实际首报精度。末次快照并非正式最终报。参考坐标仍来自此前回放参考，未全部独立核验。今日M3.7尚无独立参考坐标，本次未纳入位置误差统计。
- 与那国第19秒3站：全P基线268.6km、高斯中点185.2km、两个区间EDT均367.8km；全S基线316.3km、高斯中点121.1km、两个区间EDT均367.8km。全P区间高斯最高分1.0，参考坐标最近水平网格跨深度的最高分也1.0，808个水平网格在最高分-0.02内；说明零区间外残差平台+平局首格制造极差单点，而非参考位置被观测否定。第29秒全P71.8->196.0km、全S59.2->50.6km（高斯中点）；第33秒全P138.9->135.7km、全S159.2->133.4km；第59秒全P139.1->81.0km、全S187.7->133.4km。EDT缓解部分后期错误到时但远海仍不可靠。
- 结论：先保留高斯中点EDT作为对照候选，不直接替换生产；区间零残差平台不能任意取单点，Student-t区间核本轮未显示稳定额外收益，未验证标准中点Student-t。下一轮优先保留多峰候选、研究连续区间概率而非零罚平台，并在同样候选上做新增站P/S/延迟/离群关联及未触发站软约束消融；避免凭参考选择解或强制固定深度。六场既有样本仅诊断，30快照相关，非独立泛化验证。未改检出V1、未改生产、未启用P-A正式推算、NIED不变。


## 追加：M3.7 CWA参考震源补齐及七场连续不确定性EDT实验（2026-11-26）

- APP使用的ExpTech CWA列表 https://api.core.exptech.dev/api/v2/eq/report?limit=25 实际HTTP200，按2026-11-26 08:43:47 UTC+8唯一匹配115000-2026-1126-084347；详情 https://api.core.exptech.dev/api/v2/eq/report/115000-2026-1126-084347 HTTP200，id/time/lat/lon/mag/depth六字段完全一致。参考24.43N,121.86E,ML3.7,46.4km，最大震度1（列表），宜蘭縣政府南南東方35.1km（宜蘭縣近海），time=1795653827000，列表md5=B6175317E46B6A4CA0D944CADCFF2AC7。保存原始解析列表条目与详情至palert_m37_cwa_reference.json。CWA官网公开列表的web检索及本机直接GET（HTTP200）均未找到该时刻；此为独立于P-A估计的CWA转发报告参考，不宣称已独立官方原站核验或最终目录复核。参考仅评分，不参与候选选择。
- audit_palert_edt_continuous.py实际完成36组快照/7事件，退出状态需见本轮实测；输出palert_early_locator_seven_20261126.json（保留旧六场并追加M3.7）、palert_edt_continuous_20261126.json。M3.7沿用相同均衡三站候选及因果起跳区间/后续关联规则，未调V1；新增站仍采用上一轮宽松关联而非新波相过滤。旧Rust确认时刻来自palert_20261126_m37_current_srev_audit.json，缺少旧HYP发布参考故old_shadow_first=null。全P/全S分别假设，未自动判波相。
- 同一坐标网格/深度/走时/站组，比较高斯中点EDT、Student-t中点EDT(df3)、高斯连续不确定性核、Student-t连续不确定性核（均峰值归一；sigma_eff^2=1+(w_i^2+w_j^2)/3，w为起跳区间半宽，均匀误差差分方差匹配的近似，不是精确区间积分或校准后验；移除零罚平台）。沿用2048站对固定种子抽样上限，未验证全部站对性能或站对相关性。诊断保留最高分-0.02水平网格、最多5个间隔>30km的高分点（非严格独立峰、非概率置信区）。运行内部计时61.48秒（EDT循环全部实验，不是单帧生产性能）。
- 七场水平平均误差km，顺序旧稳健到时/高斯中点/Student-t中点/高斯不确定性/Student-t不确定性：
  - 全P首快照157.01/58.79/58.79/58.79/58.79；全部36快照75.19/57.86/59.19/59.56/58.94；末快照60.09/34.14/42.82/41.39/42.82。
  - 全S首快照155.34/48.08/48.08/48.08/48.08；全部36快照75.42/44.46/44.58/44.48/44.45；末快照51.69/39.38/40.02/39.88/39.88。
- M3.7发震后9/10/14/19/29/49秒的到时数4/5/13/32/40/40；原全P误差343.1/64.9/27.4/27.4/18.0/18.0km；高斯中点全P44.6/118.3/68.4/5.2/5.2/5.2km；全S6.9/24.5/5.2/5.2/5.2/5.2km。首报全S虽6.9km但深度100km（CWA46.4km）、11个近优水平格、半径61.8km；不可声称准确首报或正确识别波相。全P首报44.6km、深100km、57近优格，近优范围内最近参考5.2km。与那国首报全P/全S仍185.2/121.1km，四个新连续核首最优点一致，近优范围最近参考距离仍33.4..75.2km；保留多解也不等于已解决欠约束。
- 结论：中点高斯EDT仍为当前对照主候选，Student-t及连续不确定性近似未改善首报点位置，后期全P略差，不直接替换；连续核解决平坦零罚但无法独立解决几何欠约束及后续相位关联。下一轮优先检验新站传播一致性（同时保留多可行源/P/S/迟到/离群假设）、未触发站软证据与站点可观测性，保持V1和走时模型不变。七场及36快照不是独立长期泛化数据；全P/S结果仅诊断，未实现正式实时推算、未改生产/NIED/未编译。


## 追加：P-A混合P/S站级定位、M3.7参考到时及初期波相先验消融（2026-11-26）

- 本轮保持P-A检出V1、原始回放及JMA2001走时不变，只对palert_early_locator_seven_20261126.json已有七事件36组有效快照开展离线定位。未更改实际新站关联规则、生产代码、NIED或正式P-A开关。
- M3.7固定CWA转发报告24.43N/121.86E、深46.4km、08:43:47（UTC+8），逐站计算理论P/S到时，对照已冻结起跳区间，参考只用于诊断。输出palert_m37_phase_reference_audit.json。发震后9秒四站W02B/W03D/W04A/W473起跳区间分别[7,8]/[7,8]/[8,9]/[8,9]s，P理论7.303/7.219/8.457/8.037s，S理论12.560/12.415/14.549/13.826s；四站均包含理论P到时，S均不相容（1s容差）。这不是原始波形人工相位真值。+10s 5站均P相容；+14s 13站中7站P相容、5站S相容、12站任一相容；+19s 32站中7/15/22站，7站晚于两波理论到时超过1秒；+29s及+49s 40站中7/16/23站，13站晚于两波超过1秒，0站早于两波超过1秒（判断用区间端点与1s容差）。表明早期起跳可与P相容，后期起跳混有S或延迟；上一轮全S初期6.9km水平误差但100km深度不能视为正确波相。
- audit_palert_phase_mixture.py实测exit0，36快照、内部51.59秒总耗时，非实时单帧性能。采用原0.1度/5深度网格，起跳区间中点及半宽方差近似sigma=sqrt(1+w^2/3)；每个网格共用发震时刻，搜索最早3个到时减理论P或S并加-1/0/+1秒的离散候选（近似、非完整连续发震时刻优化）；站级目标为mean(log(.05+.95*k))，全P/全S/等权混合P/S高斯核，另试20%单侧延迟核（3s衰减）。常数离群底及混合权重为实验参数，非校准概率；不能将模型拟合的P/S标签作为实际拾取，未实施顺序关联、重拾取或删站。输出palert_phase_mixture_20261126.json、palert_phase_mixture_summary_20261126.json。
- 按同一快照统计平均水平误差km，顺序高斯EDT全P/全S、站级全P/全S、等权混合P/S、混合+延迟：首7组58.79/48.08/60.56/56.00/45.17/46.84；全部36组57.86/44.46/66.60/52.09/36.16/36.55；末7组34.14/39.38/69.94/48.60/21.66/21.92。平均绝对深度误差首7组46.23/53.37/46.23/53.37/20.91/20.91km，末7组19.49/19.49/32.34/19.49/20.91/20.91km。混合模型改善水平整体表现，但末次深度未改善；全36组最坏水平202.43km，仍有大错。
- 与那国19/29/33/39/59秒等权混合水平误差101.8/202.4/199.9/11.1/22.2km、深10/10/100/10/40km；高斯EDT全P185.2/196.0/135.7/142.1/81.0km。39秒虽最优点11.1km但最高分-0.1近优水平格87个、最大半径239.4km，不能认为已经可靠收敛；59秒近优半径55.4km、深40km偏离10km参考。M3.7发震后9/10/14/19/29/49秒混合误差9.9/9.9/9.9/5.2/5.2/5.2km、深10/10/40/40/40/40km；首快照推算发震时刻比CWA晚4.5秒，拟合为3P样/1S样，与固定参考下4站P相容不一致；末快照发震时刻仍晚约1.8秒。小水平误差不代表正确三维震源。
- audit_palert_phase_seed_prior.py实测exit0，16组（七事件首快照、与那国/M3.7全部快照），仅最早3站P先验从0.5调0.8/0.95，余站不变。首7组水平平均45.17/42.71/43.88km，深度平均20.91/22.34/26.63km；M3.7首水平9.9/18.0/18.0km且均深10km，发震时刻均仍晚约4.5..5秒；与那国首101.8/103.6/103.6km，后续基本不变。不能将更高P权重作为必要硬规则。输出palert_phase_seed_prior_20261126.json。
- 暂保留高斯EDT和等权混合站级模型并行作为研究候选，不用参考误差挑选实时解。下一轮真正实施新站关联/重新判定（对多个可能震源进行一致性评估，避免单点锁死）、加入可观测未触发站软证据，约束发震时刻/深度退化，独立地震及午间背景验证。候选范围不是概率置信区，七场和相关快照不等同独立泛化评估；参考六场尚未全部独立官方最终目录核验，M3.7为独立于P-A的CWA转发参考。生产未修改、正式P-A推算仍关闭，未重新编译打包。


## 追加：未触发站软约束及多候选动态关联的首轮消融（2026-11-26）

- 用户同意继续RTLoc式未触发站约束及多候选关联研究。本轮仅实验脚本、输出和研究文档，不改P-A检出V1、正式推算、NIED、UI或走时模型。
- audit_palert_quiet_association.py 实测 exit0，七场36有效快照，内部45.94秒（全实验Python总耗时，非实时性能）；基线逐快照水平误差断言与上轮混合P/S相同。输出 palert_quiet_association_20261126.json、palert_quiet_association_summary_20261126.json。所有参考震源只用于评分。此前六场参考未全部独立官方核验，M3.7采用CWA转发报告。
- 未触发站候选：冻结候选建立前2秒以前的最多90秒lower中位背景，至少3有效样本；最近3秒至少2真实观测且末帧有效；从seed-2秒到当前未观察到>=3倍冻结背景，未参与本快照定位；自身背景不高于参与站有效背景中位数，距参与站最近<=60km，最多选64站。历史中间缺测没有被补齐，因此不能把它们当作确定连续安静。每网格/深度只保留原混合P/S最优发震时刻，以候选预测S到时比当前早2秒以上、震源距安静站较参与站中位距离更近的程度连续惩罚，归一后乘0.25/1/2；并非校准可观测概率或完整RTLoc，不重新搜索发震时刻。无固定Gal门槛，无硬排除。26/36快照有合格站；剩余10组跳过，其中含早期左截断/背景不足及有效站条件不足。
- 七场首快照水平平均均45.17km、末快照均21.66km，未改善。36快照水平平均基线36.16km，权重0.25/1/2为34.66/33.37/33.33km，均仅2快照改善、0水平恶化；深度MAE从20.23升22.73km。26组有效快照水平34.81->32.73/30.94/30.89km，深度17.63->21.09km。与那国29秒202.4->148.4km（权重1），但深10->100km；33秒199.9->153.4km（深100不变）；39秒水平11.1km不变，近优半径239.4->165.7km（相对分数阈值的诊断，非校准置信区）；19/59秒不变。今日M3.7所有快照不变。不能以整体平均改善认定初期定位已改善；暂不采用。
- 新站关联消融：以前一有效快照未加权混合模型的各网格/深度最佳发震时刻为候选集合，保留分数最高值-0.1或-0.3内全部候选；本快照新增站计算与任一候选P/S最小标准化残差，若全部>2.5sigma则权重0.25而非删除；既有站权重1，重新全网格求解。每步前验来自未加权快照，不持续冻结，不是逐帧实时关联或独立波相判定；仅每网格/深度一个时刻可能遗漏可行解。共876新增站次，分别降权109/21站次。36快照平均水平36.16->38.99/41.19km；改善4/1组、恶化4/1组；平均深度20.23->21.90/22.73km。末次均值21.66->20.59/21.66km，不能抵消中途严重失败。
- 关键反例：与那国39秒新增3站均被两种前验降权，水平11.1->199.9km，深10->100km；说明即便同时保留多网格，错误先验也可能压制纠正定位的证据。29秒较严前验改善202.4->101.8km却保留了此前错误源。禁止将上一报一致性作为全局搜索的硬门槛。后续可考虑并行无前验全局重搜索与连续跟踪、站级留一/新站证据独立评价，以及以真实幅度、PGV及场址差异标定未触发站可观测性，优先解决发震时刻和深度退化。当前两项均只保留实验记录，不合入生产。午间独立背景和更多事件仍待采集验证。



## 追加：CWA正式测定与P-Alert逐测站对照（2026-11-26）

- 已更正10/13 CWA正式第069号参考：23.56N/121.45E、深33.8km；此前写成23.57N/121.43E、30km为错误。10/17先保留Rapid-only，原先提供的正式详情链接404。
- 已下载CWA E-A0015-002/E-A0016-002逐测站PGA/PGV，完成128个CWA唯一站点到786个P-Alert站点的一对一坐标候选映射。三场有P-Alert事件级PGAList的事件在250m名义近邻范围内有31组有效观测；P-Alert/CWA中位比值PGA1.137、PGV1.077，对数振幅相关0.757/0.737。不同站点和事件偏差不一致，不应用统一校正系数。
- 已下载11/25 CWA E-A0015-004原始波形47站（100Hz、120s），并取回9个近邻P-Alert站点的GraphQL波形预览（25Hz、120s）。CWA原始波形重算的PGA/PGV与官方SUM值吻合；ECL/W12F的PGA差约4.2倍，差异集中在3–10Hz，需进一步取得P-Alert完整SAC确认场址/结构响应或传感器数据质量。
- 11/17 P-Alert事件级PGAList/waveform缺项；本地回放只提供PGA快照，W395峰值9.33gal、W451峰值1.19gal，不能替代最终PGA/PGV。
- 结果、原始数据、下载/匹配/重算脚本见 `docs/cwa_palert_station_comparison_20261126.md` 和 `docs/palert_cwa_event_crosswalk_20261126.md`。本轮不修改生产代码或检出V1。
## 追加：P-Alert W12F 高频异常复核（2026-11-26）

- 重新核对CWA与P-Alert通道方向：CWA文件头明确U(+),N(+),E(+)；P-Alert官方帮助明确HLE向西为正，因此映射为CWA U,N,-E -> P-Alert HLZ,HLN,HLE。CWA ECL/ECS波形从16:47:00开始，发震时刻16:47:17；P-Alert GraphQL预览事件相对时间轴约-0.001至119.959s。统一到P-Alert时间轴后共同覆盖约103s。W39B/ECS正常对照支持方向映射和时间对齐。
- 11/25 ECL/W12F：CWA原始波形3C PGA 1.102gal，P-Alert预览3C PGA 4.558gal，比值4.14；官方PGA SUM/PGAList比值4.20。ECS/W39B对照预览比值0.958，官方比值0.90。
- W12F异常主要在水平分量：Z峰值0.605/0.657gal（CWA/P-Alert），N为0.832/1.675，W/HLE为0.988/4.545；Z峰时仅差0.04s，但N/W的P-Alert峰时分别早约7.56s/8.44s，排除整条波形的全局时钟平移。W39B三分量峰值与CWA接近，合成峰时差约0.04s。
- W12F在3–10Hz事件窗持续偏高，特别是HLE约5.9Hz。5.5–6.5Hz HLE RMS按0–10s早期基线功率扣除后，20–35s、35–50s、50–70s、70–100s的P-Alert/CWA比分别约14.82、7.65、14.20、5.52；W39B对应主震动窗约0.90–1.04。P-Alert预览早期背景噪声高于CWA，不能将全记录RMS直接当作地震信号。
- 新取回10/13、11/1的W12F/W39B历史预览；三场PGAList比值为0.887、0.505、2.758，PGVList比值0.751、0.747、0.951。异常是11/25事件特定，反对W12F固定4倍增益；但事件震中距离/方位不同，不构成同址输入对照。
- 当前证据支持“W12F在11/25事件中出现方向性水平高频响应”，建筑结构/安装、局部场址、HLE通道异常均为候选；尚不能定因。P-Alert官方文献记录传感器常安装在建筑墙面且有个别一楼异常站，支持继续检查结构/安装/场址，但不证明W12F就是建筑共振。
- 公开GraphQL只有25Hz/120s预览，预览抗混叠与W12F实际低通档位未知；完整SAC是100Hz/10min。官网下载流程要求真实邮箱、机构和交互式reCAPTCHA，本轮没有绕过或伪造。需用户正常下载2026-11-25 08:47:17 UTC的W12F/W39B SAC并上传，才能确认5.9Hz峰、排除alias并估计噪声/衰减。
- 专题报告：`docs/palert_w12f_resonance_audit_20261126.md`；复现脚本和JSON见`tmp/srev_nied_migration_20261125/`。本轮不改生产检出、定位或振幅校正。


## 追加：完整100Hz SAC复核（2026-11-26）

完整100Hz SAC已经从本机归档取得并完成W12F/W39B两站三分量分析。完整报告：`docs/palert_full_sac_100hz_validation_20261126.md`。

关键更新：
- W12F HLE的5.933Hz峰在100Hz原始SAC中真实存在；可能折叠到5.9Hz附近的18.5–19.5、30.5–31.5、43.5–44.5Hz候选频带能量极低，混叠不是主要解释。
- 20–35秒W12F/ECL 3C PGA比为4.274；HLE 5.5–6.5Hz RMS为0.7749/0.05096gal，比值15.20。35–50秒比值7.18，50–70秒13.70；100–120秒后回到W12F自身基线附近。
- W39B/ECS 0–100秒3C PGA比为0.98，作为对照基本正常。
- 100Hz 1–3Hz互相关时差约0.03–0.06秒，纠正此前将单分量绝对峰值时刻差误判为约8秒全局时钟偏移的解释。
- GraphQL 25Hz预览与100Hz SAC降采样波形相关性较高，但预览RMS普遍高约10–30%；定量振幅以完整SAC为准。
- 异常仍可能来自建筑响应、安装/通道或局部场址，尚不能定因；不做固定增益，不改生产算法。



## 追加：P-Alert 下载页面遮罩状态（2026-11-26）

页面只读检查记录见 `docs/palert_download_page_loading_check_20261126.md`。当前页面文本快照显示测站表格已到713/713，且未出现Loading/載入中等文字；但Browser工具无法提供DOM样式、Console或Network Pending请求，Codex浏览器宿主也不可用。遮罩究竟是模态框backdrop还是全局Loading仍未确认，不能据此修改页面或断言根因。


归档副本 `tmp/srev_nied_migration_20261125/incoming/2026-11-25T08_47_17.tar.gz` 与 Downloads 原件大小相同，SHA-256一致；原件未移动或覆盖。

## 追加：P-A 多候选并行搜索与 H14 三维走时第一轮研究（2026-11-26）
- 新报告：`docs/palert_multihyp_h14_3d_research_20261126.md`。本轮离线研究，不改生产检出、HYP、NIED、UI或打包；`PAlertService.sourceEstimationAvailable=false` 保持不变。
- 多候选：七场36快照，0.1°网格、5个深度，保留Δmean log-likelihood≤0.10的26邻域连通候选分量；30个快照1分量、3个2分量、3个3分量。与那国19/29秒需把阈值扩大到0.30/0.60才覆盖保存参考位置，此时近优区域分别约1940/875格、水平半径约269/248km；说明早期不确定性极大，不能强行发布单点。参考坐标非全部独立官方最终目录。
- 下载 EarthScope EMC `TW-PS-H14.r0.0-n4c.nc`（791867 bytes，SHA256 `8A9B010E6B19011D2DAF68B449A3D42B1C20F25586A4BF8F0024999CA1DE09E6`），覆盖21.3–26.1°N、119–125°E、深度-5至300km，0.08°，含Vp/Vs。TECDC LEE2025虽有模型目录条目，本轮文件下载返回404，未参与实验。
- 2011 CWA Benchmark 6890条人工P/S记录，H14三维直线路径积分有效6888条。直接时间戳口径：P MAE1.080s vs RQ JMA1.009s；S 1.249s vs1.381s。事件等权bootstrap H14-RQ：P +0.0293s [0.0059,0.0559]，S -0.1180s [-0.1601,-0.0750]。权重0/1子集同样是P略差、S更好。path字段口径排序不同，已在报告并列保留。H14训练数据与2011样本的重叠未核实。
- H14相对自身深度平均1D剖面，P/S MAE分别改善约0.033/0.169秒，说明横向结构对S更有帮助；但>100km子集H14三维直线路径变差，不能直接外推远海。
- P-A实际回放A/B仅测与那国和M3.7两场：H14对M3.7后续S兼容站数增加，但起跳并非人工S相位；水平定位大多与JMA相同，个别时刻变差。与那国59秒由22.2km恶化至52.5km。故不替换JMA主走时，仅保留H14作为S相位shadow分支研究。
- 产物位于`tmp/srev_nied_migration_20261125/`，详见新报告及脚本/JSON清单。下一步研究候选生命周期、JMA P + H14 S并行证据和3D弯曲射线/eikonal；生产P-A推算继续关闭。
