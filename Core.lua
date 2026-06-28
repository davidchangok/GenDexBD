-- GenDexBD Core.lua

local addonName, addonTable = ...

local GetLocaleString = addonTable.GetLocaleString
local GetBreedCode = addonTable.GetBreedCode
local GetBreedDisplayName = addonTable.GetBreedDisplayName
local GuessBreedByRatio = addonTable.GuessBreedByRatio
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
    EncounterStats = {},
    Options = {
        ShowInTooltip = true, AlertInBattle = true,
        AssumeRareQuality = true, ShowBestBreedNote = true, AlertDuration = 5,
        TrackEncounters = true,
    },
    DBVersion = CURRENT_DB_VERSION,
}

local function DeepMergeDefaults(target, defaults)
    for key, defaultVal in pairs(defaults) do
        if target[key] == nil then
            target[key] = defaultVal
        elseif type(defaultVal) == "table" and type(target[key]) == "table" then
            if type(next(defaultVal)) == "nil" then
            else
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
    if type(GeneDexDB.EncounterStats) ~= "table" then GeneDexDB.EncounterStats = {} end
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

-- ========== 敌方头像金色 ★ ==========
-- 参照 PetTracker 方案：hook PetBattleUnitFrame_UpdateDisplay，在敌方 UnitFrame 上创建纹理

local bangIcons = {}  -- [frame] → Texture

local function GetOrCreateBangIcon(frame)
    if bangIcons[frame] then
        return bangIcons[frame]
    end

    local tex = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalHuge')
    tex:SetText('★')
    tex:SetTextColor(1.0, 0.84, 0.0)   -- 金色
    tex:SetDrawLayer('OVERLAY', 7)
    tex:SetPoint('CENTER', frame.Icon, 'CENTER', 0, 0)
    tex:Hide()
    bangIcons[frame] = tex
    return tex
end

local function IsFrameEnemy(frame)
    return frame and frame.petOwner == 2
end

local function HasBestBreed(frame)
    if not frame or not frame.petIndex then return false end
    local speciesID = C_PetBattles.GetPetSpeciesID(2, frame.petIndex)
    if not speciesID then return false end
    local bestBreeds = GeneDexDB.BestBreeds[speciesID]
    if not bestBreeds or type(bestBreeds) ~= "table" or not next(bestBreeds) then return false end

    -- 检查敌方实际品种是否匹配保存的最优品种
    local hp = C_PetBattles.GetMaxHealth(2, frame.petIndex)
    local pw = C_PetBattles.GetPower(2, frame.petIndex)
    local sp = C_PetBattles.GetSpeed(2, frame.petIndex)
    if hp and pw and sp and hp > 0 and pw > 0 and sp > 0 then
        local actualBreed = GuessBreedByRatio(hp, pw, sp)
        if actualBreed then
            return bestBreeds[actualBreed] ~= nil
        end
    end
    return false
end

local function UpdateEnemyStarIcon(frame)
    if not IsFrameEnemy(frame) then return end
    local icon = GetOrCreateBangIcon(frame)
    icon:SetShown(HasBestBreed(frame))
end

local function ClearAllStars()
    for frame, tex in pairs(bangIcons) do
        tex:Hide()
    end
end

-- ========== 遇敌计数 ==========

local wildAutoTrackRestore = nil  -- 野外战斗前用户的 TrackEncounters 原值

local function RecordEncounter(speciesID, petIndex)
    if not GeneDexDB.Options.TrackEncounters then return end
    if not GeneDexDB.EncounterStats then GeneDexDB.EncounterStats = {} end

    local hp = C_PetBattles.GetMaxHealth(2, petIndex)
    local pw = C_PetBattles.GetPower(2, petIndex)
    local sp = C_PetBattles.GetSpeed(2, petIndex)
    if not hp or not pw or not sp or hp == 0 or pw == 0 or sp == 0 then return end

    local breedID = GuessBreedByRatio(hp, pw, sp)
    if not breedID then return end

    if not GeneDexDB.EncounterStats[speciesID] then
        GeneDexDB.EncounterStats[speciesID] = {}
    end
    local count = GeneDexDB.EncounterStats[speciesID][breedID] or 0
    GeneDexDB.EncounterStats[speciesID][breedID] = count + 1
end

-- ========== 战斗提示主逻辑 ==========

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

    -- 遇敌计数（所有宠物，无论是否最佳品种）
    RecordEncounter(speciesID, petIndex)

    -- 最佳品种提示
    if battleAlertCache[speciesID] then return end
    local bestBreeds = GeneDexDB.BestBreeds[speciesID]
    if not bestBreeds or type(bestBreeds)~="table" or not next(bestBreeds) then return end

    local breedID
    for bid, bdata in pairs(bestBreeds) do
        if type(bdata)=="table" then breedID=bid;break end
    end
    if not breedID then return end

    battleAlertCache[speciesID] = true

    local petName = C_PetBattles.GetName(2, petIndex) or "?"
    local breedCode = GetBreedCode(breedID) or "?"
    local displayText = petName .. " " .. breedCode .. " " .. GetLocaleString("ALERT_TARGET")

    local box = GetAlertGlowBox()
    box.Text:SetText(displayText)

    local enemyIcon = PetBattleFrame.ActiveEnemy.Icon
    box:ClearAllPoints();box:SetPoint("TOP", enemyIcon, "BOTTOM", 0, -20)
    box:Show()

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
local function UpdateAllEnemyStars()
    if not PetBattleFrame.ActiveEnemy or not PetBattleFrame.ActiveEnemy.Icon then return end
    -- 强制刷新当前活跃敌方的 Icon 纹理标记
    UpdateEnemyStarIcon(PetBattleFrame.ActiveEnemy)
end

local function ClearBattleCache()
    battleAlertCache = {};HideAlertBox();ClearAllStars()
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
    -- 注册敌方头像金色 ★ 更新 Hook（参照 PetTracker units.lua:14）
    hooksecurefunc('PetBattleUnitFrame_UpdateDisplay', UpdateEnemyStarIcon)
end

local function OnEvent(_, event, ...)
    if event == "ADDON_LOADED" then OnAddonLoaded(...)
    elseif event == "PLAYER_LOGIN" then OnPlayerLogin()
    elseif event == "PET_BATTLE_OPENING_START" then
        -- 野外战斗自动开启遇敌计数
        if C_PetBattles.IsWildBattle and C_PetBattles.IsWildBattle() then
            wildAutoTrackRestore = GeneDexDB.Options.TrackEncounters
            GeneDexDB.Options.TrackEncounters = true
        end
        C_Timer_After(0.5, CheckEnemyTeam)
        C_Timer_After(0.6, UpdateAllEnemyStars)
    elseif event == "PET_BATTLE_PET_CHANGED" then CheckActiveEnemyPet();C_Timer_After(0.1, UpdateAllEnemyStars)
    elseif event == "PET_BATTLE_CLOSE" then
        ClearBattleCache()
        -- 恢复野外战斗前的 TrackEncounters 设置
        if wildAutoTrackRestore ~= nil then
            GeneDexDB.Options.TrackEncounters = wildAutoTrackRestore
            wildAutoTrackRestore = nil
        end
    end
end

eventFrame = CreateFrame("Frame");eventFrame:RegisterEvent("ADDON_LOADED");eventFrame:SetScript("OnEvent", OnEvent)
addonTable.OnAddonLoaded = function(name) OnAddonLoaded(name) end
