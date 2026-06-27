-- GenDexBD JournalUI.lua
-- Rematch: Badge(五星) + Fill Hook(Breed文本) + 右键菜单
-- 暴雪原生: Hook PetJournal_InitPetButton

local addonName, addonTable = ...
local time=time;local pairs=pairs;local next=next
local function LOG(...) print("|cff00ccff[GenDexBD]|r "..string.format(...)) end

-- ========== API ==========
function addonTable.SetBestBreed(sid,bid,cat,note)
    if not sid or not bid then return end;if not GeneDexDB then return end
    local bb=GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then GeneDexDB.BestBreeds={} end
    if not GeneDexDB.BestBreeds[sid] then GeneDexDB.BestBreeds[sid]={} end
    GeneDexDB.BestBreeds[sid][bid]={category=cat or "custom",note=note or "",addedAt=time()}
end
function addonTable.RemoveBestBreed(sid,bid)
    if not sid or not bid then return end
    local bb=GeneDexDB and GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then return end
    local sd=bb[sid];if not sd or type(sd)~="table" then return end;sd[bid]=nil;if not next(sd) then bb[sid]=nil end
end
function addonTable.IsBestBreed(sid,bid)
    if not sid or not bid then return false end
    local bb=GeneDexDB and GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then return false end
    local sd=bb[sid];if not sd or type(sd)~="table" then return false end;return sd[bid]~=nil
end
function addonTable.GetAllBestBreeds(sid)
    if not sid then return {} end
    local bb=GeneDexDB and GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then return {} end
    local sd=bb[sid];return (sd and type(sd)=="table") and sd or {}
end

-- ========== Rematch Badge：金色五星（和升级标志一样用 badge 系统） ==========
local badgeRegistered=false
local function RegisterStarBadge()
    if badgeRegistered then return end
    if not Rematch or not Rematch.badges or not Rematch.badges.RegisterBadge then
        LOG("⚠ Rematch.badges 不可用，延迟注册")
        return
    end
    badgeRegistered=true
    Rematch.badges:RegisterBadge("pets","genedex_best",
        "PetJournal-FavoritesIcon", nil,
        function(button,petID)
            if not petID then return false end
            if not Rematch.petInfo then return false end
            local info=Rematch.petInfo:Fetch(petID)
            if not info or not info.hasBreed or not info.breedID or info.breedID==0 then return false end
            return addonTable.IsBestBreed(info.speciesID,info.breedID)
        end)
    LOG("金色五星 Badge 已注册到 pets 列表")
end

-- ========== Fill Hook：Breed 文本着色 ==========
local fillHooked=false
local function HookFill()
    if fillHooked then return end
    if not Rematch or not Rematch.petsPanel or not Rematch.petsPanel.FillNormal then return end
    fillHooked=true
    local function onFill(_,button)
        if not button or not button.Breed or not button.petID then return end
        if not Rematch.petInfo then return end
        local info=Rematch.petInfo:Fetch(button.petID)
        if not info or not info.hasBreed or not info.breedID or info.breedID==0 then return end
        local isBest=addonTable.IsBestBreed(info.speciesID,info.breedID)
        -- Breed 文本保持 Rematch 原有的品种名，只改颜色
        button.Breed:SetTextColor(isBest and 1 or 0.6,isBest and 0.84 or 0.6,0.6)
    end
    hooksecurefunc(Rematch.petsPanel,"FillNormal",onFill)
    hooksecurefunc(Rematch.petsPanel,"FillCompact",onFill)
    LOG("已 Hook Rematch Fill (Breed着色)")
end

-- ========== 右键菜单 ==========
function RematchSetBest(petID)
    if not Rematch or not Rematch.petInfo then return end
    local info=Rematch.petInfo:Fetch(petID)
    if not info or not info.hasBreed then return end
    addonTable.SetBestBreed(info.speciesID,info.breedID,"custom","")
    LOG("已保存: speciesID=%d breedID=%d (%s)",info.speciesID,info.breedID,info.breedName or "?")
    Rematch.petsPanel:Update()
end
function RematchRemoveBest(petID)
    if not Rematch or not Rematch.petInfo then return end
    local info=Rematch.petInfo:Fetch(petID)
    if not info or not info.hasBreed then return end
    addonTable.RemoveBestBreed(info.speciesID,info.breedID)
    LOG("已移除: speciesID=%d breedID=%d",info.speciesID,info.breedID)
    Rematch.petsPanel:Update()
end
function RematchHasBest(petID)
    if not Rematch or not Rematch.petInfo then return false end
    local info=Rematch.petInfo:Fetch(petID)
    return info and info.hasBreed and addonTable.IsBestBreed(info.speciesID,info.breedID)
end

local menuInjected=false
local function InjectMenu()
    if menuInjected then return end
    if not Rematch or not Rematch.menus or not Rematch.menus.AddToMenu then return end;menuInjected=true
    Rematch.menus:AddToMenu("PetMenu",{
        text=function(_,p) return RematchHasBest(p) and "取消最优品种" or "设为最优品种" end,
        hidden=function(_,p) return not p end,
        func=function(_,p) if RematchHasBest(p) then RematchRemoveBest(p) else RematchSetBest(p) end end
    },"Find Teams")
    LOG("Rematch 菜单已注入")
end

-- ========== 暴雪原生 ==========
local blizzHooked=false
local function TryHookBlizzard()
    if blizzHooked then return end
    if not PetJournal_InitPetButton then return end;blizzHooked=true
    hooksecurefunc("PetJournal_InitPetButton",function(button,ed)
        if not button or not ed or not ed.index then return end
        if not GeneDexDB or not GeneDexDB.Options or not GeneDexDB.Options.ShowInJournal then return end
        local petID=C_PetJournal.GetPetInfoByIndex(ed.index);if not petID then return end
        local _,speciesID=C_PetJournal.GetPetInfoByPetID(petID);if not speciesID then return end
        if next(addonTable.GetAllBestBreeds(speciesID)) and button.name then
            button.name:SetTextColor(1,0.84,0)
        end
    end)
    LOG("已 Hook PetJournal_InitPetButton")
end

-- ========== 初始化 ==========
function addonTable.InitJournalUI()
    LOG("初始化")
    local function init()
        RegisterStarBadge();HookFill();InjectMenu()
        if Rematch.petsPanel and Rematch.petsPanel.Update then Rematch.petsPanel:Update() end
    end
    if C_AddOns.IsAddOnLoaded("Rematch") then init()
    else
        local rf=CreateFrame("Frame");rf:RegisterEvent("ADDON_LOADED")
        rf:SetScript("OnEvent",function(_,_,a) if a=="Rematch" then init();rf:UnregisterEvent("ADDON_LOADED") end end)
    end

    local bcf=CreateFrame("Frame");bcf:RegisterEvent("ADDON_LOADED")
    bcf:SetScript("OnEvent",function(_,_,a) if a=="Blizzard_Collections" then TryHookBlizzard();bcf:UnregisterEvent("ADDON_LOADED") end end)
    local pjf=CreateFrame("Frame");pjf:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
    pjf:SetScript("OnEvent",function() TryHookBlizzard() end)
end
