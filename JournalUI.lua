-- GenDexBD JournalUI.lua - Mixin Fill Hook + 右键菜单（已拥有+未拥有统一）

local addonName, addonTable = ...
local time=time;local next=next;local pairs=pairs;local ipairs=ipairs
local GetLocaleString = addonTable.GetLocaleString
local GetBreedCode = addonTable.GetBreedCode
local CalculateBreedFromStats = addonTable.CalculateBreedFromStats
local function LOG(...) print("|cff00ccff[GenDexBD]|r "..string.format(...)) end

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

-- 品种列表（与 BreedData.lua 同步维护）
local ALL_BREEDS = {{3,"B/B"},{4,"P/P"},{5,"S/S"},{6,"H/H"},{7,"H/P"},{8,"P/S"},{9,"H/S"},{10,"P/B"},{11,"S/B"},{12,"H/B"},{13,"P/H"},{14,"H/S"}}

local function label(b)
    if not b or not b.Breed or not b.petID then return end
    if not Rematch or not Rematch.petInfo then return end
    local i=Rematch.petInfo:Fetch(b.petID)
    if not i or not i.hasBreed or not i.breedID or i.breedID==0 then return end
    local best=addonTable.IsBestBreed(i.speciesID,i.breedID)
    b.Breed:SetText(best and ("★"..i.breedName) or i.breedName)
    b.Breed:SetTextColor(best and 1 or 0.6,best and 0.84 or 0.6,0.6)
end

function RematchSetBest(petID)
    if not Rematch or not Rematch.petInfo then return end
    local i=Rematch.petInfo:Fetch(petID);if not i or not i.hasBreed then return end
    addonTable.SetBestBreed(i.speciesID,i.breedID,"custom","")
    LOG("已保存: speciesID=%d breedID=%d (%s)",i.speciesID,i.breedID,i.breedName or "?")
    if Rematch.petsPanel then Rematch.petsPanel:Update() end
end
function RematchRemoveBest(petID)
    if not Rematch or not Rematch.petInfo then return end
    local i=Rematch.petInfo:Fetch(petID);if not i or not i.hasBreed then return end
    addonTable.RemoveBestBreed(i.speciesID,i.breedID)
    LOG("已移除: speciesID=%d breedID=%d",i.speciesID,i.breedID)
    if Rematch.petsPanel then Rematch.petsPanel:Update() end
end
function RematchHasBest(petID)
    if not Rematch or not Rematch.petInfo then return false end
    local i=Rematch.petInfo:Fetch(petID)
    return i and i.hasBreed and addonTable.IsBestBreed(i.speciesID,i.breedID)
end
function RematchSetBestNoPet(speciesID,breedID)
    addonTable.SetBestBreed(speciesID,breedID,"custom","")
    LOG("已保存(未拥有): speciesID=%d breedID=%d",speciesID,breedID)
    if Rematch.petsPanel then Rematch.petsPanel:Update() end
end

-- ========== 已拥有品种检索 ==========

local baseStatFields = nil  -- {healthKey, powerKey, speedKey}

local function DetectBaseStatFields()
    if baseStatFields then return baseStatFields[1], baseStatFields[2], baseStatFields[3] end
    local sample = C_PetJournal.GetPetInfoBySpeciesID(39) or C_PetJournal.GetPetInfoBySpeciesID(1)
    if not sample then return nil, nil, nil end

    local allKeys = {}
    for k in pairs(sample) do allKeys[#allKeys+1] = k end

    local function findKey(patterns)
        for _, key in ipairs(allKeys) do
            local lowerKey = string.lower(key)
            for _, pat in ipairs(patterns) do
                if string.find(lowerKey, pat, 1, true) then return key end
            end
        end
        return nil
    end

    local hk = findKey({"health", "hp"})
    local pk = findKey({"power", "attack", "atk"})
    local sk = findKey({"speed", "spd"})
    baseStatFields = {hk, pk, sk}
    return hk, pk, sk
end

local function GetBaseStats(speciesID)
    local hk, pk, sk = DetectBaseStatFields()
    if not hk or not pk or not sk then return nil, nil, nil end
    local petInfo = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
    if not petInfo then return nil, nil, nil end
    return petInfo[hk], petInfo[pk], petInfo[sk]
end

-- 获取某物种已拥有的所有 breedID（用于菜单过滤）
local function GetOwnedBreedIDs(speciesID)
    local owned = {}
    if not speciesID then return owned end
    -- 获取基准属性
    local baseH, baseP, baseS = GetBaseStats(speciesID)
    if not baseH or not baseP or not baseS then return owned end
    -- 遍历已拥有宠物
    local numPets = C_PetJournal.GetNumPets()
    for i = 1, numPets do
        local petGUID, sid, _, _, level, _, _, _, _, _, _, _, _, _, _, _, _, _ = C_PetJournal.GetPetInfoByIndex(i)
        if sid == speciesID and petGUID then
            local _, maxHealth, power, speed, rarity = C_PetJournal.GetPetStats(petGUID)
            if maxHealth and power and speed and level and rarity then
                local breedID = CalculateBreedFromStats(maxHealth, power, speed, baseH, baseP, baseS, level, rarity)
                if breedID then
                    owned[breedID] = true
                end
            end
        end
    end
    return owned
end

-- ========== 菜单注入 ==========

local menuRetryCount = 0
local MAX_MENU_RETRY = 5

-- 动态子菜单构建函数（每次鼠标悬停时由 Rematch 调用 subMenuFunc(self, subject)）
local function BuildSetBestSubMenu(_, petID)
    if not Rematch or not Rematch.petInfo then return end
    local info = Rematch.petInfo:Fetch(petID)
    if not info or not info.speciesID then return end

    local speciesID = info.speciesID
    local currentBreedID = (info.hasBreed and info.breedID and info.breedID > 0) and info.breedID or nil
    local isBest = currentBreedID and addonTable.IsBestBreed(speciesID, currentBreedID)

    -- 收集已拥有品种
    local ownedBreeds = GetOwnedBreedIDs(speciesID)

    -- 构建一级子菜单
    local items = {}

    -- 1.1 当前宠物品种项（有品种且非最优 → 设为最优；已是最优 → 取消）
    if currentBreedID then
        local code = GetBreedCode(currentBreedID) or "?"
        if isBest then
            items[#items+1] = {text=code.." ★ "..GetLocaleString("REMOVE_BEST_BREED"), func=function() RematchRemoveBest(petID) end}
        else
            items[#items+1] = {text=code.." "..GetLocaleString("SET_THIS_BREED"), func=function() RematchSetBest(petID) end}
        end
    end

    -- 1.2 设为其他品种（过滤掉已拥有的）
    local otherItems = {}
    for _, br in ipairs(ALL_BREEDS) do
        if not ownedBreeds[br[1]] then
            otherItems[#otherItems+1] = {text=br[2], func=function() RematchSetBestNoPet(speciesID, br[1]) end}
        end
    end
    if #otherItems == 0 then
        otherItems[#otherItems+1] = {text="("..GetLocaleString("ALL_OWNED")..")", disable=true}
    end
    otherItems[#otherItems+1] = {text=CANCEL}
    Rematch.menus:Register("GenDexOtherBreedsMenu", otherItems)

    items[#items+1] = {text=GetLocaleString("SET_OTHER_BREED"), subMenu="GenDexOtherBreedsMenu"}

    Rematch.menus:Register("GenDexSetBestMenu", items)
end

local function injectRematchMenus()
    if not Rematch or not Rematch.menus or not Rematch.menus.AddToMenu then
        LOG("菜单注入跳过: Rematch.menus 不可用")
        return
    end

    local ok, err = pcall(function()
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

    if ok then
        LOG("菜单注入成功")
    else
        menuRetryCount = menuRetryCount + 1
        LOG("菜单注入失败(第%d次): %s", menuRetryCount, tostring(err))
        if menuRetryCount < MAX_MENU_RETRY then
            C_Timer.After(1, injectRematchMenus)
        else
            LOG("菜单重试已达上限(%d次)，放弃", MAX_MENU_RETRY)
        end
    end
end

function addonTable.InitJournalUI()
    LOG("初始化")

    local function hookFill()
        if RematchNormalPetListButtonMixin and not RematchNormalPetListButtonMixin._gHooked then
            RematchNormalPetListButtonMixin._gHooked=true
            hooksecurefunc(RematchNormalPetListButtonMixin,"Fill",function(b) label(b) end)
            LOG("已 Hook Normal Mixin Fill")
        end
        if RematchCompactPetListButtonMixin and not RematchCompactPetListButtonMixin._gHooked then
            RematchCompactPetListButtonMixin._gHooked=true
            hooksecurefunc(RematchCompactPetListButtonMixin,"Fill",function(b) label(b) end)
            LOG("已 Hook Compact Mixin Fill")
        end
        -- Rematch 已加载，立即注入菜单
        injectRematchMenus()
    end

    if C_AddOns.IsAddOnLoaded("Rematch") then hookFill()
    else
        local f=CreateFrame("Frame");f:RegisterEvent("ADDON_LOADED")
        f:SetScript("OnEvent",function(_,_,a) if a=="Rematch" then hookFill();f:UnregisterEvent("ADDON_LOADED") end end)
    end
end
