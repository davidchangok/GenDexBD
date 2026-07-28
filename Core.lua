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
addonTable.PVP_BEST_BREED_COLOR = {1.0, 0.0, 0.0}

SlashCmdList["GENEDEXBDOPEN"] = function(msg)
    if msg == "report" then
        if addonTable.GenerateReport then addonTable.GenerateReport() end
    else
        if addonTable.ToggleConfigPanel then addonTable.ToggleConfigPanel() end
    end
end
_G["SLASH_GENEDEXBDOPEN1"] = "/gbbd"

local DB_DEFAULTS = {
    BestBreeds = {},
    EncounterStats = {},
    Options = {
        ShowInTooltip = true, AlertInBattle = true,
        AssumeRareQuality = true, ShowBestBreedNote = true, AlertDuration = 5,
        TrackEncounters = true,
        DebugRecommend = false,
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
    -- SpeciesReport 保留不删，退出后从 GenDexBD.lua 搜索 SpeciesReport 复制
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

-- 战斗状态变量（需提前声明：后面定义的函数通过闭包引用，Lua 5.1 不做变量提升）
local isWildBattle = false
local encounterCache = {}
local alertedSpecies = {}
local ownedCache = {}

-- ========================================================================
-- 步骤 a：获取敌方宠物的品种（优先 Rematch 缓存，回退比例推算）
-- ========================================================================

-- 泛化：获取任意队伍宠物的品种（team: 1=己方, 2=敌方）
local function GetPetBreed(team, petIndex)
    if Rematch and Rematch.petInfo then
        local ok, info = pcall(Rematch.petInfo.Fetch, Rematch.petInfo, "battle:" .. team .. ":" .. petIndex)
        if ok and info and info.hasBreed and info.breedID and info.breedID > 0 then
            return info.breedID
        end
    end
    local hp = C_PetBattles.GetMaxHealth(team, petIndex)
    local pw = C_PetBattles.GetPower(team, petIndex)
    local sp = C_PetBattles.GetSpeed(team, petIndex)
    if hp and pw and sp and hp > 0 and pw > 0 and sp > 0 then
        return GuessBreedByRatio(hp, pw, sp)
    end
end

-- 便捷封装
local function GetEnemyBreed(petIndex) return GetPetBreed(2, petIndex) end
local function GetAllyBreed(petIndex)  return GetPetBreed(1, petIndex) end

-- 检查宠物是否可捕捉/可对战
-- 通用检查：canBattle=false 的纯伴生宠物（如尤娜）一律不可对战
-- 敌方额外检查：非野外战斗不可捕捉、Epic/Legendary 品质不可捕捉、非野外物种不可捕捉
local function IsPetCapturable(team, petIndex)
    local speciesID = C_PetBattles.GetPetSpeciesID(team, petIndex)
    if not speciesID then return false end
    -- 物种级检查：canBattle（纯伴生宠物不可对战）+ isWild（仅野外物种可捕捉）
    if C_PetJournal.GetPetInfoBySpeciesID then
        local _, _, _, _, _, _, isWild, canBattle = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
        if canBattle == false then return false end
        if team == 2 and isWild == false then return false end
    end
    if team ~= 2 then return true end
    -- 非野外战斗（训练师/NPC/PvP）：敌方宠物一律不可捕捉
    if not isWildBattle then return false end
    -- 品质检查：Epic(5)/Legendary(6) 不可捕捉
    if C_PetBattles.GetBreedQuality then
        local quality = C_PetBattles.GetBreedQuality(2, petIndex)
        if quality and quality >= 5 then return false end
    end
    return true
end

-- ========================================================================
-- 步骤 c：金色 ★ 标记（PetTracker 方案：hook PetBattleUnitFrame_UpdateDisplay）
-- ========================================================================

local starColorPvE = addonTable.BEST_BREED_COLOR
local starColorPvP = addonTable.PVP_BEST_BREED_COLOR
local showStarsPvE = {}
local showStarsPvP = {}
local starIconsPvE = {}
local starIconsPvP = {}

local function GetOrCreateStar(frame, starCache, r, g, b, anchor, x, y)
    if not frame or not frame.Icon or not frame.petOwner then return nil end
    if frame.petOwner ~= 1 and frame.petOwner ~= 2 then return nil end
    if starCache[frame] then return starCache[frame] end
    local star = frame:CreateFontString(nil, 'OVERLAY')
    star:SetFont('Fonts\\FRIZQT__.TTF', 22, 'OUTLINE')
    star:SetText(addonTable.BEST_BREED_STAR)
    star:SetTextColor(r, g, b)
    star:SetDrawLayer('OVERLAY', 7)
    star:SetPoint(anchor, frame.Icon, anchor, x, y)
    star:Hide()
    starCache[frame] = star
    return star
end

local function GetOrCreatePvEStar(frame)
    return GetOrCreateStar(frame, starIconsPvE,
        starColorPvE[1], starColorPvE[2], starColorPvE[3],
        'TOPRIGHT', 2, 3)
end

local function GetOrCreatePvPStar(frame)
    return GetOrCreateStar(frame, starIconsPvP,
        starColorPvP[1], starColorPvP[2], starColorPvP[3],
        'BOTTOMRIGHT', 2, -3)
end

local function UpdateStarOnFrame(frame)
    if not frame or not frame.petOwner or not frame.petIndex then return end
    if frame.petOwner ~= 1 and frame.petOwner ~= 2 then return end
    local captiveCheck = (frame.petOwner == 2) and not IsPetCapturable(2, frame.petIndex)
    local speciesID = C_PetBattles.GetPetSpeciesID(frame.petOwner, frame.petIndex)
    local breedID = speciesID and GetPetBreed(frame.petOwner, frame.petIndex)
    local starPvE = GetOrCreatePvEStar(frame)
    local starPvP = GetOrCreatePvPStar(frame)
    if not speciesID or captiveCheck then
        if starPvE then starPvE:Hide() end
        if starPvP then starPvP:Hide() end
        return
    end
    local showPvE = breedID and showStarsPvE[speciesID] and showStarsPvE[speciesID][breedID] or false
    local showPvP = breedID and showStarsPvP[speciesID] and showStarsPvP[speciesID][breedID] or false
    if starPvE then starPvE:SetShown(showPvE) end
    if starPvP then starPvP:SetShown(showPvP) end
end

local function HideAllStars()
    for _, star in pairs(starIconsPvE) do star:Hide() end
    for _, star in pairs(starIconsPvP) do star:Hide() end
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

-- 初始化战斗状态（变量已在文件顶部声明）
encounterCache = {}     -- {[speciesID] = {[breedID]=true, ...}}
alertedSpecies = {}    -- {[speciesID]=true}
ownedCache = {}         -- {[speciesID]=count}      同场战斗缓存
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

local bestBreedCache = {}  -- {[speciesID] = {pve=breedID, pvp=breedID}}

local function ComputeBestBreedForScenario(speciesID, petType, possibleBreedIDs, scenario)
    if not addonTable.CalculateBreedScores then return nil end
    local results = addonTable.CalculateBreedScores(speciesID, petType, possibleBreedIDs, 1, scenario)
    if results and #results > 0 then return results[1].breedID end
    return nil
end

local function ComputeBestBreeds(speciesID, petType, possibleBreedIDs)
    if bestBreedCache[speciesID] then return end
    -- always use algorithm (user settings do not affect battle stars)
    local pveBreed = ComputeBestBreedForScenario(speciesID, petType, possibleBreedIDs, "PVE")
    local pvpBreed = ComputeBestBreedForScenario(speciesID, petType, possibleBreedIDs, "PVP")
    bestBreedCache[speciesID] = {pve=pveBreed, pvp=pvpBreed}
end

local function ProcessAllPets()
    showStarsPvE = {}
    showStarsPvP = {}
    bestBreedCache = {}
    -- 敌方（team=2）：含可捕捉检查 + 遇敌记录 + 提示
    for i = 1, 3 do
        if IsPetCapturable(2, i) then
            local hp = C_PetBattles.GetHealth(2, i)
            if hp and hp > 0 then
                local speciesID = C_PetBattles.GetPetSpeciesID(2, i)
                local breedID = GetEnemyBreed(i)
                if speciesID and breedID then
                    -- 遇敌记录（使用传统IsBestBreed检查）
                    if addonTable.IsBestBreed(speciesID, breedID) then
                        if not encounterCache[speciesID] then
                            encounterCache[speciesID] = {}
                        end
                        encounterCache[speciesID][breedID] = true
                    end
                    -- 双场景星标判定
                    local petType = select(3, C_PetJournal.GetPetInfoBySpeciesID(speciesID))
                    ComputeBestBreeds(speciesID, petType, nil)
                    local bc = bestBreedCache[speciesID]
                    if bc then
                        local owned = GetOwnedCount(speciesID)
                        local doDbg = GeneDexDB and GeneDexDB.Options and GeneDexDB.Options.DebugRecommend
                        if doDbg then
                            print(string.format("[GenDexDBG] star: enemy pet=%s sid=%d bid=%d bcPvE=%s bcPvP=%s owned=%d capturable=%s",
                                C_PetBattles.GetName(2,i) or "?", speciesID, breedID,
                                bc.pve and (addonTable.GetBreedCode(bc.pve) or bc.pve) or "nil",
                                bc.pvp and (addonTable.GetBreedCode(bc.pvp) or bc.pvp) or "nil",
                                owned, IsPetCapturable(2,i) and "Y" or "N"))
                        end
                        if owned < 3 then
                            if bc.pve and bc.pve == breedID then
                                if not showStarsPvE[speciesID] then showStarsPvE[speciesID] = {} end
                                showStarsPvE[speciesID][breedID] = true
                                if doDbg then print("  -> PvE star ON") end
                            end
                            if bc.pvp and bc.pvp == breedID then
                                if not showStarsPvP[speciesID] then showStarsPvP[speciesID] = {} end
                                showStarsPvP[speciesID][breedID] = true
                                if doDbg then print("  -> PvP star ON") end
                            end
                        else
                            if doDbg then print("  -> SKIP: owned >= 3") end
                        end
                    else
                        local doDbg = GeneDexDB and GeneDexDB.Options and GeneDexDB.Options.DebugRecommend
                        if doDbg then print("[GenDexDBG] star: bc is nil for sid=" .. speciesID) end
                    end
                end
            end
        end
    end
    -- 己方（team=1）：仅星标，不记录遇敌
    for i = 1, 3 do
        local hp = C_PetBattles.GetHealth(1, i)
        if hp and hp > 0 then
            local speciesID = C_PetBattles.GetPetSpeciesID(1, i)
            local breedID = GetAllyBreed(i)
            if speciesID and breedID then
                local petType = select(3, C_PetJournal.GetPetInfoBySpeciesID(speciesID))
                ComputeBestBreeds(speciesID, petType, nil)
                local bc = bestBreedCache[speciesID]
                if bc then
                    if bc.pve and bc.pve == breedID then
                        if not showStarsPvE[speciesID] then showStarsPvE[speciesID] = {} end
                        showStarsPvE[speciesID][breedID] = true
                    end
                    if bc.pvp and bc.pvp == breedID then
                        if not showStarsPvP[speciesID] then showStarsPvP[speciesID] = {} end
                        showStarsPvP[speciesID][breedID] = true
                    end
                end
            end
        end
    end
    -- 敌方提示（仅对可捕捉的最优品种）
    local allShown = {}
    for sid in pairs(showStarsPvE) do allShown[sid] = true end
    for sid in pairs(showStarsPvP) do allShown[sid] = true end
    for sid in pairs(allShown) do
        if not alertedSpecies[sid] then
            alertedSpecies[sid] = true
            for j = 1, 3 do
                if IsPetCapturable(2, j) then
                    local msid = C_PetBattles.GetPetSpeciesID(2, j)
                    if msid == sid then
                        local cache = encounterCache[sid]
                        if cache then
                            local bid = next(cache)
                            if bid then ShowAlert(sid, bid, j) end
                        end
                        break
                    end
                end
            end
        end
    end
    -- DEBUG: 打印最终星标表
    local doDbg = GeneDexDB and GeneDexDB.Options and GeneDexDB.Options.DebugRecommend
    if doDbg then
        local pveSummary, pvpSummary = {}, {}
        for sid, bids in pairs(showStarsPvE) do for bid in pairs(bids) do pveSummary[#pveSummary+1]=sid..":"..(addonTable.GetBreedCode(bid) or bid) end end
        for sid, bids in pairs(showStarsPvP) do for bid in pairs(bids) do pvpSummary[#pvpSummary+1]=sid..":"..(addonTable.GetBreedCode(bid) or bid) end end
        print(string.format("[GenDexDBG] showStars: PvE={%s} PvP={%s} frames=%d",
            table.concat(pveSummary,","), table.concat(pvpSummary,","),
            (function()local n=0;for _ in pairs(starIconsPvE)do n=n+1 end;return n end)()))
    end
    -- 更新所有双方框体的星星
    for frame, star in pairs(starIconsPvE) do
        if (frame.petOwner == 1 or frame.petOwner == 2) and frame.petIndex then
            local sid = C_PetBattles.GetPetSpeciesID(frame.petOwner, frame.petIndex)
            local show = false
            if sid and showStarsPvE[sid] then
                local bid = GetPetBreed(frame.petOwner, frame.petIndex)
                show = bid and showStarsPvE[sid][bid] or false
            end
            if frame.petOwner == 2 and show and not IsPetCapturable(2, frame.petIndex) then show = false end
            star:SetShown(show)
        end
    end
    for frame, star in pairs(starIconsPvP) do
        if (frame.petOwner == 1 or frame.petOwner == 2) and frame.petIndex then
            local sid = C_PetBattles.GetPetSpeciesID(frame.petOwner, frame.petIndex)
            local show = false
            if sid and showStarsPvP[sid] then
                local bid = GetPetBreed(frame.petOwner, frame.petIndex)
                show = bid and showStarsPvP[sid][bid] or false
            end
            if frame.petOwner == 2 and show and not IsPetCapturable(2, frame.petIndex) then show = false end
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
    encounterCache = {}; showStarsPvE = {}; showStarsPvP = {}; alertedSpecies = {}; ownedCache = {}
    isWildBattle = false
end

local function ResetBattleSession()
    encounterCache = {}; showStarsPvE = {}; showStarsPvP = {}; alertedSpecies = {}; ownedCache = {}
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
    SlashCmdList["GENEDEXBDOPEN"] = function(msg)
        if msg == "report" then
            if addonTable.GenerateReport then addonTable.GenerateReport() end
        else
            if addonTable.ToggleConfigPanel then
                addonTable.ToggleConfigPanel()
            end
        end
    end
    _G["SLASH_GENEDEXBDOPEN1"] = "/gbbd"
    eventFrame:RegisterEvent("PET_BATTLE_OPENING_START");eventFrame:RegisterEvent("PET_BATTLE_PET_CHANGED");eventFrame:RegisterEvent("PET_BATTLE_CLOSE")
    hooksecurefunc('PetBattleUnitFrame_UpdateDisplay', UpdateStarOnFrame)

    -- 战斗界面右击菜单 — SetScript 替换模板 OnClick，彻底拦截暴雪内置右键菜单
    -- 敌方+己方均支持
    if PetBattleFrame then
        for _, key in ipairs({"ActiveEnemy","Enemy2","Enemy3","ActiveAlly","Ally2","Ally3"}) do
            local f = PetBattleFrame[key]
            if f then
                local origOnClick = f:GetScript("OnClick")
                f:SetScript("OnClick", function(self, button, down)
                    if button == "RightButton" and self.petIndex and self.petOwner then
                        -- 不可对战的宠物不继续操作
                        if not IsPetCapturable(self.petOwner, self.petIndex) then
                            if origOnClick then origOnClick(self, button, down) end
                            return
                        end
                        -- 己方(1) 或 敌方(2)：弹出最优品种设置菜单
                        if self.petOwner == 1 then
                            if not Rematch or not Rematch.menus then return end
                            local petID = "battle:1:" .. self.petIndex
                            if not addonTable.BuildSetBestSubMenu then return end
                            addonTable.BuildSetBestSubMenu(nil, petID, true)
                            Rematch.menus:Show("GenDexSetBestMenu", self, petID, "cursor")
                        elseif self.petOwner == 2 then
                            if not Rematch or not Rematch.menus then return end
                            local petID = "battle:2:" .. self.petIndex
                            if not addonTable.BuildSetBestSubMenu then return end
                            addonTable.BuildSetBestSubMenu(nil, petID, true)
                            Rematch.menus:Show("GenDexSetBestMenu", self, petID, "cursor")
                        end
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
            ProcessAllPets()
        end)
    elseif event == "PET_BATTLE_PET_CHANGED" then
        ProcessAllPets()
    elseif event == "PET_BATTLE_CLOSE" then
        RecordEncounters()
        HideAlertBox()
        HideAllStars()
        if scanTimer then C_Timer_After_Cancel(scanTimer); scanTimer = nil end
    end
end

eventFrame = CreateFrame("Frame");eventFrame:RegisterEvent("ADDON_LOADED");eventFrame:SetScript("OnEvent", OnEvent)
addonTable.OnAddonLoaded = function(name) OnAddonLoaded(name) end
