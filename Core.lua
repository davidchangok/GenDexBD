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

-- 最优品种标记常量（统一引用，避免散落各文件）
addonTable.BEST_BREED_STAR = "★"
addonTable.BEST_BREED_COLOR = {1.0, 0.84, 0.0}

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
-- 步骤 c：金色 ★ 标记（PetTracker 方案：hook PetBattleUnitFrame_UpdateDisplay）
-- ========================================================================

local starColor = addonTable.BEST_BREED_COLOR
local showStarsFor = {}
local starIcons = {}

local function GetOrCreateStar(frame)
    -- 仅对敌方 frame（有 Icon 且 petOwner==2）创建，避免非敌方 frame 泄漏
    if not frame or not frame.Icon or frame.petOwner ~= 2 then return nil end
    if starIcons[frame] then return starIcons[frame] end
    local star = frame:CreateFontString(nil, 'OVERLAY')
    star:SetFont('Fonts\\FRIZQT__.TTF', 26, 'OUTLINE')
    star:SetText(addonTable.BEST_BREED_STAR)
    star:SetTextColor(starColor[1], starColor[2], starColor[3])
    star:SetDrawLayer('OVERLAY', 7)
    star:SetPoint('TOPLEFT', frame.Icon, 'TOPLEFT', -2, 2)
    star:Hide()
    starIcons[frame] = star
    return star
end

local function UpdateStarOnFrame(frame)
    if not frame or frame.petOwner ~= 2 or not frame.petIndex then return end
    local speciesID = C_PetBattles.GetPetSpeciesID(2, frame.petIndex)
    if not speciesID or not showStarsFor[speciesID] then
        local star = GetOrCreateStar(frame)
        if star then star:Hide() end
        return
    end
    -- 品种级检查：同物种不同品种仅最优品种显示 ★
    local breedID = GetEnemyBreed(frame.petIndex)
    local show = breedID and showStarsFor[speciesID][breedID] or false
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
-- 统计数据（encounterCache 以 speciesID→breedID 聚合，防止同物种多槽位覆盖）
-- ========================================================================

local encounterCache = {}     -- {[speciesID] = {[breedID]=true, ...}}
local alertedSpecies = {}    -- {[speciesID]=true}
local ownedCache = {}         -- {[speciesID]=count}      同场战斗缓存
local isWildBattle = false
local scanTimer = nil         -- 延迟扫描 timer，用于 CLOSE 时取消

-- 同场战斗内只查一次 Rematch（pcall 保护）
local function CountOwnedSpecies(speciesID)
    if not speciesID then return 0 end
    if Rematch and Rematch.petInfo then
        local ok, info = pcall(Rematch.petInfo.Fetch, Rematch.petInfo, speciesID)
        if ok and info and info.count then
            return info.count
        end
    end
    -- Rematch 不可用：返回大数（保守策略：跳过提示而非错误提示）
    return 999
end

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
                -- 使用全局 addonTable.IsBestBreed 代替局部重复实现
                if breedID and addonTable.IsBestBreed(speciesID, breedID) then
                    -- 聚合记录：speciesID → {breedID = true}
                    if not encounterCache[speciesID] then
                        encounterCache[speciesID] = {}
                    end
                    encounterCache[speciesID][breedID] = true
                    local owned = GetOwnedCount(speciesID)
                    if owned < 3 then
                        if not showStarsFor[speciesID] then
                            showStarsFor[speciesID] = {}
                        end
                        showStarsFor[speciesID][breedID] = true
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
                    -- 取该物种第一个品种用于展示
                    local bid = next(encounterCache[sid])
                    if bid then ShowAlert(sid, bid, j) end
                    break
                end
            end
        end
    end
    -- 更新所有敌方框体的星星（品种级检查：同物种仅最优品种显示 ★）
    for frame, star in pairs(starIcons) do
        if frame.petOwner == 2 and frame.petIndex then
            local sid = C_PetBattles.GetPetSpeciesID(2, frame.petIndex)
            local show = false
            if sid and showStarsFor[sid] then
                local bid = GetEnemyBreed(frame.petIndex)
                show = bid and showStarsFor[sid][bid] or false
            end
            star:SetShown(show)
        end
    end
end

-- ========================================================================
-- 步骤 d：遇敌计数
-- ========================================================================

local function RecordEncounters()
    if not isWildBattle then return end
    if not GeneDexDB.Options.TrackEncounters then return end
    if not GeneDexDB.EncounterStats then GeneDexDB.EncounterStats = {} end
    for speciesID, breeds in pairs(encounterCache) do
        if type(speciesID) == "number" and type(breeds) == "table" then
            for breedID in pairs(breeds) do
                if type(breedID) == "number" then
                    if not GeneDexDB.EncounterStats[speciesID] then
                        GeneDexDB.EncounterStats[speciesID] = {}
                    end
                    local count = GeneDexDB.EncounterStats[speciesID][breedID] or 0
                    GeneDexDB.EncounterStats[speciesID][breedID] = count + 1
                end
            end
        end
    end
    encounterCache = {}; showStarsFor = {}; alertedSpecies = {}; ownedCache = {}
    isWildBattle = false
end

local function ResetBattleSession()
    encounterCache = {}; showStarsFor = {}; alertedSpecies = {}; ownedCache = {}
    if scanTimer then C_Timer_After_Cancel(scanTimer); scanTimer = nil end
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
    if addonTable.InitTooltip then addonTable.InitTooltip() end
    if addonTable.InitJournalUI then addonTable.InitJournalUI() end
    if addonTable.InitConfig then addonTable.InitConfig() end
    SlashCmdList["GENEDEXBDOPEN"] = function()
        if addonTable.ToggleConfigPanel then
            addonTable.ToggleConfigPanel()
        else end
    end
    _G["SLASH_GENEDEXBDOPEN1"] = "/gbbd"
    eventFrame:RegisterEvent("PET_BATTLE_OPENING_START");eventFrame:RegisterEvent("PET_BATTLE_PET_CHANGED");eventFrame:RegisterEvent("PET_BATTLE_CLOSE")
    hooksecurefunc('PetBattleUnitFrame_UpdateDisplay', UpdateStarOnFrame)

    -- 战斗界面敌方宠物右击菜单 — SetScript 替换模板 OnClick，彻底拦截暴雪内置右键菜单
    if PetBattleFrame then
        for _, key in ipairs({"ActiveEnemy","Enemy2","Enemy3"}) do
            local f = PetBattleFrame[key]
            if f then
                local origOnClick = f:GetScript("OnClick")
                f:SetScript("OnClick", function(self, button, down)
                    if button == "RightButton" and self.petOwner == 2 and self.petIndex then
                        if not Rematch or not Rematch.menus then return end
                        local petID = "battle:2:" .. self.petIndex
                        if not addonTable.BuildSetBestSubMenu then return end
                        addonTable.BuildSetBestSubMenu(nil, petID, true)
                        Rematch.menus:Show("GenDexSetBestMenu", self, petID, "cursor")
                    elseif origOnClick then
                        origOnClick(self, button, down)
                    end
                end)
            end
        end
    end
end

local function OnEvent(_, event, ...)
    if event == "ADDON_LOADED" then OnAddonLoaded(...)
    elseif event == "PLAYER_LOGIN" then OnPlayerLogin()
    elseif event == "PET_BATTLE_OPENING_START" then
        isWildBattle = C_PetBattles.IsWildBattle and C_PetBattles.IsWildBattle() or false
        ResetBattleSession()
        scanTimer = C_Timer_After(0.5, function()
            scanTimer = nil
            ProcessAllEnemyPets()
        end)
    elseif event == "PET_BATTLE_PET_CHANGED" then
        ProcessAllEnemyPets()
    elseif event == "PET_BATTLE_CLOSE" then
        RecordEncounters()
        HideAlertBox()
        HideAllStars()
        if scanTimer then C_Timer_After_Cancel(scanTimer); scanTimer = nil end
    end
end

eventFrame = CreateFrame("Frame");eventFrame:RegisterEvent("ADDON_LOADED");eventFrame:SetScript("OnEvent", OnEvent)
addonTable.OnAddonLoaded = function(name) OnAddonLoaded(name) end
