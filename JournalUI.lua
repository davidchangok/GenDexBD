-- GenDexBD JournalUI.lua — Rematch Mixin Fill Hook + 右键菜单

local addonName, addonTable = ...
local time=time;local next=next
local function LOG(...) print("|cff00ccff[GenDexBD]|r "..string.format(...)) end

-- API
function addonTable.SetBestBreed(s,b,c,n)
    if not s or not b then return end;if not GeneDexDB then return end
    local bb=GeneDexDB.BestBreeds;if not bb or type(bb)~="table" then GeneDexDB.BestBreeds={} end
    if not GeneDexDB.BestBreeds[s] then GeneDexDB.BestBreeds[s]={} end
    GeneDexDB.BestBreeds[s][b]={category=c or "custom",note=n or "",addedAt=time()}
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

-- Breed 改写
local function label(b)
    if not b or not b.Breed or not b.petID then return end
    if not Rematch or not Rematch.petInfo then return end
    local i=Rematch.petInfo:Fetch(b.petID)
    if not i or not i.hasBreed or not i.breedID or i.breedID==0 then return end
    local best=addonTable.IsBestBreed(i.speciesID,i.breedID)
    b.Breed:SetText(best and ("★"..i.breedName) or i.breedName)
    b.Breed:SetTextColor(best and 1 or 0.6,best and 0.84 or 0.6,0.6)
end

-- 右键菜单
function RematchSetBest(petID)
    if not Rematch or not Rematch.petInfo then return end
    local i=Rematch.petInfo:Fetch(petID);if not i or not i.hasBreed then return end
    addonTable.SetBestBreed(i.speciesID,i.breedID,"custom","")
    LOG("已保存: speciesID=%d breedID=%d (%s)",i.speciesID,i.breedID,i.breedName or "?")
    Rematch.petsPanel:Update()
end
function RematchRemoveBest(petID)
    if not Rematch or not Rematch.petInfo then return end
    local i=Rematch.petInfo:Fetch(petID);if not i or not i.hasBreed then return end
    addonTable.RemoveBestBreed(i.speciesID,i.breedID)
    LOG("已移除: speciesID=%d breedID=%d",i.speciesID,i.breedID)
    Rematch.petsPanel:Update()
end
function RematchHasBest(petID)
    if not Rematch or not Rematch.petInfo then return false end
    local i=Rematch.petInfo:Fetch(petID)
    return i and i.hasBreed and addonTable.IsBestBreed(i.speciesID,i.breedID)
end

-- 菜单注入（用 ADDON_LOADED for Rematch 确保在 PLAYER_LOGIN 之后）
local menuDone=false
local function injectMenu()
    if menuDone then return end
    if not Rematch or not Rematch.menus or not Rematch.menus.AddToMenu then
        return  -- 静默，等下次 PET_JOURNAL_LIST_UPDATE 触发时再试
    end
    menuDone=true
    Rematch.menus:AddToMenu("PetMenu",{
        text=function(_,p) return RematchHasBest(p) and "取消最优品种" or "设为最优品种" end,
        hidden=function(_,p) return not p end,
        func=function(_,p) if RematchHasBest(p) then RematchRemoveBest(p) else RematchSetBest(p) end end
    },"Find Teams")
    LOG("Rematch 菜单已注入")
end

-- 初始化
function addonTable.InitJournalUI()
    LOG("初始化")

    -- Mixin Fill Hook
    local function hookFill()
        if RematchNormalPetListButtonMixin and not RematchNormalPetListButtonMixin._gHooked then
            RematchNormalPetListButtonMixin._gHooked=true
            hooksecurefunc(RematchNormalPetListButtonMixin,"Fill",function(b) label(b) end)
            LOG("已 Hook Normal Mixin")
        end
        if RematchCompactPetListButtonMixin and not RematchCompactPetListButtonMixin._gHooked then
            RematchCompactPetListButtonMixin._gHooked=true
            hooksecurefunc(RematchCompactPetListButtonMixin,"Fill",function(b) label(b) end)
            LOG("已 Hook Compact Mixin")
        end
        if Rematch.petsPanel and Rematch.petsPanel.Update then Rematch.petsPanel:Update() end
    end

    -- Fill Hook 入口
    if C_AddOns.IsAddOnLoaded("Rematch") then hookFill()
    else
        local f=CreateFrame("Frame");f:RegisterEvent("ADDON_LOADED")
        f:SetScript("OnEvent",function(_,_,a) if a=="Rematch" then hookFill();f:UnregisterEvent("ADDON_LOADED") end end)
    end

    -- 菜单注入：Rematch PetMenu 在 PLAYER_LOGIN + 0.5s 延迟后才就绪
    -- 在 PET_JOURNAL_LIST_UPDATE + PLAYER_LOGIN 两个时机触发
    local function tryMenu()
        injectMenu()
    end
    C_Timer.After(2, tryMenu)  -- 2秒后肯定 PLAYER_LOGIN 都完成了

    -- 备胎：PET_JOURNAL_LIST_UPDATE 每次也尝试（用户打开宠物面板时一定触发）
    local mf=CreateFrame("Frame");mf:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
    mf:SetScript("OnEvent",function() injectMenu() end)

    -- 备胎2：Rematch ADDON_LOADED
    local rf=CreateFrame("Frame");rf:RegisterEvent("ADDON_LOADED")
    rf:SetScript("OnEvent",function(_,_,a)
        if a=="Rematch" then C_Timer.After(3,tryMenu);rf:UnregisterEvent("ADDON_LOADED") end
    end)
end
