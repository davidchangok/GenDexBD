-- GenDexBD Core.lua

local addonName, addonTable = ...

local GetLocaleString = addonTable.GetLocaleString
local CalculateBreedFromStats = addonTable.CalculateBreedFromStats
local GuessBreedByRatio = addonTable.GuessBreedByRatio
local GetBreedCode = addonTable.GetBreedCode
local GetBreedDisplayName = addonTable.GetBreedDisplayName
local time = time;local type = type;local pairs = pairs
local next = next;local tostring = tostring;local print = print
local C_Timer_After = C_Timer.After
local C_Timer_After_Cancel = C_Timer_After_Cancel

local ADDON_NAME = "GenDexBD"
local CURRENT_DB_VERSION = 2

SlashCmdList["GENEDEXBDOPEN"] = function()
    if addonTable.ToggleConfigPanel then addonTable.ToggleConfigPanel() end
end
_G["SLASH_GENEDEXBDOPEN1"] = "/gbbd"

local DB_DEFAULTS = {
    BestBreeds = {},
    Options = {
        ShowInTooltip = true, AlertInBattle = true,
        AssumeRareQuality = true, ShowBestBreedNote = true, AlertDuration = 5,
    },
    DBVersion = CURRENT_DB_VERSION,
}

local function DeepMergeDefaults(target, defaults)
    for key, defaultVal in pairs(defaults) do
        if target[key] == nil then
            target[key] = defaultVal
        elseif type(defaultVal) == "table" and type(target[key]) == "table" then
            -- 空表跳过
            if type(next(defaultVal)) == "nil" then
            else
                -- 检查是否为 BestBreeds 映射表（所有键都是数字的品种ID映射）
                -- 若全部数字键则跳过深层合并，避免覆盖用户数据
                local isBreedMap = true
                for k in pairs(defaultVal) do
                    if type(k) ~= "number" then isBreedMap = false; break end
                end
                if not isBreedMap then DeepMergeDefaults(target[key], defaultVal) end
            end
        end
    end
end

local function InitDatabase()
    if GeneDexDB == nil then GeneDexDB = {} end
    if type(GeneDexDB.BestBreeds) ~= "table" then GeneDexDB.BestBreeds = {} end
    DeepMergeDefaults(GeneDexDB, DB_DEFAULTS)
    GeneDexDB.DBVersion = CURRENT_DB_VERSION
end

function addonTable.MigrateBestBreeds(db)
    local migrated = false
    for speciesID, breeds in pairs(db.BestBreeds) do
        if type(breeds[1]) == "number" then
            migrated = true
            local newData = {}
            for _, breedID in ipairs(breeds) do
                newData[breedID] = {category="custom",note="",addedAt=time()}
            end
            db.BestBreeds[speciesID] = newData
        end
    end
    if migrated then print("|cffffd700[GenDexBD]|r " .. GetLocaleString("MIGRATION_COMPLETE")) end
end

-- ========== 战斗目标提示（GlowBoxTemplate）==========

local alertGlowBox = nil
local battleAlertCache = {}

local function GetAlertGlowBox()
    if alertGlowBox then
        if alertGlowBox._hideTimer then C_Timer_After_Cancel(alertGlowBox._hideTimer);alertGlowBox._hideTimer=nil end
        return alertGlowBox
    end
    alertGlowBox = CreateFrame("Frame", nil, PetBattleFrame, "GlowBoxTemplate")
    alertGlowBox:SetSize(220, 56)
    alertGlowBox:SetFrameStrata("HIGH")
    alertGlowBox:SetPoint("TOP", PetBattleFrame.ActiveEnemy.Icon, "BOTTOM", 0, -20)
    if alertGlowBox.Top then
        alertGlowBox.Top:Show()
        if alertGlowBox.Top.Arrow then alertGlowBox.Top.Arrow:SetClampedTextureRotation(0) end
        if alertGlowBox.Top.Glow then alertGlowBox.Top.Glow:SetClampedTextureRotation(0) end
    end
    for _, side in ipairs({"Bottom","Left","Right"}) do
        if alertGlowBox[side] then alertGlowBox[side]:Hide() end
    end
    local text = alertGlowBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("CENTER", alertGlowBox, "CENTER", 0, 2)
    text:SetWidth(200);text:SetJustifyH("CENTER")
    alertGlowBox.Text = text
    alertGlowBox:Hide()
    return alertGlowBox
end

local function HideAlertBox()
    if alertGlowBox then
        if alertGlowBox._hideTimer then C_Timer_After_Cancel(alertGlowBox._hideTimer);alertGlowBox._hideTimer=nil end
        alertGlowBox:Hide()
    end
end

local function ShowAlertForPet(petIndex)
    if not GeneDexDB.Options.AlertInBattle then return end
    local speciesID = C_PetBattles.GetPetSpeciesID(2, petIndex)
    if not speciesID then return end
    if battleAlertCache[speciesID] then return end
    local bestBreeds = GeneDexDB.BestBreeds[speciesID]
    if not bestBreeds or type(bestBreeds)~="table" or not next(bestBreeds) then return end

    local breedID, bestInfo
    for bid, bdata in pairs(bestBreeds) do
        if type(bdata)=="table" then breedID=bid;bestInfo=bdata;break end
    end
    if not bestInfo then return end

    -- 校验敌方实际品种是否匹配保存的最优品种
    local hp = C_PetBattles.GetMaxHealth(2, petIndex)
    local pw = C_PetBattles.GetPower(2, petIndex)
    local sp = C_PetBattles.GetSpeed(2, petIndex)
    if hp and pw and sp and hp > 0 and pw > 0 and sp > 0 then
        local actualBreed = GuessBreedByRatio(hp, pw, sp)
        if actualBreed and actualBreed ~= breedID then
            return  -- 敌方实际品种不匹配，不提示
        end
    end

    battleAlertCache[speciesID] = true

    local breedCode = GetBreedCode(breedID) or "?"
    local petName = C_PetBattles.GetName(2, petIndex) or "?"
    local displayText = "最优属性 " .. petName .. " " .. breedCode

    local box = GetAlertGlowBox()
    box.Text:SetText(displayText)

    local enemyIcon = PetBattleFrame.ActiveEnemy.Icon
    box:ClearAllPoints();box:SetPoint("TOP", enemyIcon, "BOTTOM", 0, -20)
    box:Show()

    -- 自动消失定时器
    local duration = GeneDexDB.Options.AlertDuration or 5
    if box._hideTimer then C_Timer_After_Cancel(box._hideTimer) end
    box._hideTimer = C_Timer_After(duration, function() box:Hide();box._hideTimer=nil end)
end

local function CheckEnemyTeam()
    for i = 1, 3 do if C_PetBattles.GetHealth(2, i) and C_PetBattles.GetHealth(2, i) > 0 then ShowAlertForPet(i) end end
end
local function CheckActiveEnemyPet()
    local idx = C_PetBattles.GetActivePet(2);if idx and idx>=1 and idx<=3 then ShowAlertForPet(idx) end
end
local function ClearBattleCache()
    battleAlertCache = {};HideAlertBox()
end

-- ========== 事件处理 ==========

local eventFrame = nil

local function OnAddonLoaded(name)
    if name ~= ADDON_NAME then return end
    InitDatabase();addonTable.MigrateBestBreeds(GeneDexDB)
    eventFrame:RegisterEvent("PLAYER_LOGIN")
end

local function OnPlayerLogin()
    print("|cff00ff00[GenDexBD]|r " .. GetLocaleString("ADDON_LOADED"))
    if addonTable.InitTooltip then addonTable.InitTooltip();print("|cff00ff00[GenDexBD]|r Tooltip 模块已启动") end
    if addonTable.InitJournalUI then addonTable.InitJournalUI();print("|cff00ff00[GenDexBD]|r JournalUI 模块已启动") end
    if addonTable.InitConfig then addonTable.InitConfig() end
    SlashCmdList["GENEDEXBDOPEN"] = function()
        if addonTable.ToggleConfigPanel then
            addonTable.ToggleConfigPanel()
        else print("|cffff0000[GenDexBD]|r 配置模块未加载，请输入 /reload") end
    end
    _G["SLASH_GENEDEXBDOPEN1"] = "/gbbd"
    eventFrame:RegisterEvent("PET_BATTLE_OPENING_START");eventFrame:RegisterEvent("PET_BATTLE_PET_CHANGED");eventFrame:RegisterEvent("PET_BATTLE_CLOSE")
end

local function OnEvent(_, event, ...)
    if event == "ADDON_LOADED" then OnAddonLoaded(...)
    elseif event == "PLAYER_LOGIN" then OnPlayerLogin()
    elseif event == "PET_BATTLE_OPENING_START" then C_Timer_After(0.5, CheckEnemyTeam)
    elseif event == "PET_BATTLE_PET_CHANGED" then CheckActiveEnemyPet()
    elseif event == "PET_BATTLE_CLOSE" then ClearBattleCache()
    end
end

eventFrame = CreateFrame("Frame");eventFrame:RegisterEvent("ADDON_LOADED");eventFrame:SetScript("OnEvent", OnEvent)
addonTable.OnAddonLoaded = function(name) OnAddonLoaded(name) end
