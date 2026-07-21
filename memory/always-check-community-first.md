---
name: always-check-community-first
description: "评估宠物品种前必须先查核心记忆→社区→不准敷衍说\"无评价\""
metadata: 
  node_type: memory
  type: feedback
  originSessionId: f09fc2ec-4be0-47da-b4a8-c2c666d87418
  modified: 2026-07-20T00:08:37.430Z
---

# 评估流程：记忆优先 → 社区次之 → 不准跳过

每次遇到宠物评分时，必须严格按以下顺序：

1. **查核心记忆** [`community-breed-consensus.md`](community-breed-consensus.md) — 是否已有该物种的社区共识？
2. **如果记忆中没有** → 必须 `WebSearch` 查社区，搜索词包含宠物名 + best breed
3. **如果社区有结论** → 记录到共识文件 + 与算法结果对比 + 不一致则调整参数
4. **如果社区确实无结果** → 记录到"未找到共识"列表 + 基于技能分析给出合理判断

**绝对禁止**：不查社区直接说"合理 ✅"，或者查了之后写"社区无评价"敷衍。

**Why:** 之前多次出现查了社区却写"无评价"（蜚蠊、土拨鼠等），浪费用户时间纠正。
**How to apply:** 每次收到 `[GenDexDBG]` 日志时，第一句话必须是"查记忆中..."或"查社区中..."，不准直接点评分。

[[community-breed-consensus]] [[keywords-in-locales]]
