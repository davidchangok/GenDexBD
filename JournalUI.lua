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

-- 获取算法推荐的 PvE/PvP 最佳品种代码
-- 注意：不缓存结果。CalculateDualScores 内部已有 speciesBuildCache/autoTagCache，
-- 重复调用的开销可忽略；但缓存空结果会导致初始化阶段 API 未就绪时永久失效。
local function GetScenarioBestCodes(speciesID, petType, possibleBreedIDs)
    local result = {pveCode=nil, pvpCode=nil}
    if addonTable.CalculateDualScores then
        local ok, ds = pcall(addonTable.CalculateDualScores, speciesID, petType, possibleBreedIDs, 1)
        if ok then
            if ds.pve and #ds.pve > 0 then result.pveCode = ds.pve[1].breedCode end
            if ds.pvp and #ds.pvp > 0 then result.pvpCode = ds.pvp[1].breedCode end
        end
    end
    return result
end

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
    -- 算法双场景最佳判定（无论是否手动设置，算法推荐即显示★）
    local codes = GetScenarioBestCodes(i.speciesID, i.petType, i.possibleBreedIDs)
    local breedCode = GetBreedCode(i.breedID)
    local isAlgoPvE = codes.pveCode and codes.pveCode == breedCode
    local isAlgoPvP = codes.pvpCode and codes.pvpCode == breedCode
    local isAnyBest = best or isAlgoPvE or isAlgoPvP
    local starR, starG = 1.0, 0.84  -- 默认金色
    if isAnyBest then
        if isAlgoPvE and isAlgoPvP then
            starR, starG = 1.0, 0.50  -- 橙色（PvE+PvP双最佳）
        elseif isAlgoPvE then
            starR, starG = 1.0, 0.84  -- 金黄色（仅PvE最佳）
        elseif isAlgoPvP then
            starR, starG = 1.0, 0.0   -- 红色（仅PvP最佳）
        end
    end
    local doDbg = GeneDexDB and GeneDexDB.Options and GeneDexDB.Options.DebugRecommend
    if doDbg then
        local dkey = i.speciesID .. "_" .. i.breedID
        local dval = (best and "Y" or "N") .. "_" .. (i.breedName or "")
        if labelDebugDone[dkey] ~= dval then
            labelDebugDone[dkey] = dval
            SummarizeSpeciesSkills(i.speciesID)
            print(string.format("[GenDexDBG] label: pet=%s sid=%d bid=%d breed=%s star=%s(pve=%s/pvp=%s)",
                i.speciesName or "?", i.speciesID, i.breedID, i.breedName or "?",
                isAnyBest and "YES" or "no",
                isAlgoPvE and "Y" or "n", isAlgoPvP and "Y" or "n"))
        end
    end
    -- ★ 独立 FontString（避免 ★ 挤占品种代码空间导致遮挡）
    -- 品种文字保持 Rematch 原生 breedName，P/P 等代码完整显示
    b.Breed:SetTextColor(isAnyBest and starR or 0.6, isAnyBest and starG or 0.6, 0.6)
    local isCompact = b:GetHeight() and b:GetHeight() < 35  -- Compact行高26,Normal行高44
    -- ★ 独立 FontString（避免★挤占品种代码空间遮挡）
    -- 复用同一 FontString：Normal锚品种左侧;Compact锚Rematch徽章队列末尾
    if not b.genDexBreedStar then
        b.genDexBreedStar = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    end
    if isCompact then
        -- Compact行高26px,品种★与右上徽章垂直重叠(y=6~18 vs y=4~18);
        -- 把★混入Rematch徽章队列末尾(最后可见徽章左侧),动态跟随徽章数量
        b.genDexBreedStar:ClearAllPoints()
        local lastBadge = nil
        if b.Badges then
            for idx = #b.Badges, 1, -1 do
                if b.Badges[idx] and b.Badges[idx]:IsShown() then lastBadge = b.Badges[idx] break end
            end
        end
        if lastBadge then
            b.genDexBreedStar:SetPoint("RIGHT", lastBadge, "LEFT", -1, 0)
        elseif isCompact then
            -- Compact徽章起始位: xoff=right(-37/-59); yoff=-14对齐徽章中心(14px Texture顶部-7)
            local notesW = b.NotesButton and b.NotesButton:IsShown() and 22 or 0
            b.genDexBreedStar:SetPoint("RIGHT", b, "TOPRIGHT", -37 - notesW, -14)
        else
            -- Normal徽章起始位: xoff=-1-notesWidth(24或2); yoff=-15对齐徽章中心(14px Texture顶部-8)
            local notesW = b.NotesButton and b.NotesButton:IsShown() and 24 or 2
            b.genDexBreedStar:SetPoint("RIGHT", b, "TOPRIGHT", -1-notesW, -15)
        end
    else
        b.genDexBreedStar:SetPoint("RIGHT", b.Breed, "LEFT", -2, 0)
    end
    if isAnyBest then
        b.genDexBreedStar:SetText(addonTable.BEST_BREED_STAR)
        b.genDexBreedStar:SetTextColor(starR, starG, 0.6)
        b.genDexBreedStar:Show()
    else
        b.genDexBreedStar:SetText("")
        b.genDexBreedStar:Hide()
    end
end

-- ========== 菜单注入 ==========

local menuRetryCount = 0
local MAX_MENU_RETRY = 5

local GOLD = "|cffffd600"
local GRAY = "|cff888888"
local RED  = "|cffff0000"
local GOLD_RED = "|cffff8000"
local GREEN = "|cff00ff00"

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
        -- ===== 多品种：PvE + PvP 合并展示 =====
        local pveRecs, pvpRecs = {}, {}
        local pveTop, pvpTop = nil, nil
        if addonTable.CalculateDualScores then
            local ok, ds = pcall(addonTable.CalculateDualScores, speciesID, petType, possibleBreedIDs, 99)
            if ok then pveRecs = ds.pve or {}; pvpRecs = ds.pvp or {} end
        end
        if #pveRecs == 0 then
            local fallback = addonTable.CalculateBreedScores(speciesID, petType, possibleBreedIDs, 99)
            pveRecs = fallback; pvpRecs = fallback
        end
        pveTop = #pveRecs > 0 and pveRecs[1].breedCode or nil
        pvpTop = #pvpRecs > 0 and pvpRecs[1].breedCode or nil

        if #pveRecs == 0 and #pvpRecs == 0 then
            items[#items + 1] = {
                text = GRAY .. "(" .. GetLocaleString("RECOMMEND_NO_DATA") .. ")|r",
                isDisabled = true,
            }
        else
            -- 构建 breedID→{pveScore,pvpScore,breedCode} 合并表
            local merged = {}
            for _, rec in ipairs(pveRecs) do
                merged[rec.breedID] = {code=rec.breedCode, pve=rec.score, pvp=0}
            end
            for _, rec in ipairs(pvpRecs) do
                if merged[rec.breedID] then
                    merged[rec.breedID].pvp = rec.score
                end
            end
            -- 收集并按 PvE 排序
            local mergedList = {}
            for bid, m in pairs(merged) do
                m.bid = bid
                mergedList[#mergedList+1] = m
            end
            table.sort(mergedList, function(a,b) return a.pve > b.pve end)

            -- 社区共识
            local pveComm = addonTable.GetCommunityBreed and addonTable.GetCommunityBreed(speciesID, "PVE")
            local pvpComm = addonTable.GetCommunityBreed and addonTable.GetCommunityBreed(speciesID, "PVP")
            local sameTop = pveTop and pvpTop and pveTop == pvpTop

            -- 头部
            items[#items + 1] = {
                text = (sameTop and GOLD_RED or GOLD) .. GetLocaleString("DUAL_HEADER") .. "|r",
                isDisabled = true,
            }
            -- 社区共识行
            local function commLine(commBreed, scenarioLabel)
                if not commBreed then return end
                local cd = (#commBreed == 1)
                    and (commBreed == "H" and "H/H" or commBreed == "P" and "P/P" or commBreed == "S" and "S/S" or commBreed == "B" and "B/B" or commBreed)
                    or commBreed
                local clr = (scenarioLabel == "PVP") and RED or GOLD
                if sameTop then clr = GOLD_RED end
                items[#items + 1] = {
                    text = clr .. string.format(GetLocaleString("COMMUNITY_CONSENSUS"), cd) .. " ▲|r",
                    isDisabled = true,
                }
            end
            if sameTop then
                commLine(pveComm or pvpComm, "PVE")
            else
                commLine(pveComm, "PVE")
                commLine(pvpComm, "PVP")
            end

            -- 品种行
            for _, m in ipairs(mergedList) do
                local isCurrent = (m.bid == currentBreedID)
                local isPvEBest = (pveTop and m.code == pveTop)
                local isPvPBest = (pvpTop and m.code == pvpTop)
                -- 文字颜色：场景最佳优先于当前品种
                -- 优先级：PvE+PvP双最佳 > PvE最佳 > PvP最佳 > 当前品种 > 普通
                local textColor
                if isPvEBest and isPvPBest then textColor = GOLD_RED
                elseif isPvEBest then textColor = GOLD
                elseif isPvPBest then textColor = RED
                elseif isCurrent then textColor = GREEN
                else textColor = nil
                end
                -- ★颜色：最佳品种加星标
                local starSuffix = ""
                if isPvEBest and isPvPBest then starSuffix = " " .. GOLD_RED .. "★|r"
                elseif isPvEBest then starSuffix = " " .. GOLD .. "★|r"
                elseif isPvPBest then starSuffix = " " .. RED .. "★|r"
                end
                local line = string.format(GetLocaleString("DUAL_SCORE_FMT"), m.code, m.pve, m.pvp)
                if textColor then
                    line = textColor .. line .. "|r"
                end
                line = line .. starSuffix
                local sid = speciesID; local bid = m.bid
                items[#items + 1] = {
                    text = line,
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

            -- 底部摘要（PvE一行/ PvP一行）
            local pveFinalTop = pveTop or "?"
            local pvpFinalTop = pvpTop or "?"
            items[#items + 1] = {
                text = GRAY .. GetLocaleString("DUAL_SCENE_LINE") .. "|r",
                isDisabled = true,
            }
            items[#items + 1] = {
                text = GOLD .. string.format(GetLocaleString("DUAL_SCENE_PVE_FMT"), pveFinalTop) .. (pveComm and " ▲" or "") .. "|r",
                isDisabled = true,
            }
            items[#items + 1] = {
                text = RED .. string.format(GetLocaleString("DUAL_SCENE_PVP_FMT"), pvpFinalTop) .. (pvpComm and " ▲" or "") .. "|r",
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
            -- 实际染色：PvE最佳/ PvP最佳/ 当前
            local isPvEBest = (pveTop and code == pveTop)
            local isPvPBest = (pvpTop and code == pvpTop)
            local isCurrent = (bID == currentBreedID)
            local savedClr
            if isCurrent and isPvEBest and isPvPBest then savedClr = GOLD_RED
            elseif isCurrent and isPvEBest then savedClr = GOLD
            elseif isCurrent and isPvPBest then savedClr = RED
            elseif isCurrent then savedClr = GREEN
            elseif isPvEBest and isPvPBest then savedClr = GOLD_RED
            elseif isPvEBest then savedClr = GOLD
            elseif isPvPBest then savedClr = RED
            else savedClr = GOLD
            end
            items[#items + 1] = {
                text = savedClr .. string.format(GetLocaleString("SAVED_BEST_BREED_FMT"), displayName) .. "|r",
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
