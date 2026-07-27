-- GenDexBD JournalUI.lua - Mixin Fill Hook + 右键菜单（已拥有+未拥有统一）

local addonName, addonTable = ...
local time=time;local next=next;local ipairs=ipairs
local GetLocaleString = addonTable.GetLocaleString
local GetBreedCode = addonTable.GetBreedCode

function addonTable.SetBestBreed(s,b,c,n)
    if not s or not b then return end;if not GeneDexDB then return end
    GeneDexDB.BestBreeds[s]={[b]={category=c or "custom",note=n or "",addedAt=time()}}
end
function addonTable.RemoveBestBreed(s,b)
    if not s or not b then return end
    local bb=GeneDexDB and GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then return end
    local sd=bb[s];if not sd or type(sd)~="table" then return end;sd[b]=nil;if not next(sd) then bb[s]=nil end
end
function addonTable.IsBestBreed(s,b)
    if not s or not b then return false end
    local bb=GeneDexDB and GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then return false end
    local sd=bb[s];if not sd or type(sd)~="table" then return false end;return sd[b]~=nil
end
function addonTable.GetAllBestBreeds(s)
    if not s then return {} end
    local bb=GeneDexDB and GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then return {} end
    local sd=bb[s];return (sd and type(sd)=="table") and sd or {}
end

local labelDebugDone = {}
local speciesSkillPrinted = {}
local autoSetDone = {}

local function SummarizeSpeciesSkills(speciesID)
    if speciesSkillPrinted[speciesID] then return end
    speciesSkillPrinted[speciesID] = true
    if addonTable.DumpSpeciesAbilities then
        addonTable.DumpSpeciesAbilities(speciesID, nil)
    end
end

local function label(b)
    if not b or not b.Breed or not b.petID then return end
    if not Rematch or not Rematch.petInfo then return end
    local i=Rematch.petInfo:Fetch(b.petID)
    if not i or not i.hasBreed or not i.breedID or i.breedID==0 then return end
    -- 单品种宠物：自动设为最佳（无选择余地）
    if not autoSetDone[i.speciesID] and i.numPossibleBreeds and i.numPossibleBreeds == 1 then
        autoSetDone[i.speciesID] = true
        if not addonTable.IsBestBreed(i.speciesID, i.breedID) then
            addonTable.SetBestBreed(i.speciesID, i.breedID, "auto", "")
        end
    end
    local best=addonTable.IsBestBreed(i.speciesID,i.breedID)
    local sc = addonTable.BEST_BREED_COLOR or {1.0, 0.84, 0.0}
    local doDbg = GeneDexDB and GeneDexDB.Options and GeneDexDB.Options.DebugRecommend
    if doDbg then
        local dkey = i.speciesID .. "_" .. i.breedID
        local dval = (best and "Y" or "N") .. "_" .. (i.breedName or "")
        if labelDebugDone[dkey] ~= dval then
            labelDebugDone[dkey] = dval
            SummarizeSpeciesSkills(i.speciesID)
            print(string.format("[GenDexDBG] label: pet=%s sid=%d bid=%d breed=%s best=%s",
                i.speciesName or "?", i.speciesID, i.breedID, i.breedName or "?",
                best and "YES" or "no"))
        end
    end
    b.Breed:SetText(best and (addonTable.BEST_BREED_STAR..i.breedName) or i.breedName)
    b.Breed:SetTextColor(best and sc[1] or 0.6, best and sc[2] or 0.6, 0.6)
end

-- ========== 菜单注入 ==========

local menuRetryCount = 0
local MAX_MENU_RETRY = 5

-- 颜色常量
local GOLD      = "|cffffd600"
local GOLD_B    = "|cffffd700"
local GRAY      = "|cff888888"
local GREEN     = "|cff00ff00"
local RED       = "|cffff0000"
local GOLD_RED  = "|cffff8000"
local CYAN      = "|cff00ffff"

-- 动态构建子菜单（每次悬停时 Rematch 调用 subMenuFunc(self, subject)）
local function BuildSetBestSubMenu(_, petID, isBattle)
    if not Rematch or not Rematch.petInfo then return end
    local info = Rematch.petInfo:Fetch(petID)
    if not info or not info.speciesID then return end

    local speciesID = info.speciesID
    local speciesName = info.speciesName
    local petType = info.petType
    local possibleBreedIDs = info.possibleBreedIDs
    local currentBreedID = (info.hasBreed and info.breedID and info.breedID > 0) and info.breedID or nil
    local numBreeds = info.numPossibleBreeds or 0

    local items = {}

    if numBreeds == 1 then
        local onlyBreedID = currentBreedID
        if not onlyBreedID and possibleBreedIDs and #possibleBreedIDs > 0 then
            onlyBreedID = possibleBreedIDs[1]
        end
        if onlyBreedID and not addonTable.IsBestBreed(speciesID, onlyBreedID) then
            addonTable.SetBestBreed(speciesID, onlyBreedID, "auto", "")
            C_Timer.After(0, function()
                if Rematch.petsPanel then Rematch.petsPanel:Update() end
            end)
        end
        local code = onlyBreedID and GetBreedCode(onlyBreedID) or "?"
        items[#items + 1] = {
            text = GRAY .. code .. " " .. GetLocaleString("ONLY_BREED_IS_BEST") .. "|r",
            isDisabled = true,
        }
    else
        -- ===== 多品种：双场景 =====
        local dualScores
        if addonTable.CalculateDualScores then
            local ok, ds = pcall(addonTable.CalculateDualScores, speciesID, petType, possibleBreedIDs, 99)
            if ok then dualScores = ds end
        end
        if not dualScores then dualScores = {pve={}, pvp={}} end

        local function buildScenario(scenario, scResults, scColor)
            if not scResults or #scResults == 0 then return end
            local scKey = "PvE"
            if scenario == "PVP" then scKey = "PvP" end
            -- header
            items[#items + 1] = {
                text = scColor .. "--- " .. scKey .. " ---|r",
                isDisabled = true,
            }
            -- community line
            local commBreed = addonTable.GetCommunityBreed and addonTable.GetCommunityBreed(speciesID, scenario)
            if commBreed then
                local commDisp = (#commBreed == 1)
                    and (commBreed == "H" and "H/H" or commBreed == "P" and "P/P" or commBreed == "S" and "S/S" or commBreed == "B" and "B/B" or commBreed)
                    or commBreed
                local marker = ""
                if addonTable.IsCommunityConsensus and addonTable.IsCommunityConsensus(speciesID, scenario) then
                    marker = " ^"
                end
                items[#items + 1] = {
                    text = scColor .. string.format(GetLocaleString("COMMUNITY_CONSENSUS"), commDisp) .. marker .. "|r",
                    isDisabled = true,
                }
            end
            -- breed scores
            local hasTags = false
            for _, r in ipairs(scResults) do if next(r.tagCounts or {}) then hasTags = true break end end
            if not hasTags then
                items[#items + 1] = {
                    text = GRAY .. GetLocaleString("RECOMMEND_NO_TAGS") .. "|r",
                    isDisabled = true,
                }
            end
            for _, rec in ipairs(scResults) do
                local line = string.format(GetLocaleString("RECOMMEND_SCORE_FMT"), rec.breedCode, rec.score)
                local isCurrent = (rec.breedID == currentBreedID)
                local isBest = (scResults[1] and rec.breedID == scResults[1].breedID)
                if isCurrent and isBest then
                    line = GOLD_B .. line .. " *|r"
                elseif isCurrent then
                    line = GREEN .. line .. "|r"
                elseif isBest then
                    line = scColor .. line .. "|r"
                end
                items[#items + 1] = {
                    text = line,
                    func = function()
                        addonTable.SetBestBreed(speciesID, rec.breedID, "auto", "")
                        C_Timer.After(0.1, function()
                            if not Rematch or not Rematch.petsPanel or not Rematch.petsPanel.List then return end
                            local children = { Rematch.petsPanel.List:GetChildren() }
                            for _, child in ipairs(children) do
                                if child.label then child:label() end
                            end
                            if Rematch.petsPanel:GetParent():IsVisible() then
                                Rematch.petsPanel:Update()
                            end
                        end)
                    end,
                }
            end
        end

        buildScenario("PVE", dualScores.pve, GOLD)
        buildScenario("PVP", dualScores.pvp, RED)

        -- summary line
        local pveTop = (#(dualScores.pve or {}) > 0) and dualScores.pve[1].breedCode or "?"
        local pvpTop = (#(dualScores.pvp or {}) > 0) and dualScores.pvp[1].breedCode or "?"
        local pveComm = addonTable.GetCommunityBreed and addonTable.GetCommunityBreed(speciesID, "PVE")
        local pvpComm = addonTable.GetCommunityBreed and addonTable.GetCommunityBreed(speciesID, "PVP")
        items[#items + 1] = {
            text = GRAY .. "------------------------|r",
            isDisabled = true,
        }
        items[#items + 1] = {
            text = GOLD .. "PvE: " .. pveTop .. (pveComm and " ^" or "") .. "|r",
            isDisabled = true,
        }
        items[#items + 1] = {
            text = RED .. "PvP: " .. pvpTop .. (pvpComm and " ^" or "") .. "|r",
            isDisabled = true,
        }
    end

    -- 已保存的最优品种
    local allSaved = addonTable.GetAllBestBreeds(speciesID)
    if next(allSaved) then
        items[#items + 1] = {spacer = true}
        for breedID, breedData in pairs(allSaved) do
            local displayName = GetBreedCode(breedID) or ("ID:" .. breedID)
            local note = (breedData.note and breedData.note ~= "") and (" - " .. breedData.note) or ""
            items[#items + 1] = {
                text = GOLD .. "best: " .. displayName .. " *" .. note .. "|r",
                isDisabled = true,
            }
        end
    end

    -- 战斗专属
    if isBattle and speciesName then
        items[#items + 1] = {spacer = true}
        items[#items + 1] = {
            text = CYAN .. GetLocaleString("SHOW_IN_JOURNAL") .. " (" .. speciesName .. ")|r",
            func = function()
                if Rematch.menus then Rematch.menus:Hide() end
                if Rematch.petsPanel then
                    Rematch.petsPanel:SetParent(UIParent)
                    Rematch.petsPanel:Show()
                end
                if Rematch and Rematch.journal and Rematch.journal.Search then
                    Rematch.journal.Search:SetText(speciesName)
                    C_Timer.After(0.15, function()
                        if Rematch and Rematch.journal and Rematch.journal.Search then
                            Rematch.journal.Search:SetText(speciesName)
                            Rematch.petsPanel:Update()
                        end
                    end)
                end
            end,
        }
    end

    Rematch.menus:Register("GenDexSetBestMenu", items)
end

addonTable.BuildSetBestSubMenu = BuildSetBestSubMenu

-- ========== Rematch 菜单注入 ==========

local function tryInjectMenu()
    if not Rematch or not Rematch.menus then
        if menuRetryCount < MAX_MENU_RETRY then
            menuRetryCount = menuRetryCount + 1
            C_Timer.After(1, tryInjectMenu)
        end
        return
    end
    Rematch.menus:Register("GenDexSetBestMenu", {{text="..."}})
    Rematch.menus:AddToMenu("PetMenu", {
        text = GetLocaleString("SET_BEST_BREED"),
        subMenu = "GenDexSetBestMenu",
        subMenuFunc = BuildSetBestSubMenu,
        hidden = function(_, p)
            if not p then return true end
            if not Rematch or not Rematch.petInfo then return true end
            local info = Rematch.petInfo:Fetch(p)
            return not info or not info.speciesID
        end,
    }, "Find Teams")
end

function addonTable.InitJournalUI()
    local rc = Rematch and Rematch.petsPanel and Rematch.petsPanel.List
    if rc then
        hooksecurefunc(rc, "label", label)
        menuRetryCount = 0
        tryInjectMenu()
    else
        if menuRetryCount < MAX_MENU_RETRY then
            menuRetryCount = menuRetryCount + 1
            C_Timer.After(1, addonTable.InitJournalUI)
        end
    end
end
