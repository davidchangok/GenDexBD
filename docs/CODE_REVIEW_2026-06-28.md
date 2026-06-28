# GenDexBD 全量代码审查报告

> **审查日期**: 2026-06-28
> **审查方式**: requesting-code-review skill → 调度 Code Reviewer 子 Agent
> **审查范围**: 全部源文件 (6 Lua + 1 TOC + 1 设计文档)，root..HEAD
> **代码版本**: commit `5c1811f` — 导入导出：设置面板加导出/导入按钮 + 弹窗+解析
> **审查级别**: 全量（Full Review）

---

## 总体评估

| 维度 | 评分 | 说明 |
|------|------|------|
| 架构设计 | ⭐⭐⭐⭐ | 模块拆分清晰，加载顺序合理，事件驱动模式得当 |
| 数据库设计 | ⭐⭐⭐⭐ | SavedVariables 结构合理，v1→v2 迁移完整 |
| 错误处理 | ⭐⭐⭐ | 核心函数有输入验证，UI 创建层防护较弱 |
| 本地化 | ⭐⭐ | Locale 系统设计良好，但多处中文硬编码 |
| 代码整洁 | ⭐⭐⭐ | 核心逻辑可读性好，部分文件过度压缩 |
| 设计一致性 | ⭐⭐ | 实现与设计文档存在多项偏差 |
| 安全性 | ⭐⭐⭐⭐⭐ | 纯本地插件，无安全问题 |

**综合评级**: B− — 存在 3 个严重 UI 层面 Bug 和多项设计偏差需优先处理。

---

## 🔴 严重问题（必须修复）

### 🔴 #1 — Tooltip 品种行重复显示品种代码（100% 用户必现）

**文件**: [Tooltip.lua:120-133](Tooltip.lua#L120-L133)；[Locales.lua:132-152](Locales.lua#L132-L152)

**问题**: `GetBreedDisplayName(breedID, breedCode)` 返回的字符串**已包含**品种短代码，例如 `"P/P 攻击型"`。但 `BuildBreedLine` 使用 `"品种: %s %s"` 格式串传入了 `breedCode` (`"P/P"`) + `breedName` (`"P/P 攻击型"`)。最终输出: `"品种: P/P P/P 攻击型"` —— 品种代码重复两次。目标品种的 `BREED_TARGET_FORMAT` 同样存在此问题，输出 `"品种: P/P P/P 攻击型 🎯 PvP 对战"`。

**影响**: ⚠️ **每个宠物 Tooltip 都能看到**，严重 UI 展示缺陷。

**修复**:
```lua
-- 方案A: 格式串改为单参数
BREED_FORMAT = { zhCN = "品种: %s", enUS = "Breed: %s" }
BREED_TARGET_FORMAT = { zhCN = "品种: %s 🎯 %s", enUS = "Breed: %s 🎯 %s" }
-- BuildBreedLine 中只传 breedName，不传 breedCode

-- 方案B: GetBreedDisplayName 只返回 "攻击型"，BuildBreedLine 自行拼接 breedCode
```

---

### 🔴 #2 — SetBestBreed/Import 清空同物种所有已有标记（破坏多场景用例）

**文件**: [JournalUI.lua:10](JournalUI.lua#L10)；[ConfigPanel.lua:70](ConfigPanel.lua#L70)

**问题**: `GeneDexDB.BestBreeds[s] = {}` 在写入前**直接清空**该物种已有全部品种映射。设计文档 §4.5a 明确要求同一物种支持多个品种对应不同场景（如品种4→PvE + 品种14→PvP）。`Locales.lua:59` 的 `ALREADY_MARKED` 字符串因此变成永不被调用的死代码。提交 `fc05b63` 中这是有意为之的"同一物种只允许一个最优"，但设计文档从未同步。

**影响**: 用户无法为同一物种标记 PvP 和 PvE 两个最优品种，核心设计意图被破坏。

**修复**: 确认设计意图后二选一：
- （如果恢复多品种）删除 `JournalUI.lua:10` 和 `ConfigPanel.lua:70` 中的 `={}` 清空操作
- （如果坚持单品种）更新设计文档、移除 `ALREADY_MARKED` 字符串

---

### 🔴 #3 — Rematch 右键菜单文本硬编码中文（英文客户端完全不可用）

**文件**: [JournalUI.lua:92](JournalUI.lua#L92), [JournalUI.lua:106](JournalUI.lua#L106)

**问题**: 菜单文本 `"取消最优品种"`、`"设为最优品种"` 是**硬编码中文**。`Locales.lua:53-54` 已定义 `SET_BEST_BREED` / `REMOVE_BEST_BREED` 但从未被引用。TOC 文件声明 `## X-Localizations: enUS, zhCN` 与实际不符。

**影响**: 英文客户端用户在 Rematch 右键菜单看到乱码，菜单功能完全不可用。

**修复**:
```lua
-- JournalUI.lua 顶部添加
local GetLocaleString = addonTable.GetLocaleString

-- 替换硬编码
text = GetLocaleString("REMOVE_BEST_BREED")  -- 替代 "取消最优品种"
text = GetLocaleString("SET_BEST_BREED")     -- 替代 "设为最优品种"
```

---

## 🟡 重要问题（应该修复）

### 🟡 #4 — 品种歧义处理逻辑依赖迭代顺序（当前侥幸正确）

**文件**: [BreedMath.lua:95-108](BreedMath.lua#L95-L108)

**问题**: `FindBestMatch` 中 `elseif preferred then` 分支（第104-106行）是**空操作**，仅靠隐式迭代顺序（breedList 按 3→14 构建，8 在 10 之前）保证正确。若有人改用 `pairs` 遍历或调整 breedList 构建顺序，`bestBreedID` 会错误停留在 10 而非 8。

**影响**: 逻辑脆弱，维护性修改可能引入难以排查的品种匹配错误。

**修复**: 将第104-106行改为 `bestBreedID = preferred`。

---

### 🟡 #5 — 战斗提示未按分类显示专属消息（设计 §5.1 未实现）

**文件**: [Core.lua:103-134](Core.lua#L103-L134)

**问题**: 设计文档 §5.1 要求按分类定制提示（PvP→"PvP 目标发现！"、PvE→"PvE 目标发现！"、收藏→"收藏目标发现！"）。`Locales.lua:79-82` 已定义对应字符串，但 `ShowAlertForPet:121` 始终显示固定文本 `"最优属性 <宠物名> <品种代码>"`，从未读取 `bestInfo.category`。

**影响**: 用户无法判断遇到的是 PvP 目标（需切换队伍）还是收藏目标（需捕获），提示实用价值大打折扣。

**修复**: 根据 `bestInfo.category` 选择 `ALERT_PVP/ALERT_PVE/ALERT_COLLECTION/ALERT_CUSTOM` 对应的标题。

---

### 🟡 #6 — ShowInJournal 配置项是僵尸代码（原生面板集成已完全移除）

**文件**: [JournalUI.lua](JournalUI.lua)（全文）；[Core.lua:24](Core.lua#L24)；[ConfigPanel.lua:9](ConfigPanel.lua#L9)

**问题**: 设计文档 §4.5/4.5a 要求大量原生 PetJournal 集成（列表品种标注、详情面板、管理 UI）。但实际实现 **100% 依赖 Rematch**。`ShowInJournal` 选项存在于 `DB_DEFAULTS`、`OPTIONS`、`Locales` 三处，但 JournalUI 中**没有任何代码读取它**。TOC 未声明 Rematch 为依赖项。

**影响**: 
- 未装 Rematch 的用户看不到任何品种标注
- 设置面板的 `ShowInJournal` 开关是纯 UI 噪音

**修复**:
- 在 TOC 添加 `## Dependencies: Rematch` + `## RequiredDeps: Rematch`
- 从 `DB_DEFAULTS`/`OPTIONS`/`Locales` 中移除 `ShowInJournal`
- 更新设计文档

---

### 🟡 #7 — Rematch 菜单注入用 C_Timer.After(1) 存在竞态条件

**文件**: [JournalUI.lua:88](JournalUI.lua#L88)

**问题**: Fill hook 正确使用了 `ADDON_LOADED` 事件处理 Rematch 延迟加载，但菜单注入使用 `C_Timer.After(1, ...)` 硬等 1 秒。慢速机器/大量插件时 Rematch 可能超时未就绪，导致菜单静默丢失。

**影响**: 间歇性 bug，难以复现，慢速环境概率更高。

**修复**: 将菜单注入也移至 `ADDON_LOADED` 回调中，与 Fill hook 统一初始化。

---

### 🟡 #8 — 导入/导出丢失全部元数据（category、note、addedAt）

**文件**: [ConfigPanel.lua:22-31,60-77](ConfigPanel.lua#L22-L31)

**问题**: 导出格式 `speciesID=breedID` 仅保存 ID 映射。导入时全部重置为 `category="custom", note=""`。富元数据在序列化中完全丢失。

**影响**: 用户导出备份/跨账号恢复后，所有分类和备注永久丢失。

**修复**: 扩展导出格式为 `speciesID=breedID|category|note`，导入时解析恢复全部字段。

---

### 🟡 #9 — 多最优品种时战斗提示仅显示第一个

**文件**: [Core.lua:111-114](Core.lua#L111-L114)

**问题**: `for ... do breedID=bid; break end` 仅取第一个品种（pairs 顺序不确定）。即使修复 #2 恢复多品种支持，提示也只会显示一个。

**影响**: 多品种标记场景下战斗提示不完整。

**修复**: 收集所有标记品种，构建综合提示（或按 PvP > PvE > 收藏 > 自定义 优先级排序后取最高）。

---

### 🟡 #10 — DeepMergeDefaults 数组检测仅看第一个键类型

**文件**: [Core.lua:36-38](Core.lua#L36-L38)

**问题**: 仅检查 `defaultVal` 第一个键是否为数字来判定是否数组。逻辑脆弱，依赖键类型的巧合分布。

**影响**: 极端情况可能导致 DB 默认值合并不完整（目前未触发）。

**修复**: 改为检查值中是否存在 `category`/`note` 字段来判断 v2 格式。

---

## 🟢 次要问题（锦上添花）

| # | 文件 | 描述 | 修复建议 |
|---|------|------|----------|
| 11 | [Locales.lua:20,26](Locales.lua#L20-L26) | Breed 7 和 Breed 13 的 enUS 名均为 `"Power/Health"`，无法区分 | 添加代号如 `"HP Power/Health"` vs `"PH Power/Health"` |
| 12 | [JournalUI.lua:28](JournalUI.lua#L28) | `ALL_BREEDS` 数组与 BreedData 表数据重复 | 使用 `GetBreedCode()` 动态生成 |
| 13 | [Core.lua:19,166](Core.lua#L19-L166) | 斜杠命令 `/gbbd` 与设计文档中 `/genedex`/`/gd` 不符 | 同步更新文档 |
| 14 | — | BreedMath 作为纯函数模块无任何测试 | 添加 `tests/BreedMath_test.lua` |
| 15 | [Core.lua:10-11](Core.lua#L10-L11) | `local ipairs = ipairs` 等变量声明后未使用 | 删除未使用的 local 别名 |

---

## 📋 问题清单汇总

| 编号 | 严重度 | 文件:行号 | 简述 | 建议 |
|------|--------|-----------|------|------|
| 🔴1 | Critical | Tooltip.lua:120-133 | Tooltip 品种代码重复显示 | 改格式串 |
| 🔴2 | Critical | JournalUI.lua:10 / ConfigPanel.lua:70 | 每物种只允许一个最优品种 | 确认设计意图后修复 |
| 🔴3 | Critical | JournalUI.lua:92,106 | Rematch 菜单硬编码中文 | 改用 Locale |
| 🟡4 | Important | BreedMath.lua:95-108 | 歧义处理逻辑顺序依赖 | 改空操作为赋值 |
| 🟡5 | Important | Core.lua:103-134 | 战斗提示未按分类定制 | 实现分类消息 |
| 🟡6 | Important | 多文件 | ShowInJournal 是僵尸代码 | 添加依赖声明/清理 |
| 🟡7 | Important | JournalUI.lua:88 | C_Timer.After(1) 竞态 | 改用事件监听 |
| 🟡8 | Important | ConfigPanel.lua:22-77 | 导入导出丢失元数据 | 扩展序列化格式 |
| 🟡9 | Important | Core.lua:111-114 | 多品种仅显第一个 | 收集全部/build综合 |
| 🟡10 | Important | Core.lua:36-38 | 数组检测脆弱 | 改字段检测 |
| 🔵11 | Minor | Locales.lua:20,26 | enUS 名 Breed7/13 重复 | 添加代号 |
| 🔵12 | Minor | JournalUI.lua:28 | ALL_BREEDS 重复数据 | 动态生成 |
| 🔵13 | Minor | Core.lua:19 | 斜杠命令与文档不符 | 更新文档 |
| 🔵14 | Minor | — | 缺少测试 | 添加测试 |
| 🔵15 | Minor | Core.lua:10-11 | 未使用的 local | 删除 |

**总计**: 🔴 3 | 🟡 7 | 🔵 5 = **15 项**

---

## ✅ 正面发现

| 项目 | 说明 |
|------|------|
| **防崩溃 API 字段探测** | `DetectPetInfoFields()` 通过运行时分析避免硬编码字段名，应对暴雪 API 变更 |
| **纯函数 + 数据分离** | `BreedData.lua` 零副作用，`BreedMath.lua` 纯函数可独立测试 |
| **DB 向后兼容** | `MigrateBestBreeds` 平滑迁移 v1→v2 格式，`DeepMergeDefaults` 补全新配置项 |
| **性能优化** | 全局函数 local 化、breedList 扁平数组预计算、欧氏距离用平方值跳过 sqrt |
| **歧义文档化** | 8 vs 10 品种歧义在代码和数据中均有明确注释 |

---

## 🔧 修复优先级建议

### P0 — 发布前必须修复
1. **🔴#3** Rematch 菜单硬编码中文（英文用户完全不可用）
2. **🔴#1** Tooltip 品种代码重复（100% 用户可见 UI 缺陷）

### P1 — v1.1 修复
3. **🔴#2** 多品种支持（确认设计意图，需决策）
4. **🟡#5** 战斗提示按分类定制
5. **🟡#8** 导入导出元数据保留

### P2 — 可延后
6. **🟡#4** 歧义逻辑强化
7. **🟡#6** ShowInJournal 清理
8. **🟡#7** 竞态条件
9. 其余所有 🟡🔵

---

## 📐 设计文档 vs 实现偏差

| 设计文档描述 | 实际实现 | 偏移等级 |
|-------------|---------|----------|
| 原生 PetJournal 完整集成 (§4.5)| 100% Rematch 依赖 | 🔴 重大 |
| 多品种/多场景支持 (§4.5a) | 每物种仅一个最优 | 🟡 中等 |
| `/genedex` / `/gd` 命令 (§1.3) | `/gbbd` | 🔵 轻微 |
| `RaidNotice_AddMessage()` 战斗提示 (§4.7) | 自建 GlowBoxTemplate Frame | 🔵 轻微 |
| 分类定制战斗提示 (§5.1) | 统一固定文本 | 🟡 中等 |

---

*报告生成时间: 2026-06-28 | 审查方法: requesting-code-review skill → Code Reviewer Subagent*
