-- GenDexBD Core.lua

local addonName, addonTable = ...

local GetLocaleString = addonTable.GetLocaleString
local GetBreedCode = addonTable.GetBreedCode
local GuessBreedByRatio = addonTable.GuessBreedByRatio
local time = time;local type = type;local pairs = pairs
local next = next;local print = print
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
                local allNumbers = true
                for k in pairs(defaultVal) do
                    if type(k) ~= "number" then allNumbers = false; break end
                end
                if not allNumbers then DeepMergeDefaults(target[key], defaultVal) end
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

-- ========================================================================
-- 步骤 a：获取敌方宠物的品种（优先 Rematch 缓存，回退比例推算）
-- ========================================================================

local function GetEnemyBreed(petIndex)
    if Rematch and Rematch.petInfo then
        local ok, info = pcall(Rematch.petInfo.Fetch, Rematch.petInfo, "battle:2:" .. petIndex)
        if ok and info and info.hasBreed and info.breedID and info.breedID > 0 then
            return info.breedID
        end
    end
    local hp = C_PetBattles.GetMaxHealth(2, petIndex)
    local pw = C_PetBattles.GetPower(2, petIndex)
    local sp = C_PetBattles.GetSpeed(2, petIndex)
    if hp and pw and sp and hp > 0 and pw > 0 and sp > 0 then
        return GuessBreedByRatio(hp, pw, sp)
    end
end

-- ========================================================================
-- 步骤 b：查询该物种是否已设置最优品种
-- ========================================================================

local function IsBestBreedMatch(speciesID, breedID)
    if not speciesID or not breedID then return false end
    local breeds = GeneDexDB.BestBreeds[speciesID]
    return breeds and type(breeds) == "table" and breeds[breedID] ~= nil
end

-- ========================================================================
-- 步骤 c：金色 ★ 标记（PetTracker 方案：hook PetBattleUnitFrame_UpdateDisplay）
-- ========================================================================

local showStarsFor = {}
local starIcons = {}

local function GetOrCreateStar(frame)
    if not frame or not frame.Icon then return nil end
    if starIcons[frame] then return starIcons[frame] end
    local star = frame:CreateFontString(nil, 'OVERLAY')
    star:SetFont('Fonts\\FRIZQT__.TTF', 26, 'OUTLINE')
    star:SetText('\226\152\133')  -- ★
    star:SetTextColor(1.0, 0.84, 0.0)
    star:SetDrawLayer('OVERLAY', 7)
    star:SetPoint('TOPLEFT', frame.Icon, 'TOPLEFT', -2, 2)
    star:Hide()
    starIcons[frame] = star
    return star
end

local function UpdateStarOnFrame(frame)
    if not frame or frame.petOwner ~= 2 or not frame.petIndex then
        local star = GetOrCreateStar(frame)
        if star then star:Hide() end
        return
    end
    local speciesID = C_PetBattles.GetPetSpeciesID(2, frame.petIndex)
    local show = speciesID and showStarsFor[speciesID] or false
    local star = GetOrCreateStar(frame)
    if star then star:SetShown(show) end
end

local function HideAllStars()
    for _, star in pairs(starIcons) do star:Hide() end
end

-- ========================================================================
-- 提示框（GlowBox）
-- ========================================================================

local alertBox = nil

local function GetAlertBox()
    if alertBox then
        if alertBox._hideTimer then C_Timer_After_Cancel(alertBox._hideTimer);alertBox._hideTimer=nil end
        return alertBox
    end
    alertBox = CreateFrame("Frame", nil, PetBattleFrame, "GlowBoxTemplate")
    alertBox:SetSize(240, 56)
    alertBox:SetFrameStrata("HIGH")
    alertBox:SetPoint("TOP", PetBattleFrame.ActiveEnemy.Icon, "BOTTOM", 0, -20)
    if alertBox.Top then
        alertBox.Top:Show()
        if alertBox.Top.Arrow then alertBox.Top.Arrow:SetClampedTextureRotation(0) end
        if alertBox.Top.Glow then alertBox.Top.Glow:SetClampedTextureRotation(0) end
    end
    for _, side in ipairs({"Bottom","Left","Right"}) do
        if alertBox[side] then alertBox[side]:Hide() end
    end
    local text = alertBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("CENTER", alertBox, "CENTER", 0, 2)
    text:SetWidth(220);text:SetJustifyH("CENTER")
    alertBox.Text = text
    alertBox:Hide()
    return alertBox
end

local function HideAlertBox()
    if alertBox then
        if alertBox._hideTimer then C_Timer_After_Cancel(alertBox._hideTimer);alertBox._hideTimer=nil end
        alertBox:Hide()
    end
end

local function ShowAlert(speciesID, breedID, petIndex)
    if not GeneDexDB.Options.AlertInBattle then return end
    local petName = C_PetBattles.GetName(2, petIndex) or "?"
    local breedCode = GetBreedCode(breedID) or "?"
    local displayText = petName .. " " .. breedCode .. " " .. GetLocaleString("ALERT_TARGET")

    local box = GetAlertBox()
    box.Text:SetText(displayText)
    box:ClearAllPoints()
    box:SetPoint("TOP", PetBattleFrame.ActiveEnemy.Icon, "BOTTOM", 0, -20)
    box:Show()

    local duration = GeneDexDB.Options.AlertDuration or 5
    if box._hideTimer then C_Timer_After_Cancel(box._hideTimer) end
    box._hideTimer = C_Timer_After(duration, function() box:Hide();box._hideTimer=nil end)
end

-- ========================================================================
-- 步骤 d：遇敌计数（野外战斗结束后存入 EncounterStats）
-- ========================================================================

local encounterCache = {}
local alertedSpecies = {}
local isWildBattle = false

local function RecordEncounters()
    if not isWildBattle then return end
    if not GeneDexDB.Options.TrackEncounters then return end
    if not GeneDexDB.EncounterStats then GeneDexDB.EncounterStats = {} end
    for speciesID, breedID in pairs(encounterCache) do
        if type(speciesID) == "number" and type(breedID) == "number" then
            if not GeneDexDB.EncounterStats[speciesID] then
                GeneDexDB.EncounterStats[speciesID] = {}
            end
            local count = GeneDexDB.EncounterStats[speciesID][breedID] or 0
            GeneDexDB.EncounterStats[speciesID][breedID] = count + 1
        end
    end
    encounterCache = {}; showStarsFor = {}; alertedSpecies = {}; ownedCache = {}
    isWildBattle = false
end

-- ========================================================================
-- 统计已拥有同物种宠物数量（用 Rematch petInfo，任何品质/品种都计入）
-- ========================================================================

local function CountOwnedSpecies(speciesID)
    if not speciesID then return 0 end
    if Rematch and Rematch.petInfo then
        local info = Rematch.petInfo:Fetch(speciesID)
        local count = (info and info.count) or 0
        return count
    end
    return 0
end

-- ========================================================================
-- 主流程：遍历敌方三宠物，检查品种匹配 → 提示 + ★
-- ========================================================================

local ownedCache = {}

local function GetOwnedCount(speciesID)
    if ownedCache[speciesID] == nil then
        ownedCache[speciesID] = CountOwnedSpecies(speciesID)
    end
    return ownedCache[speciesID]
end

local function ProcessAllEnemyPets()
    showStarsFor = {}
    for i = 1, 3 do
        local hp = C_PetBattles.GetHealth(2, i)
        if hp and hp > 0 then
            local speciesID = C_PetBattles.GetPetSpeciesID(2, i)
            if speciesID then
                local breedID = GetEnemyBreed(i)
                if breedID and IsBestBreedMatch(speciesID, breedID) then
                    encounterCache[speciesID] = breedID
                    local owned = GetOwnedCount(speciesID)
                    if owned < 3 then
                        showStarsFor[speciesID] = true
                    end
                end
            end
        end
    end
    for sid in pairs(showStarsFor) do
        if not alertedSpecies[sid] then
            alertedSpecies[sid] = true
            for j = 1, 3 do
                local msid = C_PetBattles.GetPetSpeciesID(2, j)
                if msid == sid then
                    ShowAlert(sid, encounterCache[sid], j)
                    break
                end
            end
        end
    end
    UpdateStarOnFrame(PetBattleFrame.ActiveEnemy)
end

-- ========================================================================
-- 事件处理
-- ========================================================================

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
    hooksecurefunc('PetBattleUnitFrame_UpdateDisplay', UpdateStarOnFrame)
end

local function OnEvent(_, event, ...)
    if event == "ADDON_LOADED" then OnAddonLoaded(...)
    elseif event == "PLAYER_LOGIN" then OnPlayerLogin()
    elseif event == "PET_BATTLE_OPENING_START" then
        isWildBattle = C_PetBattles.IsWildBattle and C_PetBattles.IsWildBattle() or false
        encounterCache = {}; showStarsFor = {}; alertedSpecies = {}; ownedCache = {}
        C_Timer_After(0.5, ProcessAllEnemyPets)
    elseif event == "PET_BATTLE_PET_CHANGED" then
        ProcessAllEnemyPets()
    elseif event == "PET_BATTLE_CLOSE" then
        RecordEncounters()
        HideAlertBox()
        HideAllStars()
    end
end

eventFrame = CreateFrame("Frame");eventFrame:RegisterEvent("ADDON_LOADED");eventFrame:SetScript("OnEvent", OnEvent)
addonTable.OnAddonLoaded = function(name) OnAddonLoaded(name) end
