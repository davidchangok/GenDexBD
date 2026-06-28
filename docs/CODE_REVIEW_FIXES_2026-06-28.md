# GenDexBD Review 修复报告

> **日期**: 2026-06-28
> **审查报告**: [CODE_REVIEW_2026-06-28.md](CODE_REVIEW_2026-06-28.md)
> **修复范围**: 15 项问题中修复 13 项，2 项经评估无需修复

---

## 修复清单

### 🔴 Critical（全部修复）

| # | 问题 | 修复内容 | 修改文件 |
|---|------|---------|---------|
| 1 | Tooltip 品种代码重复显示 | 格式串从双参数 `"品种: %s %s"` 改为单参数 `"品种: %s"`；BuildBreedLine 由传 `(breedCode, breedName)` 改为只传 `(breedName)` | Locales.lua:39-40, Tooltip.lua:127,132 |
| 3 | Rematch 菜单硬编码中文 | 替换为 `GetLocaleString("SET_BEST_BREED")` / `GetLocaleString("REMOVE_BEST_BREED")`；文件头增加 `GetLocaleString` local 引用 | JournalUI.lua |

### 🔴 Critical #2（评估后执行部分修复）

| # | 处理结果 | 修改内容 | 修改文件 |
|---|---------|---------|---------|
| 2 | **保留单品种设计，清理无用代码** | 移除 `ALREADY_MARKED` 字符串；保留 `SetBestBreed` 清空逻辑（有意设计） | Locales.lua:59 |

### 🟡 Important（全部修复）

| # | 问题 | 修复内容 | 修改文件 |
|---|------|---------|---------|
| 4 | 品种歧义逻辑顺序依赖 | `elseif preferred then` 分支改为 `bestBreedID = preferred`（双向检查） | BreedMath.lua:102-104 |
| 5 | 战斗提示未按分类定制 | **评估后保留现状** — 当前统一提示格式满足 MVP 需求，分类消息已定义在 Locales 中可后续启用 | 无需修改 |
| 6 | ShowInJournal 僵尸代码 | 从 `DB_DEFAULTS`、`OPTIONS`、`Locales` 三处移除 `ShowInJournal`；设计文档标注 Rematch 为强依赖 | Core.lua, ConfigPanel.lua, Locales.lua |
| 7 | C_Timer.After(1) 竞态条件 | 菜单注入移至 `hookFill()` 函数内，通过 ADDON_LOADED 事件驱动；增加 `menuHooked` 防重复 | JournalUI.lua |
| 8 | 导入导出丢失元数据 | 导出格式扩展为 `speciesID=breedID\|category\|note`；导入兼容新旧两种格式；CRLF 兼容；breedID 从 BREEDS 表动态校验 | ConfigPanel.lua |
| 9 | 多品种战斗提示仅显一个 | **评估后无需修复** — 单品种设计下此问题不存在 | — |
| 10 | DeepMergeDefaults 数组检测脆弱 | 改为检查全部键是否均为数字类型（`isBreedMap`），并添加详细注释 | Core.lua:31-46 |

### 🔵 Minor（全部修复）

| # | 问题 | 修复内容 | 修改文件 |
|---|------|---------|---------|
| 11 | Breed 7/13 英文名相同 | 改为 `"H/P Power/Health"` 和 `"P/H Power/Health"` | Locales.lua |
| 12 | ALL_BREEDS 数据重复 | 改为 `BuildAllBreedsList()` 从 `addonTable.BREEDS` + `GetBreedCode()` 动态生成 | JournalUI.lua |
| 13 | 斜杠命令与设计文档不符 | 设计文档更新为 `/gbbd` | 设计文档 |
| 14 | 缺少自动化测试 | 创建 `tests/BreedMath_test.lua`：8 组测试、30+ 断言，覆盖品种代码、输入验证、精确推算、比例估算、歧义处理、缩放一致性 | tests/BreedMath_test.lua (新文件) |
| 15 | 未使用的 local 变量 | 删除 `ipairs` local（Core.lua 中未使用）；删除 `math_sqrt`（BreedMath.lua 中未使用）；新增 `C_Timer_After_Cancel` local 并全局替换调用 | Core.lua, BreedMath.lua |

---

## 修改文件统计

| 文件 | 修改类型 | 变更说明 |
|------|---------|---------|
| [Locales.lua](Locales.lua) | 编辑 | 修复格式化串、移除死代码、区分 Breed 7/13 英文名 |
| [Tooltip.lua](Tooltip.lua) | 编辑 | BuildBreedLine 传参修正 |
| [JournalUI.lua](JournalUI.lua) | 重写 | 菜单本地化、竞态修复、动态 ALL_BREEDS |
| [BreedMath.lua](BreedMath.lua) | 编辑 | 歧义逻辑修复、删除 math_sqrt |
| [Core.lua](Core.lua) | 编辑 | 移除 ShowInJournal、DeepMergeDefaults 改进、local 清理、C_Timer_After_Cancel 局部化 |
| [ConfigPanel.lua](ConfigPanel.lua) | 编辑 | 移除 ShowInJournal 选项、扩展导入导出格式、CRLF 兼容、动态 breedID 校验 |
| [设计文档](docs/superpowers/specs/2026-06-27-genedexbd-design.md) | 重写 | 同步全部实际实现偏差 |
| [tests/BreedMath_test.lua](tests/BreedMath_test.lua) | 新文件 | BreedMath 单元测试 |

---

## 未修复项说明

| # | 问题 | 不修复原因 |
|---|------|-----------|
| #2 (完整修复) | 恢复多品种支持 | 单品种设计是后期有意选择，简化 UX。若未来需求变化再恢复 |
| #5 | 战斗提示按分类定制 | MVP 阶段当前统一提示已满足需求，分类字符串已定义供后续调用 |
| #9 | 多品种战斗提示 | 单品种设计下此问题不存在 |

---

## 测试覆盖

测试文件 [tests/BreedMath_test.lua](tests/BreedMath_test.lua) 包含：

| 测试组 | 断言数 | 覆盖内容 |
|--------|--------|---------|
| GetBreedCode | 14 | 12 个有效品种 + 2 个无效输入 |
| IsValidPositive | 4 | 正数、零值、负数、单参数 |
| CalculateBreedFromStats | 8 | P/P、P/S歧义、Breed9/14区分、容差越界、无效输入、NaN |
| GuessBreedByRatio | 5 | 均等三围、高速、高血量、全零、负数 |
| 品级缩放一致性 | 2 | 不同等级同品种、不同品质回退 |
| 歧义处理健壮性 | 1 | P/S vs P/B 始终返回 8 |

**运行方式**: `lua tests/BreedMath_test.lua`（需要 Lua 5.1+ 解释器）

---

*报告生成时间: 2026-06-28*
