-- GenDexBD Core.lua
-- 核心调度模块：事件监听、数据库初始化、版本升级、模块启动协调
-- 加载顺序：第4个（依赖 Locales、BreedData、BreedMath）

local addonName, addonTable = ...

-- ============================================================================
-- 文件作用域 local 化
-- ============================================================================

local GetLocaleString = addonTable.GetLocaleString
local CalculateBreedFromStats = addonTable.CalculateBreedFromStats
local GuessBreedByRatio = addonTable.GuessBreedByRatio
local GetBreedCode = addonTable.GetBreedCode
local GetBreedDisplayName = addonTable.GetBreedDisplayName
local GetBestBreedCategoryName = addonTable.GetBestBreedCategoryName

local time = time
local type = type
local pairs = pairs
local ipairs = ipairs
local next = next
local tostring = tostring
local print = print
local C_Timer_After = C_Timer.After
local RaidNotice_AddMessage = RaidNotice_AddMessage

-- ============================================================================
-- 常量
-- ============================================================================

local ADDON_NAME = "GenDexBD"
local CURRENT_DB_VERSION = 2

-- 战斗提示颜色：金色
local ALERT_COLOR = { r = 1.0, g = 0.84, b = 0.0 }
-- 收藏提示颜色：淡金色
local COLLECTION_ALERT_COLOR = { r = 0.9, g = 0.75, b = 0.4 }

-- 数据库默认值
local DB_DEFAULTS = {
    BestBreeds = {},       -- { [speciesID] = { [breedID] = { category, note, addedAt } } }
    Options = {
        ShowInTooltip = true,
        ShowInJournal = true,
        AlertInBattle = true,
        AssumeRareQuality = true,
        ShowBestBreedNote = true,
    },
    DBVersion = CURRENT_DB_VERSION,
}

-- ============================================================================
-- 数据库初始化
-- ============================================================================

--- 递归深度合并：将 defaults 中缺失的键写入 target，已有数据不覆盖
--- @param target table 目标表（用户数据）
--- @param defaults table 默认值表
local function DeepMergeDefaults(target, defaults)
    for key, defaultVal in pairs(defaults) do
        if target[key] == nil then
            -- 缺失的键：直接写入默认值
            target[key] = defaultVal
        elseif type(defaultVal) == "table" and type(target[key]) == "table" then
            -- 两者都是表：递归合并
            -- 但数组不递归（BestBreeds 的内容由用户管理）
            if type(next(defaultVal)) == "nil" then
                -- 空表，跳过
            else
                -- 检查是否为数组
                local isArray = false
                for k in pairs(defaultVal) do
                    if type(k) == "number" then
                        isArray = true
                    end
                    break
                end
                if not isArray then
                    DeepMergeDefaults(target[key], defaultVal)
                end
            end
        end
        -- 否则：已有值，保持不动
    end
end

--- 初始化数据库结构，首次加载时写入默认值，版本升级时补充新键
local function InitDatabase()
    -- 首次加载：GeneDexDB 可能为 nil，需要初始化
    if GeneDexDB == nil then
        GeneDexDB = {}
    end

    -- 确保 BestBreeds 是表
    if type(GeneDexDB.BestBreeds) ~= "table" then
        GeneDexDB.BestBreeds = {}
    end

    -- 递归合并默认值
    DeepMergeDefaults(GeneDexDB, DB_DEFAULTS)

    -- 版本标记更新
    GeneDexDB.DBVersion = CURRENT_DB_VERSION
end

-- ============================================================================
-- 数据迁移
-- ============================================================================

--- v1 → v2 格式迁移：将旧数组格式 [speciesID] = {breedID, ...}
--- 转换为新映射格式 [speciesID] = {[breedID] = {category, note, addedAt}}
function addonTable.MigrateBestBreeds(db)
    local migrated = false

    for speciesID, breeds in pairs(db.BestBreeds) do
        -- 检测旧格式：用数组形式存储（第一个键是数字键1而非品种ID）
        -- 旧格式: { [1] = breedID1, [2] = breedID2, ... }
        -- 新格式: { [breedID] = { category=..., note=..., addedAt=... } }
        if type(breeds[1]) == "number" then
            migrated = true
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

    if migrated then
        local msg = GetLocaleString("MIGRATION_COMPLETE")
        print("|cffffd700[GenDexBD]|r " .. msg)
    end
end

-- ============================================================================
-- 战斗缓存与提示
-- ============================================================================

-- 战斗内已提示缓存，防止重复提示同一只宠物
local battleAlertCache = {}

--- 清空战斗缓存
local function ClearBattleCache()
    battleAlertCache = {}
end

--- 检查单只敌方宠物是否在最优属性列表中
--- @param petIndex number 敌方宠物位置索引 (1-3)
local function CheckEnemyPet(petIndex)
    if not GeneDexDB.Options.AlertInBattle then
        return
    end

    -- 获取敌方宠物信息
    local speciesID = C_PetBattles.GetPetSpeciesID(2, petIndex) -- team 2 = 敌方
    local health = C_PetBattles.GetHealth(2, petIndex)
    local power = C_PetBattles.GetPower(2, petIndex)
    local speed = C_PetBattles.GetSpeed(2, petIndex)
    local name = C_PetBattles.GetName(2, petIndex)
    local level = C_PetBattles.GetLevel(2, petIndex)

    if not speciesID or not health or not power or not speed then
        return  -- 战斗数据尚未就绪
    end

    -- 缓存键：同一场战斗中不重复提示同一只宠物
    local cacheKey = speciesID
    if battleAlertCache[cacheKey] then
        return
    end

    -- 检查是否在最优属性列表中
    local bestBreeds = GeneDexDB.BestBreeds[speciesID]
    if not bestBreeds or type(bestBreeds) ~= "table" then
        return
    end

    -- 用比例估算方法推算品种
    local breedID = GuessBreedByRatio(health, power, speed)
    if not breedID then
        return
    end

    -- 检查该品种是否是最优
    local bestInfo = bestBreeds[breedID]
    if not bestInfo or type(bestInfo) ~= "table" then
        return
    end

    -- 标记已提示
    battleAlertCache[cacheKey] = true

    -- 根据分类生成提示文本
    local category = bestInfo.category or "custom"
    local alertKey = "ALERT_CUSTOM"  -- 默认
    local color = ALERT_COLOR

    if category == "pvp" then
        alertKey = "ALERT_PVP"
    elseif category == "pve" then
        alertKey = "ALERT_PVE"
    elseif category == "collection" then
        alertKey = "ALERT_COLLECTION"
        color = COLLECTION_ALERT_COLOR
    end

    local alertTitle = GetLocaleString(alertKey)
    local breedCode = GetBreedCode(breedID) or "?"
    local breedName = GetBreedDisplayName(breedID, breedCode)
    local categoryName = GetBestBreedCategoryName(category)

    -- 屏幕中央金色浮动提示
    local message = alertTitle .. " "
                    .. (name or "?") .. " - "
                    .. breedName .. " (" .. categoryName .. ")"
    RaidNotice_AddMessage(RaidBossEmoteFrame, message, color)
end

--- 检查敌方全部存活宠物（PET_BATTLE_OPENING_START 时调用）
local function CheckEnemyTeam()
    for i = 1, 3 do
        local health = C_PetBattles.GetHealth(2, i)
        if health and health > 0 then
            CheckEnemyPet(i)
        end
    end
end

--- 检查当前上场的敌方宠物（PET_BATTLE_PET_CHANGED 时调用）
local function CheckActiveEnemyPet()
    local activePet = C_PetBattles.GetActivePet(2)  -- team 2 = 敌方
    if activePet and activePet >= 1 and activePet <= 3 then
        CheckEnemyPet(activePet)
    end
end

-- ============================================================================
-- 事件处理
-- ============================================================================

local eventFrame = nil

--- ADDON_LOADED 事件处理
local function OnAddonLoaded(name)
    if name ~= ADDON_NAME then
        return
    end

    -- 初始化数据库
    InitDatabase()

    -- 执行数据迁移
    addonTable.MigrateBestBreeds(GeneDexDB)

    -- 注册延迟启动事件
    eventFrame:RegisterEvent("PLAYER_LOGIN")
end

--- PLAYER_LOGIN 事件处理（UI 就绪后执行）
local function OnPlayerLogin()
    -- 打印欢迎信息
    local msg = GetLocaleString("ADDON_LOADED")
    print("|cff00ff00[GenDexBD]|r " .. msg)

    -- 启动 UI 模块（带诊断日志）
    if addonTable.InitTooltip then
        addonTable.InitTooltip()
        print("|cff00ff00[GenDexBD]|r Tooltip 模块已启动")
    else
        print("|cffff0000[GenDexBD]|r ⚠ Tooltip 模块未找到")
    end
    if addonTable.InitJournalUI then
        addonTable.InitJournalUI()
        print("|cff00ff00[GenDexBD]|r JournalUI 模块已启动（等待首次打开宠物手册时注入）")
    else
        print("|cffff0000[GenDexBD]|r ⚠ JournalUI 模块未找到")
    end

    -- 注册斜杠命令
    SlashCmdList["GENEDEXBD"] = function()
        if addonTable.ToggleConfigPanel then
            addonTable.ToggleConfigPanel()
        end
    end
    _G["SLASH_GENEDEXBD1"] = "/genedex"
    _G["SLASH_GENEDEXBD2"] = "/gd"

    -- 注册战斗事件
    eventFrame:RegisterEvent("PET_BATTLE_OPENING_START")
    eventFrame:RegisterEvent("PET_BATTLE_PET_CHANGED")
    eventFrame:RegisterEvent("PET_BATTLE_CLOSE")

    -- 注册宠物手册刷新事件
    eventFrame:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
end

--- 统一事件回调
local function OnEvent(_, event, ...)
    if event == "ADDON_LOADED" then
        OnAddonLoaded(...)
    elseif event == "PLAYER_LOGIN" then
        OnPlayerLogin()
    elseif event == "PET_JOURNAL_LIST_UPDATE" then
        if addonTable.RefreshJournalList then
            addonTable.RefreshJournalList()
        end
    elseif event == "PET_BATTLE_OPENING_START" then
        -- 延迟 0.5 秒等战斗数据填充完毕
        C_Timer_After(0.5, CheckEnemyTeam)
    elseif event == "PET_BATTLE_PET_CHANGED" then
        CheckActiveEnemyPet()
    elseif event == "PET_BATTLE_CLOSE" then
        ClearBattleCache()
    end
end

-- ============================================================================
-- 初始化
-- ============================================================================

--- 插件入口（由 .toc 加载顺序保证在 ADDON_LOADED 之前执行）
eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", OnEvent)

-- 暴露 OnInit 给可能的测试调用
addonTable.OnAddonLoaded = function(name)
    OnAddonLoaded(name)
end
