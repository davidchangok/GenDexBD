-- GenDexBD Core.lua

local addonName, addonTable = ...

local GetLocaleString = addonTable.GetLocaleString
local GetBreedCode = addonTable.GetBreedCode
local GuessBreedByRatio = addonTable.GuessBreedByRatio
local time = time;local type = type;local pairs = pairs
local next = next;local print = print
local C_Timer_After = C_Timer.After
local C_Timer_After_Cancel = C_Timer_After_Cancel

local function LOG_DBG(...) print("|cff88ccff[GenDexBD-DBG]|r "..string.format(...)) end

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
-- 步骤 a：获取敌方宠物的品种
-- 优先通过 Rematch 缓存（BPBID 可区分 P/S vs P/B），否则用比例推算
-- ========================================================================

local function GetEnemyBreed(petIndex)
    -- 优先：Rematch battle 缓存（若 BPBID 已安装则能精确区分 8/10 歧义品种）
    if Rematch and Rematch.petInfo then
        local ok, info = pcall(Rematch.petInfo.Fetch, Rematch.petInfo, "battle:2:" .. petIndex)
        if ok and info and info.hasBreed and info.breedID and info.breedID > 0 then
            return info.breedID
        end
    end
    -- 回退：比例推算
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

local starIcons = {}  -- [frame] → FontString

local function GetOrCreateStar(frame)
    if not frame or not frame.Icon then return nil end
    if starIcons[frame] then return starIcons[frame] end
    local star = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalHuge')
    star:SetText('★')
    star:SetTextColor(1.0, 0.84, 0.0)  -- 金色
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
    LOG_DBG("★ UpdateStar: owner=%s idx=%s sid=%s show=%s",
        tostring(frame.petOwner), tostring(frame.petIndex),
        tostring(speciesID), tostring(show))
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
-- 步骤 d：野外战斗结束后计数
-- ========================================================================

local encounterCache = {}   -- {[speciesID] = breedID} 本场遇最佳匹配（用于计数）
local showStarsFor = {}      -- {[speciesID] = true}    由ProcessAllEnemyPets唯一决定★
local alertedSpecies = {}   -- {[speciesID]=true} 已提示过的物种
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
    encounterCache = {}; showStarsFor = {}; alertedSpecies = {}
    isWildBattle = false
end

-- ========================================================================
-- 检查玩家是否已拥有 ≥3 只同品种同物种宠物（满了就不再提示）
-- ========================================================================

local function CountOwnedBreedMatches(speciesID, targetBreedID)
    if not speciesID or not targetBreedID then return 0 end
    local count = 0
    -- 12.0: GetNumPets() → numOwned, numTotal (两个返回值)
    local numOwned, numTotal = C_PetJournal.GetNumPets()
    local maxIndex = numOwned or numTotal or 0
    LOG_DBG("CountOwned: sid=%d target=%d numOwned=%s numTotal=%s → max=%d",
        speciesID, targetBreedID, tostring(numOwned), tostring(numTotal), maxIndex)
    for i = 1, maxIndex do
        local petGUID, sid = C_PetJournal.GetPetInfoByIndex(i)
        if sid == speciesID and petGUID then
            local _, maxHealth, power, speed = C_PetJournal.GetPetStats(petGUID)
            if maxHealth and power and speed and maxHealth > 0 then
                local breedID = GuessBreedByRatio(maxHealth, power, speed)
                LOG_DBG("  pet[%d] guid=%s HP=%s P=%s S=%s b=%s",
                    i, tostring(petGUID), tostring(maxHealth), tostring(power),
                    tostring(speed), tostring(breedID))
                if breedID == targetBreedID then
                    count = count + 1
                    LOG_DBG("  → MATCH count=%d", count)
                    if count >= 3 then return count end
                end
            end
        end
    end
    LOG_DBG("CountOwned result: %d", count)
    return count
end

-- ========================================================================
-- 主流程：遍历敌方三宠物，检查品种匹配 → 提示 + ★
-- ========================================================================

local function ProcessAllEnemyPets()
    LOG_DBG("=== ProcessAllEnemyPets START ===")
    showStarsFor = {}
    for i = 1, 3 do
        local hp = C_PetBattles.GetHealth(2, i)
        if hp and hp > 0 then
            local speciesID = C_PetBattles.GetPetSpeciesID(2, i)
            LOG_DBG("Enemy[%d]: hp=%d speciesID=%s", i, hp, tostring(speciesID))
            if speciesID then
                local breedID = GetEnemyBreed(i)
                LOG_DBG("  breedID=%s bestMatch=%s", tostring(breedID),
                    tostring(IsBestBreedMatch(speciesID, breedID)))
                if breedID and IsBestBreedMatch(speciesID, breedID) then
                    encounterCache[speciesID] = breedID
                    local owned = CountOwnedBreedMatches(speciesID, breedID)
                    LOG_DBG("  CountOwned=%d → showStar=%s", owned, tostring(owned < 3))
                    if owned < 3 then
                        showStarsFor[speciesID] = true
                    end
                end
            end
        end
    end
    LOG_DBG("showStarsFor has=%s alerted=%s",
        tostring(next(showStarsFor) ~= nil), tostring(next(alertedSpecies) ~= nil))
    for sid in pairs(showStarsFor) do
        if not alertedSpecies[sid] then
            alertedSpecies[sid] = true
            LOG_DBG("→ ShowAlert speciesID=%d breedID=%s", sid, tostring(encounterCache[sid]))
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
    LOG_DBG("=== ProcessAllEnemyPets END ===")
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
    -- PetTracker 方案：每次敌方头像刷新时更新金色 ★
    hooksecurefunc('PetBattleUnitFrame_UpdateDisplay', UpdateStarOnFrame)
end

local function OnEvent(_, event, ...)
    if event == "ADDON_LOADED" then OnAddonLoaded(...)
    elseif event == "PLAYER_LOGIN" then OnPlayerLogin()
    elseif event == "PET_BATTLE_OPENING_START" then
        isWildBattle = C_PetBattles.IsWildBattle and C_PetBattles.IsWildBattle() or false
        encounterCache = {}; showStarsFor = {}; alertedSpecies = {}
        -- 延迟等 Rematch/BPBID 完成缓存后再扫描
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
