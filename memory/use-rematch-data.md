---
name: use-rematch-data
description: GenDexBD 以 Rematch 为基础，所有数据优先从 Rematch 获取
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 4c7850da-5d45-4890-bf03-68806b54d4e9
---

GenDexBD 在 TOC 中声明了 `## Dependencies: Rematch`，以 Rematch 为基础插件。

**核心原则：能用 Rematch 提供的数据，绝不自己调 Blizzard API。**

**已知可直接使用的 Rematch 数据接口：**
- `Rematch.roster.speciesPetIDs[speciesID]` — 该物种所有已拥有宠物的 GUID 数组，`#` 取数量（O(1)）
- `Rematch.roster:AllOwnedPets()` — 迭代所有已拥有宠物的 GUID
- `Rematch.roster:AllSpeciesPetIDs(speciesID)` — 迭代该物种所有 petID
- `Rematch.petInfo:Fetch(petID)` — 获取宠物完整信息（speciesID, breedID, breedName, hasBreed, level, rarity, maxHealth, power, speed...）
- `Rematch.petInfo:Fetch("battle:2:N")` — 获取敌方第 N 只宠物的信息（含 BPBID 缓存的精确 breedID）
- `Rematch.menus:AddToMenu(...)` — 注册右键菜单
- `Rematch.menus:Register(...)` — 注册命名菜单
- `Rematch.petsPanel:Update()` — 刷新宠物列表

**Why:** TOC 已声明依赖，重复调 Blizzard API 不仅多余，还面临 12.0 API 返回值格式变化的风险。Rematch 已经封装好了。
**How to apply:** 任何需要获取宠物数据的地方，优先查 Rematch 是否已有缓存。不要重复发明轮子。
