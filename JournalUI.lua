-- GenDexBD JournalUI.lua
-- Rematch: Hook Fill + 品种标注 + 金色五星 + 右键菜单
-- 暴雪原生: Hook PetJournal_InitPetButton + 右键菜单
-- 品种来源: 直接用 Rematch petInfo（BattlePetBreedID 提供数据）

local addonName, addonTable = ...
local GetBreedCode=addonTable.GetBreedCode;local time=time
local pairs=pairs;local next=next
local function LOG(...) print("|cff00ccff[GenDexBD]|r "..string.format(...)) end

-- ========== 最优品种管理 API ==========
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

-- ========== 品种标注 + 五星 ==========
local function Decorate(button)
    if not button or not button.petID then return end
    if not button.Breed then return end
    if not Rematch or not Rematch.petInfo then return end
    local info=Rematch.petInfo:Fetch(button.petID)
    if not info or not info.hasBreed or not info.breedID or info.breedID==0 then return end
    local breedID,breedName,speciesID=info.breedID,info.breedName,info.speciesID
    local isBest=addonTable.IsBestBreed(speciesID,breedID)

    button.Breed:SetText(isBest and ("★"..breedName) or breedName)
    button.Breed:SetTextColor(isBest and 1 or 0.6,isBest and 0.84 or 0.6,0.6)
    button.Breed:Show()

    if isBest then
        if not button._gStar then
            local star=button:CreateTexture(nil,"OVERLAY")
            star:SetAtlas("PetJournal-FavoritesIcon");star:SetSize(16,16)
            star:SetPoint("RIGHT",button.Breed,"LEFT",-80,0);button._gStar=star
        end;button._gStar:Show()
    else
        if button._gStar then button._gStar:Hide() end
    end
end

-- 扫描 RematchFrame 所有可见按钮强制 Decorate
local function DecorateAll()
    if not RematchFrame or not RematchFrame:IsShown() then return end
    local c=0
    local function s(p,d)
        if d>6 then return end
        for _,ch in ipairs({p:GetChildren()}) do
            if ch.petID and ch:IsVisible() then Decorate(ch);c=c+1 end;s(ch,d+1)
        end
    end
    s(RematchFrame,0)
    if c>0 then LOG("已标注 %d 个按钮",c) else LOG("DecorateAll: 0个可见按钮") end
end

-- ========== Rematch Fill Hook ==========
local rematchHooked=false
local function TryHookRematch()
    if rematchHooked then return end
    if not Rematch or not Rematch.petsPanel or not Rematch.petsPanel.FillNormal then return end
    rematchHooked=true
    hooksecurefunc(Rematch.petsPanel,"FillNormal",function(_,b) Decorate(b) end)
    hooksecurefunc(Rematch.petsPanel,"FillCompact",function(_,b) Decorate(b) end)
    LOG("已 Hook Rematch Fill")
    Rematch.petsPanel:Update()
    C_Timer.After(0.3,function() DecorateAll() end)
end

-- ========== Rematch 右键菜单 ==========
function RematchSetBest(petID,cat)
    if not Rematch or not Rematch.petInfo then return end
    local info=Rematch.petInfo:Fetch(petID)
    if not info or not info.hasBreed then LOG("⚠ 品种未确定");return end
    addonTable.SetBestBreed(info.speciesID,info.breedID,cat or "custom","")
    LOG("已保存: speciesID=%d breedID=%d (%s)",info.speciesID,info.breedID,info.breedName or "?")
    Rematch.petsPanel:Update();C_Timer.After(0.3,function() DecorateAll() end)
end
function RematchRemoveBest(petID)
    if not Rematch or not Rematch.petInfo then return end
    local info=Rematch.petInfo:Fetch(petID)
    if not info or not info.speciesID then return end
    for bid in pairs(addonTable.GetAllBestBreeds(info.speciesID)) do addonTable.RemoveBestBreed(info.speciesID,bid) end
    LOG("已移除: speciesID=%d",info.speciesID)
    Rematch.petsPanel:Update();C_Timer.After(0.3,function() DecorateAll() end)
end
function RematchHasBest(petID)
    if not Rematch or not Rematch.petInfo then return false end
    local info=Rematch.petInfo:Fetch(petID)
    return info and info.speciesID and next(addonTable.GetAllBestBreeds(info.speciesID))
end

local menuInjected=false
local function TryInjectRematchMenu()
    if menuInjected then return end
    if not Rematch or not Rematch.menus or not Rematch.menus.AddToMenu then return end;menuInjected=true
    Rematch.menus:AddToMenu("PetMenu",{
        text=function(_,p) return RematchHasBest(p) and "取消最优品种" or "设为最优品种" end,
        hidden=function(_,p) return not p end,
        func=function(_,p) if RematchHasBest(p) then RematchRemoveBest(p) else RematchSetBest(p,"custom") end end
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
        local isBest=next(addonTable.GetAllBestBreeds(speciesID))
        if isBest and button.name then button.name:SetTextColor(1,0.84,0) end
    end)
    LOG("已 Hook PetJournal_InitPetButton")
end

-- ========== 初始化 ==========
function addonTable.InitJournalUI()
    LOG("初始化")
    local function initR()
        C_Timer.After(0.3,function() TryHookRematch();TryInjectRematchMenu() end)
    end
    if C_AddOns.IsAddOnLoaded("Rematch") then initR() end
    local rf=CreateFrame("Frame");rf:RegisterEvent("ADDON_LOADED")
    rf:SetScript("OnEvent",function(_,_,a) if a=="Rematch" then initR();rf:UnregisterEvent("ADDON_LOADED") end end)

    local bcf=CreateFrame("Frame");bcf:RegisterEvent("ADDON_LOADED")
    bcf:SetScript("OnEvent",function(_,_,a) if a=="Blizzard_Collections" then TryHookBlizzard();bcf:UnregisterEvent("ADDON_LOADED") end end)
    local pjf=CreateFrame("Frame");pjf:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
    pjf:SetScript("OnEvent",function() TryHookBlizzard() end)
end
