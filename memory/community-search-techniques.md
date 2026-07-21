---
name: community-search-techniques
description: 社区品种评价搜索经验 — 避免重复踩坑
metadata:
  type: reference
  originSessionId: 2026-07-20-breed-testing
  modified: 2026-07-20T16:08:18.591Z
---

# 社区品种共识搜索技巧

每次搜索宠物最佳品种时，以下经验可避免重蹈覆辙。

## 搜索策略层级（优先级从高到低）

### L1: wow-petguide.com（全球最大最专业宠物对战网站）
- **`wow-petguide.com` = Xu-Fu's Pet Guides** — 品种数据最全、策略覆盖最广
- 搜索格式: `site:wow-petguide.com <英文名> breed` 或 `wow-petguide <英文名> breed best`
- 页面通常列出所有可用品种的 L25 属性表 + 品种推荐 + PvE 策略
- 部分页面返回 403，此时用 `WebSearch` 搜页面摘要
- **1749 案例**: WarcraftPets/NGA 都搜不到 → wow-petguide 直接命中 "S/S consensus best, 341 speed disruptor"

### L2: WarcraftPets（社区讨论权威）
- WarcraftPets 评论区 > WarcraftPets 论坛 > Wowhead 评论区
- `site:warcraftpets.com "Pet Name" comment` → 找评论区
- 论坛帖子如 "Spider power breeds" 常含多只宠物品种表
- 页面经常返回 403，用 `WebSearch` 搜摘要代替 `WebFetch`

### L3: NGA 中文社区（参考来源）
- `site:bbs.nga.cn` 或 `NGA 宠物对战 <中文名> 品种`
- ⚠️ **NGA 为参考，以 WarcraftPets + wow-petguide 为准**

### L4: 家族级品种指南
- 同一技能池的宠物品种推荐因可用品种库不同而不同
- 关键案例: 415 Fire Beetle 无 P/P→社区推 H/P；429 Lava Beetle 有 P/P→社区推 P/P

### L5: 备用数据源
- `wowhead.com/npc=XXXXX` → 基础数据
- Xu-Fu 策略 → PvE 品种要求
- Blizzard 官方论坛 → 极少讨论单只宠物品种

## 宠物名中英对照（必须先确认英文名再搜）

易混案例:
- 熔岩蟹(423) = Lava Crab，不是 Molten Hatchling(428)
- 熔火幼蛛(428) = Molten Hatchling，不是 Molten Spiderling
- 熔火甲虫(429) = Lava Beetle，不是 Fire Beetle(415)
- 燃灰蝰蛇(425) = Ash Viper
- 紫红泰斑蛇(1749) = Death Adder Hatchling

## 搜索失败迹象

| 症状 | 根因 | 下一步 |
|------|------|--------|
| 搜索结果引用不存在的技能 | AI幻觉/宠物混淆 | 在游戏内确认实际技能名再搜 |
| 结果全是"must-have pet tier list" | 该宠物太冷门 | 改用 wow-petguide |
| WarcraftPets 无评论区 | 宠物没有专属页面 | 先用 wow-petguide 查品种表 |
| 英文名搜不到 | 中文名翻译差异 | 先通过 speciesID 找到英文名 |

## 搜索不出的宠物处理

1. 确认是否有更多品种（可能仅1-2种，无选择余地）
2. 看同家族同技能池宠物
3. 社区推荐品种不存在→选最接近的
4. 记录到共识文件"未找到共识"列表

[[community-breed-consensus]] [[always-check-community-first]] [[project-state]]
