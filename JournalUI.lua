-- GenDexBD JournalUI.lua - Mixin Fill Hook + 右键菜单（已拥有+未拥有统一）

local addonName, addonTable = ...
local time=time;local next=next;local ipairs=ipairs
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

-- 动态构建子菜单（每次悬停时 Rematch 调用 subMenuFunc(self, subject)）
local function BuildSetBestSubMenu(_, petID)
    if not Rematch or not Rematch.petInfo then return end
    local info = Rematch.petInfo:Fetch(petID)
    if not info or not info.speciesID then return end

    local speciesID = info.speciesID
    local currentBreedID = (info.hasBreed and info.breedID and info.breedID > 0) and info.breedID or nil
    local isBest = currentBreedID and addonTable.IsBestBreed(speciesID, currentBreedID)

    local items = {}

    if currentBreedID then
        local code = GetBreedCode(currentBreedID) or "?"
        if isBest then
            items[#items+1] = {text=code.." ★ "..GetLocaleString("REMOVE_BEST_BREED"), func=function() RematchRemoveBest(petID) end}
        else
            items[#items+1] = {text=code.." "..GetLocaleString("SET_BEST_BREED"), func=function() RematchSetBest(petID) end}
        end
    end

    local otherItems = {}
    for _, br in ipairs(ALL_BREEDS) do
        otherItems[#otherItems+1] = {text=br[2], func=function() RematchSetBestNoPet(speciesID, br[1]) end}
    end
    otherItems[#otherItems+1] = {text=CANCEL}
    Rematch.menus:Register("GenDexOtherBreedsMenu", otherItems)

    items[#items+1] = {text=GetLocaleString("SET_OTHER_BREED"), subMenu="GenDexOtherBreedsMenu"}

    Rematch.menus:Register("GenDexSetBestMenu", items)
end

local function injectRematchMenus()
    if not Rematch or not Rematch.menus or not Rematch.menus.AddToMenu then return end

    Rematch.menus:Register("GenDexSetBestMenu", {{text="..."}})
    Rematch.menus:Register("GenDexOtherBreedsMenu", {{text="..."}})

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
