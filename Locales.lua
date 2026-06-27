-- GenDexBD Locales.lua
-- 多语种字符串表，根据客户端语种自动选择中文或英文
-- 加载顺序：第1个（最先加载，所有后续模块依赖）

local addonName, addonTable = ...

-- 检测客户端语种
local locale = GetLocale()  -- "zhCN", "enUS", "zhTW", "deDE", ...

-- ============================================================================
-- 字符串表
-- ============================================================================

-- 品种内部名称（用于生成显示名如"P/P 攻击型"）
local breedNames = {
    [3]  = { zhCN = "平衡型",   enUS = "Balanced" },
    [4]  = { zhCN = "攻击型",   enUS = "Power" },
    [5]  = { zhCN = "速度型",   enUS = "Speed" },
    [6]  = { zhCN = "生命型",   enUS = "Health" },
    [7]  = { zhCN = "攻血型",   enUS = "Power/Health" },
    [8]  = { zhCN = "攻速型",   enUS = "Power/Speed" },
    [9]  = { zhCN = "血速型",   enUS = "Health/Speed" },
    [10] = { zhCN = "攻平型",   enUS = "Power/Balanced" },
    [11] = { zhCN = "速平型",   enUS = "Speed/Balanced" },
    [12] = { zhCN = "血平型",   enUS = "Health/Balanced" },
    [13] = { zhCN = "攻生型",   enUS = "Power/Health" },
    [14] = { zhCN = "血速型",   enUS = "Health/Speed" },
}

-- 通用字符串表：键名 → { zhCN = "...", enUS = "..." }
local strings = {
    -- 系统消息
    ADDON_LOADED          = { zhCN = "GenDexBD 已加载。输入 /gbbd 打开设置。", enUS = "GenDexBD loaded. Type /gbbd to configure." },
    MIGRATION_COMPLETE    = { zhCN = "最优品种数据已升级到 v2 格式。",         enUS = "Best breed data migrated to v2 format." },
    SLASH_HELP            = { zhCN = "GenDexBD 命令: /gbbd 打开设置面板",       enUS = "GenDexBD commands: /gbbd to open settings" },

    -- 品种显示
    BREED_UNKNOWN         = { zhCN = "未知品种",   enUS = "Unknown Breed" },
    BREED_FORMAT          = { zhCN = "品种: %s %s", enUS = "Breed: %s %s" },
    BREED_TARGET_FORMAT   = { zhCN = "品种: %s %s 🎯 %s", enUS = "Breed: %s %s 🎯 %s" },

    -- 备注显示
    NOTE_LABEL            = { zhCN = "备注: %s",   enUS = "Note: %s" },

    -- 最优属性分类
    CATEGORY_PVP          = { zhCN = "PvP 对战",   enUS = "PvP Battle" },
    CATEGORY_PVE          = { zhCN = "PvE 任务",   enUS = "PvE Quest" },
    CATEGORY_COLLECTION   = { zhCN = "收藏",       enUS = "Collection" },
    CATEGORY_CUSTOM       = { zhCN = "自定义",     enUS = "Custom" },

    -- 最优属性管理 UI
    BEST_BREED_SECTION    = { zhCN = "★ 最优属性管理",        enUS = "★ Best Breed Management" },
    SET_BEST_BREED        = { zhCN = "设为最优品种",          enUS = "Set as Best Breed" },
    REMOVE_BEST_BREED     = { zhCN = "取消最优品种",          enUS = "Remove Best Breed" },
    UPDATE_BEST_BREED     = { zhCN = "更新分类/备注",         enUS = "Update Category/Note" },
    CATEGORY_LABEL        = { zhCN = "使用场景",              enUS = "Category" },
    NOTE_LABEL_UI         = { zhCN = "备注信息",              enUS = "Note" },
    NOTE_PLACEHOLDER      = { zhCN = "选填（如：PVE输出最高）", enUS = "Optional (e.g.: Best for PvE)" },
    ALREADY_MARKED        = { zhCN = "该物种已标记: %s",       enUS = "Species already marked: %s" },

    -- 配置面板
    CONFIG_TITLE          = { zhCN = "GenDexBD 设置",         enUS = "GenDexBD Settings" },
    OPTION_SHOW_TOOLTIP   = { zhCN = "鼠标提示显示品种",        enUS = "Show breed in tooltip" },
    OPTION_SHOW_JOURNAL   = { zhCN = "宠物手册显示品种",        enUS = "Show breed in journal" },
    OPTION_ALERT_BATTLE   = { zhCN = "战斗目标提示",           enUS = "Alert in battle" },
    OPTION_ASSUME_RARE    = { zhCN = "默认按精良品质推算",       enUS = "Assume Rare quality" },
    OPTION_SHOW_NOTE      = { zhCN = "提示中显示最优备注",       enUS = "Show best breed note in tooltip" },

    -- 战斗提示
    ALERT_PVP             = { zhCN = "PvP 目标发现！",    enUS = "PvP Target Found!" },
    ALERT_PVE             = { zhCN = "PvE 目标发现！",    enUS = "PvE Target Found!" },
    ALERT_COLLECTION      = { zhCN = "收藏目标发现！",     enUS = "Collection Target Found!" },
    ALERT_CUSTOM          = { zhCN = "目标发现！",        enUS = "Target Found!" },

    -- 品质名（用于调试/日志）
    QUALITY_POOR          = { zhCN = "灰色",   enUS = "Poor" },
    QUALITY_COMMON        = { zhCN = "白色",   enUS = "Common" },
    QUALITY_UNCOMMON      = { zhCN = "绿色",   enUS = "Uncommon" },
    QUALITY_RARE          = { zhCN = "蓝色",   enUS = "Rare" },
    QUALITY_EPIC          = { zhCN = "紫色",   enUS = "Epic" },
    QUALITY_LEGENDARY     = { zhCN = "橙色",   enUS = "Legendary" },

    -- 下拉菜单默认项
    DROPDOWN_SELECT       = { zhCN = "请选择场景", enUS = "Select Category" },
}

-- ============================================================================
-- 字符串查找函数
-- ============================================================================

-- 判断是否使用中文
local function IsChineseLocale()
    return locale == "zhCN" or locale == "zhTW"
end

-- 从字符串表中获取当前语种的文本
local function GetLocalizedString(tbl, key)
    local entry = tbl[key]
    if not entry then
        return "[" .. tostring(key) .. "]"
    end
    if IsChineseLocale() then
        return entry.zhCN or entry.enUS or tostring(key)
    else
        return entry.enUS or tostring(key)
    end
end

-- 暴露字符串查找函数供其他模块使用
addonTable.L = {
    GetString = GetLocalizedString,
    IsChineseLocale = IsChineseLocale,
}

-- ============================================================================
-- 公开 API 函数
-- ============================================================================

--- 获取品种的完整本地化显示名（如 "P/P 攻击型"）
--- @param breedID number 品种ID (3-14)
--- @param breedCode string|nil 品种短代码（如 "P/P"），传入则避免重复查找
--- @return string 本地化显示名
function addonTable.GetBreedDisplayName(breedID, breedCode)
    -- 获取短代码
    if not breedCode then
        breedCode = addonTable.GetBreedCode and addonTable.GetBreedCode(breedID)
        if not breedCode then
            return GetLocalizedString(strings, "BREED_UNKNOWN")
        end
    end

    -- 获取品种类型名
    local names = breedNames[breedID]
    if not names then
        return breedCode .. " " .. GetLocalizedString(strings, "BREED_UNKNOWN")
    end

    local typeName = IsChineseLocale() and names.zhCN or names.enUS
    if not typeName then
        typeName = GetLocalizedString(strings, "BREED_UNKNOWN")
    end

    return breedCode .. " " .. typeName
end

--- 获取最优属性分类的本地化名称
--- @param category string 分类键："pvp", "pve", "collection", "custom"
--- @return string 本地化分类名
function addonTable.GetBestBreedCategoryName(category)
    local categoryMap = {
        pvp = "CATEGORY_PVP",
        pve = "CATEGORY_PVE",
        collection = "CATEGORY_COLLECTION",
        custom = "CATEGORY_CUSTOM",
    }
    local stringKey = categoryMap[category] or "CATEGORY_CUSTOM"
    return GetLocalizedString(strings, stringKey)
end

--- 便捷函数：获取指定键的本地化字符串
--- @param key string 字符串键
--- @return string
function addonTable.GetLocaleString(key)
    return GetLocalizedString(strings, key)
end
