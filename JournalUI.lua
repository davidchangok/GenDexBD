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
        -- ===== 唯一属性：自动设为最佳 =====
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
        -- ===== 多品种：双场景智能推荐 =====
        local dualScores = nil
        if addonTable.CalculateDualScores then
            dualScores = addonTable.CalculateDualScores(speciesID, petType, possibleBreedIDs, 99)
        end
        if not dualScores then dualScores = {pve={}, pvp={}} end
        local pveResults = dualScores.pve or {}
        local pvpResults = dualScores.pvp or {}

        if #pveResults == 0 and #pvpResults == 0 then
            items[#items + 1] = {
                text = GRAY .. "(" .. GetLocaleString("RECOMMEND_NO_DATA") .. ")|r",
                isDisabled = true,
            }
        else
            -- 场景一致性检查
            local pveTop = #pveResults > 0 and pveResults[1].breedCode or nil
            local pvpTop = #pvpResults > 0 and pvpResults[1].breedCode or nil
            local sameTop = pveTop and pvpTop and pveTop == pvpTop

            -- 社区共识标记
            local commPvE = addonTable.GetCommunityBreed and addonTable.GetCommunityBreed(speciesID, "PVE")
            local commPvP = addonTable.GetCommunityBreed and addonTable.GetCommunityBreed(speciesID, "PVP")
            local commPvECode = nil
            local commPvPCode = nil
            if commPvE then
                commPvECode = (#commPvE == 1)
                    and (commPvE == "H" and "H/H" or commPvE == "P" and "P/P" or commPvE == "S" and "S/S" or commPvE == "B" and "B/B" or commPvE)
                    or commPvE
            end
            if commPvP then
                commPvPCode = (#commPvP == 1)
                    and (commPvP == "H" and "H/H" or commPvP == "P" and "P/P" or commPvP == "S" and "S/S" or commPvP == "B" and "B/B" or commPvP)
                    or commPvP
            end

            -- 辅助：菜单条目 — 品种项
            local function AddBreedItem(breedResults, scenario, scenarioColor)
                if #breedResults == 0 then return end
                -- 场景头部
                local headerKey = (scenario == "PVE") and "SCENARIO_PVE_HEADER" or "SCENARIO_PVP_HEADER"
                local headerText = GetLocaleString(headerKey) or (scenario == "PVE" and "PvE" or "PvP")
                items[#items + 1] = {
                    text = scenarioColor .. headerText .. "|r",
                    isDisabled = true,
                }
                -- 社区共识行
                local commCode = (scenario == "PVE") and commPvECode or commPvPCode
                if commCode then
                    local commDisplay = commCode
                    if #commDisplay == 1 then
                        commDisplay = commDisplay == "H" and "H/H" or commDisplay == "P" and "P/P" or commDisplay == "S" and "S/S" or commDisplay == "B" and "B/B" or commDisplay
                    end
                    local hasConsensusIcon = addonTable.IsCommunityConsensus and addonTable.IsCommunityConsensus(speciesID, scenario)
                    local triangle = hasConsensusIcon and " \226\150\178" or ""
                    items[#items + 1] = {
                        text = scenarioColor .. string.format(GetLocaleString("COMMUNITY_CONSENSUS"), commDisplay) .. triangle .. "|r",
                        isDisabled = true,
                    }
                end
                -- 品种推荐项
                for _, rec in ipairs(breedResults) do
                    local line = string.format(GetLocaleString("RECOMMEND_SCORE_FMT"), rec.breedCode, rec.score)
                    local isCurrent = (rec.breedID == currentBreedID)
                    local isBest = false
                    if scenario == "PVE" then
                        isBest = (#breedResults > 0 and rec.breedID == breedResults[1].breedID)
                    else
                        isBest = (#breedResults > 0 and rec.breedID == breedResults[1].breedID)
                    end
                    -- 颜色逻辑
                    local breedColor
                    if isCurrent and isBest then
                        breedColor = GOLD_B
                        line = line .. " \226\152\133"
                    elseif isCurrent then
                        breedColor = GREEN
                    elseif isBest then
                        breedColor = scenarioColor
                    else
                        breedColor = ""
                    end
                    -- 社区三角
                    local hasComm = false
                    if scenario == "PVE" then
                        hasComm = addonTable.IsCommunityConsensus and addonTable.IsCommunityConsensus(speciesID, "PVE")
                    else
                        hasComm = addonTable.IsCommunityConsensus and addonTable.IsCommunityConsensus(speciesID, "PVP")
                    end
                    if hasComm then
                        line = line .. " \226\150\178"
                    end
                    local displayText
                    if breedColor ~= "" then
                        displayText = breedColor .. line .. "|r"
                    else
                        displayText = line
                    end
                    items[#items + 1] = {
                        text = displayText,
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

            if sameTop then
                -- 两场景相同：单推荐 + 统一标记
                local commCode = commPvECode or commPvPCode
                if commCode then
                    local commDisplay = commCode
                    local noteText = (commPvECode and commPvPCode) and " \226\150\178" or ""
                    items[#items + 1] = {
                        text = GOLD_RED .. string.format(GetLocaleString("COMMUNITY_CONSENSUS"), commDisplay) .. noteText .. "|r",
                        isDisabled = true,
                    }
                end
                items[#items + 1] = {
                    text = GOLD_RED .. GetLocaleString("RECOMMEND_TITLE") .. " (PvE/PvP)|r",
                    isDisabled = true,
                }
                -- 从PvE结果中输出（两场景相同）
                for _, rec in ipairs(pveResults) do
                    local line = string.format(GetLocaleString("RECOMMEND_SCORE_FMT"), rec.breedCode, rec.score)
                    local isCurrent = (rec.breedID == currentBreedID)
                    local isPvEBest = (#pveResults > 0 and rec.breedID == pveResults[1].breedID)
                    local isPvPBest = (#pvpResults > 0 and rec.breedID == pvpResults[1].breedID)
                    local isBest = isPvEBest or isPvPBest
                    local breedColor
                    if isCurrent and isBest then
                        breedColor = GOLD_B
                        line = line .. " \226\152\133"
                    elseif isCurrent then
                        breedColor = GREEN
                    elseif isBest then
                        breedColor = GOLD_RED
                    else
                        breedColor = ""
                    end
                    local displayText
                    if breedColor ~= "" then
                        displayText = breedColor .. line .. "|r"
                    else
                        displayText = line
                    end
                    items[#items + 1] = {
                        text = displayText,
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
            else
                -- 两场景不同：PvE 先、PvP 后
                AddBreedItem(pveResults, "PVE", GOLD)
                AddBreedItem(pvpResults, "PVP", RED)
                -- 底部摘要
                items[#items + 1] = {
                    text = GRAY .. "-----------------------------|r",
                    isDisabled = true,
                }
                local pveLine = "PvE: " .. (pveTop or "?")
                if commPvECode then pveLine = pveLine .. " \226\150\178" end
                local pvpLine = "PvP: " .. (pvpTop or "?")
                if commPvPCode then pvpLine = pvpLine .. " \226\150\178" end
                items[#items + 1] = {
                    text = GOLD .. pveLine .. "|r",
                    isDisabled = true,
                }
                items[#items + 1] = {
                    text = RED .. pvpLine .. "|r",
                    isDisabled = true,
                }
            end
        end
    end

    -- 已保存的最优品种（如果有）
    local allSaved = addonTable.GetAllBestBreeds(speciesID)
    if next(allSaved) then
        items[#items + 1] = {spacer = true}
        for breedID, breedData in pairs(allSaved) do
            local displayName = GetBreedCode(breedID) or ("ID:" .. breedID)
            local note = (breedData.note and breedData.note ~= "") and (" - " .. breedData.note) or ""
            items[#items + 1] = {
                text = GOLD .. "\229\183\178\232\174\190\230\156\128\228\189\179: " .. displayName .. " \226\152\133" .. note .. "|r",
                isDisabled = true,
            }
        end
    end

    -- 战斗专属：在手册中显示
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
