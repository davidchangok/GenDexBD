# GenDexBD Code Review 报告

> **审查日期**: 2026-06-28
> **审查方法**: code-review skill (high effort, 8-angle + verify)
> **审查范围**: `5d54fbf..HEAD` — Core.lua 重构变更
> **代码版本**: commit `9e20ac9`

---

## 审查结果：10 项发现

### 🔴 Critical

#### 1. `ownedCache` 作用域错位 — RecordEncounters 引用全局变量

- **文件**: [Core.lua:214](Core.lua#L214)
- **摘要**: `local ownedCache = {}` 在第 236 行声明，但 `RecordEncounters` 在第 201 行定义。函数内 `ownedCache = {}` 被 Lua 解析为全局变量 `_G.ownedCache`，与 `GetOwnedCount` 读取的局部 `ownedCache` 是**两个不同变量**。
- **失败场景**: `RecordEncounters` 清空了全局变量，局部缓存从未被真正清空。`PET_BATTLE_OPENING_START` 的 OnEvent 恰好在声明后正确清空局部缓存，暂时掩盖了此 bug。
- **修复**: 将 `local ownedCache = {}` 移到第 199 行与 `encounterCache` 同级声明。

#### 2. `C_Timer_After(0.5)` 延迟扫描与 `PET_BATTLE_CLOSE` 竞态条件

- **文件**: [Core.lua:311](Core.lua#L311)
- **摘要**: `PET_BATTLE_OPENING_START` 中以 0.5s 延迟触发扫描。若战斗在 0.5s 内结束，数据永久丢失。
- **失败场景**: 野外交战 → OPENING_START → 0.5s timer 挂起 → 0.3s 后战斗结束 → CLOSE 触发 `RecordEncounters`（`encounterCache` 为空，无计数）→ 清空缓存 → 0.2s 后 `ProcessAllEnemyPets` 执行 → encounterCache 重新填充但无人消费。
- **修复**: 在 `PET_BATTLE_CLOSE` 时取消挂起的 timer。

---

### 🟡 Important

#### 3. 局部 `IsBestBreedMatch` 与全局 `addonTable.IsBestBreed` 逻辑完全重复

- **文件**: [Core.lua:98](Core.lua#L98) vs [JournalUI.lua:19-23](JournalUI.lua#L19-L23)
- **摘要**: Core.lua 自行定义了局部版，缺少 `GeneDexDB` 空值保护。全局版有完整的链式 nil 检查。
- **失败场景**: 若调用时 DB 未初始化则崩溃。虽然当前流程保证 DB 先于函数初始化，但冗余且全局版更健壮。
- **修复**: 删除局部版，改用 `addonTable.IsBestBreed`。

#### 4. `encounterCache` 以 speciesID 为键，同物种多槽位品种被覆盖

- **文件**: [Core.lua:254](Core.lua#L254)
- **摘要**: `encounterCache[speciesID] = breedID` 在同物种不同品种时后写入覆盖前写入。
- **失败场景**: 敌方槽 1 (sid=3210, bid=4) 和槽 3 (sid=3210, bid=8) 均为最优 → encounterCache 只保存 bid=8 → RecordEncounters 只计数 breedID=8。
- **修复**: 将 encounterCache 改为 `{[speciesID] = {[breedID]=true, ...}}` 聚合结构。

---

### 🔵 Minor

#### 5. `CountOwnedSpecies` 缺少 `pcall` 保护

- **文件**: [Core.lua:225](Core.lua#L225)
- **摘要**: `Rematch.petInfo:Fetch(speciesID)` 无 `pcall` 包裹，与同文件 `GetEnemyBreed`（第 78 行）不一致。
- **失败场景**: Rematch 内部状态异常 → Fetch 抛错 → 异常沿调用链传播 → ProcessAllEnemyPets 中断。
- **修复**: 统一用法，对第三方 addon 接口始终使用 `pcall`。

#### 6. Rematch 未加载时 `CountOwnedSpecies` 返回 0 而非保守值

- **文件**: [Core.lua:226](Core.lua#L226)
- **摘要**: Rematch 不可用时返回 0，导致 `owned < 3` 始终为 true，即使已满 3 只仍弹提示。
- **失败场景**: Rematch 意外卸载/未加载 → CountOwnedSpecies 返回 0 → 永远弹提示（降级行为过于激进）。
- **修复**: Rematch 不可用时返回保守值（如 999）跳过提示。

---

### 🟢 Nice to Have

#### 7. ★ 字符和金色在各模块硬编码散落 5+ 处

- **文件**: [Core.lua:108](Core.lua#L108), [JournalUI.lua:39](JournalUI.lua#L39), [Tooltip.lua:208](Tooltip.lua#L208), [Locales.lua:52](Locales.lua#L52)
- **摘要**: `★` 和 `(1.0, 0.84, 0.0)` 在 4 个文件中重复出现，调整时需改多处易遗漏。
- **修复**: 抽取为 `addonTable.BEST_BREED_STAR` 和 `addonTable.BEST_BREED_COLOR`。

#### 8. `ALL_BREEDS` 硬编码与 `BreedData.BREEDS` 重复

- **文件**: [JournalUI.lua:31](JournalUI.lua#L31)
- **摘要**: 12 个品种列表需手动同步维护，未来增删品种易遗漏。
- **修复**: 从 `addonTable.BREEDS` 动态生成，配合 `GetBreedCode()` 获取短代码。

#### 9. `DoImport` 每行清空同物种已有数据

- **文件**: [ConfigPanel.lua:112](ConfigPanel.lua#L112)
- **摘要**: `GeneDexDB.BestBreeds[sid]={}` 导致多行导入时仅保留最后一行。
- **失败场景**: 导出支持多品种行，但导入时同物种多行只保留最后 ─ 导入导出行为不对称。

#### 10. `UpdateStarOnFrame` 对非敌方 frame 仍创建无用 FontString

- **文件**: [Core.lua:130](Core.lua#L130)
- **摘要**: 友方宠物 frame 触发时 `GetOrCreateStar` 创建隐藏 ★，starIcons 表持续累积无用对象。
- **影响**: 长时间游戏内存缓慢增长。极端情况几百次战斗后有一定量的废弃 FontString。

---

## 汇总

| 严重度 | 数量 | 关键项 |
|--------|------|--------|
| 🔴 Critical | 2 | ownedCache 作用域 bug、timer 竞态 |
| 🟡 Important | 2 | 函数重复、encounterCache 覆盖 |
| 🔵 Minor | 2 | pcall 缺失、Rematch 不可用降级 |
| 🟢 Nice to Have | 4 | 魔法值散落、数据重复、导入不对称、FontString 泄漏 |

---

*报告生成: 2026-06-28 | 方法: code-review skill (high effort)*
