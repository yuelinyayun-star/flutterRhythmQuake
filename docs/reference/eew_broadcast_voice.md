# 地震中文语音与日本广播参考

核对日期：2026-09-17。

## 收集到的播报音源与广播稿

以下区分可试听音源、机构公布的广播稿和历史说明。未做录音逐字转写，不能将文本核对说成已经听辨了全部录音；没有将这些第三方音频打包进应用。

| 来源 | 资料 | 可核对的范围 |
| --- | --- | --- |
| J Corporation 接收设备官方页 | [播报模式与广播稿](https://www.jcorp.co.jp/3311/3311_sound.html)、[页面所列 NHK 电台播报示例 WAV](https://www.jcorp.co.jp/wav_video/EEW0_nhk.wav) | 厂商刊载的 NHK 广播示例包含震源所在县、应警惕强烈摇晃的县名。不是 NHK 自己提供的中文读音库。WAV HEAD 返回 200、audio/x-wav、2,237,678 字节。 |
| 上越市政府 | [防灾行政广播说明](https://www.city.joetsu.niigata.jp/soshiki/kikikanri/dentatsu.html)、[紧急地震速报 MP3](https://www.city.joetsu.niigata.jp/uploaded/attachment/60628.mp3) | 政府公开的 J-ALERT 广播样本，不冒充某次地震现场录音。MP3 HEAD 返回 200、audio/mpeg、783,316 字节。 |
| 日本放送电台 | [紧急地震速报的广播安排](https://www.1242.com/lf/jishinsokuho/) | 页面公布先中断节目播报避险提醒、再跟进详情的流程及稿件。不能据此推断所有电台使用同一套稿件。 |
| 成田机场 | [中文紧急地震广播说明](https://www.narita-airport.jp/zh-sc/news/jishin/) | 有中文固定提示，日英中韩各播放两次；公开稿不含动态地名，无法证明如何处理片假名。 |
| KANAME 技术开发 | [广播用系统说明](https://kaname-tec.co.jp/eew/audio.php) | 说明震央名来自一般向紧急地震速报电文，按剩余时间改变播报内容。该页编码为 Shift_JIS。 |
| 日本气象厅 | [EEW 获取方式](https://www.jma.go.jp/jma/kishou/know/jishin/eew/katsuyou/receive.html) | NHK 和各民营广播机构的覆盖与播报形式存在差异。 |
| 日本气象厅会议记录 | [2010 年评估会议记录，第 5 页](https://www.data.jma.go.jp/eqev/data/study-panel/eew-hyoka/03/gijiroku.pdf) | NHK 代表说明当时的电台采用自动语音播出地区名。仅作为历史证据，不代表当前中文播报实现。 |
| 日本气象厅 | [训练用视频](https://www.jma.go.jp/jma/kishou/know/jishin/eew/kunren/kit1.html) | 官方训练素材，不是实况广播，不能拿来证明中文地名读法。 |

这些音源包含警报音，试听时注意音量与周围环境。公开试听不等于获准将音源重新分发。当前没有查实一套 NHK 官方的中文震央语音库，因此应用没有伪称采用该语音库。

## 我们采用的地名依据

- [气象厅多语言词典入口](https://www.data.jma.go.jp/developer/multilingual.html)提供包含简体中文的官方对照。
- [实际多语言震央词典](https://www.data.jma.go.jp/multi/data/dictionary/epi.json)按震央代码组织日文、简体中文等名称。
- [气象厅网页加载代码](https://www.data.jma.go.jp/multi/js/util.js)加载词典，[地震列表代码](https://www.data.jma.go.jp/multi/js/quake_list.js)以震央代码和语言查名称。这是网页的地名本地化实现，不是广播语音合成源码。
- RhythmQuake 当前统一事件包含震央名，语音层用原日文名称精确匹配官方 `japanese -> chinese_zs`，不会在线请求翻译，也不按发音猜地名。
- 原始 JSON 存在 `test/fixtures/jma_voice/epi.json`，275,241 字节，343 个震央条目，未经重新排版或删改。
- 原文件 SHA-256：`fc07f4bfe60db7896a6d96c2be7641914984432f5e658601d59cb1bbe7efcd70`。
- 增补原始 [pref.json](https://www.data.jma.go.jp/multi/data/dictionary/pref.json)（47 条、25,531 字节）和 [city.json](https://www.data.jma.go.jp/multi/data/dictionary/city.json)（1,901 条、1,428,774 字节），一并保存在同一测试目录。三表去重后共 2,289 个精确名称映射。
- `pref.json` SHA-256：`a5bc51b75b6d1fd0aa7f68ed41d3a92843b7d5e90f41598ba46785ab4e6a9245`；`city.json` SHA-256：`d8f54d4a21e7e1cc875590fbb82e828f0185a6d9f47591eda0583181091f0804`。
- 生成表 `lib/core/utils/jma_voice_locations.g.dart` 只保留应用朗读所需的官方日中字段；这是由原始数据生成的语音展示资源，不替换事件字段。

官方表中的例子：

| 日文原名 | 官方简体中文 |
| --- | --- |
| カムチャツカ半島付近 | 堪察加半岛附近 |
| オホーツク海南部 | 鄂霍次克海南部 |
| トカラ列島近海 | 吐葛剌列岛近海 |
| ニセコ町 | 新雪谷町 |
| むつ市 | 陆奥市 |
| つくば市 | 筑波市 |

Tokara 的简体字段确实是“吐葛剌”，不把它擅自改成其他常见译名。未知名称原样保留，不删掉片假名、不用宽泛地区代替，也不宣称所有日文已经可读。多个名称按分隔符逐项精确查表，整个名称的精确匹配优先于分割。

重新生成：

```powershell
dart run tools/generate_jma_voice_locations.dart test/fixtures/jma_voice/epi.json test/fixtures/jma_voice/pref.json test/fixtures/jma_voice/city.json lib/core/utils/jma_voice_locations.g.dart
```

原始词典在测试目录中，不作为 Flutter 运行时资产打包。更新词典必须替换为新的完整原始文件，核对来源、哈希和测试，再运行生成器。

## 本次播报调整

原因：原组句先念来源、长标题和报次，再报震源；EEW 还朗读深度和完整预警区域。多个片段自身已有句号，随后又用逗号连接，产生冗余停顿。日文震央名未经转换直接交给中文 TTS。

- EEW：类型、地点、震级、预计最大震度或烈度、深度；来源和报次移到后句。根据用户后续要求恢复深度，未知值省略，0 读“很浅”，小数深度不取整。不再朗读整串预测预警区域，地图及详情里的数据不变。
- 地震情报：类型、地点、震级、最大震度或烈度、深度；来源和审核状态放后面。避免重复机构名和长标题。
- 保留烈度速报、震度速报、长周期地震动情报、震源机制解的类型区别，以及正式测定、自动测定、核实状态、修正、取消。
- `5+ / 6-` 转成中文朗读的强弱等级；罗马数字烈度转换成数字，只改语音文本。
- 统一入口 `AlertVoiceHelper` 覆盖已进入统一模型的各 API；旧 JMA 播报入口也使用同一个地名函数。非 JMA 事件不套用日本地名表。
- 不改变用户语速、声音、播报开关、去重、倒计时、播放队列和警报音。统一事件现有 1,250ms 延迟仍保留，本次不宣称端到端延迟已经消除。

## 震源调查中与观测区域

这里是震后观测的“震度速報”，不是震前预测强烈摇晃的“緊急地震速報”，不能混用播报规则。

- [气象厅信息种类说明](https://www.jma.go.jp/jma/kishou/know/jishin/joho/seisinfo.html)：震度速报先给出观测到震度 3 以上的区域和检测时刻，震源信息随后发布。
- [川西市公开的 NHK 播报说明](https://www.city.kawanishi.hyogo.jp/kurashi/bosai_bohan_kyukyu/1017400/1019991/1002227.html)（页面更新日期 2023-08-25）：先速報震度 3 以上区域，随后按震度从大到小播出震度 2 以上市町村，节目安排可能调整；民营电台自行决定。它是市政府的公开说明，不是 NHK 内部统一播音规范或本次逐字听辨的现场录音。
- [P2P 官方 API 规范](https://github.com/p2pquake/epsp-specifications/blob/master/json-api-v2.yaml)：`ScalePrompt` 的 `points.addr` 为区域名称，`isArea` 区分区域和观测点；震源缺失与观测区域存在并不矛盾。

没有查实“只播三个区域”的日本广播规则，因此本次实现取消了临时拟定的三地区上限。中文语音按已有观测震度从高到低分组，同等级合并播名，不截断区域、不用“另有多少地区”替代名字。分组句式是应用的中文适配，不声称是 NHK 固定原稿。

没有震源名称（包括“調査中”“震源调查中”等状态）时，使用统一事件已保留的结构化观测区域，播“观测到震度 X 的地区：……”而不是“震源待定”。这些区域不会被写回震源字段；若区域组已包含总体最大震度，不在末尾再重复播最大震度。没有区域数据时只播实际存在的参数，不补造地区。真实震源已提供时仍先播震源，不把详细测站清单塞入每次短报。

P2P 的震度速报、震源信息、震源震度信息、各地震度信息、远地地震信息分别使用中文标题。WHEWS、Jian 的震度区域经过原有统一适配器后使用相同语音逻辑，无单独绕过数据处理的入口。

真实回归样本 `test/fixtures/jma_voice/p2p_scale_prompt.json` 原样下载自 `https://api.p2pquake.net/v2/jma/quake?quake_type=ScalePrompt&limit=2`。原始响应 2,458 字节，SHA-256 `3becbd1e5ed1197d8f08dae2dd384252651025ede1da26416a19caccfc3291e1`，包含 2026-09-17 00:09:18、00:10:18 JST 两报，分别 8、9 个区域，震源为空、最大震度 3。测试验证每个区域都被播出、原始响应未被改写。

## 验证与边界

使用未修改的三份官方词典逐项验证全部名称。除上述真实 P2P 样本外，边界用例明确标注为单元测试输入，验证关键内容顺序、各入口一致、原始字段不变、强弱读法、罗马数字、审核状态、最终报、取消和缺失参数；合成边界用例不是真实事件记录。

2026-09-17：补充深度、P2P 观测区域及原始回放后，语音、偏好、统一倒计时、P2P、WHEWS、Jian 和 JMA 视野相关测试共 228 项通过，涉及的 8 个 Dart 文件静态分析通过。未完成手机扬声器实听，未测量不同 TTS 引擎的实际播报秒数，未重新编译安装包。
