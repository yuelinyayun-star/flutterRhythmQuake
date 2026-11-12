# 2026-10-16 JMA 取消报回归原文

- `original_telegrams.zip`：用户提供的「乐乐JMA误报9.9电文.zip」的逐字节副本，43 条电文，未改动报号、时间、震源要素或报文正文。SHA-256：`e53fae54ff4c02dfd011290932bc2a272b73cbf535b7f7a340d464cc3ece56b1`。
- `wolfx_original.json`：2026-10-16 从 `https://api.wolfx.jp/jma_eew.json` 保存的原始响应字节。SHA-256：`43683f6954d40ea83bffb7f9bead452c6032812a41288149842ae5b9beefab11`。

事件 ID 为 `20261016123810`。最后普通电文为第 42 报，发布时间 12:48:10 JST；取消电文为第 37 报，发布时间 12:48:50 JST，没有 earthquake 字段。Wolfx 响应中 `isCancel=true`、`Serial=42`，`AnnouncedTime` 仍为 12:48:10，不能将其描述为取消电文的真实发布时间。

测试中的 `officialReference` 是该官方电文结构到统一模型的显式参考映射，并非声称它是 Jian、FAN 或 WHEWS 的线上数据结构。映射只转换显示模型的时区表示，保留原始时间字段和完整正文。FAN/WHEWS 入口测试用原文中真实的 ID、报号和状态构造对应协议的最小投影，并明确标注为协议投影；Wolfx 适配测试直接处理原始线上响应。全量顺序测试通过注入时钟重现原始时间线，不修改电文时间。
