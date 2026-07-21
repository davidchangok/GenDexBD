---
name: keywords-in-locales
description: 自动分类关键词中英文分离后存入Locales.lua
metadata: 
  node_type: memory
  type: feedback
  originSessionId: f09fc2ec-4be0-47da-b4a8-c2c666d87418
  modified: 2026-07-19T21:47:03.813Z
---

自动分类关键词必须按语种分离，存入 Locales.lua 中便于维护。不要混合中英文在一个数组里，zhCN 和 enUS 各独立维护。

**Why:** 中英混在一起难以对比维护，放在 Locales.lua 中与其他本地化字符串统一管理。
**How to apply:** 每次新增关键词时，同步更新 Locales.lua 中对应的语种数组，BreedRecommend.lua 从 addonTable.AUTO_TAG_KEYWORDS 读取。
