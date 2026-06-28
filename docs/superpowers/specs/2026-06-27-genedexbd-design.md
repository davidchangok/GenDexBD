# GeneDexBD 插件设计文档

> **版本**: 1.0.0
> **日期**: 2026-06-28（更新）
> **目标**: World of Warcraft 12.0 (Midnight) — 接口版本 120007

---

## 1. 项目概述

### 1.1 核心目标

为宠物对战玩家提供轻量级工具，用于：
1. **计算并显示**宠物品种（Breed，如 S/S 高速型、P/P 攻击型）
2. **记录管理**每种宠物的"最佳品种"（纯手动标记）
3. **战斗中提示**遇到目标品种时醒目提醒
4. **导入导出**最优品种配置数据

### 1.2 核心预设

- 满级终极属性预测默认以 **蓝色/精良品质 (Rare, API Quality 4)** 为基准
- 品种推算优先精确匹配（已知物种基准属性），失败时回退比例估算
- 同一物种**只允许一个最优品种标记**（每个物种只能有一个"最优"品种）
- 最优品种由用户**纯手动标记**，插件绝不自动判定

### 1.3 技术选型

| 项目 | 选择 |
|------|------|
| 架构模式 | 事件驱动 MVC |
| 品种数据来源 | 内置完整品种系数表 |
| UI 集成深度 | Tooltip + Rematch 右键菜单 |
| Rematch 依赖 | 强依赖 Rematch（宠物列表品种标注 + 右键菜单） |
| 配置入口 | 斜杠命令 `/gbbd` |
| 战斗提示 | 自建 GlowBoxTemplate Frame（非 RaidNotice） |
| 支持语种 | 简体中文、英文（`GetLocale()` 自动检测） |

---

## 2. 文件架构

```
GenDexBD/
├── GenDexBD.toc            -- 插件清单：元数据、依赖、SavedVariables、加载顺序
├── Locales.lua              -- 多语种字符串表（中文/英文）
├── BreedData.lua            -- 内置品种系数映射表（纯数据，无逻辑）
├── BreedMath.lua            -- 品种推算引擎（纯函数集合）
├── Core.lua                 -- 核心调度：事件注册、DB 初始化、斜杠命令、模块协调
├── Tooltip.lua              -- 鼠标提示品种装饰（TooltipDataProcessor 现代 API）
├── JournalUI.lua            -- Rematch 集成：品种标记 + 右键菜单
├── ConfigPanel.lua          -- 配置面板 + 导入导出
└── tests/
    └── BreedMath_test.lua   -- BreedMath 单元测试
```

### 2.1 .toc 加载顺序

1. `Locales.lua` — 字符串表，所有后续模块引用
2. `BreedData.lua` — 品种系数，BreedMath 依赖
3. `BreedMath.lua` — 纯函数，UI 模块调用
4. `Core.lua` — DB 初始化 + 事件注册 + 模块调度
5. `Tooltip.lua` — Tooltip hook 注册
6. `JournalUI.lua` — Rematch hook 注入 + 菜单
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

---

## 4. 模块详细设计

### 4.1 Locales.lua — 多语种字符串表

**职责**: 根据客户端语种提供本地化字符串。

**设计要点**:
- 使用 `GetLocale()` 自动检测客户端语种
- 简体中文 (`zhCN`) 和繁体中文 (`zhTW`) 共享中文字符串
- 其他语种统一走英文兜底
- 提供 `addonTable.GetBreedDisplayName(breedID)` 便捷函数，一次调用获得完整显示名（如 `"P/P 攻击型"`）
- Breed 7 和 Breed 13 英文名区分：`"H/P Power/Health"` vs `"P/H Power/Health"`

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
| 9 | H/S | 1.4 | 0.2 | 1.4 | 旧版 H/S |
| 10 | P/B | 0.8 | 1.4 | 0.8 | ⚠️ 与 Breed 8 系数完全相同 |
| 11 | S/B | 0.8 | 0.4 | 1.6 | |
| 12 | H/B | 1.2 | 0.8 | 1.0 | |
| 13 | P/H | 1.2 | 1.2 | 0.6 | |
| 14 | H/S | 1.2 | 0.6 | 1.2 | 新版 H/S |

**已知品种歧义**:
- Breed 8 (P/S) 与 Breed 10 (P/B) 的属性系数**完全一致**，纯算法无法区分。`BREED_AMBIGUITY[10] = 8` 声明当匹配到这组系数时返回 Breed 8。
- Breed 9 和 Breed 14 短代码相同 (H/S) 但系数不同，算法**可以**通过系数区分。

---

### 4.3 BreedMath.lua — 品种推算引擎

**职责**: 纯函数模块 — 输入属性值，输出品种 ID。无副作用、无 UI 依赖、可独立测试。

**核心公式**:

```
最终属性 = 物种基础属性 × 品种系数 × 品质修正 × 等级缩放

反推:
观测品种系数 = 实际属性 / (物种基础属性 × 品质修正 × 等级缩放)

等级缩放近似公式:
LevelFactor = 1 + (level - 1) × 0.2
```

**常量**:

| 常量 | 值 | 说明 |
|------|---|------|
| `MAX_TOLERANCE` | 0.15 | 精确推算最大容差（欧氏距离²） |
| `RATIO_TOLERANCE` | 0.30 | 比例估算最大容差（欧氏距离²） |
| `DEFAULT_QUALITY` | 4 | 默认品质 = 精良(Rare) |

**匹配算法**:
1. 计算观测品种系数（反推或归一化）
2. 与 12 种品种理论系数做**欧氏距离**比对
3. 取距离最小的品种
4. 距离超出容差 → 返回 `nil`（"无法确定"）
5. Breed 8 vs 10 歧义：`BREED_AMBIGUITY` 表声明优先返回 8

**关键优化**:
- 预计算 `breedList` 扁平数组避免 pairs 哈希遍历
- 欧氏距离比较使用平方值，跳过 sqrt
- 歧义处理不依赖迭代顺序（双向检查 BREED_AMBIGUITY）

---

### 4.4 Tooltip.lua — 鼠标提示装饰

**职责**: 在鼠标提示中追加品种信息行。

**触发场景**:

| 场景 | 数据类型 | 推算方式 |
|------|---------|---------|
| 宠物手册内悬停 | `Enum.TooltipDataType.BattlePet` | 精确推算 |
| 野外宠物悬停 | `Enum.TooltipDataType.BattlePet` | 精确推算 |
| 背包宠物笼物品 | `Enum.TooltipDataType.Item` | 显示已标记品种汇总 |

**显示格式**:
- 普通品种：`品种: P/P 攻击型`（白色文本）
- 目标品种：`品种: P/P 攻击型 🎯 PvP 对战`（金色文本 `1.0, 0.84, 0.0`）
- 宠物笼物品（无推算数据）：`★ 最优属性管理: P/P(PvE), H/S(PvP)`（金色）

**API 字段自动探测**: `DetectPetInfoFields()` 通过运行时分析 `C_PetJournal.GetPetInfoBySpeciesID` 返回表的字段名来定位三围数据键，避免硬编码字段名。

**Hook 方式**: 使用 12.0 现代 API `TooltipDataProcessor.AddTooltipPostCall()`。

---

### 4.5 JournalUI.lua — Rematch 集成

**职责**: 通过 Rematch 接口在宠物列表中标注品种并提供右键菜单管理最优品种。

**集成点**:

| 功能 | 技术方式 |
|------|---------|
| 列表品种标注 | `hooksecurefunc` Rematch Mixin.Fill，修改 Breed 文本 |
| 最优品种标记 | 品种前显示 ★，金色文本 |
| 已拥有宠物菜单 | Rematch 右键菜单：`设为最优品种` / `取消最优品种` |
| 未拥有宠物菜单 | 12 品种子菜单，按 speciesID+breedID 标记 |

**初始化策略**:
- Fill hook 和菜单注入使用统一的事件驱动初始化
- Rematch 已加载 → 直接注入
- Rematch 未加载 → 监听 `ADDON_LOADED` 事件等待
- 菜单注入不再使用 `C_Timer.After(1)` 避免竞态条件

**品种列表构建**: 从 `addonTable.BREEDS` 动态生成，`GetBreedCode()` 获取短代码，无重复数据源。

**菜单本地化**: 全部通过 `GetLocaleString()` 获取，中文/英文客户端均正常显示。

---

### 4.5a 最优属性数据结构

**设计原则**: GenDexBD **绝不自动判定**哪种品种是"最优"。最优属性的定义权完全属于用户。同一物种只允许标记**一个**最优品种。

```lua
GeneDexDB.BestBreeds = {
    [258] = {  -- 水黾 (Water Strider)
        [4] = {   -- P/P
            category = "custom",
            note = "",
            addedAt = 1719500000,
        },
    },
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `category` | string | 使用场景分类：`"pvp"`, `"pve"`, `"collection"`, `"custom"` |
| `note` | string | 用户自由备注，说明为什么选这个品种 |
| `addedAt` | number | `time()` 时间戳，记录添加时间 |

---

### 4.6 ConfigPanel.lua — 配置面板

**职责**: 提供 `/gbbd` 斜杠命令入口，展示设置面板 + 导入导出。

**五个配置项**:

| 键 | 默认值 | 说明 |
|---|--------|------|
| `ShowInTooltip` | `true` | 鼠标提示中显示品种 |
| `AlertInBattle` | `true` | 战斗中目标提示 |
| `AssumeRareQuality` | `true` | 默认按精良品质推算 |
| `ShowBestBreedNote` | `true` | Tooltip 中显示最优品种备注 |
| `AlertDuration` | `5` | 目标提示显示时间（1-30秒） |

**导入导出**:

- 导出格式：`speciesID=breedID|category|note`（每行一条，元数据完整保留）
- 导入格式：兼容新旧两种格式，自动解析
- CRLF/LF 行尾均支持
- 特殊字符转义（`\n` → `\\n`，`|` → `\\|`）
- breedID 有效范围从 `addonTable.BREEDS` 表动态获取

**斜杠命令**: `/gbbd` → 打开配置面板

---

### 4.7 Core.lua — 核心调度

**职责**: 插件入口，DB 初始化和版本升级，事件注册与转发，模块启动协调。

**事件映射**:

| 事件 | 处理 |
|------|------|
| `ADDON_LOADED` (GenDexBD) | 初始化 DB + 事件注册 |
| `PLAYER_LOGIN` | 启动所有 UI 模块 |
| `PET_BATTLE_OPENING_START` | 延迟 0.5s 检查敌方队伍 |
| `PET_BATTLE_PET_CHANGED` | 检查新上场敌方宠物 |
| `PET_BATTLE_CLOSE` | 清理战斗缓存 |

**战斗提示**: 使用 `GlowBoxTemplate` Frame 定位在 `PetBattleFrame.ActiveEnemy.Icon` 下方，自动消失定时器。纯信息展示框，不可点击。

**DB 初始化策略**:
- 首次加载：用 `DB_DEFAULTS` 完整初始化
- 版本升级：`DeepMergeDefaults` 补全缺失键（检查全部 key 类型，非 BestBreeds 映射表才递归合并）
- 旧格式迁移：`MigrateBestBreeds` 将 v1 简单数组自动升级为 v2 元数据格式

---

## 5. 数据结构 (SavedVariables)

```lua
GeneDexDB = {
    BestBreeds = {
        [speciesID] = { [breedID] = { category, note, addedAt } },
    },
    Options = {
        ShowInTooltip = true,
        AlertInBattle = true,
        AssumeRareQuality = true,
        ShowBestBreedNote = true,
        AlertDuration = 5,
    },
    DBVersion = 2,
}
```

---

## 6. 全局 API 导出

| 函数 | 位置 | 说明 |
|------|------|------|
| `CalculateBreedFromStats(h, p, s, bh, bp, bs, lv, q)` | BreedMath | 精确推算品种 |
| `GuessBreedByRatio(h, p, s)` | BreedMath | 比例估算品种 |
| `GetBreedCode(breedID)` | BreedMath | 获取短代码 |
| `GetBreedDisplayName(breedID)` | Locales | 获取本地化显示名 |
| `GetLocaleString(key)` | Locales | 获取本地化字符串 |
| `GetBestBreedCategoryName(category)` | Locales | 获取分类本地化名称 |
| `SetBestBreed(speciesID, breedID, category, note)` | JournalUI | 设置最优品种 |
| `RemoveBestBreed(speciesID, breedID)` | JournalUI | 移除最优品种标记 |
| `IsBestBreed(speciesID, breedID)` | JournalUI | 查询是否最优品种 |
| `GetAllBestBreeds(speciesID)` | JournalUI | 获取某物种所有最优品种 |
| `MigrateBestBreeds(db)` | Core | 旧格式迁移（v1→v2） |

---

## 7. 关键 WoW API 依赖

| API | 用途 |
|-----|------|
| `C_PetJournal.GetPetInfoBySpeciesID()` | 获取物种基准属性 |
| `C_PetJournal.GetPetStats()` | 获取已拥有宠物当前属性 |
| `C_PetJournal.GetPetInfoByItemID()` | 物品ID → speciesID |
| `C_PetBattles.*` | 战斗内宠物属性获取 |
| `TooltipDataProcessor.AddTooltipPostCall()` | 现代 Tooltip hook (12.0) |
| `Settings.RegisterAddOnCategory()` | 设置面板注册 |
| `GetLocale()` | 客户端语种检测 |

---

## 8. 测试策略

### 8.1 单元测试（BreedMath）

在 `tests/BreedMath_test.lua` 中使用 `assert` 进行回归测试：

- 给定标准属性值 → 输出期望的 BreedID
- 边界情况：零值属性、非整数属性、极端等级
- 容差边界：恰好 0.15 / 0.30 距离值的行为
- `CalculateBreedFromStats` 与 `GuessBreedByRatio` 对比一致性
- Breed 8 vs 10 歧义处理验证
- NaN / 无效输入防御验证

---

## 9. 版本兼容性

| 版本 | 状态 |
|------|------|
| 12.0.x (Midnight) | ✅ 目标版本 |
| 11.x (Dragonflight) | 理论兼容（使用相同 API 集） |
| 10.x (The War Within) | 可能需要调整 API 调用 |

---

## 10. 与 BattlePetBreedID 的设计对比

| 维度 | GenDexBD | BattlePetBreedID |
|------|----------|-----------------|
| 品种推算 | 欧氏距离匹配 | 绝对差值 min 匹配 |
| 品种范围 | 3-14（12种，含 13/14） | 3-12（10种） |
| 品名格式 | 短代码 + 中文/英文名称 | 仅短代码 (B/B, H/P...) |
| 最优品种 | 手动标记 + 导入导出 | 无 |
| 战斗提示 | GlowBoxTemplate 纯信息框 | 品种附加到宠物名后 |
| Tooltip 方式 | TooltipDataProcessor 现代 API | hooksecurefunc 传统 hook |
| Breed 8/10 歧义 | BREED_AMBIGUITY 表声明优先 | 系统最低 diff 自然优先 |

---

*文档最后更新: 2026-06-28*
