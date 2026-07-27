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
    -- DumpSpeciesAbilities 内部已含标签摘要 + 逐技能详情
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

local GOLD = "|cffffd600"
local GRAY = "|cff888888"
local TEAL = "|cff00cccc"
local RED  = "|cffff0000"
local GOLD_RED = "|cffff8000"

-- 动态构建子菜单（每次悬停时 Rematch 调用 subMenuFunc(self, subject)）
-- 同时暴露为 addonTable.BuildSetBestSubMenu 供战斗界面右击菜单调用
-- isBattle: true=战斗界面调用, nil/false=宠物列表调用
--
-- 菜单逻辑：
--   numBreeds==1 → 自动设最佳 + 显示"已自动设为最佳品种"
--   numBreeds>=2 → 直接展示智能推荐 Top 3（可点击设为最佳）
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
        -- ===== 多品种：PvE + PvP 双场景推荐 =====
        local pveRecs, pvpRecs = {}, {}
        if addonTable.CalculateDualScores then
            local ok, ds = pcall(addonTable.CalculateDualScores, speciesID, petType, possibleBreedIDs, 99)
            if ok then pveRecs = ds.pve or {}; pvpRecs = ds.pvp or {} end
        end
        if #pveRecs == 0 then
            local fallback = addonTable.CalculateBreedScores(speciesID, petType, possibleBreedIDs, 99)
            pveRecs = fallback; pvpRecs = fallback
        end

        if #pveRecs == 0 and #pvpRecs == 0 then
            items[#items + 1] = {
                text = GRAY .. "(" .. GetLocaleString("RECOMMEND_NO_DATA") .. ")|r",
                isDisabled = true,
            }
        else
            local pveTop = #pveRecs > 0 and pveRecs[1].breedCode or nil
            local pvpTop = #pvpRecs > 0 and pvpRecs[1].breedCode or nil
            local sameTop = pveTop and pvpTop and pveTop == pvpTop
            local pveColor = sameTop and GOLD_RED or GOLD
            local pvpColor = sameTop and GOLD_RED or RED

            local function addScenario(scResults, scColor, scenario)
                if not scResults or #scResults == 0 then return end
                local headerKey = (scenario == "PVP") and "SCENARIO_PVP_HEADER" or "SCENARIO_PVE_HEADER"
                local commBreed = addonTable.GetCommunityBreed and addonTable.GetCommunityBreed(speciesID, scenario)
                items[#items + 1] = {
                    text = scColor .. GetLocaleString(headerKey) .. "|r",
                    isDisabled = true,
                }
                if commBreed then
                    local cd = (#commBreed == 1)
                        and (commBreed == "H" and "H/H" or commBreed == "P" and "P/P" or commBreed == "S" and "S/S" or commBreed == "B" and "B/B" or commBreed)
                        or commBreed
                    items[#items + 1] = {
                        text = scColor .. string.format(GetLocaleString("COMMUNITY_CONSENSUS"), cd) .. " ▲|r",
                        isDisabled = true,
                    }
                end
                for _, rec in ipairs(scResults) do
                    local line1 = string.format(GetLocaleString("RECOMMEND_SCORE_FMT"), rec.breedCode, rec.score)
                    local isCurrent = (rec.breedID == currentBreedID)
                    local isBest = addonTable.IsBestBreed(speciesID, rec.breedID)
                    if isCurrent and isBest then
                        line1 = "|cffffd700" .. line1 .. " ★|r"
                    elseif isCurrent then
                        line1 = "|cff00ff00" .. line1 .. "|r"
                    elseif isBest then
                        line1 = scColor .. line1 .. "|r"
                    end
                    local sid = speciesID; local bid = rec.breedID
                    items[#items + 1] = {
                        text = line1,
                        func = function()
                            addonTable.SetBestBreed(sid, bid, "auto", "")
                            C_Timer.After(0.1, function()
                                if not Rematch or not Rematch.petsPanel then return end
                                Rematch.petsPanel:Update()
                                local function fl(f)
                                    if not f then return end
                                    if f.Breed and f.petID then pcall(label, f) end
                                    for _, c in ipairs({f:GetChildren()}) do fl(c) end
                                end
                                if Rematch.petsPanel.List then fl(Rematch.petsPanel.List) end
                            end)
                        end,
                    }
                end
            end

            addScenario(pveRecs, pveColor, "PVE")
            addScenario(pvpRecs, pvpColor, "PVP")

            -- 底部摘要
            local pveComm = addonTable.GetCommunityBreed and addonTable.GetCommunityBreed(speciesID, "PVE")
            local pvpComm = addonTable.GetCommunityBreed and addonTable.GetCommunityBreed(speciesID, "PVP")
            local pveFinalTop = pveTop or "?"
            local pvpFinalTop = pvpTop or "?"
            items[#items + 1] = {
                text = GRAY .. GetLocaleString("DUAL_SCENE_LINE") .. "|r",
                isDisabled = true,
            }
            items[#items + 1] = {
                text = pveColor .. string.format(GetLocaleString("DUAL_SCENE_PVE_FMT"), pveFinalTop) .. (pveComm and " ▲" or "") .. "|r",
                isDisabled = true,
            }
            items[#items + 1] = {
                text = pvpColor .. string.format(GetLocaleString("DUAL_SCENE_PVP_FMT"), pvpFinalTop) .. (pvpComm and " ▲" or "") .. "|r",
                isDisabled = true,
            }
        end
    end

    -- ===== 已设最佳品种标注 =====
    local allBest = addonTable.GetAllBestBreeds(speciesID)
    if next(allBest) then
        items[#items + 1] = { spacer = true }
        for bID in pairs(allBest) do
            local code = GetBreedCode(bID) or "?"
            local displayName = addonTable.GetBreedDisplayName and addonTable.GetBreedDisplayName(bID, code) or code
            items[#items + 1] = {
                text = GOLD .. string.format(GetLocaleString("SAVED_BEST_BREED_FMT"), displayName) .. "|r",
                isDisabled = true,
            }
        end
    end

    -- ===== 在手册中显示（仅战斗界面） =====
    if isBattle and speciesName then
        items[#items + 1] = { spacer = true }
        items[#items + 1] = { text = GetLocaleString("SHOW_IN_JOURNAL"), func = function()
            Rematch.menus:Hide()
            Rematch.layout:SummonView("pets")
            Rematch.filters:SetSearch(speciesName)
            Rematch.petsPanel.Top.SearchBox:SetText(speciesName)
            Rematch.petsPanel:Update()
        end }
    end

    Rematch.menus:Register("GenDexSetBestMenu", items)
end
addonTable.BuildSetBestSubMenu = BuildSetBestSubMenu

local function injectRematchMenus()
    if not Rematch or not Rematch.menus or not Rematch.menus.AddToMenu then return end

    Rematch.menus:Register("GenDexSetBestMenu", {{text="..."}})

    local ok = pcall(function()
        Rematch.menus:AddToMenu("PetMenu",{
            text=GetLocaleString("SET_BEST_BREED"),
            subMenu="GenDexSetBestMenu",
            subMenuFunc=BuildSetBestSubMenu,
            hidden=function(_, p)
                if not p then return true end
                if not Rematch or not Rematch.petInfo then return true end
                local info = Rematch.petInfo:Fetch(p)
                return not info or not info.speciesID
            end,
        },"Find Teams")
    end)

    if not ok then
        menuRetryCount = menuRetryCount + 1
        if menuRetryCount < MAX_MENU_RETRY then
            C_Timer.After(1, injectRematchMenus)
        end
    end
end

function addonTable.InitJournalUI()
    local function hookFill()
        if RematchNormalPetListButtonMixin and not RematchNormalPetListButtonMixin._gHooked then
            RematchNormalPetListButtonMixin._gHooked=true
            hooksecurefunc(RematchNormalPetListButtonMixin,"Fill",function(b) label(b) end)
            print("|cff00ffff[GenDexDBG]|r Hooked RematchNormalPetListButtonMixin.Fill")
        end
        if RematchCompactPetListButtonMixin and not RematchCompactPetListButtonMixin._gHooked then
            RematchCompactPetListButtonMixin._gHooked=true
            hooksecurefunc(RematchCompactPetListButtonMixin,"Fill",function(b) label(b) end)
            print("|cff00ffff[GenDexDBG]|r Hooked RematchCompactPetListButtonMixin.Fill")
        end
        injectRematchMenus()
    end

    if C_AddOns.IsAddOnLoaded("Rematch") then hookFill()
    else
        local f=CreateFrame("Frame");f:RegisterEvent("ADDON_LOADED")
        f:SetScript("OnEvent",function(_,_,a) if a=="Rematch" then hookFill();f:UnregisterEvent("ADDON_LOADED") end end)
    end
end
