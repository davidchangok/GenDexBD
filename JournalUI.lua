-- GenDexBD JournalUI.lua - Mixin Fill Hook + 右键菜单（已拥有+未拥有统一）

local addonName, addonTable = ...
local time=time;local next=next;local ipairs=ipairs;local pairs=pairs;local tsort=table.sort
local GetLocaleString = addonTable.GetLocaleString
local GetBreedCode = addonTable.GetBreedCode

function addonTable.SetBestBreed(s,b,c,n)
    if not s or not b then return end;if not GeneDexDB then return end
    local bb=GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then GeneDexDB.BestBreeds={} end
    GeneDexDB.BestBreeds[s]={};GeneDexDB.BestBreeds[s][b]={category=c or "custom",note=n or "",addedAt=time()}
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

-- 品种列表（从 BreedData 表动态生成）
local ALL_BREEDS = {}
do
    local breeds = addonTable.BREEDS
    if breeds then
        for breedID = 3, 14 do
            if breeds[breedID] then
                local code = GetBreedCode(breedID)
                if code then
                    ALL_BREEDS[#ALL_BREEDS + 1] = { breedID, code }
                end
            end
        end
    end
end

local function label(b)
    if not b or not b.Breed or not b.petID then return end
    if not Rematch or not Rematch.petInfo then return end
    local i=Rematch.petInfo:Fetch(b.petID)
    if not i or not i.hasBreed or not i.breedID or i.breedID==0 then return end
    local best=addonTable.IsBestBreed(i.speciesID,i.breedID)
    local sc = addonTable.BEST_BREED_COLOR or {1.0, 0.84, 0.0}
    b.Breed:SetText(best and (addonTable.BEST_BREED_STAR..i.breedName) or i.breedName)
    b.Breed:SetTextColor(best and sc[1] or 0.6, best and sc[2] or 0.6, 0.6)
end

function RematchSetBest(petID)
    if not Rematch or not Rematch.petInfo then return end
    local i=Rematch.petInfo:Fetch(petID);if not i or not i.hasBreed then return end
    addonTable.SetBestBreed(i.speciesID,i.breedID,"custom","")
    if Rematch.petsPanel then Rematch.petsPanel:Update() end
end
function RematchRemoveBest(petID)
    if not Rematch or not Rematch.petInfo then return end
    local i=Rematch.petInfo:Fetch(petID);if not i or not i.hasBreed then return end
    addonTable.RemoveBestBreed(i.speciesID,i.breedID)
    if Rematch.petsPanel then Rematch.petsPanel:Update() end
end
function RematchHasBest(petID)
    if not Rematch or not Rematch.petInfo then return false end
    local i=Rematch.petInfo:Fetch(petID)
    return i and i.hasBreed and addonTable.IsBestBreed(i.speciesID,i.breedID)
end
function RematchSetBestNoPet(speciesID,breedID)
    addonTable.SetBestBreed(speciesID,breedID,"custom","")
    if Rematch.petsPanel then Rematch.petsPanel:Update() end
end

-- ========== 菜单注入 ==========

local menuRetryCount = 0
local MAX_MENU_RETRY = 5

-- 金色（与 BEST_BREED_COLOR 一致，用于菜单文字着色）
local GOLD = "|cffffd600"
local GRAY = "|cff888888"

    -- ===== 智能推荐子菜单构建函数 =====
    local function BuildRecommendSubMenu(_, petID)
        if not Rematch or not Rematch.petInfo then return end
        local info = Rematch.petInfo:Fetch(petID)
        if not info or not info.speciesID then return end

        local speciesID = info.speciesID
        local petType = info.petType
        local possibleBreedIDs = info.possibleBreedIDs
        local currentBreedID = (info.hasBreed and info.breedID and info.breedID > 0) and info.breedID or nil

        local items = {}

        -- 调用推荐引擎
        local recommendations = addonTable.CalculateBreedScores(speciesID, petType, possibleBreedIDs, 3)

        if #recommendations == 0 then
            items[#items + 1] = {
                text = GRAY .. "(" .. GetLocaleString("RECOMMEND_NO_DATA") .. ")|r",
                isDisabled = true,
            }
        else
            -- 标题行
            items[#items + 1] = {
                text = GOLD .. GetLocaleString("RECOMMEND_TITLE") .. "|r",
                isDisabled = true,
            }

            -- 标签统计
            local hasTags = false
            for _, rec in ipairs(recommendations) do
                if next(rec.tagCounts) then hasTags = true; break end
            end
            if not hasTags then
                items[#items + 1] = {
                    text = GRAY .. "  " .. GetLocaleString("RECOMMEND_NO_TAGS") .. "|r",
                    isDisabled = true,
                }
            end

            -- Top 3 推荐品种（显示品种代码 + 评分 + 三围）
            for _, rec in ipairs(recommendations) do
                local line1 = string.format(GetLocaleString("RECOMMEND_SCORE_FMT"), rec.breedCode, rec.score)

                -- 标记当前品种
                if rec.breedID == currentBreedID then
                    line1 = line1 .. " ←"
                end

                local line2 = string.format(GetLocaleString("RECOMMEND_STATS_FMT"),
                    rec.stats.h_coef, rec.stats.p_coef, rec.stats.s_coef)

                items[#items + 1] = {
                    text = line1,
                    func = function()
                        addonTable.SetBestBreed(speciesID, rec.breedID, "auto", "")
                        C_Timer.After(0, function()
                            if Rematch.petsPanel then Rematch.petsPanel:Update() end
                        end)
                    end,
                }
                -- 数值详情作为灰色子行
                items[#items + 1] = {
                    text = GRAY .. line2 .. "|r",
                    isDisabled = true,
                }
            end
        end

        Rematch.menus:Register("GenDexRecommendMenu", items)
    end

    -- 动态构建子菜单（每次悬停时 Rematch 调用 subMenuFunc(self, subject)）
-- 同时暴露为 addonTable.BuildSetBestSubMenu 供战斗界面右击菜单调用
-- isBattle: true=战斗界面调用, nil/false=宠物列表调用
local function BuildSetBestSubMenu(_, petID, isBattle)
    if not Rematch or not Rematch.petInfo then return end
    local info = Rematch.petInfo:Fetch(petID)
    if not info or not info.speciesID then return end

    local speciesID = info.speciesID
    local speciesName = info.speciesName
    local currentBreedID = (info.hasBreed and info.breedID and info.breedID > 0) and info.breedID or nil
    local currentBreedName = currentBreedID and info.breedName and info.breedName ~= "" and info.breedName or nil
    -- numPossibleBreeds: 该物种有多少种可选品种（0=数据暂缺, 1=唯一属性, >=2=多品种）
    local numBreeds = info.numPossibleBreeds or 0

    local items = {}

    if numBreeds == 1 then
        -- ===== 唯一属性物种：自动设为最佳属性并写入数据库 =====
        local onlyBreedID = currentBreedID
        if not onlyBreedID and info.possibleBreedIDs and #info.possibleBreedIDs > 0 then
            onlyBreedID = info.possibleBreedIDs[1]
        end
        if onlyBreedID and not addonTable.IsBestBreed(speciesID, onlyBreedID) then
            addonTable.SetBestBreed(speciesID, onlyBreedID, "auto", "")
            -- 延迟一帧刷新，避免菜单构建期间 Update() 破坏按钮 UI 层级
            C_Timer.After(0, function()
                if Rematch.petsPanel then Rematch.petsPanel:Update() end
            end)
        end
        items[#items + 1] = { text = GOLD .. GetLocaleString("ONLY_BREED_IS_BEST") .. "|r", isDisabled = true }
    else
        -- ===== 多品种物种：展示所有已设最佳品种 =====
        local allBest = addonTable.GetAllBestBreeds(speciesID)
        local hasBestBreeds = next(allBest) ~= nil

        if hasBestBreeds then
            local sorted = {}
            for bID in pairs(allBest) do
                sorted[#sorted + 1] = bID
            end
            tsort(sorted)

            for _, bID in ipairs(sorted) do
                local code = GetBreedCode(bID) or "?"
                local isCurrent = (currentBreedID == bID)

                local text = GOLD .. code .. " ★|r"
                if isCurrent then
                    text = text .. " " .. GetLocaleString("REMOVE_BEST_BREED")
                end

                if isCurrent then
                    items[#items + 1] = { text = text, func = function() RematchRemoveBest(petID) end }
                else
                    items[#items + 1] = { text = text, func = function()
                        addonTable.RemoveBestBreed(speciesID, bID)
                        if Rematch.petsPanel then Rematch.petsPanel:Update() end
                    end }
                end
            end
        else
            items[#items + 1] = { text = GRAY .. "(" .. GetLocaleString("NO_BEST_BREED_SET") .. ")|r", isDisabled = true }
        end

        -- 当前品种不在最佳列表中 → 提供设置入口
        if currentBreedID and (not hasBestBreeds or not allBest[currentBreedID]) then
            local code = currentBreedName or GetBreedCode(currentBreedID) or "?"
            items[#items + 1] = { text = code .. " " .. GetLocaleString("SET_BEST_BREED"), func = function() RematchSetBest(petID) end }
        end

        -- 分隔线 + 设为其他品种（仅限当前物种实际可用的品种）
        items[#items + 1] = { spacer = true }

        local otherItems = {}
        local pIDs = info.possibleBreedIDs
        local pNames = info.possibleBreedNames
        if pIDs and pNames and type(pIDs) == "table" and type(pNames) == "table" then
            -- 收集并排序
            local possibleList = {}
            for i = 1, #pIDs do
                local bid = pIDs[i]
                local bname = pNames[i]
                if bid and bname then
                    possibleList[#possibleList + 1] = { breedID = bid, breedName = bname }
                end
            end
            tsort(possibleList, function(a, b) return a.breedID < b.breedID end)
            for _, entry in ipairs(possibleList) do
                otherItems[#otherItems + 1] = { text = entry.breedName,
                    func = function() RematchSetBestNoPet(speciesID, entry.breedID) end }
            end
        else
            -- 回退：Rematch 未提供可能品种时用全部品种
            for _, br in ipairs(ALL_BREEDS) do
                otherItems[#otherItems + 1] = { text = br[2], func = function() RematchSetBestNoPet(speciesID, br[1]) end }
            end
        end
        otherItems[#otherItems + 1] = { text = CANCEL }
        Rematch.menus:Register("GenDexOtherBreedsMenu", otherItems)

        items[#items + 1] = { text = GetLocaleString("SET_OTHER_BREED"), subMenu = "GenDexOtherBreedsMenu" }
    end

    -- ===== 智能推荐（所有可多选的物种都显示，含唯一品种） =====
    items[#items + 1] = { spacer = true }
    items[#items + 1] = {
        text = GetLocaleString("SMART_RECOMMEND"),
        subMenu = "GenDexRecommendMenu",
        subMenuFunc = BuildRecommendSubMenu,
    }

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
    Rematch.menus:Register("GenDexOtherBreedsMenu", {{text="..."}})
    Rematch.menus:Register("GenDexRecommendMenu", {{text="..."}})

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
        end
        if RematchCompactPetListButtonMixin and not RematchCompactPetListButtonMixin._gHooked then
            RematchCompactPetListButtonMixin._gHooked=true
            hooksecurefunc(RematchCompactPetListButtonMixin,"Fill",function(b) label(b) end)
        end
        injectRematchMenus()
    end

    if C_AddOns.IsAddOnLoaded("Rematch") then hookFill()
    else
        local f=CreateFrame("Frame");f:RegisterEvent("ADDON_LOADED")
        f:SetScript("OnEvent",function(_,_,a) if a=="Rematch" then hookFill();f:UnregisterEvent("ADDON_LOADED") end end)
    end
end
