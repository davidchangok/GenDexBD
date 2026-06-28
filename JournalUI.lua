-- GenDexBD JournalUI.lua - Mixin Fill Hook + 右键菜单（已拥有+未拥有统一）

local addonName, addonTable = ...
local time=time;local next=next;local ipairs=ipairs
local GetLocaleString = addonTable.GetLocaleString
local GetBreedCode = addonTable.GetBreedCode
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

    -- 构建一级子菜单
    local items = {}

    -- 1.1 当前宠物品种操作项
    if currentBreedID then
        local code = GetBreedCode(currentBreedID) or "?"
        if isBest then
            items[#items+1] = {text=code.." ★ "..GetLocaleString("REMOVE_BEST_BREED"), func=function() RematchRemoveBest(petID) end}
        else
            items[#items+1] = {text=code.." "..GetLocaleString("SET_BEST_BREED"), func=function() RematchSetBest(petID) end}
        end
    end

    -- 1.2 "设为其他属性" → 全部12品种子菜单
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
    if not Rematch or not Rematch.menus or not Rematch.menus.AddToMenu then
        LOG("菜单注入跳过: Rematch.menus 不可用")
        return
    end

    -- 预注册占位菜单（subMenuFunc 需要 allMenus[name] 存在才触发）
    Rematch.menus:Register("GenDexSetBestMenu", {{text="..."}})
    Rematch.menus:Register("GenDexOtherBreedsMenu", {{text="..."}})

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
        injectRematchMenus()
    end

    if C_AddOns.IsAddOnLoaded("Rematch") then hookFill()
    else
        local f=CreateFrame("Frame");f:RegisterEvent("ADDON_LOADED")
        f:SetScript("OnEvent",function(_,_,a) if a=="Rematch" then hookFill();f:UnregisterEvent("ADDON_LOADED") end end)
    end
end
