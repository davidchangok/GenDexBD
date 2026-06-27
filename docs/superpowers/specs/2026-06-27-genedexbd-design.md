# GeneDexBD 插件设计文档

> **版本**: 1.0.0
> **日期**: 2026-06-27
> **目标**: World of Warcraft 12.0 (Midnight) — 接口版本 120007

---

## 1. 项目概述

### 1.1 核心目标

为宠物对战玩家提供轻量级工具，用于：
1. **计算并显示**宠物品种（Breed，如 S/S 高速型、P/P 攻击型）
2. **记录管理**每种宠物的"最佳毕业品种"
3. **战斗中提示**遇到目标品种时醒目提醒

### 1.2 核心预设

- 满级终极属性预测默认以 **蓝色/精良品质 (Rare, API Quality 4)** 为基准
- 品种推算优先精确匹配（已知物种基准属性），失败时回退比例估算
- ⚠️ 注意：用户需求原文写 "Quality 3"，但 WoW API 中 Rare = Quality 4（1=Poor, 2=Common, 3=Uncommon, 4=Rare）。实现以 API 实际值为准。

### 1.3 技术选型

| 项目 | 选择 |
|------|------|
| 架构模式 | 事件驱动 MVC |
| 品种数据来源 | 混合方式 — 内置完整品种系数表 + 运行时校验兜底 |
| UI 集成深度 | 完整交互集成 — Tooltip + Pet Journal 列表/详情 + 下拉菜单 |
| 配置入口 | 斜杠命令 `/genedex` / `/gd` |
| 支持语种 | 简体中文、英文（`GetLocale()` 自动检测） |

---

## 2. 文件架构

```GenDexBD/
├── GeneDexBD.toc            -- 插件清单：元数据、依赖、SavedVariables、加载顺序
├── Locales.lua              -- 多语种字符串表（中文/英文）
├── BreedData.lua            -- 内置品种系数映射表（纯数据，无逻辑）
├── BreedMath.lua            -- 品种推算引擎（纯函数集合）
├── Core.lua                 -- 核心调度：事件注册、DB 初始化、斜杠命令、模块协调
├── Tooltip.lua              -- 鼠标提示品种装饰
├── JournalUI.lua            -- Pet Journal 集成：列表标记、详情品种、最佳品种管理
└── ConfigPanel.lua          -- 配置面板：/genedex 打开的选项界面
```
### 2.1 .toc 加载顺序

1. `Locales.lua` — 字符串表，所有后续模块引用
2. `BreedData.lua` — 品种系数，BreedMath 依赖
3. `BreedMath.lua` — 纯函数，UI 模块调用
4. `Core.lua` — DB 初始化 + 事件注册 + 模块调度
5. `Tooltip.lua` — Tooltip hook 注册
6. `JournalUI.lua` — Pet Journal frame 注入
7. `ConfigPanel.lua` — 配置面板创建

### 2.2 启动时序

```游戏加载 .toc 文件
  → 依次执行 7 个 .lua 文件
  → ADDON_LOADED 事件 → OnAddonLoaded()
      ├── InitDatabase() — 合并默认配置到 GeneDexDB
      └── 注册事件监听（等待 PLAYER_LOGIN）
  → PLAYER_LOGIN → OnPlayerLogin()
      ├── 打印欢迎信息
      ├── InitTooltip() — TooltipDataProcessor 注册
      ├── InitJournalUI() — PetJournal frame 注入
      └── RegisterSlashCommands() — /genedex /gd
```
---

## 3. 数据流与模块交互

### 3.1 全局命名空间

通过 `.toc` 文件的 `addonTable` 在各模块间共享引用：

```Locales.lua   → addonTable.L
BreedData.lua → addonTable.BREEDS, addonTable.BREED_BY_ID, addonTable.QUALITY_MULTIPLIER
BreedMath.lua → addonTable.CalculateBreedFromStats(), addonTable.GuessBreedByRatio(), addonTable.GetBreedCode()
Tooltip.lua   → addonTable.InitTooltip()
JournalUI.lua → addonTable.InitJournalUI(), addonTable.SetBestBreed(), addonTable.IsBestBreed()
Core.lua      → addonTable.OnAddonLoaded()
```
### 3.2 主数据流

```游戏事件 (PET_JOURNAL_LIST_UPDATE / Tooltip / PET_BATTLE_*)
       │
       ▼
Core.lua (事件调度中心)
       │
       ├──► BreedMath.lua ← BreedData.lua (查找品种系数表)
       │         │
       │         ▼
       │    返回 BreedID + 品种短代码 (如 "P/P")
       │
       ├──► Tooltip.lua → 写入鼠标提示 (TooltipDataProcessor)
       ├──► JournalUI.lua → 更新列表/详情面板
       └──► ConfigPanel.lua → 读/写 GeneDexDB.Options
```
---

## 4. 模块详细设计

### 4.1 Locales.lua — 多语种字符串表

**职责**: 根据客户端语种提供本地化字符串。

**设计要点**:
- 使用 `GetLocale()` 自动检测客户端语种
- 简体中文 (`zhCN`) 和繁体中文 (`zhTW`) 共享中文字符串
- 其他语种统一走英文兜底
- 方便后续扩展更多语种
- 提供 `addonTable.GetBreedDisplayName(breedID)` 便捷函数，一次调用获得完整显示名

**关键映射**:
- `breedName_<ID>` → 品种描述名（如 "攻击型" / "Power"）
- 品质名、Tooltip/UI 标签、战斗提示文本

---

### 4.2 BreedData.lua — 品种系数数据表

**职责**: 存储语言无关的品种系数纯数据。

**品质修正系数** (`QUALITY_MULTIPLIER`):

| 品质ID | 名称 | 系数 |
|--------|------|------|
| 1 | 灰色 | 1.0 |
| 2 | 白色 | 1.1 |
| 3 | 绿色 | 1.2 |
| 4 | 蓝色（默认）| 1.3 |
| 5 | 紫色 | 1.4 |
| 6 | 橙色 | 1.5 |

**品种定义表** (`BREEDS`):

| BreedID | 短代码 | 健康系数 | 攻击系数 | 速度系数 | 备注 |
|---------|--------|---------|---------|---------|------|
| 3 | B/B | 1.0 | 1.0 | 1.0 | |
| 4 | P/P | 0.4 | 1.8 | 0.8 | |
| 5 | S/S | 0.4 | 0.8 | 1.8 | |
| 6 | H/H | 1.8 | 0.4 | 0.8 | |
| 7 | H/P | 1.4 | 1.4 | 0.2 | |
| 8 | P/S | 0.8 | 1.4 | 0.8 | ⚠️ 与 Breed 10 系数完全相同 |
| 9 | H/S | 1.4 | 0.2 | 1.4 | 旧版 H/S（1.4/0.2/1.4） |
| 10 | P/B | 0.8 | 1.4 | 0.8 | ⚠️ 与 Breed 8 系数完全相同 |
| 11 | S/B | 0.8 | 0.4 | 1.6 | |
| 12 | H/B | 1.2 | 0.8 | 1.0 | |
| 13 | P/H | 1.2 | 1.2 | 0.6 | |
| 14 | H/S | 1.2 | 0.6 | 1.2 | 新版 H/S（1.2/0.6/1.2） |

**已知品种歧义**:
- Breed 8 (P/S) 与 Breed 10 (P/B) 的属性系数**完全一致** (0.8, 1.4, 0.8)，纯算法无法区分。当匹配到这组系数时，算法返回 Breed 8 (P/S) 作为默认结果。
- Breed 9 和 Breed 14 短代码相同 (H/S) 但系数不同，算法**可以**通过系数区分，显示时均显示 "H/S"。
- BreedID 1-2 为旧版/未使用，游戏中实际使用 3-14 共 12 种。

---

### 4.3 BreedMath.lua — 品种推算引擎

**职责**: 纯函数模块 — 输入属性值，输出品种 ID。无副作用、无 UI 依赖、可独立测试。

**核心公式**:

```最终属性 = 物种基础属性 × 品种系数 × 品质修正 × 等级缩放

反推:
观测品种系数 = 实际属性 / (物种基础属性 × 品质修正 × 等级缩放)

等级缩放近似公式:
LevelFactor = 1 + (level - 1) × 0.2
```
**常量**:

| 常量 | 值 | 说明 |
|------|---|------|
| `MAX_TOLERANCE` | 0.15 | 精确推算最大容差（欧氏距离²） |
| `DEFAULT_QUALITY` | **4** | 默认品质 = 精良(Rare)，非用户原文说的3 |

> 用户原文说 "Quality 3 = 蓝色"，但 WoW API 实际为 Quality 4 = Rare。实现以 API 为准。

**两个推算入口**:

| 函数 | 场景 | 所需数据 | 容差 |
|------|------|---------|------|
| `CalculateBreedFromStats()` | 宠物手册 | 物种基准属性 + 当前属性 + 等级 + 品质 | 0.15（严格） |
| `GuessBreedByRatio()` | 战斗/捕获 | 仅当前属性（三围比例归一化） | 0.30（宽松） |

**匹配算法**:
1. 计算观测品种系数（反推或归一化）
2. 与 12 种品种理论系数做**欧氏距离**比对
3. 取距离最小的品种
4. 距离超出容差 → 返回 `nil`（"无法确定"）

**容差说明**: 欧氏距离容差用于容忍以下累积误差:
- WoW 界面显示整数，小数被截断
- 等级缩放公式为社区拟合近似
- Lua 浮点数运算微小偏差

---

### 4.4 Tooltip.lua — 鼠标提示装饰

**职责**: 在鼠标提示中追加品种信息行。

**触发场景**:

| 场景 | 数据类型 | 推算方式 |
|------|---------|---------|
| 宠物手册内悬停 | `Enum.TooltipDataType.BattlePet` | 精确推算 |
| 野外宠物悬停 | `Enum.TooltipDataType.BattlePet` | 精确推算 |
| 背包宠物笼物品 | `Enum.TooltipDataType.Item` | 尝试推算 |

**显示格式**:
- 普通品种：`品种: P/P 攻击型`（白色文本）
- 目标品种：`品种: P/P 攻击型 🎯 目标发现！`（金色文本 `1.0, 0.84, 0.0`）

**Hook 方式**: 使用 12.0 现代 API `TooltipDataProcessor.AddTooltipPostCall()`，不 hook 旧的 `OnTooltipSetItem`。

**开关控制**: `GeneDexDB.Options.ShowInTooltip` 为 `false` 时完全静默。

---

### 4.5 JournalUI.lua — 宠物手册集成

**职责**: 在暴雪 Pet Journal 面板中注入品种信息和交互控件。

**注入位置**:

| 位置 | 内容 | 技术方式 |
|------|------|---------|
| 列表页每行 | 品种短代码 (如 "P/P") + 最佳标记 ★ | 在列表按钮上创建 `FontString` 子元素 |
| 详情页 | "品种: P/P 攻击型" 文本行 | 在 `PetJournalPetCard` 上创建子 Frame |
| 详情页 | 最优属性管理区（下拉分类 + 备注输入 + 切换按钮） | 在品种行下方创建子 Frame 组 |

**列表刷新**: 监听 `PET_JOURNAL_LIST_UPDATE` 事件，遍历列表按钮更新品种短代码。

**安全策略**: 全部使用子 Frame 叠加方式，不修改暴雪原始 Frame 或其函数。

---

### 4.5a 最优属性管理 — 纯手动、用户自定义

**设计原则**: GenDexBD **绝不自动判定**哪种品种是"最优"。最优属性的定义权完全属于用户。
每种宠物、每个场景下"最优"的含义都不同——PvP 看重速度先手，PvE 看重攻击力，
收藏向玩家可能只收集特定品种。因此，本系统提供灵活的**手动标记+分类管理**接口。

#### 数据结构

```lua
-- GeneDexDB.BestBreeds[speciesID] 从简单数组升级为带元数据的映射表
GeneDexDB.BestBreeds = {
    [258] = {  -- 水黾 (Water Strider)
        [4] = {  -- P/P
            category = "pve",           -- 使用场景分类
            note = "PVE输出最高，适合日常任务",  -- 自定义备注
            addedAt = 1719500000,        -- 添加时间戳
        },
        [14] = {  -- H/S
            category = "pvp",
            note = "先手控制流必备",
            addedAt = 1719500100,
        },
    },
}
```
#### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `category` | string | 是（默认 `"custom"`） | 使用场景分类：`"pvp"`, `"pve"`, `"collection"`, `"custom"` |
| `note` | string | 否（默认 `""`） | 用户自由备注，说明为什么选这个品种 |
| `addedAt` | number | 自动 | `time()` 时间戳，记录添加时间 |

#### 预设分类（可扩展）

| 分类键 | 显示名 (zhCN) | 显示名 (enUS) | 用途 |
|--------|-------------|-------------|------|
| `"pvp"` | PvP 对战 | PvP Battle | 玩家对战最优品种 |
| `"pve"` | PvE 任务 | PvE Quest | PvE/任务/副本最优品种 |
| `"collection"` | 收藏 | Collection | 仅用于收藏，非战斗 |
| `"custom"` | 自定义 | Custom | 用户自行定义的其他场景 |

用户在添加最优品种时，通过下拉菜单选择分类，并可填写自由文本备注。
之后在宠物手册中浏览时，可以一眼看到每个品种被标记的场景和原因。

#### UI 交互流程

```宠物手册 → 选中宠物 → 详情面板显示当前品种
                              │
                              ├── 当前品种未标记为最优
                              │     ├── [分类下拉: PvP/PvE/收藏/自定义]
                              │     ├── [备注输入框: 选填]
                              │     └── [设为最优品种] 按钮
                              │
                              ├── 当前品种已标记为最优
                              │     ├── 显示已有分类标签 + 备注文本
                              │     ├── [修改分类/备注] 按钮
                              │     └── [取消最优品种] 按钮
                              │
                              └── 该物种已有其他品种被标记
                                    └── 显示 "该物种已标记: P/P(PvE), H/S(PvP)"
```
#### 详情面板最优属性区 UI 控件

```┌─────────────────────────────────────┐
│ 品种: P/P 攻击型                    │
│                                     │
│ ★ 最优属性管理 ─────────────────   │
│ 使用场景: [PvE 任务 ▼]             │  ← 下拉菜单 (Dropdown)
│ 备注信息: [PVE输出最高，适合...  ]  │  ← 输入框 (EditBox)
│                                     │
│ [取消最优品种]                      │  ← 按钮
│                                     │
│ 该物种已标记: P/P(PvE), H/S(PvP)   │  ← 信息行
└─────────────────────────────────────┘
```
#### 带备注的 Tooltip 展示

当鼠标悬停在已标记最优品种的宠物上时，Tooltip 展示分类和备注：

```品种: P/P 攻击型 🎯 PvE 任务
备注: PVE输出最高，适合日常任务
```
#### 数据迁移（v1.0 向后兼容）

首次加载时，如果检测到旧格式的简单数组数据（v1.0 初始版），自动迁移：

```lua
-- 旧格式: BestBreeds[258] = {4, 14}
-- 新格式: BestBreeds[258] = { [4] = {category="custom", note=""}, [14] = {category="custom", note=""} }
local function MigrateBestBreeds(db)
    for speciesID, breeds in pairs(db.BestBreeds) do
        if type(breeds[1]) == "number" then  -- 检测旧数组格式
            local newData = {}
            for _, breedID in ipairs(breeds) do
                newData[breedID] = {
                    category = "custom",
                    note = "",
                    addedAt = time(),
                }
            end
            db.BestBreeds[speciesID] = newData
        end
    end
end
```
---

### 4.6 ConfigPanel.lua — 配置面板

**职责**: 提供 `/genedex` 和 `/gd` 斜杠命令入口，展示简单设置面板。

**五个配置项**:

| 键 | 默认值 | 说明 |
|---|--------|------|
| `ShowInTooltip` | `true` | 鼠标提示中显示品种 |
| `ShowInJournal` | `true` | 宠物手册中显示品种 |
| `AlertInBattle` | `true` | 战斗中目标提示 |
| `AssumeRareQuality` | `true` | 默认按精良品质推算 |
| `ShowBestBreedNote` | `true` | Tooltip 中显示最优品种备注 |

**交互行为**:
- `/genedex` 或 `/gd` → 打开/关闭面板（toggle）
- 面板可拖拽移动
- 复选框即时写入 `GeneDexDB.Options`，SavedVariables 自动持久化

**UI 实现**: 使用 `BasicFrameTemplateWithInset` + `InterfaceOptionsCheckButtonTemplate` 标准模板。

---

### 4.7 Core.lua — 核心调度

**职责**: 插件入口，DB 初始化和版本升级，事件注册与转发，模块启动协调。

**事件映射**:

| 事件 | 处理 |
|------|------|
| `ADDON_LOADED` | 初始化 DB 结构 + 注册后续事件 |
| `PLAYER_LOGIN` | 启动所有 UI 模块（Tooltip / JournalUI / SlashCmd） |
| `PET_JOURNAL_LIST_UPDATE` | 通知 JournalUI 刷新列表品种 |
| `PET_BATTLE_OPENING_START` | 延迟 0.5s 后检查敌方队伍 |
| `PET_BATTLE_PET_CHANGED` | 立即检查新上场敌方宠物品种 |
| `PET_BATTLE_CLOSE` | 清理战斗临时缓存 |

**DB 初始化策略**:
- 首次加载：用 `DB_DEFAULTS` 完整初始化
- 版本升级：缺失的键自动补充默认值，不覆盖已有数据

**战斗提示**: 使用 `RaidNotice_AddMessage(RaidBossEmoteFrame, ...)` 做屏幕中央金色浮动提示。

---

## 5. 数据结构 (SavedVariables)

```lua
-- GeneDexDB 保存于 WTF/Account/<账号>/SavedVariables/GeneDexBD.lua
GeneDexDB = {
    BestBreeds = {
        -- [speciesID] = { [breedID] = { category, note, addedAt }, ... }
        [258] = {  -- 水黾 (Water Strider)
            [4] = {   -- P/P
                category = "pve",
                note = "PVE输出最高，适合日常任务",
                addedAt = 1719500000,
            },
            [14] = {  -- H/S
                category = "pvp",
                note = "先手控制流必备",
                addedAt = 1719500100,
            },
        },
    },
    Options = {
        ShowInTooltip = true,
        ShowInJournal = true,
        AlertInBattle = true,
        AssumeRareQuality = true,
        ShowBestBreedNote = true,    -- Tooltip 中显示最优备注
    },
    -- DB 版本号，用于升级迁移
    DBVersion = 2,
}
```
---

### 5.1 最优属性分类在战斗提示中的行为

战斗中当敌方宠物匹配到用户标记的最优品种时，Alert 行为按分类定制：

| 分类 | 战斗提示行为 |
|------|------------|
| `"pvp"` | 金色大字 "PvP 目标发现！" + 品种信息 |
| `"pve"` | 金色大字 "PvE 目标发现！" + 品种信息 |
| `"collection"` | 淡金色提示 "收藏目标发现！" |
| `"custom"` | 金色提示 "目标发现！" |

这样用户在战斗中可以立即知道遇到的是哪种场景的目标——PvP 目标可能需要切换特定队伍，
收藏目标可能意味着需要捕获而非击杀。

---

## 6. 全局 API 导出

| 函数 | 位置 | 说明 |
|------|------|------|
| `CalculateBreedFromStats(h, p, s, bh, bp, bs, lv, q)` | BreedMath | 精确推算品种 |
| `GuessBreedByRatio(h, p, s)` | BreedMath | 比例估算品种 |
| `GetBreedCode(breedID)` | BreedMath | 获取短代码 |
| `GetBreedDisplayName(breedID)` | Locales | 获取本地化显示名 |
| `SetBestBreed(speciesID, breedID, category, note)` | JournalUI | 设置最优品种（含分类和备注） |
| `RemoveBestBreed(speciesID, breedID)` | JournalUI | 移除最优品种标记 |
| `IsBestBreed(speciesID, breedID)` | JournalUI | 查询是否最优品种 |
| `GetBestBreedInfo(speciesID, breedID)` | JournalUI | 获取最优品种元数据（分类、备注、时间） |
| `GetAllBestBreeds(speciesID)` | JournalUI | 获取某物种所有最优品种及其元数据 |
| `GetCachedBreedText(speciesID, petID)` | JournalUI | 获取缓存品种文本 |
| `GetBestBreedCategoryName(category)` | Locales | 获取分类本地化名称 |
| `MigrateBestBreeds(db)` | Core | 旧格式数据迁移（v1→v2） |

---

## 7. 关键 WoW API 依赖

| API | 用途 | 来源 |
|-----|------|------|
| `C_PetJournal.GetPetInfoBySpeciesID()` | 获取物种基准属性 | 宠物手册 |
| `C_PetJournal.GetPetStats()` | 获取已拥有宠物当前属性 | 宠物手册 |
| `C_PetJournal.GetSelectedSpeciesID()` / `GetSelectedPetID()` | 获取当前选中宠物 | 宠物手册 |
| `C_PetJournal.GetPetInfoByItemID()` | 物品ID → speciesID | 宠物手册 |
| `C_PetBattles.GetActivePet()` | 获取战斗内宠物索引 | 宠物对战 |
| `C_PetBattles.GetPetSpeciesID()` / `GetHealth()` / `GetPower()` / `GetSpeed()` / `GetLevel()` / `GetName()` | 战斗内宠物属性 | 宠物对战 |
| `TooltipDataProcessor.AddTooltipPostCall()` | 现代 Tooltip hook | 12.0 API |
| `RaidNotice_AddMessage()` | 屏幕中央浮动提示 | UI |
| `GetLocale()` | 客户端语种检测 | 基础 |

---

## 8. 测试策略

### 8.1 单元测试（BreedMath）

在游戏外使用独立 Lua 环境验证：

- 给定标准属性值 → 输出期望的 BreedID
- 边界情况：零值属性、非整数属性、极端等级
- 容差边界：恰好 0.15 / 0.30 距离值的行为
- `CalculateBreedFromStats` 与 `GuessBreedByRatio` 对比一致性

### 8.2 集成测试

- Tooltip: 悬停宠物手册中已知品种的宠物，验证文本正确
- JournalUI: 打开宠物手册，验证列表和详情品种显示
- 配置面板: 开关各项配置，验证即时生效
- 战斗提示: 在宠物对战中验证目标发现提示

### 8.3 已知风险

- 暴雪 PetJournal Frame 命名在 12.0 可能变化，需实际验证
- `C_PetJournal.GetPetInfoBySpeciesID()` 返回字段名（baseHealth vs health）需实测确认
- 等级缩放公式为社区拟合，12.0 可能有调整

---

## 9. 版本兼容性

| 版本 | 状态 |
|------|------|
| 12.0.7 (Midnight) | 目标版本 |
| 11.x (Dragonflight) | 理论兼容（使用相同 API 集） |
| 10.x (The War Within) | 可能需要调整 API 调用 |

---

## 10. 后续扩展可能

以下功能不在 v1.0 范围内，但架构预留了扩展点：

- 更多语种支持（德语、法语、韩语等）
- 品种属性对比表（同一物种不同品种的满级属性并列展示）
- 宠物收藏进度追踪（已收集品种 / 总品种数）
- 队伍搭配建议（根据已标记最佳品种推荐 PvP 组合）
- 宠物品种数据库分享（公会/好友间共享标记数据）
