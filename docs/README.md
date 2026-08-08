# FlutterRhythmQuake 文档索引

本目录同时包含当前开发文档、来源字段说明、可复现实验记录和历史基线。阅读时应先确认文档状态，不能把研究结论或历史规划直接视为生产行为。

## 项目与架构

| 文档 | 用途 | 状态 |
| --- | --- | --- |
| [根 README](../README.md) | 项目定位、平台、构建、凭据边界和常用入口 | 当前入口 |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 主要模块、数据流和目录说明 | 架构基线，细节需结合代码核对 |
| [项目介绍.md](项目介绍.md) | 面向使用者的功能介绍 | 产品说明 |
| [settings_page_structure.md](settings_page_structure.md) | 设置页分区与默认配置 | 开发参考 |
| [字段获取与注册映射.md](字段获取与注册映射.md) | 数据字段、解析和来源注册关系 | 开发参考 |

根目录的 `PROJECT_STRUCTURE.md` 和 `REFACTOR_TASKS.md` 是历史记录，不是当前结构或待办的唯一事实来源。

## 数据源与服务器

| 文档 | 内容 |
| --- | --- |
| [FAN API 字段说明](../FAN_API字段说明.md) | FAN 推送类型与字段契约 |
| [Wolfx 字段说明](../Wolfx字段说明.md) | Wolfx 推送字段契约 |
| [FAN Studio API 文档](fan_studio_api/) | FAN GET 与 WebSocket 原始文档归档 |
| [WAuth Gateway](../server/wauth_gateway/README.md) | OAuth/PKCE 网关部署和安全边界 |
| [KMA PEWS Relay](../server/kma_pews_relay/README.md) | KMA 二进制帧转发服务部署与协议 |

任何私钥、用户 API Key、访问令牌和服务器密码都不得写入文档或示例。服务端 Secret 必须通过环境变量注入。

## 震源与烈度研究

| 路径 | 内容 | 生产状态 |
| --- | --- | --- |
| [source_estimation_roadmap.md](source_estimation_roadmap.md) | NIED 震源推算演进、验证边界和后续路线 | 路线与验证记录 |
| [core/intensity_reconstruction](../lib/core/intensity_reconstruction/README.md) | 历史烈度反演与衰减模型入口 | 实验模块，按代码调用关系判断 |
| [reference/](reference/) | 学术公式和来源核验文档 | 研究证据 |
| [baselines/](baselines/) | 工具生成的诊断基线 | 生成结果，不手工伪造 |
| [data/](data/) | 数据划分和实验清单 | 研究输入清单 |

`references/` 保存论文、网页快照和离线输入，多个诊断工具直接引用其路径。它不属于 Flutter 运行时资产，但删除或移动会破坏实验可追溯性。

## 维护规则

1. 生产行为以当前 `lib/` 代码和可重复测试为准。
2. 修改数据源时同时核对前台统一 UI、后台通知、去重、过期和来源过滤。
3. 修改测站或震源算法时保留原始输入，不用加工后的伪数据替代来源数据。
4. 回放、科研诊断与生产集成分开验证，不用单场结果直接替换生产算法。
5. Windows 终端、中文和日文源码统一使用 UTF-8。
6. 发布前检查 Git 暂存区，排除本地报告、虚拟环境、压缩包、构建产物和凭据。
