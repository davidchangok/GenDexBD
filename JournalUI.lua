-- GenDexBD JournalUI.lua — Fill Hook: ★Breed文本 + Rematch 右键菜单

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

-- Fill Hook
local function onFill(_,button)
    if not button or not button.Breed or not button.petID then return end
    if not Rematch or not Rematch.petInfo then return end
    local info=Rematch.petInfo:Fetch(button.petID)
    if not info or not info.hasBreed or not info.breedID or info.breedID==0 then return end
    local best=addonTable.IsBestBreed(info.speciesID,info.breedID)
    button.Breed:SetText(best and ("★"..info.breedName) or info.breedName)
    button.Breed:SetTextColor(best and 1 or 0.6,best and 0.84 or 0.6,0.6)
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

-- 初始化
function addonTable.InitJournalUI()
    LOG("初始化")
    -- Fill Hook：Rematch ADDON_LOADED 时安装
    local function initFill()
        hooksecurefunc(Rematch.petsPanel,"FillNormal",onFill)
        hooksecurefunc(Rematch.petsPanel,"FillCompact",onFill)
        LOG("已 Hook Rematch Fill")
        Rematch.petsPanel:Update()
    end
    -- 菜单注入：延迟重试直到 Rematch PetMenu 就绪
    local menuInjected=false
    local menuRetries=0
    local function initMenu()
        if menuInjected then return end;menuRetries=menuRetries+1
        if Rematch and Rematch.menus and Rematch.menus.AddToMenu then
            menuInjected=true
            Rematch.menus:AddToMenu("PetMenu",{
                text=function(_,p) return RematchHasBest(p) and "取消最优品种" or "设为最优品种" end,
                hidden=function(_,p) return not p end,
                func=function(_,p) if RematchHasBest(p) then RematchRemoveBest(p) else RematchSetBest(p) end end
            },"Find Teams")
            LOG("Rematch 菜单已注入 (第%d次尝试)",menuRetries)
        elseif menuRetries<30 then
            C_Timer.After(1,initMenu)
        else
            LOG("⚠ 菜单注入放弃：尝试30次后 Rematch.menus 仍不可用")
        end
    end

    -- Fill Hook：Rematch 加载后立即安装
    if C_AddOns.IsAddOnLoaded("Rematch") then initFill()
    else
        local f=CreateFrame("Frame");f:RegisterEvent("ADDON_LOADED")
        f:SetScript("OnEvent",function(_,_,a) if a=="Rematch" then initFill();f:UnregisterEvent("ADDON_LOADED") end end)
    end
    -- 菜单：延迟重试直到就绪
    C_Timer.After(1,initMenu)
end
