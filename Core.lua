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
local time = time
local type = type
local pairs = pairs
local ipairs = ipairs
local next = next
local tostring = tostring
local print = print
local C_Timer_After = C_Timer.After

-- ============================================================================
-- 常量
-- ============================================================================

local ADDON_NAME = "GenDexBD"
local CURRENT_DB_VERSION = 2

-- 斜杠命令（模块加载时立即注册，不等 PLAYER_LOGIN）
SlashCmdList["GENEDEXBDOPEN"] = function()
    if addonTable.ToggleConfigPanel then
        addonTable.ToggleConfigPanel()
    end
end
_G["SLASH_GENEDEXBDOPEN1"] = "/gbbd"

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
-- 战斗目标提示（GlowBoxTemplate — 参考 PetTracker 的方案）
-- ============================================================================
--
-- 使用暴雪内置 GlowBoxTemplate：金色发光边框 + 指向箭头
-- 锚定到 PetBattleFrame.ActiveEnemy.Icon 下方，类似 PetTracker 的提示框

-- 提示框单例
local alertGlowBox = nil

-- 本场战斗已提示的 speciesID 集合（防重复）
local battleAlertCache = {}

--- 创建或获取战斗提示框（单例，复用）
local function GetAlertGlowBox()
    if alertGlowBox then
        return alertGlowBox
    end

    -- 用 GlowBoxTemplate 创建（暴雪内置）
    alertGlowBox = CreateFrame("Frame", nil, PetBattleFrame, "GlowBoxTemplate")
    alertGlowBox:SetSize(240, 90)
    alertGlowBox:SetFrameStrata("HIGH")
    alertGlowBox:EnableMouse(true)

    -- 锚定到敌方宠物头像下方（与 PetTracker 一致的位置）
    alertGlowBox:SetPoint("TOP", PetBattleFrame.ActiveEnemy.Icon, "BOTTOM", 0, -20)

    -- 方向箭头指向上方（指向敌方宠物头像）
    -- GlowBox 有四套箭头：Bottom/Top/Left/Right，我们让 Top 箭头的 Arrow 指向 0°（朝上）
    if alertGlowBox.Top then
        alertGlowBox.Top:Show()
        if alertGlowBox.Top.Arrow then
            alertGlowBox.Top.Arrow:SetClampedTextureRotation(0)  -- 箭头朝上
        end
        if alertGlowBox.Top.Glow then
            alertGlowBox.Top.Glow:SetClampedTextureRotation(0)
        end
    end
    -- 隐藏不用的箭头
    for _, side in ipairs({"Bottom", "Left", "Right"}) do
        if alertGlowBox[side] then
            alertGlowBox[side]:Hide()
        end
    end

    -- 文本：用 GameFontHighlightLeft
    local text = alertGlowBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
    text:SetPoint("TOPLEFT", 16, -20)
    text:SetWidth(208)
    text:SetSpacing(4)
    alertGlowBox.Text = text

    -- 备注重叠行（小号灰色字体）
    local subText = alertGlowBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subText:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -2)
    subText:SetWidth(208)
    alertGlowBox.SubText = subText

    -- 关闭按钮
    local closeBtn = CreateFrame("Button", nil, alertGlowBox, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", 4, 5)
    closeBtn:SetScript("OnClick", function()
        PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_CLOSE or 850)
        alertGlowBox:Hide()
        alertGlowBox.closedInThisBattle = true
    end)
    alertGlowBox.Close = closeBtn

    alertGlowBox:Hide()
    return alertGlowBox
end

--- 在 GlowBox 中显示指定敌人的最优品种提示
--- @param petIndex number 敌方宠物索引 (1-3)
local function ShowAlertForPet(petIndex)
    if not GeneDexDB.Options.AlertInBattle then
        print("|cffff8800[GenDexBD]|r AlertInBattle 已关闭，跳过提示")
        return
    end

    -- 获取敌方宠物信息
    local speciesID = C_PetBattles.GetPetSpeciesID(2, petIndex)
    local health   = C_PetBattles.GetHealth(2, petIndex)
    local power    = C_PetBattles.GetPower(2, petIndex)
    local speed    = C_PetBattles.GetSpeed(2, petIndex)
    local name     = C_PetBattles.GetName(2, petIndex)

    print(string.format("|cffff8800[GenDexBD]|r 战斗检查: idx=%d speciesID=%s hp=%s pw=%s sp=%s name=%s",
        petIndex, tostring(speciesID), tostring(health), tostring(power), tostring(speed), tostring(name)))

    if not speciesID or not health or not power or not speed then
        return
    end

    -- 防重复
    if battleAlertCache[speciesID] then
        return
    end

    -- 检查最优列表
    local bestBreeds = GeneDexDB.BestBreeds[speciesID]
    if not bestBreeds or type(bestBreeds) ~= "table" then
        return
    end

    -- 推算敌方宠物品种（比例估算，可能有误差）
    local breedID = GuessBreedByRatio(health, power, speed)
    if not breedID then return end

    -- 精确匹配：只有推算出的 breedID 在最优列表中才提示
    local bestInfo = bestBreeds[breedID]
    if not bestInfo or type(bestInfo) ~= "table" then
        return  -- 推算出的品种不是用户标记的品种，不提示
    end

    print(string.format("|cffff8800[GenDexBD]|r 目标匹配！speciesID=%d breedID=%d", speciesID, breedID))

    -- 标记已提示
    battleAlertCache[speciesID] = true

    -- 获取 GlowBox
    local box = GetAlertGlowBox()
    if box.closedInThisBattle then
        return  -- 用户已在本场战斗中手动关闭，不再弹出
    end

    -- 分类标题
    local cat = bestInfo.category or "custom"
    local alertKey = "ALERT_CUSTOM"
    if cat == "pvp" then alertKey = "ALERT_PVP"
    elseif cat == "pve" then alertKey = "ALERT_PVE"
    elseif cat == "collection" then alertKey = "ALERT_COLLECTION" end

    local title = GetLocaleString(alertKey)
    local breedCode = GetBreedCode(breedID) or "?"
    local breedName = GetBreedDisplayName(breedID, breedCode)

    -- 主文本行：标题 + 宠物名 + 品种
    local mainText = title .. "\n" .. (name or "?") .. " — " .. breedName
    box.Text:SetText(mainText)

    -- 副文本行（备注，仅在有备注时显示）
    if bestInfo.note and bestInfo.note ~= "" then
        box.SubText:SetText(bestInfo.note)
        box.SubText:Show()
    else
        box.SubText:Hide()
    end

    -- 锚定到当前上场的敌方宠物头像
    -- 宠物切换时重新锚定
    local enemyIcon = PetBattleFrame.ActiveEnemy.Icon
    box:ClearAllPoints()
    box:SetPoint("TOP", enemyIcon, "BOTTOM", 0, -20)

    box:Show()
end

--- 检查敌方全部存活宠物（PET_BATTLE_OPENING_START 时调用）
local function CheckEnemyTeam()
    for i = 1, 3 do
        local h = C_PetBattles.GetHealth(2, i)
        if h and h > 0 then
            ShowAlertForPet(i)
        end
    end
end

--- 检查当前上场的敌方宠物（PET_BATTLE_PET_CHANGED 时调用）
local function CheckActiveEnemyPet()
    local idx = C_PetBattles.GetActivePet(2)
    if idx and idx >= 1 and idx <= 3 then
        ShowAlertForPet(idx)
    end
end

--- 清空战斗缓存 + 重置 GlowBox 关闭标记
local function ClearBattleCache()
    battleAlertCache = {}
    if alertGlowBox then
        alertGlowBox.closedInThisBattle = nil
        alertGlowBox:Hide()
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
        print("|cff00ff00[GenDexBD]|r JournalUI 模块已启动")
    else
        print("|cffff0000[GenDexBD]|r ⚠ JournalUI 模块未找到")
    end

    -- 初始化配置面板（注册到系统选项）
    if addonTable.InitConfig then
        addonTable.InitConfig()
    else
        print("|cffff0000[GenDexBD]|r ⚠ Config 模块未找到")
    end

    -- 斜杠命令：只在 PLAYER_LOGIN 最末尾注册，确保不被覆盖
    -- 用一个完全独立的前缀避免与任何插件冲突
    SlashCmdList["GENEDEXBDOPEN"] = function()
        if addonTable.ToggleConfigPanel then
            addonTable.ToggleConfigPanel()
        else
            print("|cffff0000[GenDexBD]|r 配置模块未加载，请输入 /reload")
        end
    end
    _G["SLASH_GENEDEXBDOPEN1"] = "/gbbd"

    -- 注册战斗事件
    eventFrame:RegisterEvent("PET_BATTLE_OPENING_START")
    eventFrame:RegisterEvent("PET_BATTLE_PET_CHANGED")
    eventFrame:RegisterEvent("PET_BATTLE_CLOSE")
end

--- 统一事件回调
local function OnEvent(_, event, ...)
    if event == "ADDON_LOADED" then
        OnAddonLoaded(...)
    elseif event == "PLAYER_LOGIN" then
        OnPlayerLogin()
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
