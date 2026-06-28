# GeneDexBD 插件设计文档

> **版本**: 1.0.0
> **日期**: 2026-06-28（最终更新）
> **目标**: World of Warcraft 12.0 (Midnight) — 接口版本 120007

---

## 1. 项目概述

### 1.1 核心目标

为宠物对战玩家提供轻量级工具，用于：
1. **计算并显示**宠物品种（Breed，如 S/S 高速型、P/P 攻击型）
2. **记录管理**每种宠物的最佳品种（纯手动标记，每物种一个）
3. **战斗中提示**遇到目标品种时醒目提醒
4. **导入导出**最优品种配置数据（含分类和备注）
5. **遇敌计数**野外战斗遇到目标品种自动统计

### 1.2 核心预设

- 满级终极属性预测默认以 **蓝色/精良品质 (Rare, API Quality 4)** 为基准
- 品种推算使用欧氏距离匹配 12 种品种系数
- 同一物种**只允许一个最优品种标记**
- 最优品种由用户**纯手动标记**，插件绝不自动判定
- **强依赖 Rematch**：所有数据优先从 Rematch 缓存获取

### 1.3 技术选型

| 项目 | 选择 |
|------|------|
| 架构模式 | 事件驱动 MVC |
| 品种数据来源 | 内置完整品种系数表 |
| UI 集成深度 | Tooltip + Rematch 宠物列表标注 + Rematch 右键菜单 |
| Rematch 依赖 | TOC 声明强依赖 |
| 配置入口 | 斜杠命令 `/gbbd` |
| 战斗提示 | GlowBoxTemplate 纯信息框 |
| 战斗标记 | 金色 ★ 叠加敌方头像（PetTracker 方案） |
| 遇敌计数 | Rematch roster 精确数据 |
| 支持语种 | 简体中文、英文（`GetLocale()` 自动检测） |

---

## 2. 文件架构

```
GenDexBD/
├── GenDexBD.toc            -- 插件清单：## Dependencies: Rematch
├── Locales.lua              -- 多语种字符串表（中文/英文）
├── BreedData.lua            -- 内置品种系数映射表（纯数据，无逻辑）
├── BreedMath.lua            -- 品种推算引擎（纯函数集合）
├── Core.lua                 -- 核心调度：事件注册、DB 初始化、战斗提示、遇敌计数、★标记
├── Tooltip.lua              -- 鼠标提示品种装饰（TooltipDataProcessor）
├── JournalUI.lua            -- Rematch 集成：品种标注 + 右键菜单
├── ConfigPanel.lua          -- 配置面板 + 导入导出
└── tests/
    └── BreedMath_test.lua   -- BreedMath 单元测试（30+ 断言）
```

### 2.1 TOC 加载顺序

1. `Locales.lua` — 字符串表，所有后续模块引用
2. `BreedData.lua` — 品种系数，BreedMath 依赖
3. `BreedMath.lua` — 纯函数，UI 模块调用
4. `Core.lua` — DB 初始化 + 事件注册 + 模块调度 + 战斗逻辑
5. `Tooltip.lua` — Tooltip hook 注册（TooltipDataProcessor）
6. `JournalUI.lua` — Rematch hook 注入 + 右键菜单
7. `ConfigPanel.lua` — 配置面板创建

---

## 3. 数据流与模块交互

### 3.1 全局命名空间

通过 `.toc` 文件的 `addonTable` 在各模块间共享引用：

```
Locales.lua   → addonTable.GetLocaleString, addonTable.GetBreedDisplayName, addonTable.GetBestBreedCategoryName
BreedData.lua → addonTable.BREEDS, addonTable.QUALITY_MULTIPLIER, addonTable.BREED_AMBIGUITY
BreedMath.lua → addonTable.CalculateBreedFromStats(), addonTable.GuessBreedByRatio(), addonTable.GetBreedCode()
Tooltip.lua   → addonTable.InitTooltip()
JournalUI.lua → addonTable.InitJournalUI(), addonTable.SetBestBreed(), addonTable.IsBestBreed(), addonTable.RemoveBestBreed()
Core.lua      → addonTable.InitConfig(), addonTable.ToggleConfigPanel()
```

### 3.2 战斗数据流

```
PET_BATTLE_OPENING_START  (0.5s延迟)
  │
  ├─ GetEnemyBreed(i) → Rematch.petInfo:Fetch("battle:2:N")  优选
  │                    └ GuessBreedByRatio(hp,pw,sp)          回退
  ├─ IsBestBreedMatch(sid, bid)  → GeneDexDB.BestBreeds[sid][bid]
  ├─ GetOwnedCount(sid) → Rematch.petInfo:Fetch(sid).count   缓存同场
  │   ├─ ≥3 → 跳过提示 & 不标★
  │   └─ <3 → showStarsFor[sid]=true → ★显示 + GlowBox提示
  │
  ├─ PET_BATTLE_PET_CHANGED → 重新扫描（无额外 Rematch 查询）
  │
  └─ PET_BATTLE_CLOSE
      └─ RecordEncounters() → EncounterStats[sid][bid] += 1（仅野外战）
```

---

## 4. 模块详细设计

### 4.1 Locales.lua — 多语种字符串表

**职责**: 根据客户端语种提供本地化字符串。

- `GetLocale()` 自动检测，`zhCN`/`zhTW` 共享中文
- Breed 7 (H/P) 与 Breed 13 (P/H) 英文名已区分
- 新增字符串：`SET_OTHER_BREED`、`ALL_OWNED`、`OPTION_TRACK_ENCOUNTERS`、`ALERT_TARGET`

### 4.2 BreedData.lua — 品种系数数据表

**职责**: 存储语言无关的品种系数纯数据（12 种，breedID 3-14）。

| BreedID | 短代码 | 系数 | 备注 |
|---------|--------|------|------|
| 8 | P/S | 0.8/1.4/0.8 | ⚠️ 与 Breed 10 系数完全一致 |
| 10 | P/B | 0.8/1.4/0.8 | ⚠️ BREED_AMBIGUITY[10]=8 声明优先返回 P/S |

### 4.3 BreedMath.lua — 品种推算引擎

**职责**: 纯函数模块，无副作用、无 UI 依赖、可独立测试。

- `CalculateBreedFromStats()` — 精确推算（需物种基准属性）
- `GuessBreedByRatio()` — 比例估算（仅三围比例归一化）
- `GetBreedCode()` — 获取短代码（"P/P", "H/S" 等）
- 歧义处理：`BREED_AMBIGUITY` 双向检查，不依赖迭代顺序

### 4.4 Tooltip.lua — 鼠标提示装饰

**职责**: 在鼠标提示中追加品种信息行。

| 场景 | 数据类型 | 方式 |
|------|---------|------|
| 宠物手册内悬停 | `Enum.TooltipDataType.BattlePet` | 精确推算 |
| 背包宠物笼物品 | `Enum.TooltipDataType.Item` | 显示已标记品种汇总 |

**显示格式**:
- 普通品种：`品种: P/P 攻击型`（白色）
- 目标品种：`品种: P/P 攻击型 🎯 自定义`（金色）

**字段探测**: `DetectPetInfoFields()` 运行时分析 API 返回字段名，避免硬编码。

### 4.5 JournalUI.lua — Rematch 集成

**职责**: 通过 Rematch 接口标注品种并提供右键菜单管理最优品种。

| 功能 | 技术方式 |
|------|---------|
| 列表品种标注 | `hooksecurefunc` Rematch Mixin.Fill |
| 最优品种标记 | ★ 前缀 + 金色文本 |
| 右键菜单 | `Rematch.menus:AddToMenu("PetMenu", ...)` |

**菜单结构**:
```
右键宠物 →
  ━ 最优属性设置 ━
    ├ P/P 最优属性设置 / P/P ★ 取消最优属性
    └ 设为其他属性 → [全部12品种子菜单]
```

- 使用 `subMenuFunc` 动态构建，`Rematch.menus:Register` 注册命名菜单
- `pcall` 保护注入，PetMenu 未就绪时自动延迟重试（最多 5 次）
- Fill hook 和菜单均通过 `ADDON_LOADED("Rematch")` 事件统一初始化

**品种操作函数**:
- `SetBestBreed(speciesID, breedID)` — 标记最优（每次清空同物种已有标记）
- `RemoveBestBreed(speciesID, breedID)` — 取消标记
- `IsBestBreed(speciesID, breedID)` — 查询

### 4.6 Core.lua — 核心调度

**职责**: 插件入口，DB 初始化，战斗逻辑，事件调度。

**战斗流程**:
1. `PET_BATTLE_OPENING_START` → 0.5s 后遍历敌方 3 只宠物
2. 获取品种：`Rematch.petInfo:Fetch("battle:2:N")` → `GuessBreedByRatio` 回退
3. 查询 `GeneDexDB.BestBreeds[speciesID][breedID]` 是否标记
4. `CountOwnedSpecies(speciesID)` → `Rematch.petInfo:Fetch(sid).count`
5. < 3 只 → 显示 GlowBox 提示 + 敌方头像金色 ★
6. `PET_BATTLE_CLOSE` → 野外战斗写入 `EncounterStats`

**金色 ★ 标记**: `hooksecurefunc('PetBattleUnitFrame_UpdateDisplay', ...)` 在敌方 frame 上创建 `FontString`，26pt 金色 `OUTLINE`。

**配置项**:

| 键 | 默认值 | 说明 |
|---|--------|------|
| `ShowInTooltip` | true | 鼠标提示显示品种 |
| `AlertInBattle` | true | 战斗目标提示 |
| `AssumeRareQuality` | true | 默认按精良品质推算 |
| `ShowBestBreedNote` | true | Tooltip 中显示最优备注 |
| `TrackEncounters` | true | 遇敌属性计数 |
| `AlertDuration` | 5 | 提示显示时间（1-30 秒） |

### 4.7 ConfigPanel.lua — 配置面板

**职责**: 提供 `/gbbd` 斜杠命令，展示设置面板 + 导入导出。

**导入导出格式**: `speciesID=breedID|category|note`（元数据完整保留，兼容旧格式）

---

## 5. 数据结构 (SavedVariables)

```lua
GeneDexDB = {
    BestBreeds = {
        [speciesID] = { [breedID] = { category, note, addedAt } },
    },
    EncounterStats = {
        [speciesID] = { [breedID] = count },
    },
    Options = {
        ShowInTooltip, AlertInBattle, AssumeRareQuality,
        ShowBestBreedNote, TrackEncounters, AlertDuration,
    },
    DBVersion = 2,
}
```

---

## 6. Rematch 数据依赖

| Rematch 接口 | 用途 | 位置 |
|-------------|------|------|
| `Rematch.petInfo:Fetch("battle:2:N")` | 获取敌方宠物精确 breedID | Core.lua GetEnemyBreed |
| `Rematch.petInfo:Fetch(speciesID).count` | 获取同物种已拥有数量 | Core.lua CountOwnedSpecies |
| `Rematch.petInfo:Fetch(petID)` | 获取宠物完整信息 | JournalUI.lua 多处 |
| `Rematch.menus:AddToMenu("PetMenu",...)` | 注册右键菜单 | JournalUI.lua |
| `Rematch.menus:Register(name, items)` | 注册命名子菜单 | JournalUI.lua |
| `Rematch.petsPanel:Update()` | 刷新宠物列表 | JournalUI.lua |
| `hooksecurefunc(RematchXxxMixin, "Fill", ...)` | 品种标注 | JournalUI.lua |

---

## 7. 测试

`tests/BreedMath_test.lua` — 30+ 断言覆盖：品种代码获取、输入验证、精确推算、比例估算、歧义处理、缩放一致性。

---

## 8. 版本兼容性

| 版本 | 状态 |
|------|------|
| 12.0.x (Midnight) | ✅ 目标版本 |
| 11.x | 理论兼容 |

---

*文档最后更新: 2026-06-28*
